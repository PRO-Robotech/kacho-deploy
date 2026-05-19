# Kachō — Production deployment guide

**Phase**: 11 (KAC-127 Phase 11 — production-ready next-gen).
**Audience**: SRE / platform engineers responsible for first-time production
cluster bring-up OR per-tenant cluster provisioning.
**Last reviewed**: 2026-05-19.

> Kachō is deployed as a **multi-region active-active platform** via Helm +
> Argo CD GitOps. This guide assumes you have **operator-level access** to
> the cloud provider (AWS / GCP / Azure / on-prem k8s), Cloudflare account,
> domain registrar, and a PagerDuty/Slack tenant.

---

## 0. Prerequisites (operator-provided)

The following items the platform cannot self-provision. They MUST exist before
running `helm install`. Each item below is a **gate** — failures here are
not platform bugs.

| Item | Owner | How to verify |
|---|---|---|
| **Domain** registered + NS delegated to Cloudflare | DNS / SRE | `dig +short NS your-domain.example.com` returns Cloudflare NS |
| **Cloudflare account** with Pro/Enterprise plan + API token (Zone:DNS:Edit + WAF:Edit + Access:Edit) | SRE | `curl -H "Authorization: Bearer $TOKEN" https://api.cloudflare.com/client/v4/user/tokens/verify` returns `success:true` |
| **Cloud account** + IAM credentials for each region (eu-central-1 + eu-west-1) | Cloud Ops | `aws sts get-caller-identity` per profile |
| **S3 buckets** for: postgres-backups, traces, metrics, logs, audit-cold, kafka-mm2 — per region | Cloud Ops | `aws s3 ls s3://kacho-{component}-{region}-prod` returns OK |
| **HSM** for SPIRE root CA + audit batch signing (AWS CloudHSM / GCP Cloud HSM / Azure Key Vault HSM) | Security | HSM endpoint reachable from cluster, PKCS#11 library available |
| **PagerDuty service** + API integration key | SRE | Dashboard shows incident-management routes |
| **Slack workspace** + bot token with `chat:write` scope, channels `#kacho-iam-page`, `#kacho-iam-alerts`, `#kacho-iam-info`, `#kacho-deploy` | SRE | `curl -d "channel=#kacho-iam-page&text=test" -H "Authorization: Bearer $SLACK_TOKEN" https://slack.com/api/chat.postMessage` returns `ok:true` |
| **GitHub** repos for kacho-iam, kacho-vpc, kacho-compute, etc — with CI configured per `supply-chain.md` runbook | Platform Engineering | Each repo has signed images at `ghcr.io/pro-robotech/kacho-<svc>` |
| **Cosign private key** (`cosign.key` + password) stored in Vault | Platform Engineering | `cosign public-key --key vault://secret/cosign.key` returns PEM |
| **HSTS preload submission** — domain submitted to https://hstspreload.org/ | Security | Manual one-time, expected lag 6-12 weeks |
| **SOC 2 / pentest** engagements contracted (Phase 12 deliverable, not Phase 11 gate) | Compliance | Out-of-band |

---

## 1. Bootstrap cluster (per region)

For each region (`prod-eu-central`, `prod-eu-west`):

```bash
# 1.1 Create EKS/GKE/AKS cluster.
eksctl create cluster \
  --name kacho-${REGION} \
  --region ${REGION} \
  --version 1.30 \
  --nodegroup-name kacho-platform \
  --node-type m6i.2xlarge \
  --nodes 6 \
  --nodes-min 3 \
  --nodes-max 24 \
  --node-private-networking \
  --node-volume-size 200 \
  --node-volume-type gp3 \
  --asg-access \
  --external-dns-access \
  --full-ecr-access \
  --alb-ingress-access \
  --node-labels "topology.kubernetes.io/zone=${REGION}a"
```

```bash
# 1.2 Install platform addons (CNI, cert-manager controller, ingress-nginx).
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true \
  --set prometheus.servicemonitor.enabled=true

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace
```

```bash
# 1.3 Install Cloudflare Crossplane provider (if using Crossplane GitOps).
kubectl apply -f https://raw.githubusercontent.com/crossplane-contrib/provider-cloudflare/main/package/crossplane.yaml
kubectl wait --for=condition=healthy --timeout=5m provider/provider-cloudflare
```

```bash
# 1.4 Install ArgoCD + ArgoRollouts.
kubectl create namespace argocd-system
helm install argocd argo/argo-cd \
  --namespace argocd-system \
  --set server.replicaCount=3 \
  --set redis-ha.enabled=true \
  --set repoServer.replicas=3 \
  -f helm/umbrella/charts/argo-cd/values.yaml

kubectl apply -k https://github.com/argoproj/argo-rollouts/manifests/cluster-install
```

---

## 2. Apply secrets (external-secrets-operator or sealed-secrets)

```bash
# 2.1 Cloudflare API token.
kubectl create namespace cloudflare-system
kubectl create secret generic cloudflare-api-token \
  --namespace cloudflare-system \
  --from-literal=token="$(vault kv get -field=token secret/kacho/prod/cloudflare)"

# 2.2 cert-manager DNS-01 secret.
kubectl create secret generic cert-manager-cloudflare-token \
  --namespace cert-manager \
  --from-literal=token="$(vault kv get -field=token secret/kacho/prod/cloudflare)"

# 2.3 PagerDuty + Slack integration.
kubectl create namespace observability-system
kubectl create secret generic alertmanager-pagerduty-key \
  --namespace observability-system \
  --from-literal=service_key="$(vault kv get -field=key secret/kacho/prod/pagerduty)"
kubectl create secret generic alertmanager-slack-token \
  --namespace observability-system \
  --from-literal=slack-token="$(vault kv get -field=token secret/kacho/prod/slack)"

# 2.4 Cosign trusted key (image signature verification).
kubectl create namespace cosign-system
kubectl create secret generic cosign-trusted-key \
  --namespace cosign-system \
  --from-file=cosign.pub="$(vault kv get -field=public secret/kacho/prod/cosign)"
```

---

## 3. Install umbrella chart per region

```bash
export KACHO_DOMAIN="api.kacho.cloud"
export REGION="prod-eu-central"     # OR prod-eu-west

helm dependency update helm/umbrella/
helm upgrade --install kacho ./helm/umbrella \
  --namespace kacho-system \
  --create-namespace \
  -f helm/umbrella/values.yaml \
  -f helm/umbrella/values.prod.yaml \
  -f clusters/${REGION}/overrides.yaml \
  --set kacho.domain=${KACHO_DOMAIN} \
  --set kacho.region=${REGION} \
  --timeout 30m \
  --wait

# Verify all components Ready.
kubectl get pods -A --field-selector=status.phase!=Running | tee /dev/stderr | grep -q "0 items"
```

---

## 4. Initialise GitOps (after first install completes)

```bash
# 4.1 Apply ArgoCD AppProject + Applications.
kubectl apply -f helm/umbrella/charts/argo-cd/templates/projects/app-project.yaml
kubectl apply -f helm/umbrella/charts/argo-cd/templates/applications/

# 4.2 Wait for all apps to sync.
argocd app wait -l kacho.cloud/environment=${REGION} --timeout 1800

# 4.3 Verify cosign policy enforcement.
kubectl get clusterimagepolicy
# Try to deploy an unsigned image — should fail with admission webhook denial.
```

---

## 5. Multi-region cutover

After **both** prod-eu-central AND prod-eu-west are healthy:

```bash
# 5.1 Apply Cloudflare LB config (defines geo routing + health checks).
helm upgrade kacho-cloudflare ./helm/umbrella/charts/cloudflare-config \
  --namespace cloudflare-system \
  --set cloudflare.zone=${KACHO_DOMAIN%.*}.cloud \
  --set cloudflare.accountId=$(vault kv get -field=accountId secret/kacho/prod/cloudflare)

# 5.2 Apply multi-region router.
helm upgrade kacho-multi-region ./helm/umbrella/charts/multi-region-router \
  --namespace kacho-system \
  --set multiRegion.regions[0].originIP=$(kubectl --context prod-eu-central get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}') \
  --set multiRegion.regions[1].originIP=$(kubectl --context prod-eu-west get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 5.3 Atomic DNS cutover (api.kacho.cloud → orange-cloud).
# WAF rules deployed in `simulate` mode first; 24h soak required.
# After soak, promote to `block`:
helm upgrade kacho-cloudflare ./helm/umbrella/charts/cloudflare-config \
  --reuse-values \
  --set cloudflare.waf.managed.owaspCrs.action=block \
  --set cloudflare.waf.managed.cloudflareSpecials.action=block
```

---

## 6. Smoke tests

```bash
# 6.1 End-to-end via kacho-yc-shim CLI.
kacho-yc-shim auth login --identity ops@kacho.cloud
kacho-yc-shim iam project-list
kacho-yc-shim vpc network-list
kacho-yc-shim compute instance-list

# 6.2 SLO dashboards live.
open https://grafana.${KACHO_DOMAIN}/d/iam-overview
open https://grafana.${KACHO_DOMAIN}/d/iam-slo-burn-rate

# 6.3 Argo CD health.
open https://argocd.${KACHO_DOMAIN}
```

---

## 7. Day-2 operations

* **Cert renewal** — automated by cert-manager; monitor via
  `KachoCertRenewalFailed` alert. Runbook: `cert-renewal-failed.md`.
* **JWKS rotation** — automated by jwks-rotator CronJob (Phase 2);
  90-day cycle. Runbook: `jwks-rotation-overdue.md`.
* **Regional failover drill** — quarterly tabletop. Runbook:
  `regional-failover.md`. CLI: `make failover-drill-staging`.
* **Postgres backup verify** — daily; full PITR restore test monthly to
  scratch cluster.
* **Audit ClickHouse integrity** — automated Merkle batch verifier
  CronJob (Phase 9).

---

## 8. Disaster recovery

| Scenario | RTO | RPO | Runbook |
|---|---|---|---|
| Primary region full outage | 15 min | 1 min | `regional-failover.md` |
| Postgres primary failure (within region) | 30 sec | 0 | (auto via Patroni) |
| Kafka broker failure | 0 (HA) | 0 | upstream Kafka HA |
| ClickHouse shard failure | 0 (HA) | 0 | upstream ClickHouse HA |
| HSM unavailability | <60 sec fail-closed | 0 | `hsm-recovery.md` (Phase 10) |
| Cert expiry / Cloudflare token revocation | 30 min | 0 | `cert-renewal-failed.md` |
| WAF false-positive blocking legitimate traffic | 5 min | 0 | `cloudflare-rule-rollback.md` |
| Bad image / canary rollout | <5 min via auto-rollback | 0 | `argocd-sync-failure.md` |

---

## 9. Out-of-scope (Phase 12-13)

The following are explicitly **not** Phase 11 deliverables:

* OWASP ASVS L3 conformance.
* Continuous fuzzing (go-fuzz).
* Litmus chaos game-day automation.
* External pentest engagement.
* Bug bounty program / security.txt deployment.
* OpenID Foundation Self-Certification.
* FIDO Alliance WebAuthn conformance.
* Per-tenant US/APAC region isolation.

Tracked under KAC-127 Phase 12 (`sub-phase-3.12-*-acceptance.md`).
