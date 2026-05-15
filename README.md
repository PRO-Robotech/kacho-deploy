# kacho-deploy

Локальный dev-стенд Kachō: kind + Helm + Bitnami Postgres + ingress-nginx.

## Команды

- `make dev-up` — поднять кластер (< 5 мин)
- `make dev-down` — снести
- `make reload-svc SVC=<svc>` — пересобрать и перезагрузить один сервис
- `make logs-svc SVC=<svc>` — `kubectl logs -f`
- `make psql SVC=<svc>` — psql в pod-е
- `make e2e-test` — bash-сценарии в `e2e/` (см. ниже)

## E2E (`e2e/`) и CI

Bash-сценарии против поднятого стенда через REST api-gateway (`BASE_URL`):

- `e2e/geography-move.sh` — Geography (Region/Zone) переехала в kacho-compute
  (`/compute/v1/regions`,`/compute/v1/zones`), kacho-vpc больше зон не отдаёт.
- `e2e/cp-resource-model.sh` — e2e control-plane resource model (эпик `KAC-2`):
  у `Network` публично **нет** `vpnId`; NIC — lean публичная проекция
  (`id/folder/name/subnet_id/primary_v4_address/security_group_ids/used_by/status`)
  vs `GET /vpc/v1/networkInterfaces/{id}/internal` с инфра-полями; `used_by`
  attach/detach. **Плюс негативный infra-leak audit**: краулит все публичные
  vpc & compute list/get endpoints и проверяет, что ни один не отдаёт
  `vpnId`/`hvId`/`hypervisorId`/`sid`/`sidSeq`/`hostIface`/`netns`/`gatewayIp`/
  `containerId`/`nodeIndex`; `GET /compute/v1/hypervisors` → 404. (Bare-metal
  data-plane-сценарии — отдельно, `kacho-vpc-implement/deploy/mvp/run-on-hosts.sh`.)

Оба запускаются в nightly CI-job `e2e-on-kind` (`.github/workflows/ci.yaml`,
`cron: 0 3 * * *`). Newman-suite kacho-vpc ускорена (`tests/newman/scripts/run.sh`
— per-request delay 100→15 ms, коллекции гоняются параллельно с cap 4) — CI
newman-job ~7 мин → ~3 мин.

## Требования

- docker, kind v0.20+, kubectl, helm 3, bats-core
- Свободный порт 80 на host-машине
- В `/etc/hosts`: `127.0.0.1 api.kacho.local kacho.local`

## Persistence

Postgres использует `emptyDir` — данные не сохраняются между `dev-down`/`dev-up`. Это сознательно для воспроизводимости тестов (`03-deployment-and-operations.md` §5).

## NetBox

Dev-стенд поднимает NetBox рядом с остальными сервисами (chart: `netbox-community/netbox`, app v4.5.x). PG — alias `pg-netbox` по тому же паттерну, что `pg-vpc`/`pg-resource-manager`. Valkey (Redis-совместимый) — встроенный subchart NetBox.

- В `/etc/hosts` добавить: `127.0.0.1 netbox.kacho.local`
- UI: `http://netbox.kacho.local`
- Dev-creds: `admin` / `admin`
- API token: получить через UI или `POST /api/users/tokens/provision/` с `admin`/`admin` (NetBox 4.x не принимает legacy hex-токены, поэтому статичный токен в values не задан)
- Postgres: `make psql SVC=netbox`

Persistence у NetBox media/reports/scripts и `pg-netbox` — `emptyDir`, как у остальных сервисов: данные пропадают при `make dev-down`.

`make reload-svc SVC=netbox` и `make logs-svc SVC=netbox` не работают — NetBox не пересобирается локально (внешний образ), а `logs-svc` ожидает один Deployment с именем сервиса, у NetBox их несколько (web/worker). Используйте `kubectl logs -n kacho -l app.kubernetes.io/name=netbox -f`.
