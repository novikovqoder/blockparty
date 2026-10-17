#!/usr/bin/env bash
# Материалы П5.9 блок 8 (docs/VISUAL_PLAN.md): полный набор в
# docs/screenshots/P5.9/ — склейки «было — стало» по точкам П5.7 и П5.8,
# Лес в 4 времена суток, GIF-клипы (прогулка и пролёт).
#
# «Было» точек П5.7 — main (worktree ~/blockparty-main-p59, уровень П5.7),
# «было» точек П5.8 — база ветки p5.8-realism-v2 (worktree
# ~/blockparty-p58-base): в main персонажей и точек П5.8 ещё нет, а П5.9
# стартовал именно с p5.8-realism-v2. «Стало» — текущая ветка (репозиторий).
# Склейки собирает tools/make_compare.py (чистый Python, без PIL),
# GIF — tools/make_gif.py из .rgb-серий world_scene.
#
# Прогон идемпотентен: существующие кадры/GIF не переснимаются, склейки
# пересобираются всегда. Сырые серии и логи — builds/series_p59/ (не в git).
set -euo pipefail
cd "$(dirname "$0")/.."

RES_GIF=480x270
RES_STILL=1280x720
OUT=docs/screenshots/P5.9
RAW=builds/series_p59
MAIN_WT="${P59_MAIN:-$HOME/blockparty-main-p59}"
P58_WT="${P58_BASE:-$HOME/blockparty-p58-base}"
mkdir -p "$RAW"

# have_in <подкаталог OUT> <имена...> — все ли файлы существуют. Отдельная
# функция вместо "$OUT"/sub/${NAMES[@]}: bash не клеит префикс ко всем
# элементам раскрытого массива (префикс достаётся только первому).
have_in() {
  local sub="$1" f
  shift
  for f in "$@"; do [ -f "$OUT/$sub/$f" ] || return 1; done
  return 0
}

# Запуск тура в каталоге проекта: stills <корень> <env> <подкаталог OUT>
# [extra] — доп. флаги после «--»: «стало» снимается в «Высоком качестве»
# (--high-quality: MSAA 4x + FXAA, планка качества П5.9), «было» — как
# играли тогда, обычным уровнем. Лог — абсолютный путь: тур запускается
# из чужого worktree, где относительного $RAW нет.
stills() {
  local root="$1" envs="$2" sub="$3" extra="${4:-}"
  local dir tag log
  dir="$(realpath "$OUT/$sub")"
  tag="$(basename "$(realpath "$root")")_$sub"
  log="$(realpath -m "$RAW")/stills_$tag.log"
  mkdir -p "$dir" "$(dirname "$log")"
  echo "=== $tag: съёмка ($envs ${extra:+$extra})"
  # timeout 7200: «Высокое качество» (MSAA 4x) на llvmpipe — до ~12 мин
  # на кадр после доработок 1-5 (замер: 475–739 с), тур из 8 кадров
  # в 2700 с не влезал — прогоны обрывались на 2-3 кадре.
  (cd "$root" && env $envs timeout 7200 xvfb-run -a godot --path . \
      res://scenes/world_scene.tscn --resolution "$RES_STILL" \
      --rendering-driver opengl3 -- --shot-dir="$dir" $extra \
      >"$log" 2>&1) \
    || { tail -5 "$log"; return 1; }
}

# Серия кадров → GIF: gif <серия> <подкаталог-кадров> <имя-gif> [env]
# [секунды клипа 2–12; пусто — 6].
gif() {
  local series="$1" sub="$2" stem="$3" envs="${4:-}"
  local dir="$RAW/$series"
  if [ -f "$OUT/$stem.gif" ]; then
    echo "=== $stem.gif уже есть — пропуск"
    return
  fi
  if [ -n "$(ls "$dir/$sub"/frame_*.rgb 2>/dev/null)" ]; then
    echo "=== $series: кадры уже сняты, только GIF"
  else
    echo "=== съёмка $series"
    mkdir -p "$dir"
    # Обычный уровень, не --high-quality: на llvmpipe MSAA 4x учетверяет
    # кадр (~67 с при 14 тыс. предметов — клип не влезал в таймаут), а
    # SSAO/объёмный туман Compatibility и так пропускает; на 480×270
    # разницы со «Высоким» в GIF нет. Статичные кадры — в «Высоком».
    env $envs SHOT_SECONDS="${5:-}" timeout 3600 xvfb-run -a godot \
      --path . res://scenes/world_scene.tscn --resolution "$RES_GIF" \
      --rendering-driver opengl3 -- --shot-dir="$dir" \
      >"$dir.log" 2>&1 \
      || { tail -5 "$dir.log"; return 1; }
  fi
  python3 tools/make_gif.py "$dir/$sub" --size "$RES_GIF" --fps 12 \
    --out "$OUT/$stem.gif"
}

# Кадр Леса в фазе суток: phase <имя> <фракция суток> — точка 1 тура П5.7
# (одиночный кадр SHOT_SPOT: полный тур ради одной фазы — лишние ~40 мин).
phase() {
  local name="$1" fraction="$2"
  local png="$OUT/p59_forest_$name.png"
  local dir="$RAW/phase_$name"
  if [ -f "$png" ]; then
    echo "=== p59_forest_$name.png уже есть — пропуск"
    return
  fi
  echo "=== фаза $name (доля суток $fraction)"
  rm -rf "$dir"
  mkdir -p "$dir"
  env SHOT_SPOT="-52,-52,223" SHOT_FRACTION="$fraction" \
    timeout 1200 xvfb-run -a godot --path . res://scenes/world_scene.tscn \
      --resolution "$RES_STILL" --rendering-driver opengl3 \
      -- --shot-dir="$dir" --high-quality >"$RAW/phase_$name.log" 2>&1 \
    || { tail -5 "$RAW/phase_$name.log"; return 1; }
  cp "$dir/spot_check.png" "$png"
}

# Канон набора П5.7: 5 дневных + 3 закатных кадра. Закатные точки 4/5 и
# диагностические кропы _L/_R из блока 8 ч.1 убраны (лишние ракурсы);
# 8 пар «было — стало» закрывают материал этапа.
P57_NAMES=()
for i in 1 2 3 4 5; do P57_NAMES+=("p57_forest_day_$i.png"); done
for i in 1 2 3; do P57_NAMES+=("p57_forest_sunset_$i.png"); done
P58_NAMES=(p58_crew_forest_day.png p58_crew_campfire_evening.png
  p58_folks_plaza.png p58_folk_finn.png p58_folk_lumi.png
  p58_folk_thyme.png)

# 1) GIF-клипы: прогулка по Лесу (актёр 0, 10 с) и пролёт камеры.
gif forest_walk clip_forest_walk clip_forest_walk \
  "SHOT_CLIP=forest_walk SHOT_ACTOR=0" 8
gif fly_forest fly_forest clip_forest_fly "SHOT_FLY=1" 6

# 2) Точки П5.7: было (main) — стало (visual-overhaul).
have_in before "${P57_NAMES[@]}" \
  || stills "$MAIN_WT" "SHOT_P57=1" before
have_in after "${P57_NAMES[@]}" \
  || stills . "SHOT_P57=1" after --high-quality

# 3) Точки П5.8: было (p5.8-realism-v2) — стало (visual-overhaul).
# Опционально (P59_WITH_P58=1): кадры персонажей уже сданы в
# docs/screenshots/P5.8/, для П5.9 материал этапа — только Лес.
if [ "${P59_WITH_P58:-0}" = "1" ]; then
  have_in before "${P58_NAMES[@]}" \
    || stills "$P58_WT" "SHOT_CREW=1 SHOT_FOLK=1" before
  have_in after "${P58_NAMES[@]}" \
    || stills . "SHOT_CREW=1 SHOT_FOLK=1" after --high-quality
fi

# 4) Лес в 4 времена суток (середины фаз DayMath: 0.09/0.30/0.58/0.80;
#    день и закат совпадают с кадром точки 1 «стало»).
# День и закат — копии кадра точки 1 «стало» (тот же вид и фаза), cp -n
# ДО phase: иначе phase sunset снял бы дубль и cp -n уже не сработал.
cp -n "$OUT/after/p57_forest_day_1.png" "$OUT/p59_forest_day.png"
cp -n "$OUT/after/p57_forest_sunset_1.png" "$OUT/p59_forest_sunset.png"
phase dawn 0.09
phase sunset 0.58
phase night 0.80

# 5) Склейки «было | стало» (пересобираются всегда).
mkdir -p "$OUT/compare"
COMPARE_NAMES=("${P57_NAMES[@]}")
if [ "${P59_WITH_P58:-0}" = "1" ]; then
  COMPARE_NAMES+=("${P58_NAMES[@]}")
fi
for name in "${COMPARE_NAMES[@]}"; do
  python3 tools/make_compare.py "$OUT/before/$name" "$OUT/after/$name" \
    -o "$OUT/compare/$name"
done

echo "--- материалы П5.9 ---"
ls -la "$OUT"/*.gif "$OUT"/p59_forest_*.png
ls -la "$OUT"/compare
