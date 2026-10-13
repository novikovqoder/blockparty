# Склейки «было — стало» (П5.7 блок 8, SPEC п. 8; финал П5.8 — те же точки
# Леса против П5.7). Каждая пара — один PNG: слева кадр «было», справа тот
# же ракурс «стало», между ними узкая тёмная разделительная полоса.
# По умолчанию пары П5.7 (before/ → after/ внутри BASE); переопределяется
# переменными окружения без правки кода:
#   COMPARE_BASE — каталог этапа (…/P5.7 или …/P5.8);
#   COMPARE_BEFORE_DIR / COMPARE_AFTER_DIR — половинки (по умолчанию
#     COMPARE_BASE/before и COMPARE_BASE/after; для П5.8 «было» — это
#     after П5.7);
#   COMPARE_OUT_DIR — куда класть (по умолчанию COMPARE_BASE/compare);
#   COMPARE_PAIRS — список имён через запятую.
# Запуск:
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
	var base_dir := OS.get_environment("COMPARE_BASE")
	if base_dir.is_empty():
		base_dir = BASE
	var before_dir := OS.get_environment("COMPARE_BEFORE_DIR")
	if before_dir.is_empty():
		before_dir = "%s/before" % base_dir
	var after_dir := OS.get_environment("COMPARE_AFTER_DIR")
	if after_dir.is_empty():
		after_dir = "%s/after" % base_dir
	var out_dir := OS.get_environment("COMPARE_OUT_DIR")
	if out_dir.is_empty():
		out_dir = "%s/compare" % base_dir
	var pairs: Array[String] = PAIRS
	var pairs_env := OS.get_environment("COMPARE_PAIRS")
	if not pairs_env.is_empty():
		# У PackedStringArray нет map() — собираем типизированный список циклом.
		pairs = []
		for item: String in pairs_env.split(",", false):
			pairs.append(item.strip_edges())
	var made := 0
	for pair: String in pairs:
		if _make_pair("%s/%s.png" % [before_dir, pair],
				"%s/%s.png" % [after_dir, pair],
				"%s/%s.png" % [out_dir, pair], pair):
			made += 1
	print("склеек готово: %d из %d" % [made, pairs.size()])
	quit()


## Собрать пару: true, если обе половинки нашлись и PNG записан.
func _make_pair(before_path: String, after_path: String,
		out_path: String, pair: String) -> bool:
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
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(out_path.get_base_dir()))
	var err := canvas.save_png(ProjectSettings.globalize_path(out_path))
	if err != OK:
		push_error("не записался PNG: " + out_path)
		return false
	print("склейка: ", out_path)
	return true
