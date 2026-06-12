#!/usr/bin/env bash
# SEC-F-12/14 — "openfga ingress only from kacho-iam" NetworkPolicy assertions.
#
# Renders the kacho-iam subchart standalone (precedent: networkpolicy-audit.yaml
# lives here, uses app.kubernetes.io/name selectors). NEW manifest-assertion infra.
set -euo pipefail

SCRIPT="$(basename "$0")"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHART="${REPO_ROOT}/helm/umbrella/charts/kacho-iam"
N=0
fail() { echo "FAIL: $1"; exit 1; }
ok() { N=$((N + 1)); }

# has_line <needle> <multiline> — exact whole-line membership without piping into
# `grep -q` (grep -q closes the pipe on first match → SIGPIPE upstream → flaky
# failure under `set -o pipefail`).
has_line() {
  local needle="$1" hay="$2" line
  while IFS= read -r line; do [ "$line" = "$needle" ] && return 0; done <<< "$hay"
  return 1
}

ON="$(helm template iam "$CHART" \
  --set audit.networkPolicy.openfgaIngressFromIamOnly.enabled=true 2>/dev/null)"
OFF="$(helm template iam "$CHART" \
  --set audit.networkPolicy.openfgaIngressFromIamOnly.enabled=false 2>/dev/null)"

P="$(echo "$ON" | yq eval-all 'select(.kind=="NetworkPolicy" and (.spec.podSelector.matchLabels."app.kubernetes.io/name"=="openfga"))' -)"
P_OFF="$(echo "$OFF" | yq eval-all 'select(.kind=="NetworkPolicy" and (.spec.podSelector.matchLabels."app.kubernetes.io/name"=="openfga"))' -)"

# ── SEC-F-12: policy exists, selects openfga, Ingress, from iam only ──────────
[ -n "$P" ] || fail "SEC-F-12: openfga NetworkPolicy not rendered (flag on)"
ok

[ "$(echo "$P" | yq '.spec.podSelector.matchLabels."app.kubernetes.io/name"')" = "openfga" ] \
  || fail "SEC-F-12: podSelector must target app.kubernetes.io/name=openfga (not app=)"
ok

policy_types="$(echo "$P" | yq '.spec.policyTypes[]')"
has_line "Ingress" "$policy_types" || fail "SEC-F-12: policyTypes must include Ingress"
ok

# ingress.from must select ONLY kacho-iam by app.kubernetes.io/name.
from_names="$(echo "$P" | yq '.spec.ingress[].from[].podSelector.matchLabels."app.kubernetes.io/name"' | grep -v '^null$' | grep -v '^$' | sort -u)"
[ "$from_names" = "kacho-iam" ] || fail "SEC-F-12: ingress.from must be exactly [kacho-iam], got: $(echo "$from_names" | tr '\n' ',')"
ok

# No legacy app= *selectors* (acceptance §4.1.6) — scoped to pod/ingress
# selectors, not metadata.labels (those legitimately carry app: per the shared
# kacho-iam.labels helper).
[ -z "$(echo "$P" | yq '.spec.podSelector.matchLabels.app // ""')" ] \
  || fail "SEC-F-12: podSelector must not use legacy 'app:' label"
[ -z "$(echo "$P" | yq '[.spec.ingress[].from[].podSelector.matchLabels.app] | map(select(. != null)) | .[]')" ] \
  || fail "SEC-F-12: ingress.from must not use legacy 'app:' label"
ok

# A FGA port is constrained (gRPC 8081 and/or HTTP 8080).
ports="$(echo "$P" | yq '.spec.ingress[].ports[].port')"
{ has_line "8080" "$ports" || has_line "8081" "$ports"; } \
  || fail "SEC-F-12: ingress must constrain a FGA port (8080/8081)"
ok

# ── SEC-F-12 (bootstrap): the OpenFGA provisioning hook must reach FGA ────────
# The store+model bootstrap (helm post-install Job, label
# kacho.cloud/component=openfga-bootstrap) seeds OpenFGA over HTTP. The
# iam-only allowlist would otherwise BLOCK it (helm --wait hangs on the hook →
# install never completes). It is provisioning infra, not a runtime FGA dialer,
# so it is allowed by its OWN component label (NOT app.kubernetes.io/name, which
# stays exactly [kacho-iam] above) and only on the HTTP port — least-privilege.
boot_from="$(echo "$P" | yq '[.spec.ingress[].from[].podSelector.matchLabels."kacho.cloud/component"] | map(select(. != null)) | .[]' 2>/dev/null)"
has_line "openfga-bootstrap" "$boot_from" \
  || fail "SEC-F-12: ingress must allow the openfga-bootstrap provisioning hook (kacho.cloud/component=openfga-bootstrap)"
ok

# ── SEC-F-12/14: flag off → policy absent (no failure window before SEC-D) ────
[ -z "$P_OFF" ] || fail "SEC-F-12: openfga NetworkPolicy rendered while flag off"
ok

echo "PASS: $SCRIPT ($N assertions)"
