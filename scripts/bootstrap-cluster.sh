#!/usr/bin/env bash
#
# KAC-127 Phase 11 — Production cluster bootstrap.
# Provisions a single Kachō production cluster from scratch.
# Idempotent — safe to re-run.
#
# Required environment variables:
#   KACHO_DOMAIN       — e.g. api.kacho.cloud
#   KACHO_REGION       — e.g. prod-eu-central or prod-eu-west
#   CLOUD_PROVIDER     — aws|gcp|azure|onprem
#   AWS_REGION         — only when CLOUD_PROVIDER=aws
#   CF_API_TOKEN       — Cloudflare API token
#   COSIGN_PUBLIC_KEY  — PEM-encoded cosign public key
#
# Usage:
#   ./bootstrap-cluster.sh
#
set -euo pipefail

: "${KACHO_DOMAIN:?KACHO_DOMAIN must be set, e.g. api.kacho.cloud}"
: "${KACHO_REGION:?KACHO_REGION must be set, e.g. prod-eu-central}"
: "${CLOUD_PROVIDER:?CLOUD_PROVIDER must be set (aws|gcp|azure|onprem)}"
: "${CF_API_TOKEN:?CF_API_TOKEN must be set (Cloudflare API token)}"
: "${COSIGN_PUBLIC_KEY:?COSIGN_PUBLIC_KEY must be set (PEM-encoded)}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UMBRELLA_CHART="${REPO_ROOT}/helm/umbrella"
OVERRIDES_FILE="${REPO_ROOT}/clusters/${KACHO_REGION}/overrides.yaml"

if [[ ! -f "${OVERRIDES_FILE}" ]]; then
  echo "ERROR: cluster overrides file ${OVERRIDES_FILE} not found" >&2
  echo "       run from a workspace that has clusters/${KACHO_REGION}/overrides.yaml" >&2
  exit 1
fi

log() { printf '[bootstrap] %s\n' "$*" >&2; }

# --- Step 1: Verify CLI dependencies ----------------------------------
for tool in kubectl helm argocd cosign jq curl; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "ERROR: ${tool} not found in PATH" >&2
    exit 1
  fi
done

# --- Step 2: Create core namespaces -----------------------------------
log "Creating core namespaces..."
for ns in cert-manager cloudflare-system kacho-system spire-system observability-system argocd-system cosign-system sealed-secrets-system; do
  kubectl get ns "${ns}" >/dev/null 2>&1 || kubectl create namespace "${ns}"
done

# --- Step 3: Install platform addons ----------------------------------
log "Installing cert-manager controller..."
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set installCRDs=true \
  --set prometheus.servicemonitor.enabled=true \
  --wait

log "Installing ingress-nginx..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace --wait

# --- Step 4: Apply prerequisite secrets -------------------------------
log "Applying Cloudflare API token secret..."
kubectl create secret generic cloudflare-api-token \
  --namespace cloudflare-system \
  --from-literal=token="${CF_API_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic cert-manager-cloudflare-token \
  --namespace cert-manager \
  --from-literal=token="${CF_API_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Applying cosign trusted key secret..."
echo "${COSIGN_PUBLIC_KEY}" | kubectl create secret generic cosign-trusted-key \
  --namespace cosign-system --from-file=cosign.pub=/dev/stdin \
  --dry-run=client -o yaml | kubectl apply -f -

# --- Step 5: Install ArgoCD + ArgoRollouts ----------------------------
log "Installing ArgoCD HA..."
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd-system \
  --set server.replicas=3 \
  --set redis-ha.enabled=true \
  --set repoServer.replicas=3 \
  --set controller.replicas=3 \
  --wait

log "Installing ArgoRollouts..."
kubectl apply -k "https://github.com/argoproj/argo-rollouts/manifests/cluster-install?ref=v1.7.2"

# --- Step 6: Install Kachō umbrella -----------------------------------
log "Resolving helm dependencies..."
helm dependency update "${UMBRELLA_CHART}"

log "Installing kacho umbrella chart for region=${KACHO_REGION}, domain=${KACHO_DOMAIN}..."
helm upgrade --install kacho "${UMBRELLA_CHART}" \
  --namespace kacho-system \
  -f "${UMBRELLA_CHART}/values.yaml" \
  -f "${UMBRELLA_CHART}/values.prod.yaml" \
  -f "${OVERRIDES_FILE}" \
  --set kacho.domain="${KACHO_DOMAIN}" \
  --set kacho.region="${KACHO_REGION}" \
  --timeout 30m \
  --wait

# --- Step 7: Verify smoke ---------------------------------------------
log "Verifying cluster health..."
not_ready_count=$(kubectl get pods -A --field-selector=status.phase!=Running --no-headers 2>/dev/null | grep -cv '^$' || true)
if [[ "${not_ready_count}" -gt 0 ]]; then
  echo "WARNING: ${not_ready_count} pods not in Running phase. Inspect with: kubectl get pods -A | grep -v Running" >&2
fi

log "Bootstrap complete for region=${KACHO_REGION}."
log "Next steps:"
log "  1. Apply ArgoCD AppProject + Applications: kubectl apply -k ${REPO_ROOT}/helm/umbrella/charts/argo-cd/templates/"
log "  2. Wait for syncs: argocd app wait -l kacho.cloud/environment=${KACHO_REGION} --timeout 1800"
log "  3. Run smoke tests per docs/deploy-production.md §6."
