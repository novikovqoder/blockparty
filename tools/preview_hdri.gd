# Одноразовая проверка (П5.7, блок 3): где в HDRI-панорамах солнце.
# Ищет самое яркое пятно каждой панорамы (зенит или горизонт), переводит
# его u-координату в «мировой азимут» atan2(x, z) по формуле проекции из
# sky.gdshader (u = atan(z, x) / TAU + 0.5) и печатает значение для
# DayMath.HDRI_SUN_AZIMUTH. Заодно сохраняет тонемапнутые превью в
# builds/hdri_preview/ — глазами проверить, что панорама живая. Запуск:
#   godot --headless --script tools/preview_hdri.gd --path .
extends SceneTree

const PANORAMAS: Array[String] = [
	"res://assets/third_party/polyhaven.com/kloofendal_48d_partly_cloudy_puresky/kloofendal_48d_partly_cloudy_puresky_2k.hdr",
	"res://assets/third_party/polyhaven.com/grasslands_sunset/grasslands_sunset_2k.hdr",
	"res://assets/third_party/polyhaven.com/rogland_clear_night/rogland_clear_night_2k.hdr",
]


func _init() -> void:
	await create_timer(0.01).timeout
	for path: String in PANORAMAS:
		_analyze(path)
	quit()


func _analyze(path: String) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		push_error("не читается: " + path)
		return
	var best := Color(0.0, 0.0, 0.0, 1.0)
	var best_x := 0
	var best_y := 0
	var size := img.get_size()
	# Солнце сильно ярче всего; сузим поиск: верхняя половина панорамы
	# (v < 0.55 — небо, v = 0 — зенит).
	for y: int in range(0, int(size.y * 0.55), 2):
		for x: int in range(0, size.x, 2):
			var c := img.get_pixel(x, y)
			var l := c.r + c.g + c.b
			if l > best.r + best.g + best.b:
				best = c
				best_x = x
				best_y = y
	var u := float(best_x) / float(size.x)
	var v := float(best_y) / float(size.y)
	# Мировой азимут точки u: u = 0.5 -> (x, z) = (1, 0) -> atan2 = PI / 2.
	var azimuth := PI / 2.0 - TAU * (u - 0.5)
	print("%s: пик (%.2f, %.2f, %.2f) на u=%.3f v=%.3f -> азимут %.3f"
		% [path.get_file().get_slice("_2k", 0), best.r, best.g, best.b, u, v,
			azimuth])
	# Превью: Reinhard-тонемап и уменьшение, чтобы посмотреть глазами.
	var preview := Image.create(size.x / 4, size.y / 4, false, Image.FORMAT_RGB8)
	for y: int in preview.get_height():
		for x: int in preview.get_width():
			var c := img.get_pixel(x * 4, y * 4)
			preview.set_pixel(x, y, Color(
				c.r / (1.0 + c.r), c.g / (1.0 + c.g), c.b / (1.0 + c.b)))
	var dir := "builds/hdri_preview"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(
		"res://" + dir))
	preview.save_png("res://%s/%s.png" % [dir,
		path.get_file().get_slice("_2k", 0)])
