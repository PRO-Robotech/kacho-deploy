#!/usr/bin/env bash
# cert-manager-up.sh — install the cert-manager controller (jetstack chart) so the
# umbrella's cert-manager-config subchart (internal-CA PKI for cluster-internal
# mTLS, values.mtls.yaml) can create ClusterIssuer/Certificate objects. Idempotent
# (re-run safe). Must run BEFORE `helm upgrade` of the umbrella in the MTLS=on
# profile (the Certificates need the cert-manager CRDs + webhook present).
set -euo pipefail

CM_VERSION="${CM_VERSION:-v1.20.2}"
echo "=== cert-manager ${CM_VERSION} (jetstack) ==="

if helm -n cert-manager status cert-manager >/dev/null 2>&1; then
  echo "cert-manager already installed — skipping"
else
  helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
  helm repo update jetstack >/dev/null 2>&1 || true
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager --create-namespace \
    --version "${CM_VERSION}" \
    --set crds.enabled=true \
    --wait --timeout 5m
fi

echo "Waiting for cert-manager webhook to be ready..."
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=120s
echo "cert-manager ready."
