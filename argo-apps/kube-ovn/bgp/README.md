# BGP-маршрутизация Kachō-подсетей (OP2-P-BGP) — PoC-runbook

Доставка CIDR Kachō-подсетей в маршрутизацию через **BGP (kube-ovn-speaker)** вместо
`Vpc.spec.staticRoutes`, которые kube-ovn v1.16.1 **стрипает** на custom-VPC за ~1-5с
(issue [kacho-vpc-operator#2]). Speaker анонсирует CIDR той kube-ovn Subnet, на которой
стоит аннотация `ovn.kubernetes.io/bgp=cluster` — её выставляет `kacho-vpc-operator` на
КАЖДОЙ материализуемой подсети (egress-reconciler, OP2-P-BGP S3). Acceptance:
`kacho-workspace/docs/specs/sub-phase-OP2-P-BGP-kubeovn-speaker-acceptance.md`.

## Компоненты

| Объект | Файл | Роль |
|---|---|---|
| `kube-ovn-speaker` (DaemonSet) | `speaker.yaml` | анонсит CIDR аннотированных подсетей в BGP-фабрику; gateway-ноды (`ovn.kubernetes.io/bgp=true`), hostNetwork, SA `ovn` |
| GoBGP route-reflector (Deployment) | `route-reflector.yaml` | BGP-peer/RR на kind (на kind нет upstream-роутера); точка проверки «маршрут выучен/персистит» |
| `bgp-up.sh` | `../../../scripts/bgp-up.sh` | label ноды + apply RR + speaker (рендерит pod-IP RR в `--neighbor-address`); kind-dev-safe |

ASN-план (private, RFC 6996): `cluster-as=65001` (speaker), `neighbor-as=65000` (RR).

## Развёртывание

```bash
cd kacho-deploy && bash scripts/bgp-up.sh    # после того как kube-ovn поднят
```
Оператор уже аннотирует подсети сам — отдельных действий не нужно.

## Верификация (live)

```bash
NS=kacho-kube-ovn
# 1) BGP-сессия Established (speaker ↔ RR):
kubectl -n $NS exec deploy/kube-ovn-bgp-rr -- gobgp neighbor
#   Peer  AS  Up/Down State    →  ... Establ
# 2) Аннотация на материализуемых подсетях (оператор):
kubectl get subnets.kubeovn.io \
  -o custom-columns='NAME:.metadata.name,CIDR:.spec.cidrBlock,BGP:.metadata.annotations.ovn\.kubernetes\.io/bgp'
# 3) Выученные маршруты (CIDR подсетей + pod /32):
kubectl -n $NS exec deploy/kube-ovn-bgp-rr -- gobgp global rib
#   *> 192.168.88.0/24   <nexthop>   65001 ...   ← персистит (≠ стрип staticRoutes #2)
```

Withdraw (снятие анонса): `kubectl annotate subnet.kubeovn.io <sub> ovn.kubernetes.io/bgp-`
→ маршрут исчезает из `gobgp global rib`. Удаление самой подсети снимает анонс
автоматически (аннотация уходит с объектом).

## Результаты live-PoC (kind-kacho, kube-ovn v1.16.1, 2026-06-12)

- **BGP-сессия Established** speaker↔RR (S2-01). ✓
- **Custom-VPC subnet-анонс РАБОТАЕТ** (S4-03 ИСХОД A — главный риск снят): RR учит
  CIDR подсетей из custom-VPC (`netrpwd3nst6hyyhc7m9` `192.168.88.0/24`/`192.168.89.0/24`,
  `netnqbfj22xqdjye5xtw` `29.62.0.0/16`) + pod /32 реальных Kachō-NIC (`.88.12`, `.88.39`). ✓
- **Маршрут персистит** ≥60с (S3-03) — в отличие от `Vpc.spec.staticRoutes` (#2). ✓
- **Withdraw** на снятие аннотации/prune (S3-04). ✓
- **Оператор аннотирует автоматически** все материализуемые подсети (S3-01). ✓

## Известные ограничения / заметки

- **IPv6-анонс не активен** на этом стенде: kube-ovn `NET_STACK: ipv4`; speaker
  сконфигурён на v4-peer. v6-подсети **аннотируются** оператором (корректно), но speaker
  их не анонсит без `--neighbor-ipv6-address` + v6 AFI/SAFI. Для dual-stack — отдельная
  настройка (вне scope PoC).
- **Next-hop = `10.244.0.1`** (cni-gateway): node→podIP RR'а проходит kube-proxy/cni SNAT,
  поэтому RR видит peer как `10.244.0.1`. Для PoC (learned-route verification) это
  несущественно (dynamic-neighbor принимает любой source). Для prod/multi-AZ next-hop =
  IP gateway-ноды (нужен RR вне pod-network / direct node peering).
- **Произвольные next-hop static-маршруты** (не «анонсируй CIDR») BGP-анонс не выражает —
  вне scope (см. acceptance «Не-цели» п.4).

## Безопасность (S5-01)

- ASN / `neighbor-address` — инфра-конфиг (underlay), **не** на публичной поверхности
  Kachō-ресурсов (Subnet/Network показывают только tenant-intent: id/name/CIDR/status).
- BGP-auth (`--auth-password` / TCP-MD5) в happy-path PoC **не задан**. Если нужен —
  только через **k8s Secret**, НИКОГДА не plaintext в git/values/манифесте/vault. Negative
  (auth-mismatch → session не Established, S2-02) проверяется заданием разных паролей
  на speaker и RR.
- BGP `speaker↔RR` — **новое data-plane ребро ВНЕ gRPC mTLS-mesh** Kachō (mTLS — только
  gRPC operator→{vpc,iam}, SEC-G). Аутентификация BGP — TCP-MD5, не mTLS. См. vault
  `obsidian/kacho/edges/kube-ovn-to-bgp-fabric.md`.

[kacho-vpc-operator#2]: https://github.com/PRO-Robotech/kacho-vpc-operator/issues/2
