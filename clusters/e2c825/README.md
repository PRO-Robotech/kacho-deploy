# Cluster e2c825 (Beget)

Production-like dev stand. KAC-111 baseline deploy artifacts.

## Cluster

- API: https://45.12.239.174:26443
- Nodes: 3 (Ubuntu 24.04, k8s 1.35.2, containerd)
- CNI: kube-ovn + multus (ArgoCD-managed in `kacho-kube-ovn` / `kacho-multus`)
- cert-manager: `letsencrypt-prod` ClusterIssuer available

## Endpoints

- api-gateway: http://45.12.238.176:8080 + https://45.12.238.176:8443
- UI: http://5.35.93.58/

## Deploy steps

1. Build + push images:
   ```bash
   TAG=kacho-kac111-$(date +%Y%m%d%H%M)
   for svc in resource-manager vpc compute api-gateway ui; do
     docker build -f ../../$svc/Dockerfile -t ttl.sh/$TAG/kacho-$svc:24h ../..
     docker push ttl.sh/$TAG/kacho-$svc:24h
   done
   ```
2. Update `overrides.yaml` image refs.
3. Apply cert-manager + LB services:
   ```bash
   kubectl apply -f clusters/e2c825/cert.yaml
   kubectl apply -f clusters/e2c825/loadbalancers.yaml
   ```
4. Helm install — **two-stage** (KAC-107 fix: pre-install hook'и `zitadel-init` / `zitadel-setup` зависят от `kacho-umbrella-pg-zitadel:5432`, который создаётся в основной фазе install → одностадийный install падает с `BackoffLimitExceeded`):
   ```bash
   # stage 1/2: pg-zitadel only (zitadel disabled — pre-install hook'и не рендерятся)
   helm upgrade --install kacho-umbrella ../../helm/umbrella \
     -n kacho --create-namespace \
     -f ../../helm/umbrella/values.dev.yaml \
     -f clusters/e2c825/overrides.yaml \
     --set zitadel.enabled=false \
     --wait --timeout 15m

   # ждём pg-zitadel ready
   kubectl -n kacho rollout status statefulset/kacho-umbrella-pg-zitadel --timeout=5m

   # stage 2/2: full install (zitadel enabled; pre-install hooks теперь резолвят pg-Service)
   helm upgrade --install kacho-umbrella ../../helm/umbrella \
     -n kacho \
     -f ../../helm/umbrella/values.dev.yaml \
     -f clusters/e2c825/overrides.yaml \
     --set zitadel.enabled=true \
     --wait --timeout 15m
   ```
   Дополнительно `wait-for-pg` init-container в `setupJob.initContainers` /
   `initJob.initContainers` (см. `helm/umbrella/values.dev.yaml`) служит
   safety-net'ом на случай pg-Service flap между stage 1 и stage 2.
5. `gen-tls-cert.sh` НЕ запускать — cert-manager выдаст secret автоматически.

## Squashed baseline

VPC использует single `0001_initial.sql` (KAC-111, PR #97). При первом старте `kacho-migrator up` применит весь kacho_vpc schema за один step.
