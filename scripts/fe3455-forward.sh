#!/usr/bin/env bash

# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
#
# fe3455-forward.sh — устойчивый доступ к удалённому стенду fe3455.
#
# Решает два системных источника «UI отдаёт 404»:
#   1. kubectl port-forward привязывается к ОДНОМУ поду и рвётся при каждом
#      роллауте (любой деплой катит pod) — остаётся мёртвый форвард. Здесь форвард
#      идёт на Service (re-resolve на текущий endpoint) и авто-перезапускается в
#      цикле, поэтому переживает роллаут (реконнект ~1 c).
#   2. Локальный kind-стенд держит 0.0.0.0:28080 (свой ingress, отдаёт 404). Если
#      форвардить fe3455 на тот же 28080, ядро раздаёт соединения между двумя
#      листенерами рандомно → периодический 404. Поэтому по умолчанию берём
#      выделенный порт 38080, не пересекающийся с kind, + preflight на занятость.
#
# Использование:
#   ./scripts/fe3455-forward.sh                 # UI на http://127.0.0.1:38080
#   UI_PORT=28080 ./scripts/fe3455-forward.sh   # если 28080 освобождён от kind
#   NS=kacho KUBECONFIG=/path/to/kubeconfig ./scripts/fe3455-forward.sh

set -euo pipefail

KUBECONFIG="${KUBECONFIG:-$HOME/Downloads/fe3455-client-kubeconfig}"
export KUBECONFIG
NS="${NS:-kacho}"
UI_PORT="${UI_PORT:-38080}"
GW_PORT="${GW_PORT:-38081}"

# preflight — порт должен быть свободен, иначе ловим ту же коллизию, что и с kind.
preflight() {
  local port="$1" label="$2"
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "ОШИБКА: порт $port ($label) уже занят — будет коллизия (рандомный 404)." >&2
    lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null >&2
    echo "Освободи порт (напр. остановить заброшенный kind: docker stop kacho-control-plane)" >&2
    echo "или задай другой: UI_PORT=39080 GW_PORT=39081 $0" >&2
    exit 1
  fi
}
preflight "$UI_PORT" ui
preflight "$GW_PORT" api-gateway

pids=()
cleanup() { for p in "${pids[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT INT TERM

# forward — самовосстанавливающийся port-forward к Service. kubectl выходит при
# смерти пода (роллаут); цикл сразу реконнектится к новому endpoint сервиса.
forward() {
  local lport="$1" svc="$2" sport="$3" label="$4"
  (
    while true; do
      kubectl -n "$NS" port-forward --address 127.0.0.1 "svc/$svc" "$lport:$sport" >/dev/null 2>&1 || true
      echo "[fe3455] $label :$lport — реконнект (под перекатился?)..." >&2
      sleep 1
    done
  ) &
  pids+=("$!")
}

forward "$UI_PORT" ui 8080 ui
forward "$GW_PORT" api-gateway 8080 api-gateway

echo "fe3455 доступ готов (Ctrl-C — стоп):"
echo "  UI:          http://127.0.0.1:${UI_PORT}"
echo "  api-gateway: http://127.0.0.1:${GW_PORT}   (REST/newman/debug)"
echo "Форварды самовосстанавливаются при роллауте подов."
wait
