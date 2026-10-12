# Одноразовая диагностика (П5.8, часть B): контактные листы текстур паков
# UBC/MCO — мелкие превью в один PNG, чтобы оценить тон/содержимое карт.
# Запуск: godot --headless -s tools/tex_contact.gd -- <вых.png> <файл.png> [...]
extends SceneTree

const CELL: int = 220


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("нет файлов")
		quit(1)
		return
	var out: String = args[0]
	var imgs: Array[Image] = []
	for path in args.slice(1):
		var img := Image.load_from_file(path) as Image
		if img == null:
			print("не читается %s" % path)
			continue
		img.decompress() if img.is_compressed() else null
		img.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGBA8)
		imgs.append(img)
		print("%s: %s" % [path.get_file(), _stats(img)])
	var cols := 4
	var rows := ceili(float(imgs.size()) / cols)
	var sheet := Image.create(cols * CELL, rows * CELL, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.12, 0.12, 0.14))
	for i in imgs.size():
		var pos := Vector2i((i % cols) * CELL, (i / cols) * CELL)
		sheet.blend_rect(imgs[i], Rect2i(Vector2i.ZERO, Vector2i(CELL, CELL)), pos)
	sheet.save_png(out)
	print("лист: %s" % out)
	quit(0)


func _stats(img: Image) -> String:
	var sum := Color(0, 0, 0)
	var n := 0
	for y in 32:
		for x in 32:
			var c := img.get_pixel(int(float(x) * img.get_width() / 32), int(float(y) * img.get_height() / 32))
			sum += c
			n += 1
	var avg := sum / n
	return "средний %.3f %.3f %.3f" % [avg.r, avg.g, avg.b]
