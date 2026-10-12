# П5.7, блок 8 (SPEC п. 8): склейки «было — стало» реалистичной
# переделки Леса и экрана выбора. Каждая пара — один PNG: слева кадр
# из docs/screenshots/P5.7/before/, справа тот же ракурс из after/,
# между ними узкая тёмная разделительная полоса. Кладёт результат в
# docs/screenshots/P5.7/compare/. Запуск:
#   godot --headless --script tools/make_compare.gd --path .
extends SceneTree

const BASE := "res://docs/screenshots/P5.7"
const DIVIDER := 6  # ширина полосы между половинками, px

## Пары «было — стало»: 5 точек Леса днём, 5 на закате, экран выбора
## трёх персонажей (имена файлов в before/ и after/ совпадают).
const PAIRS: Array[String] = [
	"p57_forest_day_1",
	"p57_forest_day_2",
	"p57_forest_day_3",
	"p57_forest_day_4",
	"p57_forest_day_5",
	"p57_forest_sunset_1",
	"p57_forest_sunset_2",
	"p57_forest_sunset_3",
	"p57_forest_sunset_4",
	"p57_forest_sunset_5",
	"select_character_0",
	"select_character_1",
	"select_character_2",
]


func _init() -> void:
	await create_timer(0.01).timeout
	var made := 0
	for pair: String in PAIRS:
		if _make_pair(pair):
			made += 1
	print("склеек готово: %d из %d" % [made, PAIRS.size()])
	quit()


## Собрать пару: true, если обе половинки нашлись и PNG записан.
func _make_pair(pair: String) -> bool:
	var before_path := "%s/before/%s.png" % [BASE, pair]
	var after_path := "%s/after/%s.png" % [BASE, pair]
	var before_img := Image.load_from_file(ProjectSettings.globalize_path(before_path))
	var after_img := Image.load_from_file(ProjectSettings.globalize_path(after_path))
	if before_img == null or after_img == null:
		push_error("нет половинки пары: " + pair)
		return false
	# blit_rect требует одинаковый формат у источника и холста; кадры тура
	# сохраняются в RGBA8.
	before_img.convert(Image.FORMAT_RGB8)
	after_img.convert(Image.FORMAT_RGB8)
	var size := before_img.get_size()
	# На случай разных разрешений половинок — берём минимум (кадры тура
	# всегда 1280x720, но после правок разрешения могут меняться).
	size = size.min(after_img.get_size())
	var canvas := Image.create_empty(
		size.x * 2 + DIVIDER, size.y, false, Image.FORMAT_RGB8)
	canvas.blit_rect(before_img, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	canvas.fill_rect(
		Rect2i(size.x, 0, DIVIDER, size.y), Color(0.12, 0.12, 0.12))
	canvas.blit_rect(
		after_img, Rect2i(Vector2i.ZERO, size), Vector2i(size.x + DIVIDER, 0))
	var out_path := "%s/compare/%s.png" % [BASE, pair]
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("%s/compare" % BASE))
	var err := canvas.save_png(ProjectSettings.globalize_path(out_path))
	if err != OK:
		push_error("не записался PNG: " + out_path)
		return false
	print("склейка: ", out_path)
	return true
