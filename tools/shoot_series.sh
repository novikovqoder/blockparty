#!/usr/bin/env bash
# П10: серия кадров входа в мир (boot → меню BU → LoadingScreenBU → мир)
# под xvfb/opengl3 + аудит «ни одного серого кадра» (SPEC П10 4.3) +
# игровые ракурсы героя (покой/бег/прыжок/с мечом/площадь/лицо).
# PNG: ключевые кадры перехода — builds/screenshots/series (не в git),
# игровые ракурсы — docs/screenshots/П10.
# Выход: 0 — серия снята, серых кадров нет; 2 — есть серые кадры; 3 — мир
# не достигнут.
set -euo pipefail
cd "$(dirname "$0")/.."

SERIES_DIR="builds/screenshots/series"
OUT_DIR="docs/screenshots/П10"
mkdir -p "$SERIES_DIR" "$OUT_DIR"

code=0
# --bot: без него boot без Steam останавливается на окне «Steam не запущен».
# Кадр мира под llvmpipe стоит 25-50 с (сервер 2 ядра) — серия занимает
# до ~35 мин, таймаут с запасом.
timeout 2700 xvfb-run -a godot --path . --rendering-driver opengl3 \
	--resolution 1280x720 -s res://tools/shoot_series_bu.gd -- --bot "$SERIES_DIR" || code=$?

# Игровые кадры уехали в каталог серии — переносим в отчётный набор.
for name in 20_world_idle 21_world_run 22_world_jump 23_world_sword \
	24_world_plaza 25_world_face_blink 26_world_face; do
	if [[ -f "$SERIES_DIR/$name.png" ]]; then
		mv "$SERIES_DIR/$name.png" "$OUT_DIR/$name.png"
	fi
done

echo "--- серия: $SERIES_DIR ($(ls "$SERIES_DIR" | wc -l) файлов) ---"
echo "--- отчётные: $OUT_DIR ---"
ls -la "$OUT_DIR"
exit $code
