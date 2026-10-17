#!/usr/bin/env bash
# Замер FPS по зоне (П5.9, раздел «Производительность» VISUAL_PLAN.md):
# хост ENet headless-ботом + N ботов headless (нагрузка мира) и один
# рендерящийся клиент-зонд под xvfb (SHOT_FPS в world_scene.gd — печатает
# FPS-PROBE: avg/median/p95/min + примитивы и draw calls). Сервер без GPU
# (llvmpipe) — числа относительные: сравниваются режимы между собой,
# абсолютная цель (60 FPS на GTX 1060) проверяется владельцем вручную.
#
# Использование: tools/fps_probe.sh <зона> <high|simple> [ботов=10]
#   зона — из Dev.SPAWN_ZONES (forest, plaza, ...); итого игроков
#   в мире: хост + боты + зонд (по умолчанию 12).
set -euo pipefail
cd "$(dirname "$0")/.."

ZONE="${1:?зона появления (forest, plaza, …)}"
TIER="${2:?режим графики: high | simple}"
BOTS="${3:-10}"
GODOT_CMD="godot"
if command -v godot4 >/dev/null 2>&1 && ! command -v godot >/dev/null 2>&1; then
  GODOT_CMD="godot4"
fi
TIER_FLAG=(--high-quality)
if [[ "$TIER" == "simple" ]]; then
  TIER_FLAG=(--simple-graphics)
elif [[ "$TIER" != "high" ]]; then
  echo "Неизвестный режим: $TIER (high | simple)" >&2; exit 1
fi

RAW="builds/series_p59/fps_${ZONE}_${TIER}"
mkdir -p "$RAW"
PIDS=()
cleanup() {
  for pid in "${PIDS:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

echo "=== FPS-зонд: зона=$ZONE качество=$TIER игроков=$((BOTS + 2))"
"$GODOT_CMD" --headless --path . -- --dev-host --dev-name=Host --bot \
  >"$RAW/host.log" 2>&1 &
PIDS+=($!)
sleep 2
for i in $(seq 1 "$BOTS"); do
  "$GODOT_CMD" --headless --path . -- --dev-join=127.0.0.1 \
    --dev-name="Bot$i" --bot >"$RAW/bot$i.log" 2>&1 &
  PIDS+=($!)
  sleep 0.5
done
# Зонд: 30 с замера после 12 с ожидания (боты должны войти в мир).
SHOT_FPS=30 SHOT_FPS_WAIT=12 timeout 300 xvfb-run -a "$GODOT_CMD" --path . \
  --resolution 1280x720 --rendering-driver opengl3 -- \
  --dev-join=127.0.0.1 --dev-name=Probe --dev-spawn="$ZONE" \
  --shot-dir="$RAW" "${TIER_FLAG[@]}" >"$RAW/probe.log" 2>&1
grep "FPS-PROBE" "$RAW/probe.log" || { tail -5 "$RAW/probe.log"; exit 1; }
