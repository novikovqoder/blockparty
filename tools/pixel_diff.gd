# Одноразовая утилита (возврат П5.8): сколько пикселей различается между
# двумя PNG — численная сверка «поза ходьбы отличается от T-позы» на
# headless-скриншотах. Шаг 2 (быстрее), пороги по сумме каналов.
#   godot --headless -s tools/pixel_diff.gd -- a.png b.png
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("нужно два файла")
		quit(1)
		return
	var a := Image.load_from_file(args[0])
	var b := Image.load_from_file(args[1])
	if a == null or b == null or a.get_size() != b.get_size():
		print("не читается или размеры не совпадают")
		quit(1)
		return
	var diff := 0
	var big := 0
	var total := 0
	for y: int in range(0, a.get_height(), 2):
		for x: int in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d: int = absi(int(ca.r8) - int(cb.r8)) \
				+ absi(int(ca.g8) - int(cb.g8)) \
				+ absi(int(ca.b8) - int(cb.b8))
			total += 1
			if d > 12:
				diff += 1
			if d > 60:
				big += 1
	print(("проверено %d пикселей (шаг 2): заметно различаются %d (%.2f%%), "
		+ "сильно %d (%.2f%%)") % [total, diff, 100.0 * diff / total,
		big, 100.0 * big / total])
	quit(0)
