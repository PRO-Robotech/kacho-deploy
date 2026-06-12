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
# SEC-F-NS: the dev/kind mTLS overlay must DISABLE the public ACME PKI — the
# kacho-wildcard-tls Certificate targets the prod-only `kacho-system` ns (absent
# on a kind stand → `namespaces "kacho-system" not found` aborts the upgrade) and
# the letsencrypt issuers need a real domain + Cloudflare DNS-01. Only the
# cluster-internal CA stays on. (Prod keeps public PKI via values.prod.yaml.)
[ "$(yq '.["cert-manager-config"].certManager.certificates | length' "$OVL")" = "0" ] \
  || fail "SEC-F-NS: values.mtls.yaml must set cert-manager-config.certManager.certificates=[] (no public wildcard in kacho-system)"
ok
[ "$(yq '.["cert-manager-config"].certManager.issuers.prod.enabled' "$OVL")" = "false" ] \
  || fail "SEC-F-NS: values.mtls.yaml must disable letsencrypt-prod issuer in dev"
[ "$(yq '.["cert-manager-config"].certManager.issuers.staging.enabled' "$OVL")" = "false" ] \
  || fail "SEC-F-NS: values.mtls.yaml must disable letsencrypt-staging issuer in dev"
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

# ── КРИТ#1: server-cert serverHosts = REAL Service dial-hosts (not cert key) ──
# The dialed Service differs from the cert key for vpc/compute, and iam/nlb
# answer on a public + a cluster-internal Service. Assert the single-source
# serverHosts in values.yaml covers every real dial-host (∈ api-gateway
# backends.* + each svc peers.*). Renders are exercised by
# cert-manager-internal-ca-test.sh; here we lock the values contract.
ica='.["cert-manager-config"].certManager.internalCA.services'
host_has() { # host_has <svc-key> <host>
  yq "${ica}.[\"$1\"].serverHosts[]" "$U/values.yaml" | grep -qx "$2"; }
host_has kacho-vpc vpc          || fail "КРИТ#1: kacho-vpc serverHosts must include real dial-host 'vpc'"
host_has kacho-compute compute  || fail "КРИТ#1: kacho-compute serverHosts must include real dial-host 'compute'"
host_has kacho-iam kacho-iam            || fail "КРИТ#1: kacho-iam serverHosts must include 'kacho-iam'"
host_has kacho-iam kacho-iam-internal   || fail "КРИТ#1: kacho-iam serverHosts must include 'kacho-iam-internal' (every *→iam edge dials it)"
host_has kacho-nlb kacho-nlb            || fail "КРИТ#1: kacho-nlb serverHosts must include 'kacho-nlb'"
host_has kacho-nlb kacho-nlb-internal   || fail "КРИТ#1: kacho-nlb serverHosts must include 'kacho-nlb-internal'"
# vpc/compute keys must NOT carry the cert-key host (would be the pre-fix bug).
if yq "${ica}.[\"kacho-vpc\"].serverHosts[]" "$U/values.yaml" | grep -qx "kacho-vpc"; then
  fail "КРИТ#1: kacho-vpc serverHosts must NOT contain the cert key 'kacho-vpc' (Service is 'vpc')"; fi
ok

# ── КРИТ#3: values.mtls.yaml maps the umbrella intent into each subchart ──────
# Each subchart consumes its own mtls.* block; the overlay is the single place
# that materialises umbrella mtls.edges.* → subchart flags (КРИТ#2 renders them).
[ "$(yq '.["api-gateway"].mtls.enable' "$OVL")" = "true" ]        || fail "КРИТ#3: values.mtls.yaml must set api-gateway.mtls.enable"
[ "$(yq '.["api-gateway"].mtls.edges.iam' "$OVL")" = "true" ]     || fail "КРИТ#3: values.mtls.yaml must set api-gateway.mtls.edges.iam"
[ "$(yq '.["api-gateway"].mtls.edges.vpc' "$OVL")" = "true" ]     || fail "КРИТ#3: values.mtls.yaml must set api-gateway.mtls.edges.vpc"
[ "$(yq '.vpc.mtls.enable' "$OVL")" = "true" ]                    || fail "КРИТ#3: values.mtls.yaml must set vpc.mtls.enable (server)"
[ "$(yq '.vpc.mtls.edges.iamRegister' "$OVL")" = "true" ]         || fail "КРИТ#3: values.mtls.yaml must set vpc.mtls.edges.iamRegister (vpc_to_iam)"
# SEC-I: vpc read/authz iam edges must flip ON with vpc_to_iam (completeness — else
# the un-flipped edge's handshake fails under SEC-H RequireAndVerifyClientCert).
[ "$(yq '.vpc.mtls.edges.iamProject' "$OVL")" = "true" ]         || fail "SEC-I/КРИТ#3: values.mtls.yaml must set vpc.mtls.edges.iamProject (ProjectService.Get :9090)"
[ "$(yq '.vpc.mtls.edges.iamAuthz' "$OVL")" = "true" ]           || fail "SEC-I/КРИТ#3: values.mtls.yaml must set vpc.mtls.edges.iamAuthz (Check+list-filter :9091)"
[ "$(yq '.compute.mtls.enable' "$OVL")" = "true" ]               || fail "КРИТ#3: values.mtls.yaml must set compute.mtls.enable"
[ "$(yq '.compute.mtls.edges.iamRegister' "$OVL")" = "true" ]    || fail "КРИТ#3: values.mtls.yaml must set compute.mtls.edges.iamRegister"
[ "$(yq '.["kacho-nlb"].mtls.enable' "$OVL")" = "true" ]          || fail "КРИТ#3: values.mtls.yaml must set kacho-nlb.mtls.enable"
[ "$(yq '.["kacho-nlb"].mtls.edges.iamRegister' "$OVL")" = "true" ] || fail "КРИТ#3: values.mtls.yaml must set kacho-nlb.mtls.edges.iamRegister (nlb_to_iam)"
# SEC-H: kacho-iam server-side mTLS — the iam server terminates *_to_iam edges
# (gateway/vpc/compute/nlb all dial it), so the full-stack profile turns it on.
[ "$(yq '.["kacho-iam"].mtls.enable' "$OVL")" = "true" ]          || fail "SEC-H/КРИТ#3: values.mtls.yaml must set kacho-iam.mtls.enable (server, *_to_iam terminate here)"
ok
# Base values.yaml keeps each subchart mtls OFF / absent (zero dev regression).
for sub in vpc compute api-gateway kacho-nlb kacho-iam; do
  base="$(yq ".[\"$sub\"].mtls.enable // \"absent\"" "$U/values.yaml")"
  [ "$base" = "false" ] || [ "$base" = "absent" ] || fail "SEC-F-05: values.yaml $sub.mtls.enable must default off (got $base)"
done
dev_off="$(yq '.vpc.mtls.enable // "absent"' "$U/values.dev.yaml")"
[ "$dev_off" = "false" ] || [ "$dev_off" = "absent" ] || fail "SEC-F-05: values.dev.yaml must not enable vpc.mtls (got $dev_off)"
ok

# ── SEC-G — operator edges present in the mTLS overlay (operator→{vpc,iam}) ────
# The operator is a sibling (its own config/), so these are documentary INTENT
# flags in the overlay; the operator pod-spec env/mount live in
# kacho-vpc-operator/config. The full-stack profile turns both edges on.
for edge in operator_to_vpc operator_to_iam; do
  [ "$(yq ".mtls.edges.${edge}" "$OVL")" = "true" ] \
    || fail "SEC-G: values.mtls.yaml must enable edge ${edge}"
done
# Base values.yaml must NOT carry operator edges on (zero dev regression).
for edge in operator_to_vpc operator_to_iam; do
  b="$(yq ".mtls.edges.${edge} // \"absent\"" "$U/values.yaml")"
  [ "$b" = "false" ] || [ "$b" = "absent" ] || fail "SEC-G: values.yaml ${edge} must default off (got $b)"
done
ok

echo "PASS: $SCRIPT ($N assertions)"
