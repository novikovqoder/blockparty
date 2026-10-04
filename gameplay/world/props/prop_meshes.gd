# Процедурные меши предметов (раздел 6 SPEC, «Предметы из gameplay/world/props/»):
# каждое здание/дерево/камень — ArrayMesh из огранённых примитивов
# (6-гранные призмы, конусы, сферы с малым числом сегментов) с цветом
# в вершинах; нормали не пишем — шейдер lowpoly.gdshader затеняет по
# производным на грань. Меши собираются из «деталей» (box/цилиндр/сфера/
# пирамида) со сдвигом, поворотом и детерминированным джиттером — вариант
# предмета задаёт вариацию, никаких randi()/randf() вне rng с сеедом от
# (тип, вариант). Все модели стоят «ногами» в начале координат (origin
# у земли): позиция предмета из IslandGen — точка на рельефе.
#
# Два типа размеров: «метровые» (rock_wall, ruin_block, plank_deck,
# pier_post) — scale равен размерам в метрах, mesh — единичный куб;
# остальные — mesh натурального размера, scale — множитель ~0.85–1.25.
# Коллизии — только типы из IslandGen.SOLID_TYPES, упрощённый бокс
# (collision_size): ствол дерева без кроны, стены и настилы — точно.
class_name PropMeshes
extends RefCounted

const PAL: Palette = preload("res://assets/palette.tres")


## Меш предмета: тип и вариант (варианты отличаются джиттером и деталями).
static func mesh(type: StringName, variant: int) -> ArrayMesh:
	match String(type):
		"tree_leafy":
			return _tree_leafy(variant)
		"tree_spruce":
			return _tree_spruce(variant)
		"bush":
			return _bush(variant)
		"boulder":
			return _boulder(variant)
		"rock_pillar":
			return _rock_pillar(variant)
		"rock_wall":
			return _rock_wall(variant)
		"pebble":
			return _pebble(variant)
		"grass_tuft":
			return _grass_tuft(variant)
		"flower":
			return _flower(variant)
		"ruin_block":
			return _ruin_block(variant)
		"ruin_tower":
			return _ruin_tower()
		"ruin_gate":
			return _ruin_gate()
		"ruin_column":
			return _ruin_column()
		"bench":
			return _bench()
		"board":
			return _board()
		"beacon":
			return _beacon()
		"pier_post":
			return _pier_post()
		"plank_deck":
			return _plank_deck()
		"boat":
			return _boat()
	push_error("Неизвестный тип предмета: %s" % type)
	return ArrayMesh.new()


## Радиус видимости MultiMesh предмета, м (0 — без ограничения;
# SPEC 16: трава исчезает дальше 40 м).
static func visibility_range(type: StringName) -> float:
	match String(type):
		"grass_tuft":
			return 40.0
		"flower":
			return 60.0
		"pebble":
			return 80.0
		"bush":
			return 70.0
	return 0.0


## Размер бокса коллизии предмета (Vector3.ZERO — предмет проходим).
## Для «метровых» типов это сам scale; для остальных — доля натурального
## размера, умноженная на масштаб предмета.
static func collision_size(type: StringName, scale: Vector3) -> Vector3:
	match String(type):
		"rock_wall", "ruin_block", "plank_deck", "pier_post":
			return Vector3(maxf(scale.x, 0.05), maxf(scale.y, 0.05), maxf(scale.z, 0.05))
		"tree_leafy", "tree_spruce":
			return Vector3(0.7 * scale.x, 2.8 * scale.y, 0.7 * scale.x)
		"boulder":
			return Vector3(1.1 * scale.x, 0.8 * scale.y, 1.1 * scale.x)
		"rock_pillar":
			return Vector3(0.95 * scale.x, 2.9 * scale.y, 0.95 * scale.x)
		"ruin_tower":
			return Vector3(1.9, 3.4, 1.9) * scale.x
		"ruin_gate":
			return Vector3(2.4, 3.55, 0.5)
		"ruin_column":
			return Vector3(0.9, 1.6, 0.9) * scale.x
		"bench":
			return Vector3(1.7, 1.0, 0.55)
		"board":
			return Vector3(1.5, 1.6, 0.55)
		"beacon":
			return Vector3(1.9, 4.4, 1.9) * scale.x
		"boat":
			return Vector3(1.3, 0.5, 2.35)
	return Vector3.ZERO


# --- Деревья и растительность ---

## Лиственное дерево: 6-гранный ствол, крона из 2–4 огранённых сфер.
static func _tree_leafy(variant: int) -> ArrayMesh:
	var rng := _rng("tree_leafy", variant)
	var parts: Array = []
	var trunk_h: float = 2.0 + 0.2 * variant
	parts.append(_cyl(0.1, 0.18, trunk_h, 6, PAL.trunk,
		Vector3(0, trunk_h * 0.5, 0)))
	var crown: Color = PAL.zone_leaf[1].lerp(Color.WHITE, 0.06 * variant)
	var blobs: int = 2 + variant
	var radius: float = 0.95 - 0.07 * variant
	for i: int in blobs:
		var angle: float = TAU * (float(i) / float(blobs)) + rng.randf_range(-0.3, 0.3)
		var off := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.0, 0.35)
		var y: float = trunk_h - 0.1 + i * 0.55 * rng.randf_range(0.9, 1.1)
		parts.append(_sphere(radius * (1.0 - 0.22 * i), 5, 2, crown,
			Vector3(off.x, y, off.z), rng, 0.04))
	return _merge(parts)


## Ель: ствол и стопка из трёх конусов.
static func _tree_spruce(variant: int) -> ArrayMesh:
	var rng := _rng("tree_spruce", variant)
	var parts: Array = []
	var trunk_h: float = 1.0 + 0.15 * variant
	parts.append(_cyl(0.09, 0.13, trunk_h, 6, PAL.trunk,
		Vector3(0, trunk_h * 0.5, 0)))
	var needle: Color = PAL.zone_leaf[1].darkened(0.12 + 0.04 * variant)
	var tiers: Array = [
		[1.15, 1.5, 1.35],
		[0.85, 1.15, 2.15],
		[0.52, 0.95, 2.85],
	]
	for tier: Array in tiers:
		var r: float = tier[0] * (1.0 + rng.randf_range(-0.06, 0.06))
		parts.append(_cyl(0.03, r, tier[1], 6, needle,
			Vector3(0, tier[2] + tier[1] * 0.5 - 0.6, 0)))
	return _merge(parts)


## Куст: три огранённых сферы у земли.
static func _bush(variant: int) -> ArrayMesh:
	var rng := _rng("bush", variant)
	var parts: Array = []
	var leaf: Color = PAL.zone_leaf[1].lerp(PAL.grass, 0.25 + 0.1 * variant)
	for blob: Vector3 in [
		Vector3(0, 0.32, 0),
		Vector3(0.3, 0.24, 0.12),
		Vector3(-0.28, 0.22, -0.1),
	]:
		parts.append(_sphere(0.42 - 0.05 * variant, 4, 2, leaf, blob, rng, 0.05))
	return _merge(parts)


## Валун: огранённый многогранник с детерминированным смещением вершин.
static func _boulder(variant: int) -> ArrayMesh:
	var rng := _rng("boulder", variant)
	var parts: Array = [_sphere(0.6, 4, 2, PAL.stone, Vector3(0, 0.42, 0),
		rng, 0.08 + 0.04 * variant, Vector3(1.0, 0.72 + 0.06 * variant, 1.0))]
	return _merge(parts)


## Скальный столб: гранёная колонна с «шапкой».
static func _rock_pillar(variant: int) -> ArrayMesh:
	var rng := _rng("rock_pillar", variant)
	var parts: Array = [
		_cyl(0.3, 0.55, 2.7, 6, PAL.stone, Vector3(0, 1.35, 0)),
		_sphere(0.45, 4, 1, PAL.stone.lerp(Color.WHITE, 0.08),
			Vector3(0, 2.75, 0), rng, 0.02, Vector3(1.0, 0.5, 1.0)),
	]
	return _merge(parts)


## Камешек.
static func _pebble(variant: int) -> ArrayMesh:
	var rng := _rng("pebble", variant)
	return _merge([_sphere(0.14, 4, 1, PAL.stone, Vector3(0, 0.08, 0),
		rng, 0.03, Vector3(1.1 + 0.1 * variant, 0.6, 1.0 - 0.05 * variant))])


## Пучок травы: тонкие конусы-«лезвия».
static func _grass_tuft(variant: int) -> ArrayMesh:
	var rng := _rng("grass_tuft", variant)
	var parts: Array = []
	var blade_color: Color = PAL.grass.lerp(PAL.zone_ground[1], 0.3)
	for i: int in 4 + variant:
		var angle: float = TAU * float(i) / 5.0 + rng.randf_range(-0.4, 0.4)
		var off := Vector3(cos(angle), 0.0, sin(angle)) * 0.06
		parts.append(_cyl(0.008, 0.035, rng.randf_range(0.28, 0.5), 3,
			blade_color.lerp(Color.WHITE, rng.randf_range(0.0, 0.15)),
			Vector3(off.x, 0.2, off.z)))
	return _merge(parts)


## Цветок: стебель и головка (цвет даёт instance-тон из палитры flowers).
static func _flower(variant: int) -> ArrayMesh:
	var parts: Array = [
		_cyl(0.014, 0.022, 0.26, 3, Color(0.55, 0.72, 0.45), Vector3(0, 0.13, 0)),
		_sphere(0.075 + 0.012 * variant, 5, 1, Color.WHITE, Vector3(0, 0.29, 0)),
	]
	return _merge(parts)


# --- Камень: стены и руины ---

## Скальная стена («метровый» тип: scale = длина × высота × глубина,
## единичный меш). Верхний ряд валунов ломает ровную кромку.
static func _rock_wall(variant: int) -> ArrayMesh:
	var rng := _rng("rock_wall", variant)
	var parts: Array = [
		_box(Vector3(0.99, 1.0, 0.99), PAL.stone, Vector3(0, 0.5, 0)),
	]
	# Валунчики на кромке: в относительных единицах (0..1 по длине).
	for i: int in 2 + variant % 2:
		var x: float = 0.25 + 0.5 * float(i) / float(1 + variant % 2) \
			+ rng.randf_range(-0.08, 0.08)
		parts.append(_box(
			Vector3(0.28, 0.1 + 0.04 * variant, 0.8),
			PAL.stone.lerp(Color.WHITE, 0.06),
			Vector3(x - 0.5, 1.02, 0), rng.randf_range(-0.1, 0.1)))
	return _merge(parts)


## Блок стены руин («метровый» тип): кладка со сколотой кромкой.
static func _ruin_block(variant: int) -> ArrayMesh:
	var rng := _rng("ruin_block", variant)
	var brick: Color = PAL.ruin_brick
	var parts: Array = [
		_box(Vector3(0.96, 1.0, 0.96), brick, Vector3(0, 0.5, 0)),
		_box(Vector3(0.6, 0.09, 0.55), brick.lerp(Color.WHITE, 0.1),
			Vector3(rng.randf_range(-0.15, 0.15), 0.99,
				rng.randf_range(-0.15, 0.15)), rng.randf_range(-0.2, 0.2)),
	]
	if variant == 2:
		parts.append(_box(Vector3(0.4, 0.5, 0.1), PAL.ruin_dark,
			Vector3(0, 0.25, 0.48)))
	return _merge(parts)


## Башня руин у ворот: гранёное основание, тело, венец с зубцами и проём.
static func _ruin_tower() -> ArrayMesh:
	var brick: Color = PAL.ruin_brick
	var parts: Array = [
		_box(Vector3(1.9, 0.7, 1.9), brick.darkened(0.08), Vector3(0, 0.35, 0)),
		_cyl(0.78, 0.85, 2.0, 6, brick, Vector3(0, 1.7, 0)),
		_cyl(0.98, 0.98, 0.35, 6, brick.lerp(Color.WHITE, 0.1), Vector3(0, 2.85, 0)),
		_box(Vector3(0.6, 1.0, 0.12), PAL.ruin_dark, Vector3(0, 0.5, 0.82)),
	]
	for i: int in 4:
		var angle: float = TAU * float(i) / 4.0 + PI / 4.0
		var off := Vector3(cos(angle), 0.0, sin(angle)) * 0.8
		parts.append(_box(Vector3(0.3, 0.3, 0.24), brick,
			Vector3(off.x, 3.15, off.z), angle))
	return _merge(parts)


## Ворота руин: тёмная плита в проёме (откроется на П5) в каменной раме.
static func _ruin_gate() -> ArrayMesh:
	var parts: Array = [
		_box(Vector3(2.0, 2.9, 0.32), PAL.ruin_dark, Vector3(0, 1.45, 0)),
		_box(Vector3(0.35, 3.2, 0.45), PAL.ruin_brick, Vector3(-1.05, 1.6, 0)),
		_box(Vector3(0.35, 3.2, 0.45), PAL.ruin_brick, Vector3(1.05, 1.6, 0)),
		_box(Vector3(2.6, 0.5, 0.45), PAL.ruin_brick.lerp(Color.WHITE, 0.08),
			Vector3(0, 3.3, 0)),
	]
	return _merge(parts)


## Обломок колонны: гранёный ствол с упавшим «барабаном».
static func _ruin_column() -> ArrayMesh:
	var parts: Array = [
		_cyl(0.42, 0.46, 1.3, 7, PAL.ruin_brick, Vector3(0, 0.65, 0)),
		_cyl(0.36, 0.42, 0.32, 7, PAL.ruin_brick.lerp(Color.WHITE, 0.07),
			Vector3(0.16, 1.35, -0.12), 0.5),
	]
	return _merge(parts)


# --- Площадь и постройки --

## Лавка у костра (модель смотрит в +Z, спинка — с −Z).
static func _bench() -> ArrayMesh:
	var parts: Array = [
		_box(Vector3(1.6, 0.09, 0.45), PAL.planks, Vector3(0, 0.42, 0)),
		_box(Vector3(0.12, 0.42, 0.4), PAL.planks.darkened(0.12),
			Vector3(-0.65, 0.21, 0)),
		_box(Vector3(0.12, 0.42, 0.4), PAL.planks.darkened(0.12),
			Vector3(0.65, 0.21, 0)),
		_box(Vector3(1.6, 0.5, 0.07), PAL.planks.lerp(Color.WHITE, 0.06),
			Vector3(0, 0.75, -0.21)),
	]
	return _merge(parts)


## Доска мирового события: помост на двух ногах.
static func _board() -> ArrayMesh:
	var parts: Array = [
		_box(Vector3(0.1, 1.3, 0.5), PAL.trunk, Vector3(-0.55, 0.65, 0)),
		_box(Vector3(0.1, 1.3, 0.5), PAL.trunk, Vector3(0.55, 0.65, 0)),
		_box(Vector3(1.35, 0.85, 0.07), PAL.planks, Vector3(0, 1.15, 0)),
		_box(Vector3(1.45, 0.12, 0.14), PAL.planks.darkened(0.1),
			Vector3(0, 1.62, 0)),
	]
	return _merge(parts)


## Маяк (раздел 7): постамент, колонна, фонарь с тёмной «лампой»
## (зажигание — П5) и пирамидальной крышей.
static func _beacon() -> ArrayMesh:
	var stone: Color = PAL.zone_stone[0]
	return _merge([
		_cyl(0.85, 0.95, 0.7, 6, stone.darkened(0.1), Vector3(0, 0.35, 0)),
		_cyl(0.42, 0.5, 2.4, 6, stone, Vector3(0, 1.9, 0)),
		_box(Vector3(0.78, 0.7, 0.78), stone.lerp(Color.WHITE, 0.12),
			Vector3(0, 3.45, 0)),
		# Стекло фонаря чуть выступает из фонаря; до П5 — не светится.
		_box(Vector3(0.52, 0.42, 0.52), PAL.beacon_glow.darkened(0.45),
			Vector3(0, 3.45, 0)),
		# Крыша-пирамида: 4-гранный конус, повёрнут гранями к боксу.
		_cyl(0.02, 0.62, 0.55, 4, stone.darkened(0.05), Vector3(0, 4.07, 0), PI / 4.0),
	])


## Свая пирса/опора моста («метровый» тип): гранёный столб единичной
## высоты со шляпкой.
static func _pier_post() -> ArrayMesh:
	var wood: Color = PAL.planks.darkened(0.15)
	return _merge([
		_cyl(0.46, 0.48, 1.0, 6, wood, Vector3(0, 0.5, 0)),
		_cyl(0.52, 0.52, 0.07, 6, PAL.planks, Vector3(0, 0.965, 0)),
	])


## Настил из досок («метровый» тип: scale = ширина × толщина × длина):
## пять прогонов с щелями, единичный меш.
static func _plank_deck() -> ArrayMesh:
	var parts: Array = []
	for i: int in 5:
		var shade: Color = PAL.planks.lerp(Color.WHITE, 0.06 * ((i * 7) % 3) - 0.03)
		parts.append(_box(Vector3(0.96, 1.0, 0.17), shade,
			Vector3(0, 0.5, i * 0.2 - 0.4)))
	return _merge(parts)


## Лодочка-плот: корпус с носом-клином и скамьёй (модель по +Z).
static func _boat() -> ArrayMesh:
	var hull: Color = PAL.trunk.lerp(PAL.planks, 0.4)
	var parts: Array = [
		_box(Vector3(1.15, 0.35, 1.9), hull, Vector3(0, 0.2, -0.15)),
		_prism(Vector3(1.15, 0.35, 0.7), hull, Vector3(0, 0.2, 1.15)),
		_box(Vector3(1.25, 0.07, 0.09), PAL.planks, Vector3(0, 0.4, -0.9)),
		_box(Vector3(1.25, 0.07, 0.09), PAL.planks, Vector3(0, 0.4, 0.55)),
		_box(Vector3(1.05, 0.06, 0.22), PAL.planks.lerp(Color.WHITE, 0.08),
			Vector3(0, 0.42, -0.2)),
	]
	return _merge(parts)


# --- Детали примитивов ---

## Куб заданного размера; pos — центр.
static func _box(
	size: Vector3, color: Color, pos: Vector3, yaw: float = 0.0
) -> Array:
	var prim := BoxMesh.new()
	prim.size = size
	return _prim(prim, color, pos, yaw)


## Призма-клин (наклонная грань к +Z); pos — центр.
static func _prism(
	size: Vector3, color: Color, pos: Vector3, yaw: float = 0.0
) -> Array:
	var prim := PrismMesh.new()
	prim.size = size
	return _prim(prim, color, pos, yaw)


## Гранёный цилиндр/конус (r_top ≈ 0 — конус); pos — центр по высоте.
static func _cyl(
	r_top: float, r_bottom: float, height: float, segments: int, color: Color,
	pos: Vector3, yaw: float = 0.0,
) -> Array:
	var prim := CylinderMesh.new()
	prim.top_radius = r_top
	prim.bottom_radius = r_bottom
	prim.height = height
	prim.radial_segments = segments
	return _prim(prim, color, pos, yaw)


## Огранённая сфера; pos — центр.
static func _sphere(
	radius: float, segments: int, rings: int, color: Color, pos: Vector3,
	rng: RandomNumberGenerator = null, jitter_amount: float = 0.0,
	squash: Vector3 = Vector3.ONE,
) -> Array:
	var prim := SphereMesh.new()
	prim.radius = radius
	prim.height = radius * 2.0
	prim.radial_segments = segments
	prim.rings = rings
	return _prim(prim, color, pos, 0.0, rng, jitter_amount, squash)


## ГПСЧ детали: сеед от (тип, вариант) — меши не зависят от порядка вызовов.
static func _rng(type: String, variant: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([type, variant])
	return rng


## Массивы поверхности примитива: только вершины с цветом и индексы
## (нормали и UV шейдеру low-poly не нужны), сдвиг/поворот/джиттер
## применяются к вершинам сразу.
static func _prim(
	prim: PrimitiveMesh, color: Color, pos: Vector3, yaw: float,
	rng: RandomNumberGenerator = null, jitter_amount: float = 0.0,
	squash: Vector3 = Vector3.ONE,
) -> Array:
	var arrays: Array = prim.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	colors.resize(verts.size())
	colors.fill(color)
	if jitter_amount > 0.0 and rng != null:
		for i: int in verts.size():
			verts[i] += Vector3(
				rng.randf_range(-jitter_amount, jitter_amount),
				rng.randf_range(-jitter_amount, jitter_amount) * 0.5,
				rng.randf_range(-jitter_amount, jitter_amount),
			)
	var basis := Basis(Vector3.UP, yaw)
	for i: int in verts.size():
		verts[i] = (basis * (verts[i] * squash)) + pos
	arrays[Mesh.ARRAY_COLOR] = colors
	for channel: int in [
		Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2,
	]:
		arrays[channel] = null
	return arrays


## Склеить детали в один ArrayMesh (одна поверхность, сдвиг индексов).
static func _merge(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for arrays: Array in parts:
		var base: int = verts.size()
		verts.append_array(arrays[Mesh.ARRAY_VERTEX])
		colors.append_array(arrays[Mesh.ARRAY_COLOR])
		for index: int in arrays[Mesh.ARRAY_INDEX]:
			indices.append(base + index)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
