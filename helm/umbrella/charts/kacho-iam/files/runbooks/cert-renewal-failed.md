# Runbook — cert-manager renewal failure

**Severity**: P1 (TLS cert expiry imminent → full outage on expiry)
**Target time-to-mitigate**: 30 minutes
**Last reviewed**: 2026-05-19 (Phase 11)

## Problem

`KachoCertRenewalFailed` alert is firing. cert-manager has failed renewal
≥3 times. Possible causes:

1. Let's Encrypt rate-limit hit (50 certs/week/zone — usually not).
2. Cloudflare API token expired or rotated without secret update.
3. DNS-01 challenge propagation delay.
4. ACME-server outage.

## Diagnosis

1. Identify the certificate:
   ```
   kubectl get certificate -A --field-selector=status.conditions[*].type=Ready \
     -o jsonpath='{range .items[?(@.status.conditions[0].status=="False")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'
   ```
2. Inspect the failing CertificateRequest:
   ```
   kubectl describe certificaterequest -n <ns> <cr-name>
   ```
3. Check cert-manager controller logs:
   ```
   kubectl -n cert-manager logs -l app.kubernetes.io/name=cert-manager --tail=200
   ```
4. Test Cloudflare API token:
   ```
   curl -sf -H "Authorization: Bearer $(kubectl -n cert-manager get secret \
     cert-manager-cloudflare-token -o jsonpath='{.data.token}' | base64 -d)" \
     "https://api.cloudflare.com/client/v4/zones?name={{kacho.domain}}"
   ```
   Expect HTTP 200 + `"success":true`. If 401/403 — token expired → rotate.

## Mitigation

### Token expired

1. Rotate Cloudflare API token via Cloudflare dashboard (Zone: DNS:Edit only).
2. Update sealed-secret or ExternalSecrets vault path:
   ```
   vault kv put secret/kacho/prod/cert-manager-cloudflare-token token=<new-token>
   ```
3. Force-refresh cert-manager solver:
   ```
   kubectl -n cert-manager rollout restart deployment cert-manager
   ```
4. Trigger renewal:
   ```
   kubectl -n <ns> annotate certificate <name> cert-manager.io/issue-temporary-certificate=true
   ```

### Rate-limit hit

1. Switch to `letsencrypt-staging` ClusterIssuer until rate-limit window
   expires (1 week):
   ```
   kubectl -n <ns> patch certificate <name> --type merge \
     --patch '{"spec":{"issuerRef":{"name":"letsencrypt-staging"}}}'
   ```
2. Staging certs are not browser-trusted — communicate via status-page;
   external clients add staging CA to trust store temporarily.
3. Once rate-limit clears, switch back to `letsencrypt-prod`.

### Cert expires in <24h

1. Issue manual emergency cert via cert-manager + DNS-01:
   ```
   kubectl apply -f <(envsubst < emergency-cert.yaml)
   ```
2. If automated renewal still fails → engage cert-manager support OR
   manually request via certbot + DNS challenge.

## Escalation

* If certificate <6h to expiry — page `kacho-sre-oncall` PagerDuty escalation
  level 2.
* If domain is hijacked (Cloudflare account compromise) — execute
  `cloudflare-rule-rollback.md` runbook first; consider revoking issued certs
  via Let's Encrypt revocation endpoint.

## Post-mortem

* Why did automation fail? (Token rotation gap / monitoring gap / etc.)
* Was HSTS preload list affected? (yes if cert outage > minutes)
* Action items: token-rotation playbook update, monitoring of
  Cloudflare-token expiry, etc.
