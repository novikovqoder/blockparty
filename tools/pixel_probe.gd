# Одноразовая утилита диагностики: средние цвета областей PNG-скриншотов.
# Запуск: godot --headless -s tools/pixel_probe.gd -- <файл.png> [ещё.png ...]
# (создана для шага 1 этапа П4.5 — поиск «пропавшей земли»).
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
		print(
			"%s %dx%d низ=%s середина=%s верх=%s центр=%s"
			% [
				path, w, h,
				_avg(image, Rect2i(0, int(h * 0.75), w, int(h * 0.25))),
				_avg(image, Rect2i(0, int(h * 0.45), w, int(h * 0.15))),
				_avg(image, Rect2i(0, 0, w, int(h * 0.2))),
				_avg(image, Rect2i(int(w * 0.4), int(h * 0.4), int(w * 0.2), int(h * 0.2))),
			]
		)
	quit(0)


func _avg(image: Image, region: Rect2i) -> Color:
	var sum := Color(0, 0, 0)
	var n := 0
	for y in range(region.position.y, region.end.y, 4):
		for x in range(region.position.x, region.end.x, 4):
			sum += image.get_pixel(x, y)
			n += 1
	return sum / maxf(1.0, float(n))
