#!/usr/bin/env bash
# Запуск хоста и N клиентов в режиме разработки (ENet, без Steam) — раздел 3 SPEC.
#
# Использование:
#   tools/run_local.sh [N] [опции]
#     N           число клиентов (по умолчанию 3; итого с хостом 4 окна)
#     --headless  без окон — для Linux-сервера без экрана
#     --bot       все копии (хост и клиенты) управляются ботами --bot;
#                 хост стартует забег сам (для нагрузочных прогонов)
#     --lag=MS    эмуляция задержки сети (--net-lag), например --lag=150
#     --loss=PCT  эмуляция потери пакетов (--net-loss), например --loss=5
#     --seed=N    фиксированный seed уровня (--dev-seed)
#     --wait=SEC  завершить все процессы через SEC секунд (headless-проверки)
#
# Прерывание: Ctrl+C закрывает все запущенные копии игры.
set -euo pipefail
cd "$(dirname "$0")/.."

CLIENTS=3
HEADLESS=0
BOT=0
WAIT=0
NET_ARGS=()
SEED_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --headless) HEADLESS=1 ;;
    --bot) BOT=1 ;;
    --lag=*) NET_ARGS+=("--net-lag=${arg#--lag=}") ;;
    --loss=*) NET_ARGS+=("--net-loss=${arg#--loss=}") ;;
    --seed=*) SEED_ARGS+=("--dev-seed=${arg#--seed=}") ;;
    --wait=*) WAIT="${arg#--wait=}" ;;
    ''|*[!0-9]*) echo "Неизвестный аргумент: $arg (ожидается число клиентов или одна из опций --headless/--bot/--lag/--loss/--seed/--wait)" >&2; exit 1 ;;
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
BOT_FLAG=()
if [[ "$BOT" == "1" ]]; then
  BOT_FLAG=(--bot)
fi

PIDS=()
cleanup() {
  for pid in "${PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

echo "Хост ENet ${HOST_ADDR}:7777 + ${CLIENTS} клиент(ов)${BOT_FLAG:+ (боты)}${NET_ARGS:+ (${NET_ARGS[*]})}"
"$GODOT_CMD" "${HEADLESS_FLAG[@]}" --path . -- --dev-host --dev-name=Host "${BOT_FLAG[@]}" "${NET_ARGS[@]}" "${SEED_ARGS[@]}" &
PIDS+=($!)
sleep 2
for i in $(seq 1 "$CLIENTS"); do
  "$GODOT_CMD" "${HEADLESS_FLAG[@]}" --path . -- --dev-join="$HOST_ADDR" --dev-name="Bot$i" "${BOT_FLAG[@]}" "${NET_ARGS[@]}" "${SEED_ARGS[@]}" &
  PIDS+=($!)
  sleep 0.5  # разброс старта: рукопожатия ENet не должны прийти одновременно
done

if [[ "$WAIT" -gt 0 ]]; then
  sleep "$WAIT"
  echo "Прогон ${WAIT} с завершён, останавливаю копии игры"
  exit 0
fi
wait
