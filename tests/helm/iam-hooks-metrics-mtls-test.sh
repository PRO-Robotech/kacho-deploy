#!/usr/bin/env bash
# P0 hardening — the kacho-iam Hydra/Kratos hooks listener (:9092) and the
# Prometheus /metrics listener (:9095) were served over PLAINTEXT. The serving
# binary now supports per-edge, default-off server-side mTLS
# (KACHO_IAM_HOOKS_SERVER_MTLS_* / KACHO_IAM_METRICS_SERVER_MTLS_*), mirroring the
# SEC-H gRPC listener pattern and reusing the SEC-F internal-CA server cert.
#
# This guard asserts the deploy contract:
#   - PROD profile (mtls.enable=true) emits the four hooks + four metrics mTLS
#     env vars, each pointing at the SAME mounted server cert-trio that the gRPC
#     listeners already use (<mountPath>/server/{tls.crt,tls.key,ca.crt}) — no
#     new PKI;
#   - DEV profile (mtls.enable=false) emits NONE of them → listeners stay
#     PLAINTEXT (dev/newman stand byte-identical, zero regression).
#
# Offline manifest-assertion harness (no kind cluster). Mirrors tests/helm/*.
set -euo pipefail

SCRIPT="$(basename "$0")"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UMBRELLA="$REPO_ROOT/helm/umbrella"
PROD="$UMBRELLA/values.prod.yaml"
DEV="$UMBRELLA/values.dev.yaml"
N=0
fail() { echo "FAIL: $1"; exit 1; }
ok() { N=$((N + 1)); }

[ -f "$PROD" ] || fail "values.prod.yaml not found at $PROD"
[ -f "$DEV" ]  || fail "values.dev.yaml not found at $DEV"

render_only() {
  helm template kacho-umbrella "$UMBRELLA" -f "$1" --show-only "$2" 2>/dev/null
}
# env_val <ENV_NAME> <render> — value of the named container env entry ("" if absent).
env_val() {
  echo "$2" | yq eval-all \
    "select(.kind==\"Deployment\") | .spec.template.spec.containers[].env[] | select(.name==\"$1\") | .value" -
}

HOOKS_METRICS_ENV=(
  KACHO_IAM_HOOKS_SERVER_MTLS_ENABLE
  KACHO_IAM_HOOKS_SERVER_MTLS_CERTFILE
  KACHO_IAM_HOOKS_SERVER_MTLS_KEYFILE
  KACHO_IAM_HOOKS_SERVER_MTLS_CLIENTCAFILES
  KACHO_IAM_METRICS_SERVER_MTLS_ENABLE
  KACHO_IAM_METRICS_SERVER_MTLS_CERTFILE
  KACHO_IAM_METRICS_SERVER_MTLS_KEYFILE
  KACHO_IAM_METRICS_SERVER_MTLS_CLIENTCAFILES
)

# ── 1. PROD profile — hooks + metrics mTLS env present, reusing SEC-F cert ────
IAM_DEPLOY_PROD="$(render_only "$PROD" charts/kacho-iam/templates/deployment.yaml)"
[ -n "$IAM_DEPLOY_PROD" ] || fail "kacho-iam deployment did not render in prod profile"

for name in "${HOOKS_METRICS_ENV[@]}"; do
  v="$(env_val "$name" "$IAM_DEPLOY_PROD")"
  [ -n "$v" ] || fail "prod: env $name is missing on kacho-iam (hooks/metrics listener still plaintext)"
done
ok

# enable flags must be "true" in prod.
[ "$(env_val KACHO_IAM_HOOKS_SERVER_MTLS_ENABLE "$IAM_DEPLOY_PROD")" = "true" ] \
  || fail "prod: KACHO_IAM_HOOKS_SERVER_MTLS_ENABLE != true"
[ "$(env_val KACHO_IAM_METRICS_SERVER_MTLS_ENABLE "$IAM_DEPLOY_PROD")" = "true" ] \
  || fail "prod: KACHO_IAM_METRICS_SERVER_MTLS_ENABLE != true"; ok

# Cert paths must REUSE the existing mounted server cert-trio (no new PKI): the
# same <mountPath>/server/{tls.crt,tls.key,ca.crt} the gRPC listeners use.
pub_cert="$(env_val KACHO_IAM_PUBLIC_SERVER_MTLS_CERTFILE "$IAM_DEPLOY_PROD")"
pub_key="$(env_val KACHO_IAM_PUBLIC_SERVER_MTLS_KEYFILE "$IAM_DEPLOY_PROD")"
pub_ca="$(env_val KACHO_IAM_PUBLIC_SERVER_MTLS_CLIENTCAFILES "$IAM_DEPLOY_PROD")"
[ -n "$pub_cert" ] || fail "prod: gRPC public cert path missing — cannot verify cert reuse"
for prefix in HOOKS METRICS; do
  c="$(env_val "KACHO_IAM_${prefix}_SERVER_MTLS_CERTFILE" "$IAM_DEPLOY_PROD")"
  k="$(env_val "KACHO_IAM_${prefix}_SERVER_MTLS_KEYFILE" "$IAM_DEPLOY_PROD")"
  a="$(env_val "KACHO_IAM_${prefix}_SERVER_MTLS_CLIENTCAFILES" "$IAM_DEPLOY_PROD")"
  [ "$c" = "$pub_cert" ] || fail "prod: ${prefix} certfile=$c != gRPC server certfile=$pub_cert (must reuse SEC-F cert)"
  [ "$k" = "$pub_key" ]  || fail "prod: ${prefix} keyfile=$k != gRPC server keyfile=$pub_key (must reuse SEC-F cert)"
  [ "$a" = "$pub_ca" ]   || fail "prod: ${prefix} clientcafiles=$a != gRPC server ca=$pub_ca (must reuse SEC-F cert)"
done
ok

# ── 2. DEV profile — NONE of the hooks/metrics mTLS env present (plaintext) ───
IAM_DEPLOY_DEV="$(render_only "$DEV" charts/kacho-iam/templates/deployment.yaml)"
[ -n "$IAM_DEPLOY_DEV" ] || fail "kacho-iam deployment did not render in dev profile"
for name in "${HOOKS_METRICS_ENV[@]}"; do
  v="$(env_val "$name" "$IAM_DEPLOY_DEV")"
  [ -z "$v" ] || fail "dev: env $name=$v is set — dev hooks/metrics listener must stay PLAINTEXT (regression!)"
done
ok

echo "PASS: $SCRIPT ($N assertions)"
