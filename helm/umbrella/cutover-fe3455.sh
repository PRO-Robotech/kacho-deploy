#!/usr/bin/env bash
# cutover-fe3455.sh — fe3455 PROD umbrella CONVERGENCE upgrade (NOT a nuke/reinstall).
# =============================================================================
# WHAT THIS DOES
#   Runs `helm upgrade kacho-umbrella` against the LIVE fe3455 cluster with the
#   fe3455 prod overlays whose service/console images have been reconciled to the
#   CURRENTLY-LIVE working tags (helm/umbrella/values.fe3455.yaml +
#   values.fe3455-prod.yaml). Because every image in the overlays already equals
#   what is running, this upgrade CONVERGES the Helm release state onto the live
#   workloads — it does NOT revert or recreate the working control-plane.
#
#   VERIFIED before shipping (helm template of all 4 overlays): every core service
#   image (api-gateway/compute/kacho-geo/kacho-iam/kacho-nlb/vpc/registry), every
#   uif console remote (host + dashboard/vpc/iam/nlb/registry/system/compute/storage),
#   the zot image (v2.1.18) and every Postgres image (16.1.0-debian-11-r25, pg-hydra
#   16.4.0-debian-12-r0) in the render EQUALS the live kubectl-observed tag.
#
#   ONE INTENDED ADDITION (not a revert): values.fe3455-prod.yaml has
#   storage.enabled=true + pg-storage.enabled=true, but kacho-storage + pg-storage
#   are NOT yet on the cluster → this upgrade INSTALLS them (storage-split rollout)
#   and adds the compute->storage edge env to the compute Deployment (compute pod
#   restarts, same image). The pg-storage Secret is already pre-provisioned. If you
#   want a PURE zero-new-workload convergence, set storage.enabled=false +
#   pg-storage.enabled=false and drop the compute KACHO_COMPUTE_STORAGE_* env before
#   running — otherwise storage rolls out as the intended next step.
#
# WHY A SCRIPT (not run by the coding agent): the auto-mode classifier blocks `helm`
#   against the fe3455 context, so the agent cannot run the upgrade. You run this.
#
# DEP RESOLUTION: uses `helm dependency build` (respects the committed Chart.lock),
#   NOT `helm dependency update`. This PINS postgresql to 13.4.4 so the upgrade can
#   never bump the pg image tag — critical because every Postgres here runs emptyDir
#   (persistence.enabled=false), so a pg image change would recreate the pod and WIPE
#   the database. `dependency build` still re-vendors the local file:// sub-charts
#   (registry from ../kacho-registry@main with the merged S3/compat chart), which is
#   the reason a re-vendor is needed. If build fails because a sibling chart version
#   changed, run `helm dependency update` manually AND re-confirm pg pins stay 13.4.4.
#
# NO SECRET VALUES are written in this file. Postgres passwords are read from the
#   pre-created k8s Secrets at run time and passed via --set only to satisfy the
#   bitnami passwords-on-upgrade guard (they are never echoed).
# =============================================================================
set -euo pipefail

NS=kacho
RELEASE=kacho-umbrella
CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$CHART_DIR"

log()  { printf '\033[1;34m[cutover]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[cutover WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[cutover ABORT]\033[0m %s\n' "$*" >&2; exit 1; }

# ── 0. tools + cluster context ────────────────────────────────────────────────
command -v helm    >/dev/null || die "helm not found in PATH"
command -v kubectl >/dev/null || die "kubectl not found in PATH"
CTX="$(kubectl config current-context 2>/dev/null || true)"
log "kubectl context: ${CTX:-<none>}   namespace: $NS   chart: $CHART_DIR"
case "$CTX" in
  *fe3455*) : ;;
  *) warn "context '$CTX' does not look like fe3455 — Ctrl-C within 5s if this is the wrong cluster"; sleep 5 ;;
esac

# ── 1. required value files present (values.fe3455-ory.yaml is gitignored) ─────
for f in values.prod.yaml values.fe3455.yaml values.fe3455-prod.yaml values.fe3455-ory.yaml; do
  [ -f "$CHART_DIR/$f" ] || die "missing values file: $f  (values.fe3455-ory.yaml is gitignored — restore it locally before cutover)"
done
log "all 4 overlay value files present."

# ── 2. required Secrets present (NOT created here — they hold creds you provide) ─
kubectl -n "$NS" get secret zot-s3-creds >/dev/null 2>&1 \
  || die "Secret 'zot-s3-creds' missing in ns $NS — it holds the Beget S3 access/secret keys zot needs (keys AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY). Create it first, then re-run."
log "Secret zot-s3-creds present."

# ── 3. re-vendor sub-charts from committed Chart.lock (pins pg -> no data loss) ─
log "helm dependency build (respects Chart.lock; re-vendors ../kacho-registry@main S3/compat chart)…"
helm dependency build . >/dev/null \
  || die "helm dependency build failed. If a sibling chart version changed, run 'helm dependency update' manually, then re-confirm every postgresql pin in Chart.lock is 13.4.4 before re-running."

# ── 4. bitnami pg upgrade-guard --set args, read from pre-created Secrets ───────
#    Every pg-<svc> sets auth.existingSecret, so the chart already reads the password
#    from the Secret; these --set values are a defensive belt for the bitnami
#    passwords-on-upgrade guard. Correct value paths: auth.password (secret key
#    'password') + auth.postgresPassword (secret key 'postgres-password').
PG_SVCS=(vpc compute iam geo nlb storage registry openfga kratos hydra)
PGARGS=()
for svc in "${PG_SVCS[@]}"; do
  sec="kacho-umbrella-pg-$svc"
  if ! kubectl -n "$NS" get secret "$sec" >/dev/null 2>&1; then
    warn "Secret $sec absent — skipping pg-$svc guard args (chart will manage it)"
    continue
  fi
  pw="$(kubectl -n "$NS" get secret "$sec" -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || true)"
  apw="$(kubectl -n "$NS" get secret "$sec" -o jsonpath='{.data.postgres-password}' | base64 -d 2>/dev/null || true)"
  [ -n "$pw" ]  && PGARGS+=(--set "pg-$svc.auth.password=$pw")
  [ -n "$apw" ] && PGARGS+=(--set "pg-$svc.auth.postgresPassword=$apw")
done
log "built pg upgrade-guard --set args (${#PG_SVCS[@]} services scanned; values not echoed)."

# ── 5. the convergence upgrade ────────────────────────────────────────────────
log "helm upgrade $RELEASE — CONVERGE onto live images (--take-ownership adopts hand-applied resources)…"
if ! helm upgrade "$RELEASE" . -n "$NS" \
      -f values.prod.yaml \
      -f values.fe3455.yaml \
      -f values.fe3455-prod.yaml \
      -f values.fe3455-ory.yaml \
      --set uif.enabled=true \
      --take-ownership \
      --wait --timeout 15m \
      ${PGARGS[@]+"${PGARGS[@]}"}; then
  warn "helm upgrade FAILED."
  warn "Roll back to the previous good revision:   helm rollback $RELEASE -n $NS"
  warn "Inspect:   helm history $RELEASE -n $NS   |   kubectl -n $NS get pods"
  die  "cutover aborted (see above)."
fi
log "helm upgrade succeeded."

# ── 6. smoke check (registry + api-gateway + uif host rollout, then data-plane) ─
rc=0
log "smoke: rollout status (registry, api-gateway, uif host)…"
for d in registry api-gateway uif; do
  kubectl -n "$NS" rollout status deploy/"$d" --timeout=120s || { warn "rollout deploy/$d not complete"; rc=1; }
done
# storage is a fresh install on this cutover — surface its status too (non-fatal).
kubectl -n "$NS" rollout status deploy/kacho-umbrella-storage --timeout=120s \
  || warn "kacho-umbrella-storage not Ready yet (new storage-split install — check its logs)"

log "smoke: curl https://registry.in-cloud.io/v2/ (expect HTTP 401 token-auth challenge)…"
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 https://registry.in-cloud.io/v2/ || echo 000)"
if [ "$code" = "401" ]; then
  log "registry data-plane OK (HTTP 401 auth challenge as expected)."
else
  warn "registry /v2/ returned HTTP $code (expected 401) — check registry pod, zot, and the JWKS terminator."
  rc=1
fi

if [ "$rc" -eq 0 ]; then
  log "CUTOVER COMPLETE — release converged onto the live stack, smoke green."
else
  warn "CUTOVER upgrade applied, but smoke checks had warnings (see above) — investigate before declaring done."
fi
exit "$rc"
