extends SceneTree
## Числовой разбор PNG-кадров (П5.9: сервер без глаз, Read по PNG недоступен).
## Для каждого файла печатает размер, средние цвета шести горизонтальных
## полос (сверху вниз: небо → горизонт → земля) и ярчайший пиксель — так
## на headless-стенде проверяются времена суток, туман и пересветы.
## Запуск:
##   godot --headless --path . -s tools/image_stats.gd -- путь1.png путь2.png

func _initialize() -> void:
	# Аргументы после «--» godot отдаёт скрипту без самого разделителя:
	# берём из user_args всё, что похоже на PNG.
	var files: PackedStringArray = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.ends_with(".png"):
			files.append(arg)
	if files.is_empty():
		print("нет файлов: godot --headless -s tools/image_stats.gd -- a.png b.png")
		quit(1)
		return
	for path: String in files:
		var image := Image.load_from_file(path)
		if image == null:
			print("%s\tERROR" % path)
			continue
		var bands: Array[Color] = _band_colors(image, 6)
		var parts: PackedStringArray = []
		for color: Color in bands:
			parts.append("%.3f,%.3f,%.3f" % [color.r, color.g, color.b])
		var bright := _brightest(image)
		print("%s\t%dx%d\t%s\t%.3f,%.3f,%.3f" % [
			path, image.get_width(), image.get_height(),
			" | ".join(parts), bright.r, bright.g, bright.b])
	quit(0)


## Средний цвет каждой из count горизонтальных полос (верх — небо).
func _band_colors(image: Image, count: int) -> Array[Color]:
	var result: Array[Color] = []
	var band_h: int = image.get_height() / count
	var step_x: int = maxi(1, image.get_width() / 64)
	for b: int in count:
		var sum := Color(0.0, 0.0, 0.0)
		var n := 0
		for y: int in range(b * band_h, (b + 1) * band_h, 2):
			for x: int in range(0, image.get_width(), step_x):
				sum += image.get_pixel(x, y)
				n += 1
		result.append(sum / maxf(1.0, float(n)))
	return result


## Ярчайший по яркости пиксель (диагностика пересветов и «пиксельных»
## артефактов: одиночные белые точки дают чистые 1.0).
func _brightest(image: Image) -> Color:
	var best := Color.BLACK
	var best_l := -1.0
	var step_x: int = maxi(1, image.get_width() / 128)
	for y: int in range(0, image.get_height(), 2):
		for x: int in range(0, image.get_width(), step_x):
			var c := image.get_pixel(x, y)
			var l := c.get_luminance()
			if l > best_l:
				best_l = l
				best = c
	return best
