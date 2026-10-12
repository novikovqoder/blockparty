# Одноразовая диагностика (П5.8 A1): статистика текстур фотосканов Poly Haven
# — доля почти чёрных пикселей (фон атласа листвы), цвета углов, каналы ARM.
# Цель: понять, где упакована маска вырезки листвы в JPG-наборах.
# Запуск: godot --headless -s tools/tex_stats.gd -- <файл.jpg> [...]
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("нет файлов")
		quit(1)
		return
	for path in args:
		var image := Image.load_from_file(path)
		if image == null:
			print("%s: не читается" % path)
			continue
		var w := image.get_width()
		var h := image.get_height()
		var black := 0
		var n := 0
		var corners := [
			image.get_pixel(2, 2),
			image.get_pixel(w - 3, 2),
			image.get_pixel(2, h - 3),
			image.get_pixel(w - 3, h - 3),
		]
		var sum := Color()
		for y in range(0, h, 7):
			for x in range(0, w, 7):
				var p := image.get_pixel(x, y)
				sum += p
				if maxf(p.r, maxf(p.g, p.b)) < 0.06:
					black += 1
				n += 1
		print(
			"%s %dx%d чёрных=%.1f%% ср=%s углы=%s" % [
				path.get_file(), w, h, 100.0 * black / maxf(1.0, float(n)),
				sum / maxf(1.0, float(n)), corners,
			]
		)
	quit(0)
