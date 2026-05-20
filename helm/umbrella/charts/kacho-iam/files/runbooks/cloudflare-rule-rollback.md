# Runbook — Cloudflare rule rollback

**Severity**: P1 if production traffic affected; P3 if test mode.
**Last reviewed**: 2026-05-19 (Phase 11)

## Problem

A recently deployed WAF / firewall / rate-limit rule is causing false
positives (legitimate traffic blocked) or accidentally relaxing security.

Alerts that trigger this runbook:
* `KachoApiGatewayErrorRate5xxHigh` (4xx spike from blocks)
* `KachoCloudflareBlockRateSpike` (custom — Phase 11)

## Diagnosis

1. Identify the offending rule (rollouts dashboard):
   `https://grafana.{{kacho.domain}}/d/cloudflare-overview`
2. Inspect block rate per rule (Cloudflare Logpush → ClickHouse):
   ```
   SELECT rule_id, action, count() FROM cloudflare_logs
   WHERE timestamp >= now() - INTERVAL 30 MINUTE
     AND action != 'allow'
   GROUP BY rule_id, action ORDER BY count() DESC LIMIT 20;
   ```
3. Sample blocked requests:
   ```
   SELECT * FROM cloudflare_logs
   WHERE rule_id = '<id>' AND timestamp >= now() - INTERVAL 10 MINUTE
   LIMIT 50;
   ```

## Mitigation

### Move rule to simulate mode (recommended first step)

```
kubectl -n cloudflare-system patch ruleset <id> --type merge \
  --patch '{"spec":{"forProvider":{"rules":[{"action":"log"}]}}}'
```

### Disable rule entirely

```
kubectl -n cloudflare-system patch ruleset <id> --type merge \
  --patch '{"spec":{"forProvider":{"rules":[{"enabled":false}]}}}'
```

Wait ~30s for Cloudflare API to propagate; re-check error rate.

### GitOps rollback

If rule came in via Helm — `git revert <commit>` + push branch + ArgoCD
auto-sync (or manual `argocd app sync cloudflare-config`).

## Verification

```
for endpoint in /healthz /v1/iam/projects /v1/vpc/networks; do
  for i in {1..5}; do
    curl -sH "Host: api.kacho.cloud" -o /dev/null -w "%{http_code}\n" \
      https://api.kacho.cloud${endpoint}
  done
done
```

All return 200/401 (auth) — never 403/406 (WAF block).

## Escalation

* If issue is global (all WAF rules over-blocking) — pause Cloudflare proxy
  via `--proxied false` on DNS records (grey-cloud); engage Cloudflare
  support concurrently.
* If issue indicates active attack abusing relaxed rules — re-enable +
  invoke `slo-burn-investigation.md` for impact.

## Post-mortem

* Was the rule load-tested in `simulate` mode before promotion? (Phase 11
  policy: 24h soak required for new WAF rules.)
* Action items: CI gate for WAF rule changes (require staging approval).
