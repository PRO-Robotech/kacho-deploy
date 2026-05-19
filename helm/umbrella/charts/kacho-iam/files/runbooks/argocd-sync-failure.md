# Runbook — Argo CD sync failure

**Severity**: P2 (Phase 11)
**Last reviewed**: 2026-05-19

## Problem

Argo CD Application `<name>` is `OutOfSync` / `Degraded` / sync hook failed.
Detected by `on-sync-failed` notification or `KachoArgoCDApplicationDegraded`
alert.

## Diagnosis

1. List failing apps:
   ```
   argocd app list --output wide | grep -v Synced
   ```
2. Inspect events:
   ```
   argocd app get <name> --show-operation --show-params
   ```
3. Common failure classes:
   * **Sync hook script failed** → `argocd app logs <name> --container ...`.
   * **Manifest invalid** → `helm template` locally → kubeval.
   * **RBAC denial** → AppProject scope wrong / new namespace not whitelisted.
   * **cosign verify failed** → image not signed by trusted signer.

## Mitigation

### Manifest issue

1. Roll back to previous revision:
   ```
   argocd app rollback <name> <history-id>
   ```
2. Patch the source repo on a feature branch, open PR.

### Image signature issue (Phase 10/11 cosign attestor)

1. Verify image signature locally:
   ```
   cosign verify --key /etc/cosign/cosign.pub kacho/<svc>:<sha>
   ```
2. If unsigned — investigate CI pipeline; do **NOT** disable cosign attestor.
3. Re-build + re-sign image via `make sbom-verify && make slsa-verify-image`.

### Cluster connectivity issue

1. Check kubectl context: `argocd cluster get <cluster>`.
2. Restart cluster proxy: `kubectl rollout restart deployment argocd-server -n argocd-system`.

## Escalation

* If multiple apps degraded simultaneously → could indicate cluster-wide
  issue → page `kacho-sre-oncall`.
* If sync hook touches data — engage Data Engineering before manual
  intervention.

## Post-mortem

* Root cause (manifest / image / cluster / etc.).
* SLO budget consumed during outage.
* Action item: CI gate that prevents the failure class.
