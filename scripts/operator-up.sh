#!/usr/bin/env bash
# operator-up.sh — build + load + deploy the kacho-vpc-operator into the kind
# cluster. The operator is the data-plane materializer: its ingress poll-syncers
# mirror Kachō Subnets/Projects into the cluster-scoped KachoSubnet CRD, and its
# egress controller-runtime Reconciler materializes each KachoSubnet into
# N×(kube-ovn Subnet + Multus NAD) — one per CIDR (dual-stack policy A) — owned
# via OwnerReferences + finalizer (cascade-on-delete, prune-on-CIDR-removal).
#
# Runs AFTER the umbrella helm release (the operator's mTLS client-cert
# `vpc-operator-client-tls` is issued by cert-manager-config) and AFTER kube-ovn
# + Multus CRDs are present (dataplane-up.sh applies them just before this).
# Idempotent (re-run safe). Deploy unit = `kubectl apply -k config/dev`
# (CRD + RBAC + both operator binaries + SEC-G mTLS overlay + Pod webhook).
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-kacho}"
CTX="${CTX:-kind-${CLUSTER_NAME}}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"          # kacho-deploy root
PROJECT_DIR="$(cd "${HERE}/.." && pwd)"           # project/ (sibling repos)
OP_DIR="${PROJECT_DIR}/kacho-vpc-operator"
IMG="kacho-vpc-operator:dev"

if [ ! -d "${OP_DIR}" ]; then
  echo "NOTE: ${OP_DIR} not present — skipping operator deploy."
  exit 0
fi

# ── build + kind-load the operator image ────────────────────────────────────
# Build-context MUST be the project parent dir so the Dockerfile can COPY both
# ../kacho-proto and ../kacho-corelib (go.mod replace ../). Mirrors the Makefile
# service-image pattern (build-svc-images).
echo "--- build ${IMG} ---"
( cd "${PROJECT_DIR}" && docker build -f kacho-vpc-operator/Dockerfile -t "${IMG}" . )
echo "--- kind load ${IMG} → ${CLUSTER_NAME} ---"
kind load docker-image "${IMG}" --name "${CLUSTER_NAME}"

# ── namespace (cert-manager-config also emits it; create idempotently in case
#    operator-up runs standalone) ─────────────────────────────────────────────
kubectl --context "${CTX}" create namespace kacho-vpc-operator \
  --dry-run=client -o yaml | kubectl --context "${CTX}" apply -f - >/dev/null

# ── Pod mutating webhook cert (self-signed → Secret + MutatingWebhookConfig).
#    cert-manager is NOT used for the webhook (failurePolicy=Ignore, scoped to
#    project namespaces). ─────────────────────────────────────────────────────
echo "--- webhook cert ---"
CTX="${CTX}" bash "${OP_DIR}/scripts/deploy-webhook.sh"

# ── RBAC bundle (Namespace + SA + ClusterRole + ClusterRoleBinding) ──────────
# Applied via `-f` (NOT kustomize): kustomize's load-restrictor refuses a raw
# file above the config/dev root, and config/rbac as a whole drags in a
# controller-manager SA in the non-existent `system` namespace. `kubectl -f`
# has no such restriction. Idempotent.
echo "--- RBAC bundle ---"
kubectl --context "${CTX}" apply -f "${OP_DIR}/config/rbac/role.yaml"

# ── deploy: KachoSubnet CRD + both operator binaries + mTLS overlay ──────────
echo "--- kubectl apply -k config/dev ---"
kubectl --context "${CTX}" apply -k "${OP_DIR}/config/dev"

# ── wait for rollout (best-effort; mTLS client-cert / CRDs may settle async) ──
echo "--- rollout ---"
kubectl --context "${CTX}" -n kacho-vpc-operator rollout status deploy/kacho-vpc-operator --timeout=120s || true
kubectl --context "${CTX}" -n kacho-vpc-operator rollout status deploy/kacho-project-operator --timeout=120s || true

echo "kacho-vpc-operator up."
