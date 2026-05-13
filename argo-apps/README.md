# argo-apps — Kachō K8s addons (ArgoCD)

ArgoCD-приложения для CNI-стека, который нужен для K8s-прототипа Kachō (см. workspace
`CLAUDE.md` → стратегия Kube-OVN + Multus + Cilium chaining).

Каждое приложение деплоится в **свой** namespace с префиксом `kacho-*` (никаких прав
в `kube-system`). `Application` CR живут в `in-cloud-argocd` на client-кластере
(тот же argocd, который ставит istio/monitoring/idp/etc).

| Application | namespace | source | роль |
|---|---|---|---|
| `kacho-multus` | `kacho-multus` | этот репо, `argo-apps/multus/` (kustomize-overlay поверх vendor'нутого upstream `multus-daemonset-thick.yml`) | dispatcher secondary NIC через `k8s.v1.cni.cncf.io/networks` annotation; вызывает Kube-OVN-CNI per NetworkAttachmentDefinition |
| `kacho-kube-ovn` | `kacho-kube-ovn` | helm `kubeovn/kube-ovn` v1.16.1 с `cni_conf.NON_PRIMARY_CNI=true` | OVN northbound/southbound + OVS на нодах; **не перезаписывает primary CNI** (Cilium остаётся primary на eth0); подключается только как secondary CNI через Multus |

## Применение

```bash
kubectl --context client apply -f argo-apps/multus/application.yaml
kubectl --context client apply -f argo-apps/kube-ovn/application.yaml

# Дождаться Synced/Healthy
kubectl --context client -n in-cloud-argocd get application kacho-multus kacho-kube-ovn -w
```

## Проверка

```bash
# CRDs появились?
kubectl --context client get crd | grep -E "k8s.cni.cncf.io|kubeovn.io"

# Multus и Kube-OVN-pods в своих namespace'ах
kubectl --context client -n kacho-multus get pods
kubectl --context client -n kacho-kube-ovn get pods

# Тестовый под с secondary NIC через NetworkAttachmentDefinition
kubectl --context client apply -f - <<'EOF'
apiVersion: kubeovn.io/v1
kind: Subnet
metadata:
  name: kacho-test-subnet
spec:
  cidrBlock: 10.99.0.0/24
  provider: kacho-test.kacho-multus
---
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: kacho-test
  namespace: kacho-multus
spec:
  config: '{
    "cniVersion": "0.3.1",
    "type": "kube-ovn",
    "server_socket": "/run/openvswitch/kube-ovn-daemon.sock",
    "provider": "kacho-test.kacho-multus"
  }'
---
apiVersion: v1
kind: Pod
metadata:
  name: kacho-nic-probe
  namespace: default
  annotations:
    k8s.v1.cni.cncf.io/networks: kacho-multus/kacho-test
spec:
  containers:
    - name: probe
      image: nicolaka/netshoot:latest
      command: ["sh", "-c", "ip -br a; sleep 3600"]
EOF

kubectl --context client logs kacho-nic-probe
# Ожидаем 3 интерфейса: lo, eth0 (Cilium), net1 (Kube-OVN из kacho-test-subnet, 10.99.0.x)
```

## Известное

- **Kube-OVN MULTUS_MODE** vs **NON_PRIMARY_CNI**: используется `NON_PRIMARY_CNI` (новое имя c v1.15+); старое `MULTUS_MODE` deprecated.
- Multus thick mode: запускает controller + per-node daemon. Thin mode (один daemonset) тоже работает, но thick — currently recommended.
- Argo-приложения предполагают public-read доступ ArgoCD к `github.com/PRO-Robotech/kacho-deploy.git` (так же как другие apps читают public oci и github repos).
