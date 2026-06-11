#!/usr/bin/env bash
# SEC-G-01/12 (S1/S3 DoD) — kacho-vpc-operator client-cert manifest assertions.
#
# Renders the cert-manager-config subchart standalone and asserts the operator
# gets its OWN client-cert (separate from the webhook server-cert, requirement
# #5) with the canonical SPIRE URI-SAN whose ns-segment is the operator's ACTUAL
# namespace (kacho-vpc-operator, §4.1.4) — NOT the core kacho/kacho-system ns.
# Manifest-assertion infra (SEC-F precedent: tests/helm/*-test.sh).
set -euo pipefail

SCRIPT="$(basename "$0")"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHART="${REPO_ROOT}/helm/umbrella/charts/cert-manager-config"
N=0
fail() { echo "FAIL: $1"; exit 1; }
ok() { N=$((N + 1)); }

# Render with internal-CA ENABLED (the mTLS / prod profile).
ON="$(helm template cmc "$CHART" \
  --set certManager.internalCA.enabled=true \
  --set spiffe.trustDomain=kacho.cloud \
  --set spiffe.namespace=kacho 2>/dev/null)"

# Render with internal-CA DISABLED (the dev default).
OFF="$(helm template cmc "$CHART" \
  --set certManager.internalCA.enabled=false \
  --set spiffe.trustDomain=kacho.cloud \
  --set spiffe.namespace=kacho 2>/dev/null)"

doc() { echo "$ON" | yq eval-all "select(.kind == \"$1\" and .metadata.name == \"$2\")" -; }
rendered() { echo "$2" | yq eval-all "$1" -; }
has_line() {
  local needle="$1" hay="$2" line
  while IFS= read -r line; do [ "$line" = "$needle" ] && return 0; done <<< "$hay"
  return 1
}

# ── SEC-G-01: operator client-cert exists, issued by internal CA ──────────────
cli="$(doc Certificate "vpc-operator-client-tls")"
[ -n "$cli" ] || fail "SEC-G-01: operator client Certificate vpc-operator-client-tls not rendered"
[ "$(echo "$cli" | yq '.spec.issuerRef.name')" = "kacho-internal-ca" ] \
  || fail "SEC-G-01: operator client-cert issuer != kacho-internal-ca"
ok

# ── §4.1.4: client-cert lands in the operator's OWN namespace (kacho-vpc-operator)
op_ns="$(echo "$cli" | yq '.metadata.namespace')"
[ "$op_ns" = "kacho-vpc-operator" ] \
  || fail "§4.1.4: operator client-cert must live in ns kacho-vpc-operator, got '$op_ns'"
ok

# ── §4.1.4: SPIRE URI-SAN with the operator's ACTUAL namespace segment ────────
cli_uris="$(echo "$cli" | yq '.spec.uris[]')"
want_san="spiffe://kacho.cloud/ns/kacho-vpc-operator/sa/kacho-vpc-operator"
has_line "$want_san" "$cli_uris" \
  || fail "§4.1.4: operator client-cert URI-SAN must be $want_san (got: $(echo "$cli_uris" | tr '\n' ',') )"
# The ns-segment must NOT be the core 'kacho' ns (would mismatch the SPIRE entry).
if has_line "spiffe://kacho.cloud/ns/kacho/sa/kacho-vpc-operator" "$cli_uris"; then
  fail "§4.1.4: operator SAN ns-segment must be kacho-vpc-operator, not core ns kacho"
fi
ok

# ── requirement #5: separate client / server certs (client-auth usage only) ───
[ "$(echo "$cli" | yq '.spec.secretName')" = "vpc-operator-client-tls" ] \
  || fail "#5: operator client secretName != vpc-operator-client-tls"
cli_usages="$(echo "$cli" | yq '.spec.usages[]')"
has_line "client auth" "$cli_usages" || fail "#5: operator client-cert missing 'client auth' usage"
if has_line "server auth" "$cli_usages"; then fail "#5: operator client-cert must not carry 'server auth'"; fi
# It must NOT share the webhook server-cert secret (webhook is a separate channel).
if [ "$(echo "$cli" | yq '.spec.secretName')" = "webhook-server-cert" ]; then
  fail "#5: operator client-cert must not reuse the webhook-server-cert secret"
fi
ok

# ── distinct identity: operator SAN differs from every core service SAN ────────
client_ids="$(rendered 'select(.kind=="Certificate" and (.metadata.name | test("-client-tls$"))) | .spec.uris[0]' "$ON" | grep '^spiffe://' | sort -u)"
distinct="$(printf '%s\n' "$client_ids" | sed '/^$/d' | wc -l | tr -d ' ')"
# 5 core services (api-gateway/iam/vpc/compute/nlb) + operator = 6 distinct ids.
[ "$distinct" = "6" ] || fail "SEC-G-01: expected 6 distinct client spiffe ids (5 core + operator), got $distinct"
ok

# ── internal-CA OFF → operator client-cert not rendered (dev = insecure) ───────
[ -z "$(rendered 'select(.kind=="Certificate" and .metadata.name=="vpc-operator-client-tls")' "$OFF")" ] \
  || fail "SEC-G-03: operator client-cert rendered while internalCA.enabled=false"
ok

echo "PASS: $SCRIPT ($N assertions)"
