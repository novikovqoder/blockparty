# Объективный осмотр снимков самопроверки (шаг 0 доработки П4.5): печатает
# ASCII-карту цветов кадра и доли категорий по горизонтальным полосам —
# «я сам посмотрел» без неверного зрения моделей. Категории подобраны под
# поиск «молочной пелены» и пропавшей земли: пересвет, блёклость, вода/небо,
# зелень, песок, камень. Запуск:
#   godot --headless --path . -s res://tools/shot_ground.gd -- <png> [png...]
extends SceneTree

## Сетка карты: клетка = средний цвет блока пикселей.
const COLS: int = 32
const ROWS: int = 18
## Пороги категорий, 0..255.
const BURN: int = 243  # чистый пересвет
const PALE: int = 205  # блёклый «молочный» тон


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
	print("\n=== %s (%dx%d) ===" % [file.get_file(), image.get_width(), image.get_height()])
	var counts := {}
	for row: int in ROWS:
		var line := ""
		for col: int in COLS:
			var rgb := _block_average(image, col, row)
			var tag := _category(rgb)
			line += tag
			counts[tag] = int(counts.get(tag, 0)) + 1
		print(line)
	var total: int = COLS * ROWS
	var parts: PackedStringArray = []
	for tag: String in ["W", "w", "B", "c", "G", "g", "S", "s", "d", "."]:
		var n: int = counts.get(tag, 0)
		if n > 0:
			parts.append("%s=%d(%.0f%%)" % [tag, n, 100.0 * n / total])
	print("доли: " + " ".join(parts))
	for band: int in 3:
		var from_y: float = 0.15 + 0.7 * band / 3.0
		var to_y: float = 0.15 + 0.7 * (band + 1) / 3.0
		var rgb := _area_average(image, 0.28, 0.72, from_y, to_y)
		print("полоса %d (%d–%d%% кадра): ср. #%02x%02x%02x" % [
			band, int(from_y * 100), int(to_y * 100), rgb.x, rgb.y, rgb.z,
		])


## Средний цвет клетки сетки.
func _block_average(image: Image, col: int, row: int) -> Vector3i:
	return _area_average(
		image,
		float(col) / COLS, float(col + 1) / COLS,
		float(row) / ROWS, float(row + 1) / ROWS,
	)


## Средний цвет прямоугольной доли кадра (в долях ширины/высоты).
func _area_average(
	image: Image, x0: float, x1: float, y0: float, y1: float
) -> Vector3i:
	var x_from: int = clampi(int(image.get_width() * x0), 0, image.get_width() - 1)
	var x_to: int = clampi(int(image.get_width() * x1), x_from + 1, image.get_width())
	var y_from: int = clampi(int(image.get_height() * y0), 0, image.get_height() - 1)
	var y_to: int = clampi(int(image.get_height() * y1), y_from + 1, image.get_height())
	var sum := Vector3i()
	var n: int = 0
	for y: int in range(y_from, y_to, 3):
		for x: int in range(x_from, x_to, 3):
			var px := image.get_pixel(x, y)
			sum += Vector3i(int(px.r8), int(px.g8), int(px.b8))
			n += 1
	return sum / maxi(n, 1)


## Категория цвета: W пересвет, w блёклость, B синева (небо/вода),
## c голубо-зелёная дымка, G зелень, g желтоватая зелень, S песок/тепло,
## s серый камень, d тёмное, . прочее.
func _category(rgb: Vector3i) -> String:
	var r: int = rgb.x
	var g: int = rgb.y
	var b: int = rgb.z
	var max_c: int = maxi(maxi(r, g), b)
	var min_c: int = mini(mini(r, g), b)
	if r >= BURN and g >= BURN and b >= BURN:
		return "W"
	if r >= PALE and g >= PALE and b >= PALE:
		return "w"
	if max_c < 80:
		return "d"
	if b > r + 20 and b >= g:
		return "B"
	if g > r + 20 and b > r + 20:
		return "c"
	if g > r + 25 and g > b + 15:
		return "G"
	if g > b + 25 and g >= r:
		return "g"
	if r > b + 25 and r > 120:
		return "S"
	if max_c - min_c < 18 and r >= 80:
		return "s"
	return "."
