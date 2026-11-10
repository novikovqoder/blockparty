# Панельная пятиэтажка района (постапокалипсис): меш строится кодом —
# цоколь, панели со швами (у каждой свой тон), окна с откосами (стекло,
# выбитые, заколоченные), подъезды с козырьком и окнами лестничной клетки,
# балконы с обратной стороны, плоская крыша с парапетом. Пока только
# внешний вид: внутрь зайти нельзя (коллизия — коробка дома).
# Локальные оси: длина по X, глубина по Z, подъезды смотрят в +Z.
# brick = true — кирпичная коробка без швов и балконов (руины, все окна выбиты).
class_name PanelHouse
extends RefCounted

const BAY: float = 3.2
const FLOOR_H: float = 2.8
const PLINTH: float = 0.9
const PARAPET: float = 0.5
const WIN_W: float = 1.5
const WIN_H: float = 1.45
const SILL: float = 0.85
const REVEAL: float = 0.22
const GROUP_ENTRANCE: StringName = &"district_entrance"


## Высота стены до парапета, м.
static func wall_top(floors: int) -> float:
	return PLINTH + float(floors) * FLOOR_H


## Номера секций (пролётов) с подъездами.
static func stair_bays(bays: int, entrances: int) -> Array[int]:
	var result: Array[int] = []
	for e: int in entrances:
		result.append(int(floorf((float(e) + 0.5) * float(bays) / float(entrances))))
	return result


static func bay_count(length: float) -> int:
	return maxi(1, roundi(length / BAY))


static func build(
	house_name: String, length: float, depth: float, floors: int,
	entrances: int, open_entrance: int, seed_value: int, brick: bool = false
) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var kit := MeshKit.new()
	var bays: int = bay_count(length)
	var bay: float = length / float(bays)
	var top: float = wall_top(floors)
	var stairs: Array[int] = stair_bays(bays, entrances)
	var root := Node3D.new()
	root.name = house_name

	kit.add_box(
		&"plinth", Vector3(0.0, PLINTH * 0.5, 0.0),
		Vector3(length + 0.12, PLINTH, depth + 0.12), Color.WHITE,
		Basis.IDENTITY, true)

	# Фасады: 0 — со стороны подъездов (+Z), 1 — обратный (−Z).
	for side: int in 2:
		var right := Vector3.RIGHT if side == 0 else Vector3.LEFT
		var normal := Vector3.BACK if side == 0 else Vector3.FORWARD
		var origin := Vector3(
			-length * 0.5 if side == 0 else length * 0.5, PLINTH,
			depth * 0.5 if side == 0 else -depth * 0.5)
		var basis := Basis(right, Vector3.UP, normal)
		for i: int in bays:
			var is_stair: bool = side == 0 and i in stairs
			for f: int in floors:
				var u0: float = float(i) * bay
				var v0: float = float(f) * FLOOR_H
				var tone: Color = _panel_tone(rng, f, floors, brick)
				var hole := Rect2()
				if is_stair:
					if f > 0:
						hole = Rect2(bay * 0.5 - 0.6, 0.2, 1.2, 0.9)
				else:
					hole = Rect2((bay - WIN_W) * 0.5, SILL, WIN_W, WIN_H)
				var pane: int = _pane_kind(rng, brick, is_stair)
				_cell(kit, origin, basis, u0, v0, bay, FLOOR_H, hole, tone, pane, rng, not brick)
				if side == 1 and not brick and f >= 1 and i % 4 in [1, 2]:
					_balcony(kit, origin, basis, u0, v0, bay, rng)

	# Торцы: глухие панели.
	var end_cells: int = maxi(1, roundi(depth / 3.0))
	var end_w: float = depth / float(end_cells)
	for side: int in 2:
		var right := Vector3.FORWARD if side == 0 else Vector3.BACK
		var normal := Vector3.RIGHT if side == 0 else Vector3.LEFT
		var origin := Vector3(
			length * 0.5 if side == 0 else -length * 0.5, PLINTH,
			depth * 0.5 if side == 0 else -depth * 0.5)
		var basis := Basis(right, Vector3.UP, normal)
		for i: int in end_cells:
			for f: int in floors:
				_cell(
					kit, origin, basis, float(i) * end_w, float(f) * FLOOR_H,
					end_w, FLOOR_H, Rect2(), _panel_tone(rng, f, floors, brick),
					0, rng, not brick)

	_ivy(kit, rng, length, depth, top, brick)

	# Крыша с парапетом, будки выходов на крышу и вентшахты.
	var hx: float = length * 0.5
	var hz: float = depth * 0.5
	kit.add_quad(
		&"roof", Vector3(-hx, top, hz), Vector3(hx, top, hz),
		Vector3(hx, top, -hz), Vector3(-hx, top, -hz))
	for side: int in 2:
		var sign: float = 1.0 if side == 0 else -1.0
		kit.add_box(
			&"concrete", Vector3(0.0, top + PARAPET * 0.5, sign * (hz - 0.12)),
			Vector3(length, PARAPET, 0.24))
		kit.add_box(
			&"concrete", Vector3(sign * (hx - 0.12), top + PARAPET * 0.5, 0.0),
			Vector3(0.24, PARAPET, depth - 0.48))
	for i: int in stairs:
		var x: float = -hx + (float(i) + 0.5) * bay
		kit.add_box(&"concrete", Vector3(x, top + 0.55, 0.0), Vector3(2.4, 1.1, 2.4))
		kit.add_box(
			&"metal", Vector3(x + 3.0, top + 0.6, rng.randf_range(-1.5, 1.5)),
			Vector3(0.5, 1.2, 0.5))

	# Подъезды: ступени, дверь, козырёк на стойках.
	for e: int in stairs.size():
		var x: float = -hx + (float(stairs[e]) + 0.5) * bay
		var open: bool = e == open_entrance
		_entrance(kit, x, hz, open)
		var marker := Node3D.new()
		marker.name = "EntranceOpen" if open else "Entrance%d" % e
		marker.position = Vector3(x, 0.2, hz + 0.2)
		marker.add_to_group(GROUP_ENTRANCE)
		root.add_child(marker)

	var instance := MeshInstance3D.new()
	instance.name = "Mesh"
	instance.mesh = kit.commit(DistrictMaterials.house_set(brick))
	root.add_child(instance)
	root.set_meta(&"triangles", kit.triangle_count())
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, top + PARAPET, depth)
	SolidBody.add(root, shape, Vector3(0.0, (top + PARAPET) * 0.5, 0.0))
	return root


## Плющ: «шторы» листьев снизу вверх на всех четырёх стенах (у руин гуще),
## плотность листьев убывает к верху шторы.
static func _ivy(
	kit: MeshKit, rng: RandomNumberGenerator, length: float, depth: float,
	top: float, brick: bool
) -> void:
	var hx: float = length * 0.5
	var hz: float = depth * 0.5
	# Стены: начало, направление вдоль стены, наружная нормаль, длина.
	var walls: Array = [
		[Vector3(-hx, 0.0, hz), Vector3.RIGHT, Vector3.BACK, length],
		[Vector3(hx, 0.0, -hz), Vector3.LEFT, Vector3.FORWARD, length],
		[Vector3(hx, 0.0, hz), Vector3.FORWARD, Vector3.RIGHT, depth],
		[Vector3(-hx, 0.0, -hz), Vector3.BACK, Vector3.LEFT, depth],
	]
	var per_m: float = 1.0 / 5.0 if brick else 1.0 / 9.0
	for wall: Array in walls:
		var start: Vector3 = wall[0]
		var along: Vector3 = wall[1]
		var normal: Vector3 = wall[2]
		var span: float = wall[3]
		var columns: int = maxi(1, roundi(span * per_m * rng.randf_range(0.6, 1.3)))
		for c: int in columns:
			var cx: float = rng.randf_range(0.6, span - 0.6)
			var height: float = minf(top + 0.3, rng.randf_range(2.5, top * (1.0 if brick else 0.85)))
			var width: float = rng.randf_range(1.0, 3.2)
			var area: float = width * height * 0.7
			var leaves: int = int(area * (34.0 if brick else 26.0))
			for i: int in leaves:
				# Высота: чаще внизу (квадрат случайного), штора сужается к верху.
				var t: float = rng.randf()
				var y: float = t * t * height
				var w_here: float = width * (1.0 - 0.6 * y / height)
				var u: float = clampf(cx + rng.randf_range(-0.5, 0.5) * w_here, 0.1, span - 0.1)
				var size: float = rng.randf_range(0.16, 0.26)
				var angle: float = rng.randf_range(0.0, TAU)
				var out: float = rng.randf_range(0.03, 0.14)
				var tilt: float = rng.randf_range(0.2, 0.7)
				var center: Vector3 = start + along * u + Vector3.UP * (y + 0.05) + normal * out
				var right: Vector3 = (along * cos(angle) + Vector3.UP * sin(angle)) * size
				var up: Vector3 = (Vector3.UP * cos(angle) - along * sin(angle)) * size
				up = (up + normal * size * tilt).normalized() * size
				var tone: float = rng.randf_range(0.55, 1.0)
				kit.add_card(
					&"ivy", center, right, up, (normal + Vector3.UP * 0.3).normalized(),
					Color(tone * rng.randf_range(0.85, 1.05), tone, tone * 0.8))


static func _panel_tone(
	rng: RandomNumberGenerator, floor_index: int, floors: int, brick: bool
) -> Color:
	var g: float = rng.randf_range(0.84, 1.02)
	g *= 0.92 + 0.08 * float(floor_index) / float(maxi(1, floors - 1))
	var w: float = rng.randf_range(-0.025, 0.025)
	if brick:
		g = lerpf(g, 0.92, 0.6)
	return Color(g * (1.0 + w), g, g * (1.0 - w))


## Вид проёма: 0 — стекло, 1 — выбито, 2 — заколочено.
static func _pane_kind(rng: RandomNumberGenerator, brick: bool, stair: bool) -> int:
	var roll: float = rng.randf()
	if brick:
		return 1
	if stair:
		return 0 if roll < 0.5 else 1
	if roll < 0.5:
		return 0
	return 1 if roll < 0.86 else 2


static func _pt(origin: Vector3, basis: Basis, u: float, v: float, depth: float) -> Vector3:
	return origin + basis.x * u + basis.y * v - basis.z * depth


## Ячейка фасада (панель) с проёмом hole (в координатах ячейки; пустой
## Rect2 — глухая панель): стена вокруг проёма, откосы, заполнение, шов.
static func _cell(
	kit: MeshKit, origin: Vector3, basis: Basis, u0: float, v0: float,
	w: float, h: float, hole: Rect2, tone: Color, pane: int,
	rng: RandomNumberGenerator, seams: bool
) -> void:
	var u1: float = u0 + w
	var v1: float = v0 + h
	if hole.size.x <= 0.0:
		kit.add_quad(
			&"wall", _pt(origin, basis, u0, v0, 0.0), _pt(origin, basis, u1, v0, 0.0),
			_pt(origin, basis, u1, v1, 0.0), _pt(origin, basis, u0, v1, 0.0), tone)
	else:
		var a0: float = u0 + hole.position.x
		var a1: float = a0 + hole.size.x
		var b0: float = v0 + hole.position.y
		var b1: float = b0 + hole.size.y
		var strips: Array = [
			[u0, v0, a0, v1], [a1, v0, u1, v1], [a0, v0, a1, b0], [a0, b1, a1, v1],
		]
		for s: Array in strips:
			kit.add_quad(
				&"wall", _pt(origin, basis, s[0], s[1], 0.0),
				_pt(origin, basis, s[2], s[1], 0.0),
				_pt(origin, basis, s[2], s[3], 0.0),
				_pt(origin, basis, s[0], s[3], 0.0), tone)
		var shade: Color = tone * 0.78
		var r: float = REVEAL
		kit.add_quad(
			&"wall", _pt(origin, basis, a0, b0, 0.0), _pt(origin, basis, a0, b0, r),
			_pt(origin, basis, a0, b1, r), _pt(origin, basis, a0, b1, 0.0), shade)
		kit.add_quad(
			&"wall", _pt(origin, basis, a1, b0, r), _pt(origin, basis, a1, b0, 0.0),
			_pt(origin, basis, a1, b1, 0.0), _pt(origin, basis, a1, b1, r), shade)
		kit.add_quad(
			&"wall", _pt(origin, basis, a0, b0, 0.0), _pt(origin, basis, a1, b0, 0.0),
			_pt(origin, basis, a1, b0, r), _pt(origin, basis, a0, b0, r), shade)
		kit.add_quad(
			&"wall", _pt(origin, basis, a0, b1, r), _pt(origin, basis, a1, b1, r),
			_pt(origin, basis, a1, b1, 0.0), _pt(origin, basis, a0, b1, 0.0), shade)
		var key: StringName = &"glass" if pane == 0 else &"void"
		kit.add_quad(
			key, _pt(origin, basis, a0, b0, r), _pt(origin, basis, a1, b0, r),
			_pt(origin, basis, a1, b1, r), _pt(origin, basis, a0, b1, r))
		var cu: float = (a0 + a1) * 0.5
		var cv: float = (b0 + b1) * 0.5
		if pane == 0:
			# Переплёт: рама по контуру, стойка и горизонталь.
			var d: float = r - 0.03
			var fw: float = 0.06
			for bar: Array in [
				[cu, b0 + fw * 0.5, hole.size.x, fw], [cu, b1 - fw * 0.5, hole.size.x, fw],
				[a0 + fw * 0.5, cv, fw, hole.size.y], [a1 - fw * 0.5, cv, fw, hole.size.y],
				[cu, cv, fw, hole.size.y], [cu, b0 + hole.size.y * 0.66, hole.size.x, fw],
			]:
				kit.add_box(
					&"frame", _pt(origin, basis, bar[0], bar[1], d),
					Vector3(bar[2], bar[3], 0.05), Color.WHITE, basis)
		elif pane == 2:
			# Доски внахлёст поверх проёма.
			var count: int = 4
			for k: int in count:
				var bv: float = b0 + (float(k) + 0.5) * hole.size.y / float(count)
				var tilt := Basis(basis.z, rng.randf_range(-0.06, 0.06)) * basis
				kit.add_box(
					&"boards", _pt(origin, basis, cu, bv, 0.04),
					Vector3(hole.size.x + 0.25, hole.size.y / float(count) - 0.05, 0.03),
					Color.WHITE * rng.randf_range(0.75, 1.0), tilt)
		# Отлив под окном.
		kit.add_box(
			&"concrete", _pt(origin, basis, cu, b0 - 0.025, -0.03),
			Vector3(hole.size.x + 0.12, 0.05, 0.14), Color.WHITE, basis)
	if seams:
		kit.add_quad(
			&"seam", _pt(origin, basis, u0 - 0.015, v0, -0.004),
			_pt(origin, basis, u0 + 0.015, v0, -0.004),
			_pt(origin, basis, u0 + 0.015, v1, -0.004),
			_pt(origin, basis, u0 - 0.015, v1, -0.004))
		kit.add_quad(
			&"seam", _pt(origin, basis, u0, v0 - 0.015, -0.004),
			_pt(origin, basis, u1, v0 - 0.015, -0.004),
			_pt(origin, basis, u1, v0 + 0.015, -0.004),
			_pt(origin, basis, u0, v0 + 0.015, -0.004))


static func _balcony(
	kit: MeshKit, origin: Vector3, basis: Basis, u0: float, v0: float,
	w: float, rng: RandomNumberGenerator
) -> void:
	var cu: float = u0 + w * 0.5
	var bw: float = w - 0.3
	var tones: Array[Color] = [
		Color(0.72, 0.8, 0.84), Color(0.85, 0.8, 0.66), Color(0.7, 0.78, 0.68),
		Color(0.8, 0.8, 0.8),
	]
	var tone: Color = tones[rng.randi_range(0, tones.size() - 1)] * rng.randf_range(0.8, 1.0)
	kit.add_box(
		&"concrete", _pt(origin, basis, cu, v0 + 0.06, -0.55),
		Vector3(bw, 0.12, 1.1), Color.WHITE, basis)
	kit.add_box(
		&"balcony", _pt(origin, basis, cu, v0 + 0.62, -1.07),
		Vector3(bw, 1.0, 0.06), tone, basis)
	for side: float in [-1.0, 1.0]:
		kit.add_box(
			&"balcony", _pt(origin, basis, cu + side * (bw * 0.5 - 0.03), v0 + 0.62, -0.55),
			Vector3(0.06, 1.0, 1.1), tone, basis)


static func _entrance(kit: MeshKit, x: float, hz: float, open: bool) -> void:
	kit.add_box(
		&"concrete", Vector3(x, 0.1, hz + 0.95), Vector3(2.8, 0.2, 1.9),
		Color.WHITE, Basis.IDENTITY, true)
	kit.add_box(&"concrete", Vector3(x, 1.35, hz + 0.07), Vector3(1.5, 2.3, 0.14))
	if open:
		kit.add_box(&"void", Vector3(x, 1.25, hz + 0.1), Vector3(1.1, 2.1, 0.1))
		# Створка распахнута наружу.
		var hinge := Vector3(x - 0.55, 1.25, hz + 0.16)
		var swing := Basis(Vector3.UP, deg_to_rad(-72.0))
		kit.add_box(
			&"metal", hinge + swing * Vector3(0.55, 0.0, 0.0),
			Vector3(1.1, 2.1, 0.05), Color.WHITE, swing)
	else:
		kit.add_box(&"metal", Vector3(x, 1.25, hz + 0.12), Vector3(1.1, 2.1, 0.06))
	kit.add_box(&"concrete", Vector3(x, 2.72, hz + 0.95), Vector3(3.0, 0.14, 1.9))
	for side: float in [-1.0, 1.0]:
		kit.add_box(
			&"metal", Vector3(x + side * 1.35, 1.42, hz + 1.75),
			Vector3(0.1, 2.45, 0.1))
