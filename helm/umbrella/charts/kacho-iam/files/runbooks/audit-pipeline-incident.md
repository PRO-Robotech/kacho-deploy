# Audit Pipeline Incident Runbook (KAC-127 Phase 9)

> Acceptance: `docs/specs/sub-phase-3.9-iam-audit-pipeline-acceptance.md` §4.3 +
> P9-D14.
> Severity tiers: **P0** (audit-tamper — wake CISO), **P1** (HSM/break-glass —
> page on-call), **P2** (Kafka/CH lag — alert team), **P3** (SIEM backpressure
> — notify tenant).

This runbook covers four primary incident classes. For each class — symptoms,
PagerDuty/alert mapping, immediate triage steps, recovery, post-incident
follow-up.

---

## 1. Kafka outage recovery

**Trigger alerts**: `KachoAuditKafkaConsumerLagHigh`, `KachoAuditDrainerDown`,
`KachoAuditOutboxBacklog`.

**Symptoms**:
- Audit events accumulating in Postgres `audit_outbox` (kafka producer failing).
- ClickHouse `audit_events` ingestion stopped.
- SIEM subscribers receiving nothing.

**Triage**:
1. `kubectl -n kacho get pods -l app.kubernetes.io/name=kafka` — check broker pods.
2. `kubectl -n kacho logs <kafka-pod>` — look for ISR violations, replication errors.
3. `kubectl -n kacho exec -it <kafka-0> -- kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic kacho-audit-events.shared` — confirm partitions healthy.
4. Check `min.insync.replicas=2` is met for all partitions.

**Recovery** (in order of severity):

| Scenario | Action |
|---|---|
| 1 broker down, 2 alive | min.isr=2 still met; auto-recovers on broker restart. Verify writes resume. |
| 2 brokers down | producer ack=all fails; drainer accumulates outbox. Restore second broker ASAP. |
| All 3 brokers down | Drainer paused. Outbox keeps growing — Postgres OK для до ~72h (depends on volume). Restore brokers. |
| Data loss (broker disk lost without replication) | Recreate from outbox; events with `delivered_at=NULL` re-publish via drainer restart. |

**Post-incident**:
- Verify all `audit_outbox.status` rows transitioned: `pending → delivered`.
- Check audit_signing_batches sequence intact (no gap in `batch_seq` if outage
  spanned Merkle signer run).

---

## 2. ClickHouse replication failure

**Trigger alerts**: `KachoClickHouseReplicationLagHigh`.

**Symptoms**:
- Forensic queries return stale data.
- Activity tab UI shows missing recent events.

**Triage**:
1. `kubectl exec -it clickhouse-0 -- clickhouse-client -q "SELECT * FROM system.replicas WHERE is_readonly OR future_parts > 100"` — find broken replicas.
2. Check Keeper coordination — `kubectl logs clickhouse-keeper-0`.
3. Check disk space on all CH pods (`df -h /var/lib/clickhouse`).

**Recovery**:

| Scenario | Action |
|---|---|
| One replica behind, replication active | Wait — auto-catches. If >5min lag persists, force fetch: `SYSTEM SYNC REPLICA <table>`. |
| Replica `is_readonly=1` (lost Keeper session) | Restart pod. CH auto-rejoins on startup. |
| Disk full | Add PVC capacity (StatefulSet PVC resize), or drop oldest partition: `ALTER TABLE audit_events_local DROP PARTITION <old>`. |
| Keeper quorum lost (2/3 down) | Restore Keeper StatefulSet (priority — without quorum, CH replication frozen). |

**Post-incident**:
- Run independent verifier ad-hoc: `kubectl create job --from=cronjob/audit-verifier audit-verifier-manual-$(date +%s)` to confirm no data corruption.

---

## 3. HSM unavailable failover

**Trigger alerts**: `KachoAuditHSMSigningFailureRate`, `KachoAuditMerkleBatchUnsignedTooLong`.

**Symptoms**:
- Merkle batch signer CronJob fails repeatedly.
- S3 archive stops (no `.manifest.signed` files in S3).
- ClickHouse + Kafka continue working (graceful degradation per P9-D8 §4.3).

**Triage by HSM provider**:

### AWS CloudHSM
1. `kubectl exec -it kacho-iam-merkle-signer-<pod> -- cloudhsm_mgmt_util` — check HSM cluster reachability.
2. AWS Console → CloudHSM → check cluster state (ACTIVE / DEGRADED).
3. ENI security group allows port 2223,2224,2225 from K8s VPC?

### GCP Cloud HSM
1. `gcloud kms keys describe <key-name> --location=<region> --keyring=<keyring>`.
2. Workload Identity binding: `gcloud iam service-accounts get-iam-policy <iam-sa>`.

### Azure Key Vault Managed HSM
1. Az CLI: `az keyvault key show --hsm-name <hsm> --name <key>`.
2. Federated identity OIDC binding healthy?

### Thales Luna (on-prem)
1. `vtl listSlots` from kacho-iam pod — slots visible?
2. Network reachability on TCP/1792 to Luna appliance.
3. Partition PIN valid (not expired)?

### SoftHSM (dev only)
1. `softhsm2-util --show-slots` inside pod.
2. PIN secret mounted correctly?

**Recovery**:
- If HSM transient (network blip) — wait, signer auto-retries on next CronJob tick.
- If HSM persistent outage (>1h) — escalate to vendor + fail over to standby HSM
  (rotate `audit.hsm.libraryPath` / `tokenLabel` via helm upgrade).
- After recovery: re-run signer manually to catch up backlog:
  `kubectl create job --from=cronjob/merkle-batch-signer signer-catchup-$(date +%s)`.

**Post-incident**:
- Audit log: gap window in S3 (events present in Kafka + ClickHouse, but
  unsigned manifests). Verifier next-day run will flag — file `wontfix`
  if HSM outage formally documented (force-majeure clause).

---

## 4. Independent verifier mismatch investigation (P0)

**Trigger alert**: `KachoAuditVerifierMismatch` (severity=critical, priority=P0).

**This is potentially an APT or insider attack. Wake CISO immediately.**

**Symptoms**:
- PagerDuty P0 incident `incident_key=audit-tamper-<batch_id>`.
- Slack #security-critical message.
- Email to security@kacho.cloud + CISO SMS.

**Triage**:
1. **DO NOT** restart any audit-pipeline component until forensics complete.
2. Pull `audit_verifier_runs` row for run_id from alert:
   ```sql
   SELECT * FROM audit_verifier_runs WHERE run_id = '<vrn_...>';
   ```
3. Identify `anomaly_batch_ids` — list of suspect batches.
4. For each suspect batch:
   - Download `s3_manifest_uri` + `s3_uri` to forensic workstation.
   - Recompute Merkle root locally (`kacho-iam audit verify-batch <batch_id> --local`).
   - Compare with manifest.merkle_root + audit_signing_batches.merkle_root.
   - Check S3 object metadata `LastModified` vs `signed_at` — should match ±1min.
5. Check audit_signing_batches.previous_batch_hash chain — broken link
   indicates batch insertion / deletion.

**Anomaly classes**:

| Anomaly | Indicator | Likely cause |
|---|---|---|
| `broken_chain` | `prev.batch_hash != this.previous_batch_hash` | Batch insertion (forge) or deletion |
| `signature_mismatch` | HSM verify failed | Manifest tampered post-signing |
| `merkle_root_mismatch` | Recomputed root ≠ manifest root | jsonl.gz tampered |

**Response**:
- Lock down affected pods (`kubectl scale --replicas=0 kacho-iam`).
- Preserve all S3 objects (S3 Object Lock should be enabled per Phase 11);
  Glacier preserves automatically.
- Engage forensics vendor + legal counsel.
- Notify customers per breach notification SLA (GDPR 72h, US state laws vary).
- Post-incident: full external audit by security firm.

**Recovery** (only after forensics complete):
- Rotate HSM signing key (`hsm-audit-v1` → `hsm-audit-v2`, dual-sign 7d window
  per P9-D28).
- Investigate root cause (insider, compromised K8s SA, supply-chain attack).
- File incident report with auditor (SOC2 CC7.4 requires).

---

## Quick reference commands

```bash
# Outbox status snapshot
kubectl exec -it kacho-iam-0 -- psql -U iam -d kacho_iam -c \
  "SELECT status, count(*) FROM audit_outbox GROUP BY status;"

# Latest Merkle batch
kubectl exec -it kacho-iam-0 -- psql -U iam -d kacho_iam -c \
  "SELECT batch_id, batch_seq, signed_at, verifier_status FROM audit_signing_batches ORDER BY batch_seq DESC LIMIT 5;"

# Force verifier run
kubectl create job --from=cronjob/kacho-iam-audit-verifier verifier-manual-$(date +%s)

# Force merkle signer
kubectl create job --from=cronjob/kacho-iam-merkle-batch-signer signer-manual-$(date +%s)

# Kafka consumer lag
kubectl exec -it kacho-umbrella-kafka-0 -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group kacho-audit-clickhouse

# SIEM subscriber status
kubectl exec -it kacho-iam-0 -- psql -U iam -d kacho_iam -c \
  "SELECT id, account_id, provider, enabled, failure_count, last_failure_reason FROM siem_subscribers;"
```
