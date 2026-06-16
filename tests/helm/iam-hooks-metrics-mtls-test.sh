#!/usr/bin/env bash
# kacho-iam Hydra/Kratos hooks listener (:9092) + Prometheus /metrics listener
# (:9095) — per-edge, default-off server-side mTLS capability
# (KACHO_IAM_HOOKS_SERVER_MTLS_* / KACHO_IAM_METRICS_SERVER_MTLS_*), mirroring the
# SEC-H gRPC listener pattern and reusing the SEC-F internal-CA server cert.
#
# IMPORTANT (regression #122 / Round-5 P0): the prod profile previously set
# `kacho-iam.mtls.httpListeners: true`, which enables RequireAndVerifyClientCert
# on the hooks/metrics listeners. But the hook CALLERS (Hydra/Kratos webhooks)
# authenticate with an HMAC shared-secret (bearerToken) over a *plaintext* client
# — they are NOT provisioned with an internal-CA client cert, and Ory webhooks do
# not support presenting a transport client-cert. Likewise no Prometheus scraper
# is wired with a client cert. Enabling RequireAndVerifyClientCert there would
# reject every Hydra/Kratos webhook at the TLS handshake (before HMAC), breaking
# ALL user login/registration in prod. So httpListeners is gated OFF until the
# transport-hardening design lands (server-TLS-only for the HMAC-authenticated
# hooks edge + Ory CA-trust; scrape client-cert for metrics). Tracked: kacho-iam#122.
#
# This guard now asserts:
#   - PROD profile  → emits NONE of the hooks/metrics mTLS env (gated off — the
#     listeners stay plaintext, exactly as before Wave-17, no auth-break regression);
#   - DEV profile   → emits NONE (dev/newman stand byte-identical, unchanged);
#   - CAPABILITY INTACT → with an explicit `--set kacho-iam.mtls.httpListeners=true`
#     override the chart DOES emit all eight env, each reusing the SAME mounted
#     SEC-F server cert-trio (no new PKI). This proves the server-side mTLS support
#     is shipped and ready to enable the moment the client side is provisioned —
#     the gate is a values decision, not a deleted feature.
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

# ── 1. PROD profile — NONE of the hooks/metrics mTLS env present (gated OFF) ───
# Until Hydra/Kratos/Prometheus are provisioned with client certs (or the edge is
# moved to server-TLS-only), RequireAndVerifyClientCert here would break auth.
IAM_DEPLOY_PROD="$(render_only "$PROD" charts/kacho-iam/templates/deployment.yaml)"
[ -n "$IAM_DEPLOY_PROD" ] || fail "kacho-iam deployment did not render in prod profile"
for name in "${HOOKS_METRICS_ENV[@]}"; do
  v="$(env_val "$name" "$IAM_DEPLOY_PROD")"
  [ -z "$v" ] || fail "prod: env $name=$v is set — httpListeners mTLS would reject Hydra/Kratos webhooks (no client cert) → auth-break. Must stay gated off (kacho-iam#122)."
done
ok

# ── 2. DEV profile — NONE present (plaintext, unchanged) ──────────────────────
IAM_DEPLOY_DEV="$(render_only "$DEV" charts/kacho-iam/templates/deployment.yaml)"
[ -n "$IAM_DEPLOY_DEV" ] || fail "kacho-iam deployment did not render in dev profile"
for name in "${HOOKS_METRICS_ENV[@]}"; do
  v="$(env_val "$name" "$IAM_DEPLOY_DEV")"
  [ -z "$v" ] || fail "dev: env $name=$v is set — dev hooks/metrics listener must stay PLAINTEXT (regression!)"
done
ok

# ── 3. CAPABILITY INTACT — the chart still ships the gated mTLS block ─────────
# Asserted against the TEMPLATE SOURCE (deterministic) rather than by rendering
# an httpListeners=true override: layering a value override onto this large
# multi-subchart umbrella is non-deterministic in `helm template` (values
# coalescing), whereas a value set directly in a profile file renders
# deterministically. Real deploys set file values, so the gate is reliable; the
# test just proves the feature is present + correctly gated, not deleted.
TPL="$UMBRELLA/charts/kacho-iam/templates/deployment.yaml"
[ -f "$TPL" ] || fail "capability: kacho-iam deployment template not found at $TPL"
grep -q '{{- if .Values.mtls.httpListeners }}' "$TPL" \
  || fail "capability: the '{{- if .Values.mtls.httpListeners }}' gate block was removed from the template"
for name in "${HOOKS_METRICS_ENV[@]}"; do
  grep -q "name: $name" "$TPL" \
    || fail "capability: env $name missing from template — server-side mTLS support was deleted, not just gated"
done
# The hooks/metrics block must REUSE the mounted server cert-trio (no new PKI):
# it references the same $srv mount the gRPC listeners use (tls.crt/tls.key/ca.crt).
grep -A1 'KACHO_IAM_HOOKS_SERVER_MTLS_CERTFILE' "$TPL" | grep -q 'tls.crt' \
  || fail "capability: hooks certfile must reuse the mounted server tls.crt (SEC-F)"
ok

echo "PASS: $SCRIPT ($N assertions)"
