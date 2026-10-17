# Генератор альфа-текстур крон процедурных деревьев Леса (П5.9, доработка
# под эталон EZ-Tree): каждая карточка листвы — гроздь листьев с читаемыми
# листиками по краям и прозрачными «дырами» между ними, хвоя — веточка с
# парами игл «ёлочкой». RGB — оттенок грозди (затемнение к черешку,
# подсветка кончиков, лёгкая вариация тона листа), умножается на палитру
# кроны в canopy.gdshader; A — форма с дырами. Текстуры процедурные,
# наши (CC0), детерминированные (RandomNumberGenerator с фикс. seed).
# Запуск:
#   godot --headless --path . -s tools/make_leaf_textures.gd
extends SceneTree

const SIZE := 1024
const SEED := 20261017

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = SEED
	_make_leaf_cluster("res://assets/visual/leaf_cluster.png")
	_rng.seed = SEED + 1
	_make_needle_cluster("res://assets/visual/needle_cluster.png")
	quit(0)


# Гроздь широких листьев: ~20 листьев веером от черешка (низ карточки,
# UV (0.5, 0) в canopy.gdshader); центральные длиннее — силуэт грозди
# округлый, боковые короче и гнутся наружу. Между листьями прозрачные
# «дыры» — сквозь крону читаются небо и дальние деревья.
func _make_leaf_cluster(path: String) -> void:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var attach := Vector2(SIZE * 0.5, SIZE * 1.02)
	var count := 20
	for i: int in count:
		# Угол от вертикали: равномерный веер −155°…+155° с jitter.
		var spread: float = lerpf(-2.70, 2.70, float(i) / float(count - 1))
		spread += _rng.randf_range(-0.14, 0.14)
		# Центральные листья длиннее — округлый силуэт грозди.
		var length: float = 240.0 + 260.0 * cos(spread * 0.72)
		length *= _rng.randf_range(0.88, 1.12)
		var width: float = length * 0.44 * _rng.randf_range(0.9, 1.1)
		var tone: float = _rng.randf_range(0.88, 1.06)
		# Часть листьев с тёплым кончиком (желтизна на свету) — гроздь
		# не выглядит одним плоским цветом.
		var warm: float = 1.0 if _rng.randf() < 0.35 else 0.0
		# Изгиб листа наружу от центра грозди.
		var bend: float = signf(spread) * _rng.randf_range(0.10, 0.22)
		_paint_leaf(image, attach, spread, length, width, tone, warm, bend)
	image.save_png(path)
	print("leaf cluster: " + path)


# Хвойная веточка: стволик снизу вверх с лёгкой S-волной, ~26 пар игл
# «ёлочкой», иглы длиннее к середине веточки; между иглами дыры.
func _make_needle_cluster(path: String) -> void:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var bottom := Vector2(SIZE * 0.5, SIZE * 1.02)
	var top := Vector2(SIZE * 0.5 + SIZE * 0.05, SIZE * 0.10)
	var nodes := 30
	# Стволик: точки вдоль слегка изогнутой оси.
	var axis: Array[Vector2] = []
	for n: int in nodes:
		var t := float(n) / float(nodes - 1)
		var sway: float = sin(t * TAU * 0.75) * SIZE * 0.045
		axis.append(bottom.lerp(top, t) + Vector2(sway, 0.0))
	# Полоска стволика (сужается к вершине).
	for n: int in nodes - 1:
		var w: float = lerpf(9.0, 3.5, float(n) / float(nodes - 1))
		_paint_strip(image, axis[n], axis[n + 1], w, w * 0.8,
			Color(0.42, 0.40, 0.38, 1.0))
	# Пары игл: пропускаем комель и самый кончик, длиннее к середине.
	for n: int in range(2, nodes - 2):
		var t := float(n) / float(nodes - 1)
		var along: Vector2 = (axis[n + 1] - axis[n]).normalized()
		var perp := Vector2(-along.y, along.x)
		var reach: float = (130.0 + 95.0 * sin(PI * t)) \
			* _rng.randf_range(0.85, 1.15)
		var tone: float = _rng.randf_range(0.90, 1.05)
		var cool: float = 1.0 if _rng.randf() < 0.4 else 0.0
		for side: float in [-1.0, 1.0]:
			var dir: Vector2 = (along * 0.72 + perp * side).normalized()
			_paint_needle(image, axis[n], dir, reach,
				13.0 * _rng.randf_range(0.85, 1.15), tone, cool, side)
	image.save_png(path)
	print("needle cluster: " + path)


# Лист — вытянутая пластина с остриём на конце: полуширина
# w·sin(πt)^0.62, у черешка и кончика сходит в ноль; изгиб — квадратичный
# увод вбок. Оттенок: 0.55 у черешка → 1.0 к кончику (умножается на цвет
# палитры кроны в шейдере — внутри грозди темнее, край светлее), хребет —
# чуть темнее пластины. Край мягкий ~2.5 пикселя — без «пилы».
func _paint_leaf(
		image: Image, attach: Vector2, spread: float, length: float,
		width: float, tone: float, warm: float, bend: float,
) -> void:
	var dir := Vector2(sin(spread), -cos(spread)).normalized()
	var perp := Vector2(-dir.y, dir.x)
	# Бокс листа (изгиб небольшой — берём ось + запас на кривизну).
	var reach := attach + dir * length + perp * (bend * length * signf(bend))
	var min_p := attach.min(reach) - Vector2(width, width) * 1.5 \
		- Vector2(4.0, 4.0)
	var max_p := attach.max(reach) + Vector2(width, width) * 1.5 \
		+ Vector2(4.0, 4.0)
	min_p = min_p.max(Vector2.ZERO)
	max_p = max_p.min(Vector2(SIZE - 1.0, SIZE - 1.0))
	var edge := 2.5
	for y: int in range(int(min_p.y), int(max_p.y) + 1):
		for x: int in range(int(min_p.x), int(max_p.x) + 1):
			var d := Vector2(x, y) - attach
			var u := d.dot(dir)
			if u < -edge or u > length + edge:
				continue
			var t := clampf(u / length, 0.0, 1.0)
			# Кривизна: перпендикулярный увод растёт к кончику.
			var v := d.dot(perp) - bend * length * t * t
			var half_w := width * pow(maxf(sin(PI * t), 0.0), 0.62)
			var alpha := smoothstep(half_w + edge * 0.5, half_w - edge, absf(v)) \
				* smoothstep(0.0, 0.02 + edge / length, t) \
				* (1.0 - smoothstep(1.0, 1.0 + edge / length, u / length))
			if alpha <= 0.0:
				continue
			# Хребет: затемнение к оси листа.
			var vein := 1.0 - 0.10 * exp(-(v * v) / maxf(half_w * half_w, 1.0))
			var value := (0.55 + 0.45 * t) * tone * vein
			var color := Color(value, value, value)
			if warm > 0.0:
				color = color.lerp(
					Color(value, value * 0.95, value * 0.72), 0.30 * t)
			_composite(image, x, y, color, alpha)


# Игла — узкая пластина, сужающаяся к кончику, с лёгким изгибом вверх.
func _paint_needle(
		image: Image, base: Vector2, dir: Vector2, length: float,
		width: float, tone: float, cool: float, side: float,
) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var tip := base + dir * length + Vector2(0.0, -length * 0.18)
	var min_p := base.min(tip) - Vector2(width, width)
	var max_p := base.max(tip) + Vector2(width, width)
	min_p = min_p.max(Vector2.ZERO)
	max_p = max_p.min(Vector2(SIZE - 1.0, SIZE - 1.0))
	var edge := 2.0
	for y: int in range(int(min_p.y), int(max_p.y) + 1):
		for x: int in range(int(min_p.x), int(max_p.x) + 1):
			var d := Vector2(x, y) - base
			var u := d.dot(dir)
			if u < -edge or u > length + edge:
				continue
			var t := clampf(u / length, 0.0, 1.0)
			var lift: float = -length * 0.18 * t * t
			var v := d.dot(perp) - lift
			var half_w := width * (1.0 - 0.85 * t) * maxf(sin(PI * t), 0.05)
			var alpha := smoothstep(half_w + edge * 0.5, half_w - edge, absf(v)) \
				* smoothstep(0.0, 0.05, t) \
				* (1.0 - smoothstep(0.96, 1.0, u / length))
			if alpha <= 0.0:
				continue
			var value := (0.50 + 0.50 * t) * tone
			var color := Color(value, value, value)
			if cool > 0.0:
				color = color.lerp(Color(value * 0.92, value, value * 0.96), 0.5)
			_composite(image, x, y, color, alpha)


# Стволик веточки: полоска между точками (четырёхугольник по нормали).
func _paint_strip(
		image: Image, a: Vector2, b: Vector2, w_a: float, w_b: float,
		color: Color,
) -> void:
	var dir := (b - a).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var corners := [
		a + perp * w_a, a - perp * w_a, b - perp * w_b, b + perp * w_b,
	]
	var min_p: Vector2 = corners[0]
	var max_p: Vector2 = corners[0]
	for c: Vector2 in corners:
		min_p = min_p.min(c)
		max_p = max_p.max(c)
	min_p = min_p.max(Vector2.ZERO).floor()
	max_p = max_p.min(Vector2(SIZE - 1.0, SIZE - 1.0)).floor()
	for y: int in range(int(min_p.y), int(max_p.y) + 1):
		for x: int in range(int(min_p.x), int(max_p.x) + 1):
			var d := Vector2(x, y) - a
			var u := d.dot(dir) / maxf((b - a).length(), 1.0)
			var v := d.dot(perp) - lerpf(-w_a, -w_b, clampf(u, 0.0, 1.0))
			var half_w := lerpf(w_a, w_b, clampf(u, 0.0, 1.0))
			var alpha := smoothstep(half_w + 1.0, half_w - 1.0, absf(v)) \
				* smoothstep(-0.02, 0.02, u) * (1.0 - smoothstep(1.0, 1.02, u))
			if alpha <= 0.0:
				continue
			_composite(image, x, y, color, alpha)


# Композит «поверх»: перекрытие листьев у черешка — берём более плотный.
func _composite(image: Image, x: int, y: int, color: Color, alpha: float) -> void:
	var old := image.get_pixel(x, y)
	if alpha > old.a:
		image.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
