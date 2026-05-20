# Runbook — SLO budget burn investigation

**Severity**: P1 if burn-rate-1h > 14.4; P2 if burn-rate-6h > 6.
**Last reviewed**: 2026-05-19 (Phase 11)

## Problem

An SLO error budget is burning faster than sustainable. At current rate
the 30-day budget will exhaust prematurely.

Burn rate formula: `(error_rate_window / SLO_target_error_rate)`. 14.4× over
1h exhausts the budget in 2.5 days.

## Diagnosis

1. Open SLO dashboard:
   `https://grafana.{{kacho.domain}}/d/iam-slo-burn-rate`
2. Identify which SLO and which service:
   * `auth-availability` → check Hydra/Kratos.
   * `fga-check-latency-p95` → check OpenFGA + Postgres replica lag.
   * `token-issuance-latency-p95` → Hydra + DB.
   * `caep-delivery-p99` → Phase 8 drainer + subscribers.
   * `audit-ingest-lag-p99` → Kafka + ClickHouse + MM2.
   * `api-gateway-5xx` → upstream service health.
3. Correlate with concurrent alerts (Alertmanager UI).
4. Recent deploys?
   ```
   argocd app history kacho-iam --output json | jq '.[-5:]'
   ```

## Mitigation tree

### Recent deploy correlates with burn start

1. **Pause canary rollout**:
   ```
   kubectl argo rollouts pause <svc>-canary -n kacho-system
   ```
2. **Roll back if confirmed bad**:
   ```
   kubectl argo rollouts undo <svc>-canary -n kacho-system
   ```
3. Verify burn rate begins decreasing within 5 min.

### Postgres replica lag

1. Run `regional-failover.md` § Diagnosis section to check lag.
2. If lag > 60s sustained → consider failover; consult
   `regional-failover.md`.

### Sudden traffic spike (legitimate)

1. Scale up HPA: `kubectl scale deploy <svc> --replicas=<higher>`.
2. Add capacity headroom: edit HPA max replicas (`values.prod.yaml`).
3. Pre-warm DB connection pools via pgbouncer admin.

### Sudden traffic spike (attack)

1. Engage `cloudflare-rule-rollback.md` to add/strengthen rate-limit.
2. Enable Cloudflare "Under Attack" mode for the affected hostname:
   ```
   cf-cli zone setting set --zone {{kacho.domain}} --setting security_level --value under_attack
   ```
3. Open incident; investigate via Hubble UI for traffic patterns.

## Escalation

* If 5min burn-rate >> 14.4 (e.g. > 100) — full outage candidate; consider
  static-page mode (Cloudflare worker → 503 with retry-after).
* If budget already exhausted — freeze deploys (`argocd app set <svc>
  --sync-policy none`) until budget recovers.

## Post-mortem

* Budget consumed (percentage of 30d).
* Root cause class (deploy / capacity / dependency / attack).
* Action items: capacity bump / regression test / new alert.
