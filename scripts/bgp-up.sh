#!/usr/bin/env bash
# bgp-up.sh — deploy the BGP routing PoC (OP2-P-BGP) into the kind cluster:
# a GoBGP route-reflector + the kube-ovn-speaker DaemonSet, so Kachō subnet
# CIDRs are delivered into routing via BGP instead of Vpc.spec.staticRoutes
# (which kube-ovn v1.16.1 strips on custom VPCs — kacho-vpc-operator#2).
#
# Runs AFTER kube-ovn is up. Idempotent (re-run safe). The kacho-vpc-operator
# already annotates each materialized kube-ovn Subnet with
# `ovn.kubernetes.io/bgp=cluster` (OP2-P-BGP S3) — the speaker advertises those.
#
# kind-dev-safe: refuses to run against a non-kind context.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-kacho}"
CTX="${CTX:-kind-${CLUSTER_NAME}}"
NS="${NS:-kacho-kube-ovn}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"          # kacho-deploy root
BGP_DIR="${HERE}/argo-apps/kube-ovn/bgp"

# ── kind-only safety guard ───────────────────────────────────────────────────
case "${CTX}" in
  kind-*) ;;
  *) echo "REFUSING: context '${CTX}' is not a kind-* context (kind-dev-safe only)." >&2; exit 1 ;;
esac

echo "--- label gateway node(s) ovn.kubernetes.io/bgp=true ---"
# Single-node kind: the control-plane node is the gateway node. Idempotent.
for n in $(kubectl --context "${CTX}" get nodes -o name); do
  kubectl --context "${CTX}" label "${n}" ovn.kubernetes.io/bgp=true --overwrite >/dev/null
done

echo "--- apply GoBGP route-reflector ---"
kubectl --context "${CTX}" apply -f "${BGP_DIR}/route-reflector.yaml"
kubectl --context "${CTX}" -n "${NS}" rollout status deploy/kube-ovn-bgp-rr --timeout=120s || true

# The speaker (hostNetwork) dials the RR pod IP DIRECTLY — node→podIP preserves the
# source (= node IP), unlike the ClusterIP path (kube-proxy SNAT broke peer
# identity). Pod IP is dynamic → resolve it and render into the speaker args,
# replacing the committed default 172.19.0.2.
RR_IP=""
for _ in $(seq 1 30); do
  RR_IP="$(kubectl --context "${CTX}" -n "${NS}" get pod -l app=kube-ovn-bgp-rr \
    -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)"
  [ -n "${RR_IP}" ] && break
  sleep 2
done
[ -n "${RR_IP}" ] || { echo "ERROR: route-reflector pod IP not resolved" >&2; exit 1; }
echo "--- route-reflector pod IP = ${RR_IP} ---"

echo "--- apply kube-ovn-speaker DaemonSet (neighbor=${RR_IP}) ---"
sed "s/172\\.19\\.0\\.2/${RR_IP}/g" "${BGP_DIR}/speaker.yaml" | kubectl --context "${CTX}" apply -f -

echo "--- wait for rollout ---"
kubectl --context "${CTX}" -n "${NS}" rollout status ds/kube-ovn-speaker --timeout=120s || true

cat <<EOF

BGP PoC up. Verify (see argo-apps/kube-ovn/bgp/README.md):
  # BGP session Established (speaker ↔ RR):
  kubectl -n ${NS} exec deploy/kube-ovn-bgp-rr -- gobgp neighbor
  # learned routes (Kachō subnet CIDRs advertised by the speaker):
  kubectl -n ${NS} exec deploy/kube-ovn-bgp-rr -- gobgp global rib
EOF
