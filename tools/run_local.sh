#!/usr/bin/env bash
# Запуск хоста и N клиентов в режиме разработки (ENet, без Steam) — раздел 3 SPEC.
#
# Использование:
#   tools/run_local.sh [N] [--headless]
#     N         число клиентов (по умолчанию 3; итого с хостом 4 окна)
#     --headless без окон — для Linux-сервера без экрана
#
# Прерывание: Ctrl+C закрывает все запущенные копии игры.
set -euo pipefail
cd "$(dirname "$0")/.."

CLIENTS=3
HEADLESS=0
for arg in "$@"; do
  case "$arg" in
    --headless) HEADLESS=1 ;;
    ''|*[!0-9]*) echo "Неизвестный аргумент: $arg (ожидается число клиентов или --headless)" >&2; exit 1 ;;
    *) CLIENTS="$arg" ;;
  esac
done

HOST_ADDR="127.0.0.1"
GODOT_CMD="godot"
if command -v godot4 >/dev/null 2>&1 && ! command -v godot >/dev/null 2>&1; then
  GODOT_CMD="godot4"
fi
HEADLESS_FLAG=()
if [[ "$HEADLESS" == "1" ]]; then
  HEADLESS_FLAG=(--headless)
fi

PIDS=()
cleanup() {
  for pid in "${PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

echo "Хост ENet ${HOST_ADDR}:7777 + ${CLIENTS} клиент(ов)…"
"$GODOT_CMD" "${HEADLESS_FLAG[@]}" --path . -- --dev-host --dev-name=Host &
PIDS+=($!)
sleep 2
for i in $(seq 1 "$CLIENTS"); do
  "$GODOT_CMD" "${HEADLESS_FLAG[@]}" --path . -- --dev-join="$HOST_ADDR" --dev-name="Bot$i" &
  PIDS+=($!)
done
wait
