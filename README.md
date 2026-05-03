# kacho-deploy

Локальный dev-стенд Kachō: kind + Helm + Bitnami Postgres + ingress-nginx.

## Команды

- `make dev-up` — поднять кластер (< 5 мин)
- `make dev-down` — снести
- `make reload-svc SVC=<svc>` — пересобрать и перезагрузить один сервис
- `make logs-svc SVC=<svc>` — `kubectl logs -f`
- `make psql SVC=<svc>` — psql в pod-е
- `make e2e-test` — bash-сценарии в `e2e/`

## Требования

- docker, kind v0.20+, kubectl, helm 3, bats-core
- Свободный порт 80 на host-машине
- В `/etc/hosts`: `127.0.0.1 api.kacho.local kacho.local`

## Persistence

Postgres использует `emptyDir` — данные не сохраняются между `dev-down`/`dev-up`. Это сознательно для воспроизводимости тестов (`03-deployment-and-operations.md` §5).
