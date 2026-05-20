# Runbook — Regional failover (prod-eu-central → prod-eu-west)

**Severity**: P1
**Target RTO**: ≤ 15 minutes
**Target RPO**: ≤ 1 minute
**Authors**: kacho-platform-team
**Last reviewed**: 2026-05-19 (Phase 11)

## Problem

Primary region `prod-eu-central` has lost connectivity, lost quorum, suffered
a control-plane outage, or was identified as compromised. Alert
`KachoRegionFailoverTriggered` is firing or operator-initiated cutover is
required.

Affected: all kacho-iam-platform writes (auth, FGA writes, audit ingest,
CAEP delivery) — reads degraded to last-known state in eu-west.

## Diagnosis (≤ 2 min)

1. Confirm primary region health:
   ```
   curl -sf https://api.kacho.cloud/healthz -H "Host: api.kacho.cloud" \
     --resolve api.kacho.cloud:443:<eu-central-anycast-ip>
   ```
   Expect 200; if 5xx / timeout / DNS-fail → continue.
2. Check Cloudflare LB health-check status:
   `cf-cli loadbalancer pool-status --pool prod-eu-central-origin-pool`
3. Check Patroni leader election state:
   ```
   kubectl -n kacho-system exec -it kacho-iam-postgres-1 -- \
     patronictl list kacho-iam-postgres
   ```
4. Confirm eu-west replication lag is < 60s (RPO):
   ```
   kubectl --context prod-eu-west -n kacho-system exec -it kacho-iam-postgres-1 -- \
     psql -U postgres -c "SELECT pg_wal_lsn_diff(pg_current_wal_lsn(),replay_lsn) FROM pg_stat_replication;"
   ```

## Mitigation

### Automatic failover (Cloudflare LB driven)

If RTO≤15min met automatically by Cloudflare health-check (default):
1. Verify `kubectl --context prod-eu-west get nodes` — all Ready.
2. Watch `KachoIamAuthSuccessRateLow` alert clear within 5 min.
3. Page handoff completed — proceed to "Post-mortem".

### Manual / operator-initiated cutover (planned)

1. **Promote eu-west Postgres** (per service):
   ```
   for svc in kacho-iam kacho-vpc kacho-compute kacho-loadbalancer; do
     kubectl --context prod-eu-west -n kacho-system \
       patch cluster ${svc}-postgres --type merge \
       --patch '{"spec":{"replica":{"enabled":false}}}'
   done
   ```
2. **Promote OpenFGA writer to eu-west**:
   ```
   kubectl --context prod-eu-west -n kacho-system patch deployment openfga \
     --type merge --patch '{"spec":{"template":{"metadata":{"annotations":{"kacho.cloud/role":"writer"}}}}}'
   ```
3. **Switch Kafka MirrorMaker 2 direction** (eu-west → eu-central):
   ```
   kubectl --context prod-eu-west apply -f \
     helm/umbrella/charts/kafka/templates/mm2-eu-west-to-eu-central.yaml
   ```
4. **Update Cloudflare LB priority**:
   ```
   cf-cli loadbalancer pool-update --pool prod-eu-central-origin-pool --priority 2
   cf-cli loadbalancer pool-update --pool prod-eu-west-origin-pool --priority 1
   ```
5. **Verify traffic shift**:
   ```
   for i in {1..10}; do
     curl -sH "Host: api.kacho.cloud" https://api.kacho.cloud/healthz \
       | grep -o '"region":"prod-eu-[a-z]*"'
     sleep 1
   done
   ```
   Expect ≥ 9/10 returning `prod-eu-west`.
6. **Smoke test** end-to-end via `kacho-yc-shim`:
   ```
   kacho-yc-shim auth login --identity ops@kacho.cloud
   kacho-yc-shim iam project-list
   kacho-yc-shim vpc network-list
   ```
   All commands must return 200 OK with `x-kacho-region: prod-eu-west` header.

## Escalation

* If RTO > 15 min — page `kacho-platform-oncall-l2` via PagerDuty.
* If RPO > 1 min (data loss on planned cutover) — engage Data Engineering
  team for replay procedure from Kafka audit-events.
* If neither region is healthy — declare full outage, page CTO + activate
  status-page incident.

## Post-mortem template

* Trigger time / detection time / mitigation time / fully-recovered time.
* RTO actual / RPO actual / SLO budget consumed (use
  `https://grafana.{{kacho.domain}}/d/iam-slo-burn-rate`).
* Cloudflare LB logs + Patroni leader election history attached.
* Action items: tracker → KAC tickets.

## Cross-references

* `slo-budget-burn.md` — if budget exhausted during incident.
* `audit-pipeline-incident.md` — if Kafka MirrorMaker fell behind.
* `key-rotation.md` — if HSM cross-region trust failed during cutover.
