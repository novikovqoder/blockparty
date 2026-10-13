#!/usr/bin/env bash
# Серии кадров финала П5.8 → GIF (SPEC «Этап П5.8», «Что показать владельцу»,
# п. 4): ходьба, бег, прыжок, «помахать», сесть у костра — на двух разных
# персонажах Appearance.SHOWCASE (индексы 0 и 1: мужчина в кепке, женщина
# в шляпе), плюс пролёт камеры над Лесом. Кадры снимает world_scene
# (SHOT_CLIP/SHOT_ACTOR/SHOT_FLY, 12 кадров/с), GIF собирает чистый
# Python-энкодер tools/make_gif.py. Сырые кадры — builds/series/ (не в git),
# готовые GIF — docs/screenshots/P5.8/. Прогон идемпотентен: клипы с уже
# существующим GIF пропускаются, оборванная серия переснимается (rm -rf).
set -euo pipefail
cd "$(dirname "$0")/.."

RES=480x270
OUT=docs/screenshots/P5.8
RAW=builds/series

# clip <клип> <актёр>: SHOT_CLIP=walk → серия пишется в <shot-dir>/clip_walk
clip() {
  local sub="$1" actor="$2" name="clip_${1}_a${2}"
  if [ -f "$OUT/$name.gif" ]; then
    echo "=== $name.gif уже есть — пропуск"
    return
  fi
  if [ -d "$RAW/$name/clip_$sub" ] \
      && [ "$(ls "$RAW/$name/clip_$sub" 2>/dev/null | wc -l)" -gt 0 ]; then
    echo "=== $name: кадры уже сняты, только GIF"
  else
    echo "=== съёмка $name (клип $sub, актёр $actor)"
    rm -rf "$RAW/$name"
    env SHOT_CLIP="$sub" SHOT_ACTOR="$actor" \
      timeout 590 xvfb-run -a godot --path . res://scenes/world_scene.tscn \
        --resolution "$RES" --rendering-driver opengl3 \
        -- --shot-dir="$RAW/$name" >"$RAW/$name.log" 2>&1 \
      || { tail -5 "$RAW/$name.log"; return 1; }
  fi
  python3 tools/make_gif.py "$RAW/$name/clip_$sub" --size "$RES" --fps 12 \
    --out "$OUT/$name.gif"
}

fly() {
  if [ -f "$OUT/clip_fly_forest.gif" ]; then
    echo "=== clip_fly_forest.gif уже есть — пропуск"
    return
  fi
  echo "=== съёмка clip_fly_forest (пролёт над Лесом)"
  rm -rf "$RAW/fly"
  env SHOT_FLY=1 \
    timeout 590 xvfb-run -a godot --path . res://scenes/world_scene.tscn \
      --resolution "$RES" --rendering-driver opengl3 \
      -- --shot-dir="$RAW/fly" >"$RAW/fly.log" 2>&1 \
    || { tail -5 "$RAW/fly.log"; return 1; }
  python3 tools/make_gif.py "$RAW/fly/fly_forest" --size "$RES" --fps 12 \
    --out "$OUT/clip_fly_forest.gif"
}

for actor in 0 1; do
  clip walk "$actor"
  clip run "$actor"
  clip jump "$actor"
  clip wave "$actor"
  clip sit "$actor"
done
fly

echo "--- GIF ---"
ls -la "$OUT"/*.gif
