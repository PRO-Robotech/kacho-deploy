#!/usr/bin/env bash
# dataplane-up.sh — bring up the data-plane add-ons the kacho-vpc-operator
# materializes into: Multus (secondary-CNI dispatcher) + Kube-OVN (OVN/OVS as a
# NON_PRIMARY secondary CNI behind kindnet). Idempotent. Runs AFTER the umbrella
# helm release (the operator + its mTLS client-cert come from cert-manager-config).
#
# These live in `kube` (data-plane infra) and do NOT participate in the Kachō
# mTLS mesh — only the operator (kacho stack-adjacent) is on mTLS.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-kacho}"
KUBEOVN_VERSION="${KUBEOVN_VERSION:-v1.16.1}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

NODE="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"
NODE_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
echo "=== data-plane on node ${NODE} (${NODE_IP}) ==="

# ── Multus (thin) — NetworkAttachmentDefinition CRD + DaemonSet in kacho-multus ──
echo "--- multus ---"
kubectl create namespace kacho-multus --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -k "${HERE}/argo-apps/multus" >/dev/null
echo "multus applied"

# ── Kube-OVN — secondary CNI (NON_PRIMARY behind kindnet) ───────────────────────
echo "--- kube-ovn ${KUBEOVN_VERSION} ---"
kubectl label node "${NODE}" kube-ovn/role=master --overwrite >/dev/null
kubectl create namespace kacho-kube-ovn --dry-run=client -o yaml | kubectl apply -f - >/dev/null
helm repo add kubeovn https://kubeovn.github.io/kube-ovn >/dev/null 2>&1 || true
helm repo update kubeovn >/dev/null 2>&1 || true
# MASTER_NODES MUST equal the master node InternalIP (computed above — the
# committed values.kind.yaml hardcodes a stale IP; --set overrides it).
helm upgrade --install kube-ovn kubeovn/kube-ovn \
  --version "${KUBEOVN_VERSION}" -n kacho-kube-ovn \
  -f "${HERE}/argo-apps/kube-ovn/values.kind.yaml" \
  --set MASTER_NODES="${NODE_IP}"
echo "kube-ovn applied (ovn-central + ovs-ovn may take ~1-2min to be Ready)"

# ── kacho-vpc-operator — wired to the Kachō control-plane over mTLS ──────────────
# (Materializes Kachō Subnets → KachoSubnet CRD → kube-ovn Subnet + Multus NAD.)
if [ -x "${HERE}/scripts/operator-up.sh" ]; then
  echo "--- kacho-vpc-operator ---"
  bash "${HERE}/scripts/operator-up.sh"
else
  echo "NOTE: scripts/operator-up.sh not present — operator not deployed by this script."
fi

echo "data-plane up."
