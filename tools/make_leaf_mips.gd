# П17 п.1 «Листва без таяния» (Castano 2010, alpha-mipmapping): движковая
# генерация мипов усредняет альфу карточек листьев бокс-фильтром — доля
# пикселей выше alpha_cut падает с каждым уровнем, крона вдали редеет
# («таяние»). Тула строит свою цепочку мипов: RGB усредняется с
# премультиплированной альфой (цвет пустых пикселей не подтекает в листву),
# альфа каждого уровня масштабируется так, чтобы УСЛОВНАЯ плотность — доля
# пикселей выше порога среди пикселей «активной» области ( footprint’ы, где
# у уровня 0 есть альфа: карточки листьев и их окрестность) — оставалась
# ≥ 0.85 × уровня 0. Плотность по всей текстуре — неверная метрика:
# пустоты между карточками атласа UV не сэмплят никогда, а буст до
# глобальной цели пересолил бы карточки сплошной альфой. Пороги — все
# alphaTest пресетов ez-tree этого вида листвы. Результат — готовая
# ImageTexture с мипами внутри: assets/visual/trees/leaves/<вид>_mips.res
# (импортёр движка не вмешивается; исходные PNG и их .import остаются —
# тулa читает PNG как Image). Запуск:
#   godot --headless -s res://tools/make_leaf_mips.gd
# Повторный запуск идемпотентен (перезаписывает те же файлы).
extends SceneTree

const LEAVES_DIR: String = "res://assets/visual/trees/leaves"

## Листва и пороги вырезки alphaTest, под которыми её используют пресеты
## ez-tree из manifest.json (лиственные — 0.5; сосновая хвоя 0.3 убрана
## вместе с елями, П18-фикс 3 — на острове только лиственные).
const JOBS: Dictionary = {
	"oak": [0.5],
	"aspen": [0.5],
	"ash": [0.5],
}

## Целевая доля условной плотности уровня N от уровня 0 (план П17: ≥ 0.85).
const COVERAGE_KEEP: float = 0.85


func _init() -> void:
	var made := 0
	for kind: String in JOBS:
		if not _bake_kind(kind, JOBS[kind]):
			quit(1)
			return
		made += 1
	print("make_leaf_mips: готово текстур — %d" % made)
	quit(0)


## Одна текстура: PNG → RGBA8 → мипы с сохранением плотности → .res.
func _bake_kind(kind: String, cuts: Array) -> bool:
	var src_path := "%s/%s.png" % [LEAVES_DIR, kind]
	var image := Image.load_from_file(ProjectSettings.globalize_path(src_path))
	if image == null:
		push_error("make_leaf_mips: не читается %s" % src_path)
		return false
	image.convert(Image.FORMAT_RGBA8)

	# Активная область уровня 0 — пиксели с альфой (карточки листьев):
	# условная плотность считается только по ней.
	var mask := _alpha_mask(image)
	var active: int = 0
	for value: int in mask:
		active += value
	if active == 0:
		push_error("make_leaf_mips: %s без альфы" % src_path)
		return false
	var base_density: Dictionary = {}
	for cut: float in cuts:
		base_density[cut] = _density(image, mask, cut)

	# Собрать данные всех уровней в один массив (RGBA8, паддинга строк нет).
	var full := PackedByteArray()
	var width := image.get_width()
	var height := image.get_height()
	full.append_array(image.get_data())
	var level: Image = image
	var report := "%dx%d: 1.00" % [width, height]
	while width > 1 or height > 1:
		level = _next_mip(level, mask, cuts, base_density)
		mask = _mask_down(mask, width, height)
		width = maxi(1, width >> 1)
		height = maxi(1, height >> 1)
		full.append_array(level.get_data())
		report += " → %d: %.2f" % [width,
			_density(level, mask, float(cuts[0]))
			/ maxf(float(base_density[float(cuts[0])]), 1e-6)]

	# Image с мипами собирается из общих данных: RGBA8 без паддинга строк,
	# уровни идут по порядку от крупных к мелким.
	var mipped := Image.create_from_data(
		image.get_width(), image.get_height(), true,
		Image.FORMAT_RGBA8, full)
	var texture := ImageTexture.create_from_image(mipped)
	var out_path := "%s/%s_mips.res" % [LEAVES_DIR, kind]
	var error := ResourceSaver.save(texture, out_path)
	if error != OK:
		push_error("make_leaf_mips: не записался %s (код %d)" % [out_path, error])
		return false
	var message := "make_leaf_mips: %s — плотность карточек (порог %.1f, " \
		+ "доли от уровня 0): %s"
	print(message % [out_path, float(cuts[0]), report])
	return true


## Следующий мип: RGB — среднее с премультиплированной альфой (цвет
## накапливается с весом альфы), альфа — обычное среднее 2×2; затем альфа
## масштабируется, чтобы условная плотность по каждому порогу была
## ≥ COVERAGE_KEEP × уровня 0. Возвращает новый Image (уровень не меняется).
func _next_mip(
	level: Image, mask: PackedByteArray, cuts: Array, base_density: Dictionary
) -> Image:
	var w := maxi(1, level.get_width() >> 1)
	var h := maxi(1, level.get_height() >> 1)
	var data: PackedByteArray = level.get_data()
	var src_w := level.get_width()
	var next_data := PackedByteArray()
	next_data.resize(w * h * 4)
	var src_px := 0
	var dst_px := 0
	for _y: int in h:
		for _x: int in w:
			var sum_r := 0.0
			var sum_g := 0.0
			var sum_b := 0.0
			var sum_a := 0.0
			for corner: int in 4:
				var p := src_px + (corner & 1) * 4 + (corner >> 1) * src_w * 4
				var a: float = data[p + 3] / 255.0
				sum_r += data[p] / 255.0 * a
				sum_g += data[p + 1] / 255.0 * a
				sum_b += data[p + 2] / 255.0 * a
				sum_a += a
			var alpha: float = sum_a / 4.0
			var norm := 1.0 / maxf(sum_a, 1e-4)
			next_data[dst_px] = _to_byte(sum_r * norm)
			next_data[dst_px + 1] = _to_byte(sum_g * norm)
			next_data[dst_px + 2] = _to_byte(sum_b * norm)
			next_data[dst_px + 3] = _to_byte(alpha)
			src_px += 8
			dst_px += 4
		# Внутренний цикл прошёл строку источника (по 2 текселя на выходной
		# тексель) — пропустить вторую строку пары.
		src_px += src_w * 4
	var mip := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, next_data)
	var mip_mask := _mask_down(mask, level.get_width(), level.get_height())

	# Масштаб альфы: минимальный множитель, при котором условная плотность
	# по каждому порогу достигает цели (бинарный поиск по гистограмме альфы
	# активных пикселей).
	for cut: float in cuts:
		var target: float = COVERAGE_KEEP * float(base_density[cut])
		var factor := _boost_factor(mip, mip_mask, cut, target)
		if factor > 1.0:
			mip = _apply_boost(mip, factor)
	return mip


## Маска альфы (1 — есть альфа) для условной плотности.
static func _alpha_mask(image: Image) -> PackedByteArray:
	var data := image.get_data()
	var mask := PackedByteArray()
	mask.resize(image.get_width() * image.get_height())
	var i := 3
	var px := 0
	while i < data.size():
		mask[px] = 1 if data[i] > 0 else 0
		i += 4
		px += 1
	return mask


## Маска следующего уровня: ИЛИ четырёх потомков (дилатация активной
## области на тексель — фильтр следа выборки растёт с уровнем).
static func _mask_down(
	mask: PackedByteArray, width: int, height: int
) -> PackedByteArray:
	var w := maxi(1, width >> 1)
	var h := maxi(1, height >> 1)
	var out := PackedByteArray()
	out.resize(w * h)
	var src := 0
	var dst := 0
	for _y: int in h:
		for _x: int in w:
			var quad: int = mask[src] + mask[src + 1] \
				+ mask[src + width] + mask[src + width + 1]
			out[dst] = 1 if quad > 0 else 0
			src += 2
			dst += 1
		src += width
	return out


## Условная плотность: доля активных пикселей с альфой ≥ порога.
static func _density(
	image: Image, mask: PackedByteArray, cut: float
) -> float:
	var data := image.get_data()
	var count := 0
	var active := 0
	var i := 3
	var px := 0
	while i < data.size():
		if mask[px] > 0:
			active += 1
			if data[i] / 255.0 >= cut:
				count += 1
		i += 4
		px += 1
	if active == 0:
		return 0.0
	return float(count) / float(active)


## Минимальный множитель альфы, дающий условную плотность ≥ target:
## пиксель проходит порог, если a·f ≥ cut, то есть a ≥ cut/f — бинарный
## поиск по гистограмме альфы активных пикселей (256 корзин).
static func _boost_factor(
	image: Image, mask: PackedByteArray, cut: float, target: float
) -> float:
	if cut <= 0.0:
		return 1.0
	var data := image.get_data()
	var histogram := PackedInt32Array()
	histogram.resize(256)
	histogram.fill(0)
	var active := 0
	var i := 3
	var px := 0
	while i < data.size():
		if mask[px] > 0:
			histogram[data[i]] += 1
			active += 1
		i += 4
		px += 1
	if active == 0:
		return 1.0
	var min_byte := 255
	for bin: int in 256:
		if histogram[bin] > 0:
			min_byte = bin
			break
	if min_byte >= 255:
		return 1.0
	var suffix := PackedInt32Array()
	suffix.resize(257)
	for bin: int in range(255, -1, -1):
		suffix[bin] = suffix[bin + 1] + histogram[bin]
	var low := 1.0
	var high: float = cut / maxf(min_byte / 255.0, 1.0 / 255.0)
	if high <= 1.0 or _covered(suffix, active, cut, low) >= target:
		return 1.0
	for _step: int in 24:
		var middle := (low + high) * 0.5
		if _covered(suffix, active, cut, middle) >= target:
			high = middle
		else:
			low = middle
	return high


## Доля активных пикселей, проходящих порог при множителе.
static func _covered(
	suffix: PackedInt32Array, active: int, cut: float, factor: float
) -> float:
	# Пиксель проходит, если a ≥ cut/f; байт = ceil(a·255 − eps).
	var byte_cut: int = clampi(ceili(cut / factor * 255.0 - 1e-4), 0, 255)
	return float(suffix[byte_cut]) / float(active)


## Умножить альфу уровня на множитель (насыщение к 1.0) — новый Image.
static func _apply_boost(image: Image, factor: float) -> Image:
	var data := image.get_data()
	var i := 3
	while i < data.size():
		data[i] = _to_byte(data[i] / 255.0 * factor)
		i += 4
	return Image.create_from_data(
		image.get_width(), image.get_height(), false,
		Image.FORMAT_RGBA8, data)


static func _to_byte(value: float) -> int:
	return clampi(int(round(value * 255.0)), 0, 255)
