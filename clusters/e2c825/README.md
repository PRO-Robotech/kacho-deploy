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
4. Helm install:
   ```bash
   helm install kacho-umbrella ../../helm/umbrella \
     -n kacho --create-namespace \
     -f ../../helm/umbrella/values.dev.yaml \
     -f clusters/e2c825/overrides.yaml \
     --timeout 15m
   ```
5. `gen-tls-cert.sh` НЕ запускать — cert-manager выдаст secret автоматически.

## Squashed baseline

VPC использует single `0001_initial.sql` (KAC-111, PR #97). При первом старте `kacho-migrator up` применит весь kacho_vpc schema за один step.
