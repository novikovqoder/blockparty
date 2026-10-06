# Одноразовая диагностика П4.5: грубая цветовая карта PNG (сетка 48x27),
# каждая ячейка — символ по доминирующему оттенку: N=небо/бледный, W=вода-циан,
# G=зелёный, T=дерево-тёмный, R=рыжий/песок, S=серый-камень, K=почти чёрный,
# Y=жёлтый, .=прочее. Запуск: godot --headless --path . -s tools/ascii_map.gd -- f.png
extends SceneTree


func _initialize() -> void:
	for path in OS.get_cmdline_user_args():
		var image := Image.load_from_file(path)
		if image == null:
			print("%s: не читается" % path)
			continue
		var cols := 48
		var rows := 27
		var cell := Vector2i(image.get_width() / cols, image.get_height() / rows)
		print("== %s (%dx%d, клетка %dx%d)" % [path, image.get_width(), image.get_height(), cell.x, cell.y])
		for row: int in rows:
			var line := ""
			for col: int in cols:
				var sum := Color(0, 0, 0)
				var n := 0
				for y: int in range(row * cell.y, (row + 1) * cell.y, 3):
					for x: int in range(col * cell.x, (col + 1) * cell.x, 3):
						sum += image.get_pixel(x, y)
						n += 1
				var c := sum / maxf(1.0, float(n))
				line += _sym(c)
			print(line)
	quit(0)


func _sym(c: Color) -> String:
	var v := (c.r + c.g + c.b) / 3.0
	var mx := maxf(c.r, maxf(c.g, c.b))
	var sat := mx - minf(c.r, minf(c.g, c.b))
	if v < 0.16:
		return "K"
	if mx == c.g and sat > 0.12:
		return "G"
	if mx == c.b and sat > 0.10 and c.g > 0.75:
		return "W"
	if mx == c.r and sat > 0.16:
		return "R"
	if mx == c.r and sat > 0.08:
		return "Y"
	if v > 0.86 and sat < 0.08:
		return "N"
	if sat < 0.10:
		return "S"
	if v < 0.45:
		return "T"
	return "."
