#!/usr/bin/env bash
# E2E-проверка заданий жителей (П5.5, критерий 3 приёмки): ДВЕ headless-
# копии через ENet — хост (--dev-host) и клиент (--dev-join), обе с
# --quest-bot. Клиент-автопрогон берёт «Вечерний чай» у Тимьяна,
# собирает пять пучков мяты и садится у костра; хост-автопрогон стоит
# в радиусе финала — задание выполняется, награда уходит КАЖДОМУ
# участнику (обоим).
#
# Проверяет логи ОБОИХ копий: взятие задания (кем), прогресс шагов,
# начисление награды каждому участнику. Чего-то нет — ненулевой код.
#
# Логи и полный вывод копий: builds/quest_e2e/{host,client}.log.
# Запуск: tools/quest_e2e.sh (сборка Windows/Steam не нужна).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="builds/quest_e2e"
rm -rf "$OUT"
mkdir -p "$OUT"
HOST_LOG="$OUT/host.log"
CLIENT_LOG="$OUT/client.log"

GODOT_CMD="godot"
if command -v godot4 >/dev/null 2>&1 && ! command -v godot >/dev/null 2>&1; then
  GODOT_CMD="godot4"
fi

# Сколько секунд ждать финала задания в логе клиента (мир строется,
# клиент подключается, 5 пучков по паузе на снапшоты).
FINISH_TIMEOUT=150

PIDS=()
cleanup() {
  for pid in "${PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

echo "Хост ENet 127.0.0.1:7777 + клиент с автопрогоном задания"
"$GODOT_CMD" --headless --path . -- --dev-host --dev-name=Host --quest-bot \
  >"$HOST_LOG" 2>&1 &
PIDS+=($!)
sleep 3
"$GODOT_CMD" --headless --path . -- --dev-join=127.0.0.1 --dev-name=QuestBot \
  --quest-bot >"$CLIENT_LOG" 2>&1 &
PIDS+=($!)

echo "Жду финал «Вечернего чая» (до ${FINISH_TIMEOUT} с)…"
finished=0
for _ in $(seq 1 "$FINISH_TIMEOUT"); do
  sleep 1
  if grep -q "thyme_tea» выполнено" "$CLIENT_LOG" 2>/dev/null; then
    finished=1
    break
  fi
  # Копия упала раньше времени — дальше ждать нечего.
  kill -0 "${PIDS[0]}" 2>/dev/null || break
  kill -0 "${PIDS[1]}" 2>/dev/null || break
done
# Даём копиям дописать награду и эффект финала.
sleep 4
cleanup
trap - EXIT INT TERM

if [[ "$finished" != "1" ]]; then
  echo "ОШИБКА: финал задания не появился в логе клиента за ${FINISH_TIMEOUT} с"
  tail -n 30 "$CLIENT_LOG" || true
  exit 1
fi

echo "--- Проверка логов обеих копий ---"
fail=0
check() {
  local log="$1" pattern="$2" what="$3"
  if grep -q "$pattern" "$log"; then
    echo "  OK  $what: $(grep "$pattern" "$log" | tail -n 1)"
  else
    echo "  НЕТ $what в $(basename "$log") (искал «$pattern»)"
    fail=1
  fi
}

# Взятие кем: лог пишут обе копии (дельта quest_state), имя пира — из peers.
check "$HOST_LOG"   "Задание «thyme_tea» взято игроком" "взятие задания (хост)"
check "$CLIENT_LOG" "Задание «thyme_tea» взято игроком" "взятие задания (клиент)"
# Прогресс шагов: 5/5 — все пучки мяты.
check "$HOST_LOG"   "Задание «thyme_tea»: прогресс 5/5" "прогресс шагов 5/5 (хост)"
check "$CLIENT_LOG" "Задание «thyme_tea»: прогресс 5/5" "прогресс шагов 5/5 (клиент)"
# Награда каждому участнику: обе копии логируют список «peer:+монеты»,
# в списке должны быть ОБА пира (хост 1 — помощник у костра, клиент — сборщик).
reward_line_host="$(grep "награда каждому участнику" "$HOST_LOG" | tail -n 1 || true)"
reward_line_client="$(grep "награда каждому участнику" "$CLIENT_LOG" | tail -n 1 || true)"
for side in host client; do
  var="reward_line_$side"
  line="${!var}"
  log="$HOST_LOG"; [[ "$side" == "client" ]] && log="$CLIENT_LOG"
  if [[ -z "$line" ]]; then
    echo "  НЕТ награды в $(basename "$log")"
    fail=1
    continue
  fi
  echo "  OK  награда ($side): $line"
  # Оба пира в списке: токены «peer:+монеты» (порядок — по присоединению,
  # сборщик первым, хост-помощник вторым), среди них хост (peer 1).
  tail_part="${line##*— }"
  tokens="$(grep -oE "[0-9]+:\+[0-9]+" <<<"$tail_part" || true)"
  token_count="$(grep -c . <<<"$tokens" || true)"
  if [[ "$token_count" -lt 2 ]] || ! grep -qx "1:+[0-9]*" <<<"$tokens"; then
    echo "  НЕТ обоих участников в награде ($side): $line"
    fail=1
  fi
done

echo "---"
if [[ "$fail" != "0" ]]; then
  echo "E2E ПРОВАЛЕН: чего-то из проверок нет (логи: $OUT)"
  exit 1
fi
echo "E2E OK: взятие, прогресс и награда каждому участнику видны в обеих копиях"
