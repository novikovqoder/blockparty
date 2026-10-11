# Одноразовая утилита диагностики: разность двух детерминированных кадров
# (с --debug-collisions и без) показывает наложенные debug-формы. Печатает
# bounding box разницы, долю по десятым кадра сверху вниз и профиль колонок
# (шаг 16 px) в центре фигуры — видно высоту капсулы NPC относительно модели
# (vfx-fix, баг 1). Запуск: godot --headless -s tools/capsule_probe.gd --
# <debug.png> <ref.png> [центр_x доля]
extends SceneTree

const DIFF: float = 0.12


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("нужно два файла: <debug.png> <ref.png>")
		quit(1)
		return
	var image := Image.load_from_file(String(args[0]))
	var ref := Image.load_from_file(String(args[1]))
	if image == null or ref == null:
		print("не читается")
		quit(1)
		return
	# Режим колонки: третий аргумент «col» — печать hex-цветов пикселей колонки
	# x=args[3] (в долях ширины) из обоих кадров, шаг 6 px по y.
	if args.size() >= 4 and String(args[2]) == "col":
		var fx := String(args[3]).to_float()
		var x := mini(image.get_width() - 1, int(fx * float(image.get_width())))
		for y in range(0, image.get_height(), 6):
			print("y=%3d  debug=%s  ref=%s" % [y, image.get_pixel(x, y).to_html(false), ref.get_pixel(x, y).to_html(false)])
		quit(0)
		return
	var w := image.get_width()
	var h := image.get_height()
	var total := 0
	var min_x := w
	var max_x := -1
	var min_y := h
	var max_y := -1
	var by_band := PackedInt32Array()
	by_band.resize(10)
	for y in range(h):
		var band := mini(9, int(float(y) / float(h) * 10.0))
		for x in range(w):
			if _differs(image.get_pixel(x, y), ref.get_pixel(x, y)):
				total += 1
				by_band[band] += 1
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	print(
		"%s vs %s: разных=%d (%.2f%%) x=[%d..%d] y=[%d..%d]"
		% [args[0], args[1], total, 100.0 * float(total) / float(w * h), min_x, max_x, min_y, max_y]
	)
	var bands: Array[String] = []
	for i in range(10):
		bands.append("%d" % by_band[i])
	print("  по десятым сверху вниз: %s" % ", ".join(bands))
	# Профили трёх колонок внутри bounding box (тело фигуры, не края).
	for frac: float in [0.3, 0.5, 0.7]:
		var cx := mini(w - 1, min_x + int(float(max_x - min_x) * frac))
		var profile := ""
		var diff_color := Color.BLACK
		var diff_count := 0
		for y in range(0, h, 8):
			var c := image.get_pixel(cx, y)
			var r := ref.get_pixel(cx, y)
			if _differs(c, r):
				profile += "o"
				diff_color += c - r
				diff_count += 1
			else:
				profile += "."
		var tint := diff_color / maxf(1.0, float(diff_count)) if diff_count > 0 else Color.BLACK
		print("  колонка x=%.0f (%d px): %s" % [frac, cx, profile])
		print("    средний цвет разницы: %s" % [tint])
	quit(0)


func _differs(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) > DIFF or absf(a.g - b.g) > DIFF or absf(a.b - b.b) > DIFF
