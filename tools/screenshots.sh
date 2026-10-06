#!/usr/bin/env bash
# Самопроверка картинки (SPEC 2.2, раздел 18; шаг 2 П4.5): снимает игру
# и кладёт PNG в builds/screenshots/ (папка не в git).
# Ракурсы: спавн на Площади с высоты глаз, вид под ноги, персонаж крупно
# спереди и сбоку, 6 зон общим планом, закат. Запускать после каждого
# визуального изменения и просматривать снимки.
#
# Сервер без экрана: xvfb-run + программная отрисовка llvmpipe. Годится
# только с --rendering-driver opengl3: Forward+ под llvmpipe сегфолтит
# на get_image() (см. STATUS, П1). Glow/SSAO в compatibility-рендерере
# отличаются от Forward+ — финальную картинку проверяет владелец на ПК.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="builds/screenshots"
rm -rf "$OUT"
mkdir -p "$OUT"

timeout 560 xvfb-run -a godot --path . res://scenes/world_scene.tscn \
	--resolution 1280x720 --rendering-driver opengl3 -- --shot-dir="$OUT"

echo "--- снимки ---"
ls -la "$OUT"
