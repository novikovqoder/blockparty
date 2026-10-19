# Генератор текстур ночного неба (П5.9 блок 6; доработка-2 П5.13, П9).
# Небо Sky3D рисует звёзды двумя экти-текстурами: starmap — слабый Млечный
# Путь и свечение неба, starfield — россыпь точек-звёзд. Прежняя версия
# рисовала их процедурно; у неё ярчайшие звёзды получались гауссовыми
# пятнами до ~10 px («размытые пятна» прогона владельца), а фактура полосы
# Млечного Пути — fbm, растянутым 2:1 по горизонтали («чёрточки»).
# Доработка-2 П5.13, П9: источник — реальный снимок ночного неба, ночное
# HDRI Poly Haven (CC0, локальная библиотека library/polyhaven/hdris/).
# Позиции, яркость и цвет звёзд извлекаются из снимка (кластеры ярких
# точек над горизонтом), звёзды перерисовываются чёткими точками 1–3 px
# без ореолов; фон снимка (настоящий Млечный Путь и воздушное свечение)
# даёт полосу стармапа. Никакого ГПСЧ — результат детерминирован файлом
# источника. Запуск:
#   анализ кандидатов (без записи):
#     godot --headless -s tools/make_star_textures.gd -- analyze <файл.hdr>...
#   сборка текстур (записывает assets/visual/sky_starmap.png и
#   sky_starfield.png):
#     godot --headless -s tools/make_star_textures.gd -- build <файл.hdr>
extends SceneTree

## Источник по умолчанию (Poly Haven, rogland_clear_night — эталонно чистое
## звёздное небо с Млечным Путём; CC0). Локальная библиотека не в git.
const DEFAULT_SOURCE := (
	"/home/ai-agent/blockparty/library/polyhaven/hdris/rogland_clear_night/"
	+ "rogland_clear_night_4k.hdr")

## Размер выходных текстур: 4K-экти — звёзды чёткие при любом зуме камеры.
const OUT_SIZE := Vector2i(4096, 2048)
## Пик полосы Млечного Пути в текстуре стармапа. Шейдер умножает на 0.71
## (starmap_color) и контраст mix(v, v³, 0.855): 0.62 → ~0.20 эффективных —
## «слабый Млечный Путь», не выбеленный и не чёрный.
const BAND_PEAK := 0.62
## Кластеры ярче — не звёзды (облака, спутники): отбрасываются.
const CLUSTER_MAX_AREA := 90
## Порог избытка яркости над фоном, в сигмах шума неба.
const STAR_SIGMA := 4.0
## Верхняя граница числа звёзд — защита от шума заниженного порога.
const STAR_COUNT_CAP := 16000
## Блок фоновой карты, px (32 → сетка 128×64 для 4K).
const BLOCK_SHIFT := 5

var _src_w := 0
var _src_h := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "analyze":
		for path: String in args.slice(1):
			_analyze(path)
	elif args.size() >= 1 and args[0] == "build":
		_build(args[1] if args.size() > 1 else DEFAULT_SOURCE)
	else:
		print("использование: -- analyze <hdr>... | -- build [<hdr>]")
	quit(0)


# --- Разбор Radiance .hdr (RGBE, RLE-сканлайны; формат Poly Haven) ---


func _parse_hdr(path: String) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("не открывается: %s" % path)
		return {}
	var line := file.get_line()
	if not line.begins_with("#?"):
		push_error("%s: не Radiance .hdr" % path)
		return {}
	var width := 0
	var height := 0
	# Спецификация Radiance: строки заголовка, пустая строка, затем строка
	# размеров «-Y N +X M» — размеры ищем до неё, пустые строки пропуская.
	while not file.eof_reached():
		line = file.get_line()
		if line.begins_with("-Y"):
			var parts := line.split(" ", false)
			height = int(parts[1])
			width = int(parts[3])
			break
	if width <= 0 or height <= 0:
		push_error("%s: размеры не найдены" % path)
		return {}
	# Линейные RGB в плоском массиве 3×float на пиксель (без Image —
	# пер-пиксельные вызовы движка на 8 Мп слишком медленные).
	var rgb := PackedFloat32Array()
	rgb.resize(width * height * 3)
	var chan := PackedByteArray()
	chan.resize(width * 4)
	for y: int in height:
		var b0 := file.get_8()
		var b1 := file.get_8()
		var b2 := file.get_8()
		var b3 := file.get_8()
		if b0 != 2 or b1 != 2 or ((b2 << 8) | b3) != width:
			push_error("%s: сканлайн %d не RLE" % [path, y])
			return {}
		for c: int in 4:
			var pos := 0
			while pos < width:
				var code := file.get_8()
				if code > 128:
					var run := code - 128
					var value := file.get_8()
					for i: int in run:
						chan[c * width + pos + i] = value
					pos += run
				else:
					for i: int in code:
						chan[c * width + pos + i] = file.get_8()
					pos += code
		var row := y * width * 3
		for x: int in width:
			var i := row + x * 3
			var e := chan[3 * width + x]
			if e == 0:
				rgb[i] = 0.0
				rgb[i + 1] = 0.0
				rgb[i + 2] = 0.0
			else:
				var scale := pow(2.0, e - 128) / 256.0
				rgb[i] = (chan[x] + 0.5) * scale
				rgb[i + 1] = (chan[width + x] + 0.5) * scale
				rgb[i + 2] = (chan[2 * width + x] + 0.5) * scale
	print("  разбор %dx%d: %d мс" % [width, height, Time.get_ticks_msec() - t0])
	return {"w": width, "h": height, "rgb": rgb}


func _lum_at(rgb: PackedFloat32Array, i: int) -> float:
	return 0.2126 * rgb[i] + 0.7152 * rgb[i + 1] + 0.0722 * rgb[i + 2]


# --- Фон неба: блочные средние по верхней полусфере ---


## Сетка блоков BLOCK×BLOCK px: средний цвет фона (звёзды редки и на
## среднее не влияют). Под горизонтом фон зеркалится из неба — половина
## снимка с землёй не используется. Возвращает блоки RGB и их люминанс.
func _background_map(img: Dictionary) -> Dictionary:
	var w: int = img["w"]
	var h: int = img["h"]
	var rgb: PackedFloat32Array = img["rgb"]
	var sky_h: int = h / 2 - 2
	var bw := w >> BLOCK_SHIFT
	var bh := sky_h >> BLOCK_SHIFT
	var blocks := PackedFloat32Array()
	blocks.resize(bw * bh * 3)
	for by: int in bh:
		var y0 := by << BLOCK_SHIFT
		for bx: int in bw:
			var x0 := bx << BLOCK_SHIFT
			var sum_r := 0.0
			var sum_g := 0.0
			var sum_b := 0.0
			for y: int in range(y0, y0 + (1 << BLOCK_SHIFT)):
				var row := y * w * 3
				for x: int in range(x0, x0 + (1 << BLOCK_SHIFT)):
					var i := row + x * 3
					sum_r += rgb[i]
					sum_g += rgb[i + 1]
					sum_b += rgb[i + 2]
			var n := float(1 << BLOCK_SHIFT) * float(1 << BLOCK_SHIFT)
			var bi := (by * bw + bx) * 3
			blocks[bi] = sum_r / n
			blocks[bi + 1] = sum_g / n
			blocks[bi + 2] = sum_b / n
	return {"bw": bw, "bh": bh, "blocks": blocks, "sky_h": sky_h}


# --- Звёзды: кластеры избытка яркости над фоном ---


## Индекс блока фоновой карты для пикселя (последний блок дотягивается
## до горизонта — sky_h не кратен размеру блока).
func _block_at(bw: int, bh: int, px: int, py: int) -> int:
	return mini(py >> BLOCK_SHIFT, bh - 1) * bw \
		+ mini(px >> BLOCK_SHIFT, bw - 1)


func _detect_stars(img: Dictionary, bg: Dictionary) -> Array[Dictionary]:
	var t0 := Time.get_ticks_msec()
	var w: int = img["w"]
	var rgb: PackedFloat32Array = img["rgb"]
	var bw: int = bg["bw"]
	var bh: int = bg["bh"]
	var blocks: PackedFloat32Array = bg["blocks"]
	var sky_h: int = bg["sky_h"]
	# Люминанс блоков фона (ближайший блок — порог детекции не любит
	# билинейные изыски, скорость важнее).
	var block_lum := PackedFloat32Array()
	block_lum.resize(bw * bh)
	for bi: int in bw * bh:
		block_lum[bi] = _lum_at(blocks, bi * 3)
	# Порог: сигма шума неба — робастная оценка по разреженной выборке
	# избытков (межпроцентильный размах), затем ×STAR_SIGMA.
	var sample: Array[float] = []
	for p: int in range(0, w * sky_h, 37):
		var i := p * 3
		sample.append(_lum_at(rgb, i)
			- block_lum[_block_at(bw, bh, p % w, p / w)])
	sample.sort()
	var p16: float = sample[int(sample.size() * 0.16)]
	var p84: float = sample[int(sample.size() * 0.84)]
	var sigma := maxf((p84 - p16) * 0.5, 1e-6)
	var threshold := maxf(sigma * STAR_SIGMA, 2e-4)
	# Кандидаты: избыток над фоном (индекс пикселя py*w+px).
	var cand := PackedInt32Array()
	for py: int in sky_h:
		var row := py * w * 3
		for px: int in w:
			var i := row + px * 3
			if _lum_at(rgb, i) > threshold \
					+ block_lum[_block_at(bw, bh, px, py)]:
				cand.append(py * w + px)
	var claimed := PackedByteArray()
	claimed.resize(w * sky_h)
	var stars: Array[Dictionary] = []
	var queue := PackedInt32Array()
	for head: int in cand:
		if claimed[head] == 1:
			continue
		queue.clear()
		queue.append(head)
		claimed[head] = 1
		var area := 0
		var sum_w := 0.0
		var sum_x := 0.0
		var sum_y := 0.0
		var peak_ex := 0.0
		var col := Vector3.ZERO
		var at := 0
		var too_big := false
		while at < queue.size() and not too_big:
			var p := queue[at]
			at += 1
			area += 1
			if area > CLUSTER_MAX_AREA:
				too_big = true
				break
			var px := p % w
			var py := p / w
			var i := p * 3
			var bi := _block_at(bw, bh, px, py) * 3
			var ex_r := rgb[i] - blocks[bi]
			var ex_g := rgb[i + 1] - blocks[bi + 1]
			var ex_b := rgb[i + 2] - blocks[bi + 2]
			var ex_l := maxf(
				0.2126 * ex_r + 0.7152 * ex_g + 0.0722 * ex_b, 0.0)
			sum_w += ex_l
			sum_x += ex_l * px
			sum_y += ex_l * py
			peak_ex = maxf(peak_ex, ex_l)
			col += Vector3(maxf(ex_r, 0.0), maxf(ex_g, 0.0), maxf(ex_b, 0.0))
			for d: int in 4:
				var nx := px + (1 if d == 0 else -1 if d == 1 else 0)
				var ny := py + (0 if d < 2 else 1 if d == 2 else -1)
				if nx < 0 or nx >= w or ny < 0 or ny >= sky_h:
					continue
				var np := ny * w + nx
				if claimed[np] == 1:
					continue
				var ni := np * 3
				if _lum_at(rgb, ni) > threshold * 0.5 \
						+ block_lum[_block_at(bw, bh, nx, ny)]:
					claimed[np] = 1
					queue.append(np)
		# Кластеры, чей пик едва выше порога — шум сенсора, не звёзды:
		# у настоящей звезды ядро хотя бы в 1.3 раза выше порога.
		if too_big or sum_w <= 0.0 or peak_ex < threshold * 1.3:
			continue
		stars.append({
			"x": sum_x / sum_w,
			"y": sum_y / sum_w,
			"flux": sum_w,
			"col": Vector3(col.x / sum_w, col.y / sum_w, col.z / sum_w),
		})
	stars.sort_custom(func(a: Dictionary, b: Dictionary): return a["flux"] > b["flux"])
	if stars.size() > STAR_COUNT_CAP:
		stars.resize(STAR_COUNT_CAP)
	print("  звёзды: %d (порог %.5f, сигма %.5f, %d мс)" % [
		stars.size(), threshold, sigma, Time.get_ticks_msec() - t0])
	return stars


# --- Анализ кандидатов ---


func _analyze(path: String) -> void:
	print("== %s ==" % path)
	var img := _parse_hdr(path)
	if img.is_empty():
		return
	var w: int = img["w"]
	var rgb: PackedFloat32Array = img["rgb"]
	var sky_h: int = img["h"] / 2 - 2
	var lums := PackedFloat32Array()
	lums.resize(sky_h * w)
	for p: int in sky_h * w:
		lums[p] = _lum_at(rgb, p * 3)
	lums.sort()
	print("  небо: p50 %.5f p99 %.4f max %.2f" % [
		lums[lums.size() * 50 / 100],
		lums[lums.size() * 99 / 100],
		lums[lums.size() - 1]])
	var bg := _background_map(img)
	var stars := _detect_stars(img, bg)
	var warm := 0
	var cold := 0
	for star: Dictionary in stars.slice(0, mini(500, stars.size())):
		var c: Vector3 = star["col"]
		if c.x > c.z * 1.12:
			warm += 1
		elif c.z > c.x * 1.12:
			cold += 1
	print("  из top-500: тёплых %d, холодных %d" % [warm, cold])


# --- Сборка текстур ---


func _build(path: String) -> void:
	var t0 := Time.get_ticks_msec()
	var img := _parse_hdr(path)
	if img.is_empty():
		return
	_src_w = img["w"]
	_src_h = img["h"]
	var bg := _background_map(img)
	var stars := _detect_stars(img, bg)
	if stars.size() < 500:
		push_error("звёзд слишком мало: %d — источник забракован" % stars.size())
		return
	_write_starfield(stars)
	_write_starmap(img, bg)
	print("сборка: %d мс" % (Time.get_ticks_msec() - t0))


## Чёткие точки: ядро 1–2 px с быстрым спадом, без гауссовых ореолов.
## Яркие звёзды чуть крупнее, тусклые — субпиксельные точки.
func _write_starfield(stars: Array[Dictionary]) -> void:
	var w := OUT_SIZE.x
	var h := OUT_SIZE.y
	var sx := float(w) / float(_src_w)
	var sy := float(h) / float(_src_h)
	# Норма яркости — 99-й перцентель потока: одиночные выбросы (планета,
	# горячий пиксель) не сжимают кривую всем остальным звёздам.
	var flux_ref: float = stars[mini(int(stars.size() * 0.01), stars.size() - 1)]["flux"]
	var accum := PackedFloat32Array()
	accum.resize(w * h * 3)
	for star: Dictionary in stars:
		var peak: float = clampf(pow(star["flux"] / flux_ref, 0.28), 0.16, 1.0)
		var radius: float = 0.55 + 0.75 * pow(peak, 1.5)
		var cx: float = star["x"] * sx
		var cy: float = star["y"] * sy
		# Цвет звезды нормируется по максимальному каналу: доминирующий
		# канал пика достигает 1.0, яркость задаёт peak (нормировка по
		# длине вектора гасила бы белые звёзды до ~0.6 яркости).
		var c: Vector3 = star["col"]
		var cmax := maxf(c.x, maxf(c.y, c.z))
		if cmax < 0.001:
			c = Vector3.ONE
		else:
			c /= cmax
		var reach := ceili(radius * 2.5)
		for py: int in range(ceili(cy) - reach, ceili(cy) + reach + 1):
			if py < 0 or py >= h:
				continue
			for px: int in range(int(cx) - reach, int(cx) + reach + 1):
				var dx := (float(px) - cx) / radius
				var dy := (float(py) - cy) / radius
				var amp := peak * exp(-2.6 * (dx * dx + dy * dy))
				if amp < 0.004:
					continue
				var wx := (px + w) % w
				var i := (py * w + wx) * 3
				accum[i] = minf(accum[i] + c.x * amp, 1.0)
				accum[i + 1] = minf(accum[i + 1] + c.y * amp, 1.0)
				accum[i + 2] = minf(accum[i + 2] + c.z * amp, 1.0)
	_write_png("res://assets/visual/sky_starfield.png", accum, w, h)
	var bright_threshold := pow(0.6, 1.0 / 0.28) * flux_ref
	var bright := 0
	for star: Dictionary in stars:
		if star["flux"] > bright_threshold:
			bright += 1
	print("starfield: %d звёзд, ярких (peak>0.6) %d" % [stars.size(), bright])


## Стармап: настоящий Млечный Путь со снимка. Световой купол засветки у
## горизонта занимает целый пояс высоты — вычитается пер-поясной базой
## (35-й перцентиль блочной яркости пояса), остаётся локально яркое:
## полоса галактики и её пыль. Строится в разрешении блоков и тянется
## бикубиком движка — широкая и мягкая, без мелкой фактуры и «чёрточек».
func _write_starmap(img: Dictionary, bg: Dictionary) -> void:
	var bw: int = bg["bw"]
	var bh: int = bg["bh"]
	var blocks: PackedFloat32Array = bg["blocks"]
	# Избыток над базой своего пояса, с сохранением цвета блока.
	var excess := PackedFloat32Array()
	excess.resize(bw * bh * 3)
	var band_raw := 0.0
	for by: int in bh:
		var ring: Array[float] = []
		for bx: int in bw:
			ring.append(_lum_at(blocks, (by * bw + bx) * 3))
		ring.sort()
		var base: float = ring[int(ring.size() * 0.35)]
		for bx: int in bw:
			var bi := (by * bw + bx) * 3
			var l := _lum_at(blocks, bi)
			var ex := maxf(l - base, 0.0) / maxf(l, 1e-6)
			band_raw = maxf(band_raw, ex * l)
			for c: int in 3:
				excess[bi + c] = blocks[bi + c] * ex
	var gain := BAND_PEAK / maxf(band_raw, 1e-6)
	# Малое изображение блоков: верх — небо, низ — зеркало неба (пол
	# снимка с землёй не используется, под горизонтом свечение зеркалится).
	# Остатки ниже 6% полосы гасятся до нуля — шум блоков не даёт пятен.
	var small := Image.create(bw, bh * 2, false, Image.FORMAT_RGB8)
	for y: int in bh * 2:
		var sy := y if y < bh else bh * 2 - 1 - y
		for x: int in bw:
			var bi := (sy * bw + x) * 3
			var ex_l := _lum_at(excess, bi)
			var fade := clampf(ex_l / (band_raw * 0.06), 0.0, 1.0)
			small.set_pixel(x, y, Color(
				clampf(excess[bi] * gain * fade, 0.0, 1.0),
				clampf(excess[bi + 1] * gain * fade, 0.0, 1.0),
				clampf(excess[bi + 2] * gain * fade, 0.0, 1.0)))
	small.resize(OUT_SIZE.x, OUT_SIZE.y, Image.INTERPOLATE_CUBIC)
	var err := small.save_png("res://assets/visual/sky_starmap.png")
	if err != OK:
		push_error("starmap не записан (err %d)" % err)
	else:
		print("starmap: полоса %.4f→%.2f, записан" % [band_raw, BAND_PEAK])


## Линейные 0..1 float → 8-бит PNG (мип-мапы включит импортёр проекта;
## их наличие контролирует тест текстурного аудита).
func _write_png(path: String, accum: PackedFloat32Array, w: int, h: int) -> void:
	var bytes := PackedByteArray()
	bytes.resize(w * h * 3)
	for p: int in w * h:
		bytes[p * 3] = int(clampf(accum[p * 3], 0.0, 1.0) * 255.0 + 0.5)
		bytes[p * 3 + 1] = int(clampf(accum[p * 3 + 1], 0.0, 1.0) * 255.0 + 0.5)
		bytes[p * 3 + 2] = int(clampf(accum[p * 3 + 2], 0.0, 1.0) * 255.0 + 0.5)
	var image := Image.create_from_data(w, h, false, Image.FORMAT_RGB8, bytes)
	var err := image.save_png(path)
	if err != OK:
		push_error("не записан %s (err %d)" % [path, err])
	else:
		print("записан: %s" % path)
