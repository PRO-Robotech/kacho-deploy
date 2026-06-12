#!/usr/bin/env bash
# SEC-F-01/02/03/04/14 — internal-CA PKI manifest assertions.
#
# Renders the cert-manager-config subchart standalone (no kind cluster, no
# sibling-chart checkout) and asserts the internal-CA issuer chain + per-service
# Certificate ×2 with the correct SANs. NEW manifest-assertion infra (SEC-F
# §«Тест-харнессы») — there is no precedent S7.1.
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

doc() { # doc <kind> <name> — extract one yaml doc from $ON by kind+name
  echo "$ON" | yq eval-all "select(.kind == \"$1\" and .metadata.name == \"$2\")" -
}

# has_line <needle> <multiline-value> — exact whole-line membership without a
# pipe into `grep -q`. (`grep -q` closes the pipe on first match → SIGPIPE to
# the upstream yq → under `set -o pipefail` the pipeline reports failure
# nondeterministically. Capturing first and matching with a glob avoids the race.)
has_line() {
  local needle="$1" hay="$2" line
  while IFS= read -r line; do [ "$line" = "$needle" ] && return 0; done <<< "$hay"
  return 1
}

# rendered <yq-expr> <stream> — capture yq output (no pipe into grep -q, avoids
# the SIGPIPE-under-pipefail race). Returns the (possibly empty) text.
rendered() { echo "$2" | yq eval-all "$1" -; }

# ── SEC-F-01: bootstrap selfSigned root → CA-root Certificate → CA-issuer ──────
si="$(doc ClusterIssuer kacho-selfsigned)"
[ -n "$si" ] || fail "SEC-F-01: ClusterIssuer/kacho-selfsigned not rendered (internal-CA on)"
[ "$(echo "$si" | yq '.spec.selfSigned != null')" = "true" ] \
  || fail "SEC-F-01: kacho-selfsigned is not a selfSigned issuer"
ok

# Exactly ONE selfSigned issuer (do not breed a second overlapping one).
selfsigned_names="$(rendered 'select(.kind == "ClusterIssuer" and .spec.selfSigned != null) | .metadata.name' "$ON" | sed '/^$/d')"
selfsigned_count="$(printf '%s\n' "$selfsigned_names" | sed '/^$/d' | wc -l | tr -d ' ')"
[ "$selfsigned_count" = "1" ] || fail "SEC-F-01: expected exactly 1 selfSigned ClusterIssuer, got $selfsigned_count"
ok

ca_root="$(doc Certificate kacho-internal-ca-root)"
[ -n "$ca_root" ] || fail "SEC-F-01: CA-root Certificate/kacho-internal-ca-root not rendered"
[ "$(echo "$ca_root" | yq '.spec.isCA')" = "true" ] || fail "SEC-F-01: CA-root Certificate must have isCA=true"
[ "$(echo "$ca_root" | yq '.spec.issuerRef.name')" = "kacho-selfsigned" ] \
  || fail "SEC-F-01: CA-root must be issued by kacho-selfsigned"
ok

# SEC-F-NS (КРИТ install): a CA-type ClusterIssuer reads its ca.secretName from
# the cert-manager controller's cluster-resource-namespace (default `cert-manager`,
# `--cluster-resource-namespace=$(POD_NAMESPACE)`). The CA-root Certificate (whose
# secret the issuer consumes) MUST therefore be created IN that namespace — not in
# the wildcard cert's `kacho-system` (which doesn't even exist on the dev stand and
# broke `make dev-up MTLS=on` with `namespaces "kacho-system" not found`).
ca_root_ns="$(echo "$ca_root" | yq '.metadata.namespace')"
[ "$ca_root_ns" = "cert-manager" ] \
  || fail "SEC-F-NS: CA-root Certificate must live in cert-manager (cluster-resource-namespace), got '$ca_root_ns'"
ok

ca_issuer="$(doc ClusterIssuer kacho-internal-ca)"
[ -n "$ca_issuer" ] || fail "SEC-F-01: ClusterIssuer/kacho-internal-ca not rendered"
[ "$(echo "$ca_issuer" | yq '.spec.ca != null')" = "true" ] \
  || fail "SEC-F-01: kacho-internal-ca must be type ca (spec.ca), not acme"
[ "$(echo "$ca_issuer" | yq '.spec.acme')" = "null" ] || fail "SEC-F-01: kacho-internal-ca must NOT be acme"
[ -n "$(echo "$ca_issuer" | yq '.spec.ca.secretName')" ] || fail "SEC-F-01: kacho-internal-ca must reference a CA secretName"
ok

# ── SEC-F-02/03/04: per-service Certificate ×2, separate secrets, SANs ─────────
for svc in api-gateway kacho-iam kacho-vpc kacho-compute kacho-nlb; do
  srv="$(doc Certificate "${svc}-server-tls")"
  cli="$(doc Certificate "${svc}-client-tls")"
  [ -n "$srv" ] || fail "SEC-F-02: server Certificate ${svc}-server-tls missing"
  [ -n "$cli" ] || fail "SEC-F-02: client Certificate ${svc}-client-tls missing"

  # Separate secrets (requirement #5).
  ssec="$(echo "$srv" | yq '.spec.secretName')"
  csec="$(echo "$cli" | yq '.spec.secretName')"
  [ "$ssec" = "${svc}-server-tls" ] || fail "SEC-F-02: ${svc} server secretName=$ssec"
  [ "$csec" = "${svc}-client-tls" ] || fail "SEC-F-02: ${svc} client secretName=$csec"
  [ "$ssec" != "$csec" ] || fail "SEC-F-02: ${svc} server/client share a secret"

  # SEC-F-NS (КРИТ install): a leaf-cert secret is mounted by the consuming pod,
  # so it MUST live in that pod's namespace = spiffe.namespace (`kacho` here), NOT
  # the wildcard's `kacho-system`. A secret in the wrong namespace is invisible to
  # the pod (mount fails / pod never reads the cert).
  srv_ns="$(echo "$srv" | yq '.metadata.namespace')"
  cli_ns="$(echo "$cli" | yq '.metadata.namespace')"
  [ "$srv_ns" = "kacho" ] || fail "SEC-F-NS: ${svc}-server-tls must live in pod ns 'kacho', got '$srv_ns'"
  [ "$cli_ns" = "kacho" ] || fail "SEC-F-NS: ${svc}-client-tls must live in pod ns 'kacho', got '$cli_ns'"

  # Both issued by the internal CA.
  [ "$(echo "$srv" | yq '.spec.issuerRef.name')" = "kacho-internal-ca" ] || fail "SEC-F-02: ${svc}-server issuer != kacho-internal-ca"
  [ "$(echo "$cli" | yq '.spec.issuerRef.name')" = "kacho-internal-ca" ] || fail "SEC-F-02: ${svc}-client issuer != kacho-internal-ca"

  # rotationPolicy Always (SEC-F-02).
  [ "$(echo "$srv" | yq '.spec.privateKey.rotationPolicy')" = "Always" ] || fail "SEC-F-02: ${svc}-server rotationPolicy != Always"

  # usages (SEC-F-02): server has 'server auth'; client has 'client auth' only.
  srv_usages="$(echo "$srv" | yq '.spec.usages[]')"
  cli_usages="$(echo "$cli" | yq '.spec.usages[]')"
  has_line "server auth" "$srv_usages" || fail "SEC-F-02: ${svc}-server missing 'server auth' usage"
  has_line "client auth" "$cli_usages" || fail "SEC-F-02: ${svc}-client missing 'client auth' usage"
  if has_line "server auth" "$cli_usages"; then fail "SEC-F-02: ${svc}-client must not carry 'server auth'"; fi

  # SEC-F-03 / КРИТ#1 (assertion (a)): server-cert SAN ⊇ the ACTUAL dial-host of
  # every edge terminating at this server. The cert KEY (kacho-vpc) is NOT the
  # dial-host (the kacho-vpc deployment's Service is `vpc`; iam/nlb answer on a
  # public AND a cluster-internal Service). The client verifies its dial-host
  # ServerName against this SAN, so a key-derived SAN (the pre-КРИТ#1 bug) fails
  # the handshake for vpc/compute and misses the *-internal hosts for iam/nlb.
  # Expected dial-hosts (source: api-gateway backends.* + each svc peers.*):
  case "$svc" in
    kacho-vpc)     want_hosts="vpc" ;;
    kacho-compute) want_hosts="compute" ;;
    kacho-iam)     want_hosts="kacho-iam kacho-iam-internal" ;;
    kacho-nlb)     want_hosts="kacho-nlb kacho-nlb-internal" ;;
    api-gateway)   want_hosts="api-gateway" ;;
    *)             want_hosts="$svc" ;;
  esac
  srv_dns="$(echo "$srv" | yq '.spec.dnsNames[]')"
  for h in $want_hosts; do
    has_line "${h}.kacho.svc.cluster.local" "$srv_dns" \
      || fail "КРИТ#1: ${svc}-server SAN missing real dial-host ${h}.kacho.svc.cluster.local (got: $(echo "$srv_dns" | tr '\n' ',') )"
  done
  # The cert KEY must NOT leak into the SAN unless it is also a real dial-host
  # (guards against regressing to the key-derived SAN for vpc/compute).
  case "$svc" in
    kacho-vpc|kacho-compute)
      if has_line "${svc}.kacho.svc.cluster.local" "$srv_dns"; then
        fail "КРИТ#1: ${svc}-server SAN must use the Service dial-host, not the cert key ${svc}.*"
      fi ;;
  esac
  [ "$(echo "$srv" | yq '.spec.uris | length')" = "0" ] || fail "SEC-F-03: ${svc}-server must NOT carry URI-SAN"

  # SEC-F-04: client-cert URI-SAN = SPIRE-format spiffe id (sa-part = pod's SA,
  # MUST match spire-registration); trustDomain not hardcoded. api-gateway's SA
  # is kacho-api-gateway; the kacho-* services' SA == their name.
  case "$svc" in
    api-gateway) sa="kacho-api-gateway" ;;
    *)           sa="$svc" ;;
  esac
  cli_uris="$(echo "$cli" | yq '.spec.uris[]')"
  has_line "spiffe://kacho.cloud/ns/kacho/sa/${sa}" "$cli_uris" \
    || fail "SEC-F-04: ${svc}-client missing URI-SAN spiffe://kacho.cloud/ns/kacho/sa/${sa}"
  ok
done

# Distinct spiffe ids per service (personal identity, requirement #4). SEC-G adds
# a 6th client identity — the kacho-vpc-operator (client-only, separate ns/SAN).
client_ids="$(rendered 'select(.kind=="Certificate" and (.metadata.name | test("-client-tls$"))) | .spec.uris[0]' "$ON" | grep '^spiffe://' | sort -u)"
distinct="$(printf '%s\n' "$client_ids" | sed '/^$/d' | wc -l | tr -d ' ')"
[ "$distinct" = "6" ] || fail "SEC-F/G-04: expected 6 distinct client spiffe ids (5 core + vpc-operator), got $distinct"
ok

# SEC-G/NS: the vpc-operator is client-only and consumes its cert in its OWN
# namespace → its client-cert Certificate must be created in kacho-vpc-operator,
# and no server-cert is emitted for it.
op_cli="$(doc Certificate vpc-operator-client-tls)"
[ -n "$op_cli" ] || fail "SEC-G: vpc-operator-client-tls Certificate missing"
op_cli_ns="$(echo "$op_cli" | yq '.metadata.namespace')"
[ "$op_cli_ns" = "kacho-vpc-operator" ] \
  || fail "SEC-G/NS: vpc-operator-client-tls must live in kacho-vpc-operator ns, got '$op_cli_ns'"
[ -z "$(doc Certificate vpc-operator-server-tls)" ] || fail "SEC-G: vpc-operator must be client-only (no server cert)"
ok

# SEC-G/NS: the override namespace (kacho-vpc-operator) is NOT a release/subchart
# namespace and need not pre-exist when cert-manager creates the leaf there
# (→ `namespaces "kacho-vpc-operator" not found` broke `dev-up MTLS=on`). The
# chart MUST pre-create every per-service override namespace. The release pod-ns
# (kacho) and CA cluster-resource-namespace (cert-manager) are created elsewhere
# and must NOT be emitted here (helm would clash on an externally-owned ns).
op_ns_doc="$(doc Namespace kacho-vpc-operator)"
[ -n "$op_ns_doc" ] || fail "SEC-G/NS: Namespace/kacho-vpc-operator not rendered (cert would fail to place)"
[ -z "$(doc Namespace kacho)" ] || fail "SEC-G/NS: must NOT emit the release ns 'kacho' (externally owned)"
[ -z "$(doc Namespace cert-manager)" ] || fail "SEC-G/NS: must NOT emit 'cert-manager' ns (externally owned)"
ok

# ── SEC-F-14: external letsencrypt + wildcard untouched, additive ─────────────
[ -n "$(rendered 'select(.kind=="ClusterIssuer" and .metadata.name=="letsencrypt-prod")' "$ON")" ] \
  || fail "SEC-F-14: letsencrypt-prod ClusterIssuer disappeared"
[ -n "$(rendered 'select(.kind=="Certificate" and .metadata.name=="kacho-wildcard-tls")' "$ON")" ] \
  || fail "SEC-F-14: kacho-wildcard-tls Certificate disappeared"
ok

# ── SEC-F-14/05: internal-CA OFF → no internal-CA objects rendered ────────────
[ -z "$(rendered 'select(.kind=="ClusterIssuer" and .metadata.name=="kacho-internal-ca")' "$OFF")" ] \
  || fail "SEC-F-05: kacho-internal-ca rendered while internalCA.enabled=false"
[ -z "$(rendered 'select(.kind=="Certificate" and (.metadata.name | test("-server-tls$|-client-tls$")))' "$OFF")" ] \
  || fail "SEC-F-05: per-svc internal Certificates rendered while internalCA.enabled=false"
# letsencrypt still present when internal-CA off (additive, not a replacement).
[ -n "$(rendered 'select(.kind=="Certificate" and .metadata.name=="kacho-wildcard-tls")' "$OFF")" ] \
  || fail "SEC-F-05: external wildcard cert missing while internalCA off"
ok

echo "PASS: $SCRIPT ($N assertions)"
