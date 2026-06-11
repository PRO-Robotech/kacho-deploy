#!/usr/bin/env bash
# SEC-F-05/06/07/09/14 — mTLS values-profile + spiffe single-source + NLB
# spire-registration alignment.
#
# The umbrella can't be `helm template`d offline (needs sibling-chart checkouts +
# `helm dep update`), so these assert the values structure with `yq` directly and
# inspect the static spire-registration files (watched by the spire-server
# registration-job, not rendered by helm). NEW manifest-assertion infra.
set -euo pipefail

SCRIPT="$(basename "$0")"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
U="${REPO_ROOT}/helm/umbrella"
N=0
fail() { echo "FAIL: $1"; exit 1; }
ok() { N=$((N + 1)); }

# ── SEC-F-05: default mtls.enabled=false in base + dev values ─────────────────
[ "$(yq '.mtls.enabled' "$U/values.yaml")" = "false" ] || fail "SEC-F-05: values.yaml mtls.enabled must default false"
ok
# dev profile must not flip mTLS on (zero regression).
dev_mtls="$(yq '.mtls.enabled // "absent"' "$U/values.dev.yaml")"
[ "$dev_mtls" = "false" ] || [ "$dev_mtls" = "absent" ] || fail "SEC-F-05: values.dev.yaml must not enable mTLS (got $dev_mtls)"
ok

# ── SEC-F-07: per-edge flags exist (default off) ─────────────────────────────
for edge in gateway_to_vpc gateway_to_compute gateway_to_iam gateway_to_nlb vpc_to_iam compute_to_iam nlb_to_iam; do
  v="$(yq ".mtls.edges.${edge}" "$U/values.yaml")"
  [ "$v" = "false" ] || fail "SEC-F-07: mtls.edges.${edge} must exist and default false (got $v)"
  ok
done

# ── SEC-F-06: values.mtls.yaml overlay flips mTLS + all edges on ─────────────
OVL="$U/values.mtls.yaml"
[ -f "$OVL" ] || fail "SEC-F-06: values.mtls.yaml overlay missing"
[ "$(yq '.mtls.enabled' "$OVL")" = "true" ] || fail "SEC-F-06: values.mtls.yaml must set mtls.enabled=true"
ok
for edge in gateway_to_vpc gateway_to_compute gateway_to_iam gateway_to_nlb vpc_to_iam compute_to_iam nlb_to_iam; do
  [ "$(yq ".mtls.edges.${edge}" "$OVL")" = "true" ] || fail "SEC-F-06: values.mtls.yaml must enable edge ${edge}"
  ok
done
# Overlay must also turn on the internal-CA + openfga NetworkPolicy.
[ "$(yq '.["cert-manager-config"].certManager.internalCA.enabled' "$OVL")" = "true" ] \
  || fail "SEC-F-06: values.mtls.yaml must enable cert-manager-config.certManager.internalCA"
[ "$(yq '.["cert-manager-config"].enabled' "$OVL")" = "true" ] \
  || fail "SEC-F-06: values.mtls.yaml must enable cert-manager-config subchart"
ok

# ── SEC-F-09/04: spiffe.namespace single-source; svc→spiffeId table ──────────
NS="$(yq '.spiffe.namespace' "$U/values.yaml")"
[ -n "$NS" ] && [ "$NS" != "null" ] || fail "SEC-F-09: spiffe.namespace single-source missing in values.yaml"
ok
TD="$(yq '.spiffe.trustDomain' "$U/values.yaml")"
[ "$TD" = "kacho.cloud" ] || fail "SEC-F-04: spiffe.trustDomain must be kacho.cloud (got $TD)"
ok
# cert-manager-config gets the same spiffe block (pass-through so SANs use single-source).
[ "$(yq '.["cert-manager-config"].spiffe.namespace' "$U/values.yaml")" = "$NS" ] \
  || fail "SEC-F-09: cert-manager-config.spiffe.namespace must match top-level spiffe.namespace"
ok
# internalCA.services lists the 5 canonical services (kacho-nlb, NOT loadbalancer).
svcs="$(yq -o=json '.["cert-manager-config"].certManager.internalCA.services' "$U/values.yaml" | yq 'keys | .[]' 2>/dev/null | sort | tr '\n' ',')"
for s in api-gateway kacho-iam kacho-vpc kacho-compute kacho-nlb; do
  echo ",$svcs" | grep -q ",$s," || fail "SEC-F-02: internalCA.services missing $s (got: $svcs)"
done
if echo ",$svcs" | grep -q ",kacho-loadbalancer,"; then fail "SEC-F-02: internalCA.services must use kacho-nlb, not legacy kacho-loadbalancer"; fi
ok

# ── SEC-F-04/§4.1.6: NLB spire-registration aligned to kacho-nlb ─────────────
NLB_REG="$U/spire-registration/kacho-nlb.yaml"
[ -f "$NLB_REG" ] || fail "SEC-F-04: spire-registration/kacho-nlb.yaml missing (renamed from kacho-loadbalancer)"
[ ! -f "$U/spire-registration/kacho-loadbalancer.yaml" ] || fail "SEC-F-04: legacy spire-registration/kacho-loadbalancer.yaml must be removed"
ok
grep -q "sa/kacho-nlb" "$NLB_REG" || fail "SEC-F-04: kacho-nlb registration must carry sa/kacho-nlb spiffe id"
if grep -q "sa/kacho-loadbalancer" "$NLB_REG"; then fail "SEC-F-04: kacho-nlb registration must not reference kacho-loadbalancer"; fi
ok

# All spire-registration entries use the single-source namespace ns/<NS>.
for f in "$U"/spire-registration/kacho-vpc.yaml "$U"/spire-registration/kacho-compute.yaml \
         "$U"/spire-registration/kacho-iam.yaml "$U"/spire-registration/kacho-api-gateway.yaml "$NLB_REG"; do
  grep -q "ns/${NS}/sa/" "$f" || fail "SEC-F-09: $(basename "$f") spiffe id must use single-source ns/${NS} (got != ns/${NS})"
done
ok

# values.yaml registrations table (spire-server) aligned to kacho-nlb + ns/<NS>.
# Capture first (no pipe into grep -q → no SIGPIPE-under-pipefail flakiness).
reg_ids="$(yq '.["spire-server"].registrations.entries[].spiffeId' "$U/values.yaml")"
case "$reg_ids" in
  *"ns/${NS}/sa/kacho-nlb"*) : ;;
  *) fail "SEC-F-04: spire-server registrations must include ns/${NS}/sa/kacho-nlb" ;;
esac
case "$reg_ids" in
  *"sa/kacho-loadbalancer"*) fail "SEC-F-04: spire-server registrations must not reference kacho-loadbalancer" ;;
esac
ok

echo "PASS: $SCRIPT ($N assertions)"
