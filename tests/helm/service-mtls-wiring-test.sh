#!/usr/bin/env bash
# SEC-F КРИТ#2/#3 (assertion (b)) — service-chart mTLS consumption wiring.
#
# Renders each sibling service chart (kacho-{vpc,compute,nlb,api-gateway}/deploy)
# standalone — both with mtls OFF (default) and ON — and asserts:
#   OFF → NO cert volume/mount, NO KACHO_*_MTLS_* env  (zero dev regression).
#   ON  → server-cert + client-cert secrets mounted (separate dirs, req #5) and
#         the per-edge env named exactly per corelib LoadPrefixed (SEC-B) /
#         api-gateway EdgeTLSClient (SEC-E).
#
# These charts are the source the umbrella vendors via file:// (КРИТ#3): a
# `helm dep update` repackages them, so flag→pod-spec proven here holds in the
# umbrella render too. NEW manifest-assertion infra (SEC-F §«Тест-харнессы»).
set -euo pipefail

SCRIPT="$(basename "$0")"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJ="$(cd "$REPO_ROOT/.." && pwd)"   # project/  (siblings live next to kacho-deploy)
N=0
fail() { echo "FAIL: $1"; exit 1; }
ok() { N=$((N + 1)); }

# Exact whole-line membership without piping into `grep -q` (grep -q closes the
# pipe on first match → SIGPIPE to upstream yq → flaky non-zero under pipefail;
# the sibling cert-manager-internal-ca-test.sh hit the same race). Capture first,
# match with a shell loop.
has_line() { local needle="$1" hay="$2" line; while IFS= read -r line; do [ "$line" = "$needle" ] && return 0; done <<< "$hay"; return 1; }
# has_env <ENV_NAME> <render> — true if a container env entry with that name exists.
has_env() { has_line "$1" "$(echo "$2" | yq eval-all 'select(.kind=="Deployment") | .spec.template.spec.containers[].env[]?.name' -)"; }
# has_vol <vol-name> <render>
has_vol() { has_line "$1" "$(echo "$2" | yq eval-all 'select(.kind=="Deployment") | .spec.template.spec.volumes[]?.name' -)"; }
# has_secret <secret-name> <render>
has_secret() { has_line "$1" "$(echo "$2" | yq eval-all 'select(.kind=="Deployment") | .spec.template.spec.volumes[]?.secret.secretName' -)"; }

# ─────────────────────────────────────────────────────────────────────────────
# kacho-vpc — corelib LoadPrefixed (KACHO_VPC_*), server (both listeners) +
# client edges iam-register + compute.
# ─────────────────────────────────────────────────────────────────────────────
VPC="$PROJ/kacho-vpc/deploy"
[ -d "$VPC" ] || fail "kacho-vpc chart not found at $VPC"
OFF="$(helm template vpc "$VPC" 2>/dev/null)"
ON="$(helm template vpc "$VPC" --set mtls.enable=true --set mtls.edges.iamRegister=true \
        --set mtls.edges.iamProject=true --set mtls.edges.iamAuthz=true \
        --set mtls.edges.compute=true 2>/dev/null)"

if has_env KACHO_VPC_PUBLIC_SERVER_MTLS_ENABLE "$OFF"; then fail "vpc OFF leaks server mTLS env"; fi
# SEC-I: OFF must NOT leak the new iam read/authz edge env (zero dev regression).
if has_env KACHO_VPC_IAM_PROJECT_MTLS_ENABLE "$OFF"; then fail "vpc OFF leaks iam-project mTLS env"; fi
if has_env KACHO_VPC_IAM_AUTHZ_MTLS_ENABLE "$OFF"; then fail "vpc OFF leaks iam-authz mTLS env"; fi
if has_vol mtls-server "$OFF"; then fail "vpc OFF leaks mtls-server volume"; fi; ok
for e in KACHO_VPC_PUBLIC_SERVER_MTLS_ENABLE KACHO_VPC_PUBLIC_SERVER_MTLS_CERTFILE \
         KACHO_VPC_PUBLIC_SERVER_MTLS_KEYFILE KACHO_VPC_PUBLIC_SERVER_MTLS_CLIENTCAFILES \
         KACHO_VPC_INTERNAL_SERVER_MTLS_ENABLE KACHO_VPC_INTERNAL_SERVER_MTLS_CLIENTCAFILES \
         KACHO_VPC_IAM_REGISTER_MTLS_ENABLE KACHO_VPC_IAM_REGISTER_MTLS_CAFILES KACHO_VPC_IAM_REGISTER_MTLS_SERVERNAME \
         KACHO_VPC_IAM_PROJECT_MTLS_ENABLE KACHO_VPC_IAM_PROJECT_MTLS_CAFILES KACHO_VPC_IAM_PROJECT_MTLS_SERVERNAME \
         KACHO_VPC_IAM_AUTHZ_MTLS_ENABLE KACHO_VPC_IAM_AUTHZ_MTLS_CAFILES KACHO_VPC_IAM_AUTHZ_MTLS_SERVERNAME \
         KACHO_VPC_COMPUTE_MTLS_ENABLE KACHO_VPC_COMPUTE_MTLS_SERVERNAME; do
  has_env "$e" "$ON" || fail "vpc ON missing env $e"
done; ok
has_secret kacho-vpc-server-tls "$ON" || fail "vpc ON missing server secret kacho-vpc-server-tls"
has_secret kacho-vpc-client-tls "$ON" || fail "vpc ON missing client secret kacho-vpc-client-tls"; ok
env_val_vpc() { echo "$1" | yq eval-all 'select(.kind=="Deployment") | .spec.template.spec.containers[].env[] | select(.name=="'"$2"'") | .value' -; }
# vpc→iam register server-name = the cluster-internal iam dial-host (КРИТ#1 ∈ iam SAN).
sn="$(env_val_vpc "$ON" KACHO_VPC_IAM_REGISTER_MTLS_SERVERNAME)"
[ "$sn" = "kacho-iam-internal.kacho.svc.cluster.local" ] || fail "vpc iam-register SERVERNAME=$sn (want kacho-iam-internal.*)"; ok
# SEC-I per-listener ServerName (I6): ProjectService.Get :9090 = kacho-iam.*,
# Check/list-filter :9091 = kacho-iam-internal.* — both ∈ iam server-SAN.
psn="$(env_val_vpc "$ON" KACHO_VPC_IAM_PROJECT_MTLS_SERVERNAME)"
[ "$psn" = "kacho-iam.kacho.svc.cluster.local" ] || fail "vpc iam-project SERVERNAME=$psn (want kacho-iam.*, :9090)"
asn="$(env_val_vpc "$ON" KACHO_VPC_IAM_AUTHZ_MTLS_SERVERNAME)"
[ "$asn" = "kacho-iam-internal.kacho.svc.cluster.local" ] || fail "vpc iam-authz SERVERNAME=$asn (want kacho-iam-internal.*, :9091)"
[ "$psn" != "$asn" ] || fail "vpc iam-project and iam-authz share a ServerName (not per-listener split, I6)"; ok
# I1: the new iam read/authz edges REUSE the already-mounted kacho-vpc-client-tls
# cert (same $cli dir as register) — no new secret/volume.
pcf="$(env_val_vpc "$ON" KACHO_VPC_IAM_PROJECT_MTLS_CERTFILE)"
rcf="$(env_val_vpc "$ON" KACHO_VPC_IAM_REGISTER_MTLS_CERTFILE)"
acf="$(env_val_vpc "$ON" KACHO_VPC_IAM_AUTHZ_MTLS_CERTFILE)"
[ "$pcf" = "$rcf" ] || fail "vpc iam-project certfile ($pcf) != register certfile ($rcf) — must reuse client cert (I1)"
[ "$acf" = "$rcf" ] || fail "vpc iam-authz certfile ($acf) != register certfile ($rcf) — must reuse client cert (I1)"; ok

# ─────────────────────────────────────────────────────────────────────────────
# kacho-compute — KACHO_COMPUTE_*; server + client edges iam-register + vpc +
# SEC-I iam read/authz (iam-project ProjectService.Get :9090, iam-authz
# Check+list-filter :9091).
# ─────────────────────────────────────────────────────────────────────────────
CMP="$PROJ/kacho-compute/deploy"
[ -d "$CMP" ] || fail "kacho-compute chart not found at $CMP"
OFF="$(helm template compute "$CMP" 2>/dev/null)"
ON="$(helm template compute "$CMP" --set mtls.enable=true \
        --set mtls.edges.iamRegister=true --set mtls.edges.iamProject=true \
        --set mtls.edges.iamAuthz=true --set mtls.edges.vpc=true 2>/dev/null)"
if has_env KACHO_COMPUTE_PUBLIC_SERVER_MTLS_ENABLE "$OFF"; then fail "compute OFF leaks server mTLS env"; fi
# SEC-I: OFF must NOT leak the new iam read/authz edge env (zero dev regression).
if has_env KACHO_COMPUTE_IAM_PROJECT_MTLS_ENABLE "$OFF"; then fail "compute OFF leaks iam-project mTLS env"; fi
if has_env KACHO_COMPUTE_IAM_AUTHZ_MTLS_ENABLE "$OFF"; then fail "compute OFF leaks iam-authz mTLS env"; fi; ok
for e in KACHO_COMPUTE_PUBLIC_SERVER_MTLS_ENABLE KACHO_COMPUTE_PUBLIC_SERVER_MTLS_CLIENTCAFILES \
         KACHO_COMPUTE_INTERNAL_SERVER_MTLS_ENABLE \
         KACHO_COMPUTE_IAM_REGISTER_MTLS_ENABLE KACHO_COMPUTE_IAM_REGISTER_MTLS_SERVERNAME \
         KACHO_COMPUTE_IAM_PROJECT_MTLS_ENABLE KACHO_COMPUTE_IAM_PROJECT_MTLS_CAFILES KACHO_COMPUTE_IAM_PROJECT_MTLS_SERVERNAME \
         KACHO_COMPUTE_IAM_AUTHZ_MTLS_ENABLE KACHO_COMPUTE_IAM_AUTHZ_MTLS_CAFILES KACHO_COMPUTE_IAM_AUTHZ_MTLS_SERVERNAME \
         KACHO_COMPUTE_VPC_MTLS_ENABLE KACHO_COMPUTE_VPC_MTLS_SERVERNAME; do
  has_env "$e" "$ON" || fail "compute ON missing env $e"
done; ok
has_secret kacho-compute-server-tls "$ON" || fail "compute ON missing server secret"
has_secret kacho-compute-client-tls "$ON" || fail "compute ON missing client secret"; ok
sn="$(echo "$ON" | yq eval-all 'select(.kind=="Deployment") | .spec.template.spec.containers[].env[] | select(.name=="KACHO_COMPUTE_VPC_MTLS_SERVERNAME") | .value' -)"
[ "$sn" = "vpc.kacho.svc.cluster.local" ] || fail "compute vpc SERVERNAME=$sn (want vpc.*)"; ok
# SEC-I per-listener ServerName (I6): ProjectService.Get :9090 = kacho-iam.*,
# Check/list-filter :9091 = kacho-iam-internal.* — both ∈ iam server-SAN.
env_val() { echo "$1" | yq eval-all 'select(.kind=="Deployment") | .spec.template.spec.containers[].env[] | select(.name=="'"$2"'") | .value' -; }
psn="$(env_val "$ON" KACHO_COMPUTE_IAM_PROJECT_MTLS_SERVERNAME)"
[ "$psn" = "kacho-iam.kacho.svc.cluster.local" ] || fail "compute iam-project SERVERNAME=$psn (want kacho-iam.*, :9090)"
asn="$(env_val "$ON" KACHO_COMPUTE_IAM_AUTHZ_MTLS_SERVERNAME)"
[ "$asn" = "kacho-iam-internal.kacho.svc.cluster.local" ] || fail "compute iam-authz SERVERNAME=$asn (want kacho-iam-internal.*, :9091)"
[ "$psn" != "$asn" ] || fail "compute iam-project and iam-authz share a ServerName (not per-listener split, I6)"; ok
# I1: the new iam read/authz edges REUSE the already-mounted kacho-compute-client-tls
# cert (same $cli dir as register) — no new secret/volume.
pcf="$(env_val "$ON" KACHO_COMPUTE_IAM_PROJECT_MTLS_CERTFILE)"
rcf="$(env_val "$ON" KACHO_COMPUTE_IAM_REGISTER_MTLS_CERTFILE)"
[ "$pcf" = "$rcf" ] || fail "compute iam-project certfile ($pcf) != register certfile ($rcf) — must reuse client cert (I1)"; ok

# ─────────────────────────────────────────────────────────────────────────────
# kacho-nlb — viper mtls.* config block in config.yaml ConfigMap + cert mounts.
# ─────────────────────────────────────────────────────────────────────────────
NLB="$PROJ/kacho-nlb/deploy"
[ -d "$NLB" ] || fail "kacho-nlb chart not found at $NLB"
OFF="$(helm template nlb "$NLB" --set db.password=x 2>/dev/null)"
ON="$(helm template nlb "$NLB" --set db.password=x --set mtls.enable=true \
        --set mtls.edges.iamRegister=true --set mtls.edges.iamProject=true \
        --set mtls.edges.vpc=true --set mtls.edges.compute=true 2>/dev/null)"
# OFF: config.yaml has no top-level mtls section + no cert volume.
off_cfg="$(echo "$OFF" | yq eval-all 'select(.kind=="ConfigMap") | .data["config.yaml"]' -)"
[ "$(echo "$off_cfg" | yq '.mtls // "absent"' -)" = "absent" ] || fail "nlb OFF config has mtls section"
if has_vol mtls-server "$OFF"; then fail "nlb OFF leaks mtls-server volume"; fi; ok
on_cfg="$(echo "$ON" | yq eval-all 'select(.kind=="ConfigMap") | .data["config.yaml"]' -)"
[ "$(echo "$on_cfg" | yq '.mtls.server.enable' -)" = "true" ] || fail "nlb ON config mtls.server.enable != true"
# SEC-I: BOTH iam read/authz edges present a client-cert with PER-LISTENER
# ServerNames — internal :9091 (Check+Register) = kacho-iam-internal.*, public
# :9090 (ProjectService.Get) = kacho-iam.* (I6 / latent-bug D-04 fix).
[ "$(echo "$on_cfg" | yq '.mtls.["iam-register"].enable' -)" = "true" ] || fail "nlb ON config mtls.iam-register.enable != true"
[ "$(echo "$on_cfg" | yq '.mtls.["iam-register"].servername' -)" = "kacho-iam-internal.kacho.svc.cluster.local" ] \
  || fail "nlb iam-register servername wrong (want kacho-iam-internal.*, :9091 Check+Register)"
[ "$(echo "$on_cfg" | yq '.mtls.["iam-project"].enable' -)" = "true" ] || fail "nlb ON config mtls.iam-project.enable != true"
[ "$(echo "$on_cfg" | yq '.mtls.["iam-project"].servername' -)" = "kacho-iam.kacho.svc.cluster.local" ] \
  || fail "nlb iam-project servername wrong (want kacho-iam.*, :9090 ProjectService.Get)"
# Per-listener split: the two iam edges must NOT share a ServerName (D-04).
[ "$(echo "$on_cfg" | yq '.mtls.["iam-project"].servername' -)" != "$(echo "$on_cfg" | yq '.mtls.["iam-register"].servername' -)" ] \
  || fail "nlb iam-project and iam-register share a ServerName (D-04: not per-listener split)"
# iam-project reuses the SAME client cert as the register edge (no new secret, I1).
[ "$(echo "$on_cfg" | yq '.mtls.["iam-project"].certfile' -)" = "$(echo "$on_cfg" | yq '.mtls.["iam-register"].certfile' -)" ] \
  || fail "nlb iam-project must reuse the kacho-nlb-client-tls cert ($cli), not a new mount"
[ "$(echo "$on_cfg" | yq '.mtls.vpc.servername' -)" = "vpc.kacho.svc.cluster.local" ] || fail "nlb vpc servername wrong"
[ "$(echo "$on_cfg" | yq '.mtls.compute.servername' -)" = "compute.kacho.svc.cluster.local" ] || fail "nlb compute servername wrong"; ok
# OFF must NOT render the iam-project read edge.
[ "$(echo "$off_cfg" | yq '.mtls.["iam-project"] // "absent"' -)" = "absent" ] || fail "nlb OFF leaks iam-project mtls edge"; ok
has_secret kacho-nlb-server-tls "$ON" || fail "nlb ON missing server secret"
has_secret kacho-nlb-client-tls "$ON" || fail "nlb ON missing client secret"; ok

# ─────────────────────────────────────────────────────────────────────────────
# api-gateway — backend-dial client; shared client cert + per-edge ENABLE,
# SERVER_NAME intentionally unset (derived per dial-host, covers pub+internal).
# ─────────────────────────────────────────────────────────────────────────────
AGW="$PROJ/kacho-api-gateway/deploy"
[ -d "$AGW" ] || fail "kacho-api-gateway chart not found at $AGW"
OFF="$(helm template ag "$AGW" 2>/dev/null)"
ON="$(helm template ag "$AGW" --set mtls.enable=true \
        --set mtls.edges.vpc=true --set mtls.edges.compute=true \
        --set mtls.edges.iam=true --set mtls.edges.nlb=true 2>/dev/null)"
if has_env KACHO_API_GATEWAY_MTLS_CLIENT_CERT_FILE "$OFF"; then fail "api-gateway OFF leaks mTLS env"; fi; ok
for e in KACHO_API_GATEWAY_MTLS_CLIENT_CERT_FILE KACHO_API_GATEWAY_MTLS_CLIENT_KEY_FILE KACHO_API_GATEWAY_MTLS_CA_FILE \
         KACHO_API_GATEWAY_MTLS_VPC_ENABLE KACHO_API_GATEWAY_MTLS_COMPUTE_ENABLE \
         KACHO_API_GATEWAY_MTLS_IAM_ENABLE KACHO_API_GATEWAY_MTLS_NLB_ENABLE; do
  has_env "$e" "$ON" || fail "api-gateway ON missing env $e"
done; ok
has_secret api-gateway-client-tls "$ON" || fail "api-gateway ON missing client secret api-gateway-client-tls"; ok
# SERVER_NAME overrides must NOT be emitted (derive per dial-host so the iam/nlb
# edges verify against BOTH public and internal dial-hosts — КРИТ#1).
for e in KACHO_API_GATEWAY_MTLS_IAM_SERVER_NAME KACHO_API_GATEWAY_MTLS_NLB_SERVER_NAME \
         KACHO_API_GATEWAY_MTLS_VPC_SERVER_NAME KACHO_API_GATEWAY_MTLS_COMPUTE_SERVER_NAME; do
  if has_env "$e" "$ON"; then fail "api-gateway must NOT set $e (derive per dial-host, КРИТ#1)"; fi
done; ok
# api-gateway still terminates EXTERNAL TLS (regression: tls secret coexists).
has_secret api-gateway-tls "$ON" || fail "api-gateway external TLS secret disappeared under mTLS"; ok

# ─────────────────────────────────────────────────────────────────────────────
# kacho-iam — SEC-H server-side mTLS on BOTH gRPC listeners (public :9090 +
# internal :9091). corelib LoadPrefixed (KACHO_IAM_*). IAM is a leaf-owner: no
# outgoing peer-dial edges in scope, so SEC-H wires the SERVER only (no client
# secret/edges). The subchart lives IN the umbrella (file://./charts/kacho-iam),
# not a sibling deploy/ dir — render it standalone the same way.
# ─────────────────────────────────────────────────────────────────────────────
IAM="$REPO_ROOT/helm/umbrella/charts/kacho-iam"
[ -d "$IAM" ] || fail "kacho-iam subchart not found at $IAM"
OFF="$(helm template iam "$IAM" 2>/dev/null)"
ON="$(helm template iam "$IAM" --set mtls.enable=true 2>/dev/null)"

# OFF (default): zero dev regression — no server mTLS env, no cert volume/secret.
if has_env KACHO_IAM_PUBLIC_SERVER_MTLS_ENABLE "$OFF"; then fail "iam OFF leaks server mTLS env"; fi; ok
if has_vol mtls-server "$OFF"; then fail "iam OFF leaks mtls-server volume"; fi
if has_secret kacho-iam-server-tls "$OFF"; then fail "iam OFF leaks kacho-iam-server-tls secret"; fi; ok
# ON: full server cert-trio env for BOTH listeners (8 keys) + cert mount + secret.
for e in KACHO_IAM_PUBLIC_SERVER_MTLS_ENABLE KACHO_IAM_PUBLIC_SERVER_MTLS_CERTFILE \
         KACHO_IAM_PUBLIC_SERVER_MTLS_KEYFILE KACHO_IAM_PUBLIC_SERVER_MTLS_CLIENTCAFILES \
         KACHO_IAM_INTERNAL_SERVER_MTLS_ENABLE KACHO_IAM_INTERNAL_SERVER_MTLS_CERTFILE \
         KACHO_IAM_INTERNAL_SERVER_MTLS_KEYFILE KACHO_IAM_INTERNAL_SERVER_MTLS_CLIENTCAFILES; do
  has_env "$e" "$ON" || fail "iam ON missing env $e"
done; ok
has_vol mtls-server "$ON" || fail "iam ON missing mtls-server volume"
has_secret kacho-iam-server-tls "$ON" || fail "iam ON missing server secret kacho-iam-server-tls"; ok
# server cert-trio env points at the mounted server-cert dir (tls.crt/tls.key/ca.crt).
cf="$(echo "$ON" | yq eval-all 'select(.kind=="Deployment") | .spec.template.spec.containers[].env[] | select(.name=="KACHO_IAM_INTERNAL_SERVER_MTLS_CERTFILE") | .value' -)"
[ "$cf" = "/etc/kacho-iam/tls/server/tls.crt" ] || fail "iam INTERNAL_SERVER_MTLS_CERTFILE=$cf (want /etc/kacho-iam/tls/server/tls.crt)"; ok

echo "PASS: $SCRIPT ($N assertions)"
