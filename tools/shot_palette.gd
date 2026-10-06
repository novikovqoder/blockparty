# Пиксельная проверка снимков самопроверки (шаг 5 П4.5): считает в центре
# кадра доли цветов «Фонарщика» (мятное тело, тёмный капюшон, тёплый фонарик,
# розовые щёчки) и пересвета в белый. Зрение моделей на мелких персонажах
# нестабильно — цифры однозначнее. Запуск:
#   godot --headless --path . -s res://tools/shot_palette.gd -- <png> [png...]
extends SceneTree

## Эталонные цвета палитры «Мята» (id=1 в турах) и пороги сравнения, 0..255.
const REF_MINT := Vector3i(143, 214, 192)  # 8fd6c0 — тело
const REF_TEAL := Vector3i(47, 93, 115)  # 2f5d73 — капюшон и накидка
const REF_EYE := Vector3i(33, 28, 41)  # глаза
const TOL_BODY := 45
const TOL_DARK := 38


func _init() -> void:
	var files: PackedStringArray = OS.get_cmdline_user_args()
	if files.is_empty():
		push_error("нет аргументов: жду пути к PNG")
		quit(1)
		return
	for file: String in files:
		_report(file)
	quit()


func _report(file: String) -> void:
	var image := Image.load_from_file(file)
	if image == null:
		print("%s: НЕ ОТКРЫЛСЯ" % file)
		return
	var width := image.get_width()
	var height := image.get_height()
	# Центральная треть кадра: персонаж в ракурсах char_* стоит в центре.
	var counts := {
		"mint_body": 0, "teal_hood": 0, "yellow_lantern": 0,
		"pink_cheeks": 0, "white_burn": 0, "dark_eyes": 0, "other": 0,
	}
	for y: int in range(int(height * 0.15), int(height * 0.9)):
		for x: int in range(int(width * 0.28), int(width * 0.72)):
			var rgb := Vector3i(
				int(image.get_pixel(x, y).r8),
				int(image.get_pixel(x, y).g8),
				int(image.get_pixel(x, y).b8),
			)
			if _is(rgb, Vector3i(250, 250, 250), 12):
				counts.white_burn += 1
			elif _is(rgb, REF_MINT, TOL_BODY):
				counts.mint_body += 1
			elif _is(rgb, REF_TEAL, TOL_BODY):
				counts.teal_hood += 1
			elif _is(rgb, REF_EYE, TOL_DARK):
				counts.dark_eyes += 1
			elif rgb.x > 225 and rgb.y > 195 and absi(rgb.z - 168) <= 55:
				counts.yellow_lantern += 1
			elif rgb.x > 225 and absi(rgb.y - 158) <= 48 and absi(rgb.z - 158) <= 48:
				counts.pink_cheeks += 1
			else:
				counts.other += 1
	var total := 0
	for key: String in counts:
		total += counts[key]
	var parts: PackedStringArray = [file + ":"]
	for key: String in counts:
		parts.append(" %s=%d(%.1f%%)" % [key, counts[key], 100.0 * counts[key] / maxf(total, 1.0)])
	print("".join(parts))
	print("  verdict: mint>2%%=%s teal>0.3%%=%s yellow>0%%=%s pink>0%%=%s white<15%%=%s" % [
		100.0 * counts.mint_body / maxf(total, 1.0) > 2.0,
		100.0 * counts.teal_hood / maxf(total, 1.0) > 0.3,
		counts.yellow_lantern > 0,
		counts.pink_cheeks > 0,
		100.0 * counts.white_burn / maxf(total, 1.0) < 15.0,
	])


func _is(rgb: Vector3i, ref: Vector3i, tolerance: int) -> bool:
	return absi(rgb.x - ref.x) <= tolerance \
		and absi(rgb.y - ref.y) <= tolerance \
		and absi(rgb.z - ref.z) <= tolerance
