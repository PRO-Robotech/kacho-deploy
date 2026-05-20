# Quarterly Chaos Game-Day Report Template

**Date**: YYYY-MM-DD
**Environment**: production | staging | dev
**Operator**: <name / Slack handle>
**On-call shadow**: <name>
**Approval**: <Platform Lead name>

---

## Pre-flight

- [ ] Game-day announcement sent to #engineering 24h ahead
- [ ] PagerDuty alert maintenance window set
- [ ] DR snapshot taken (Postgres + ClickHouse + S3 baseline)
- [ ] k6 background-load probe configured (target URL + thresholds)
- [ ] Grafana dashboard "Chaos Game-Day" open
- [ ] Approval signed-off by Platform Lead

## Experiments Executed

| # | Experiment | Started | Duration | Verdict | SLO maintained (p95<500ms, errors<1%) | Auto-recovered |
|---|------------|---------|----------|---------|---------------------------------------|----------------|
| 1 | pod-delete-kacho-iam | | 30s | | | |
| 2 | pod-delete-openfga | | 60s | | | |
| 3 | network-latency-spike | | 180s | | | |
| 4 | network-partition-kafka | | 180s | | | |
| 5 | disk-fill-postgres | | 120s | | | |
| 6 | cpu-stress-clickhouse | | 300s | | | |
| 7 | dns-failure | | 120s | | | |
| 8 | hsm-unavailable | | 180s | | | |
| 9 | cert-expiry | | 90s | | | |
| 10 | argocd-out-of-sync | | 300s | | | |
| 11 | caep-subscriber-down | | 240s | | | |
| 12 | node-drain-region | | 300s | | | |

## Findings

(Document any unexpected behaviour, regressions, missing alerts, broken auto-recovery, latency spikes, error rates exceeding thresholds.)

### Critical (P0)
- (none expected; if any → SEV-1 incident, immediate stop)

### High (P1)
-

### Medium (P2)
-

### Observations / Improvements
-

## Action Items

| # | Description | Owner | KAC ticket | Target date |
|---|-------------|-------|------------|-------------|
| 1 | | | | |

## Post-game-day

- [ ] All experiments completed or aborted safely
- [ ] All findings documented and triaged
- [ ] KAC tickets opened for High / Critical findings
- [ ] Game-day announcement of completion sent
- [ ] Report uploaded to `docs/security/chaos-reports/<date>.md`
- [ ] Grafana annotations preserved
- [ ] Lessons learned added to `obsidian/kacho/chaos-lessons.md`

## Verdict

[PASS / PASS-WITH-FOLLOWUPS / FAIL]

(PASS = all 12 experiments completed AND all SLOs maintained.)
(PASS-WITH-FOLLOWUPS = experiments completed but P2/P3 followups identified.)
(FAIL = SLO violated OR experiment couldn't run OR system did not auto-recover.)

## Sign-off

- Operator: ______________________
- On-call shadow: ______________________
- Platform Lead: ______________________
