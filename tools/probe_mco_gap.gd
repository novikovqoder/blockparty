# Одноразовая диагностика (П5.8, часть B): сравнивает профили ширины
# силуэта «тело+одежда» и «одежда без тела» по срезам роста. Там, где
# одежда не покрывает тело (открытые руки/голени), силуэт mco-кадра
# сильно уже (геометрии просто нет) — видна разница профилей.
# Запуск: godot --headless -s tools/probe_mco_gap.gd -- <full.png> <mco.png>
extends SceneTree


const BG_TOL: float = 0.06  # допуск цвета фона (доля от 1.0)
const SLICES: int = 20      # срезов по высоте силуэта (0 = верх)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var full := _profile(args[0])
	var mco := _profile(args[1])
	print("срез  full  mco   (доля ширины от max; срез 0 — верх силуэта)")
	for i in SLICES:
		print("%3d  %.3f  %.3f" % [i, full[i], mco[i]])
	quit(0)


## Ширина силуэта в каждом срезе (доля от максимальной), снизу-вверх по bbox.
func _profile(path: String) -> PackedFloat32Array:
	var img := Image.load_from_file(path) as Image
	var bg := img.get_pixel(2, 2)
	var w := img.get_width()
	var h := img.get_height()
	var min_x := w
	var min_y := h
	var max_x := 0
	var max_y := 0
	for y in h:
		for x in w:
			if not _is_bg(img.get_pixel(x, y), bg):
				min_x = mini(min_x, x); max_x = maxi(max_x, x)
				min_y = mini(min_y, y); max_y = maxi(max_y, y)
	var widths := PackedFloat32Array()
	widths.resize(SLICES)
	var max_width := 1.0
	for i in SLICES:
		var y: int = min_y + int(float(max_y - min_y) * float(i) / float(SLICES - 1))
		var hits := 0
		for x in range(min_x, max_x + 1):
			if not _is_bg(img.get_pixel(x, y), bg):
				hits += 1
		widths[i] = hits
		max_width = maxf(max_width, hits)
	for i in SLICES:
		widths[i] /= max_width
	return widths


func _is_bg(c: Color, bg: Color) -> bool:
	return absf(c.r - bg.r) < BG_TOL and absf(c.g - bg.g) < BG_TOL \
		and absf(c.b - bg.b) < BG_TOL
