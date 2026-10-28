# П15-ДОП2, п. 1 «Дно моря плавно до горизонта»: юбка морского дна —
# квадратные рамки-кольца вокруг карты острова (256 × 256 м). Внутри
# карты дно рисуют чанки рельефа; за краем (дальше узлов ±128) геометрии
# не было — буфер глубины давал «бесконечную» толщину, и на воде висела
# прямая тёмная граница по краю квадрата карты. Юбка закрывает край:
# глубина растёт от края карты плавной кривой (quintic smoothstep, C²,
# по чебышевскому расстоянию за край): у шва с картой совпадают высота,
# наклон И кривизна (дно карты у края плоское, у кривой производные до
# второй нулевые на концах — шов невозможен по построению), вдали — ил.
# Только визуал: без коллизии (за ограждением мира не ходят) и без тени
# (рельеф уже в тенях чанков). Материал — общий lowpoly с вершинными
# цветами: у шва цвет тот же, что у дна карты (формула краски узла края
# из TerrainBuilder.point_color), дальше — градиент в тёмный ил.
class_name SeafloorSkirt
extends MeshInstance3D

const PAL: Palette = preload("res://assets/palette.tres")

## Ширина пологого шельфа от края карты, м: константа «подбирает владелец»
## (ползунок F3 «Дно: шельф», вкладка «Вода»).
const SHELF_M: float = 70.0
## Глубина ровного дна вдали от острова (положительная), м: 80–120 по
## постановке; ползунок F3 «Дно: глубина вдали».
const FAR_DEPTH_M: float = 95.0

## Кольца юбки [внутренняя полусторона, внешняя, квад], м. Решётки колец
## независимы: обе границы кольца кратны его кваду, а стык двух колец —
## квадрат-контур функции высоты (чебышевское расстояние по стыку
## постоянно, значит и высота постоянна), поэтому вершины разных решёток
## на стыке лежат в одной плоскости — без щелей и z-fighting. Квад
## крупнее с расстоянием (как кольца Ocean). Первое кольцо мелкое (2 м):
## дно карты у края плоское, и первый квад юбки не должен торчать над
## ним углом — на кривой C² излом у шва чуть заметен только на сетке.
## Край юбки — 640 м от центра: камера (far 160 м) дальше ограждения
## мира (127.5 м) не уходит, край не виден никогда.
const RINGS: Array = [
	[128.0, 136.0, 2.0],
	[136.0, 152.0, 4.0],
	[152.0, 176.0, 8.0],
	[176.0, 256.0, 16.0],
	[256.0, 384.0, 32.0],
	[384.0, 640.0, 64.0],
]
## Градиент цвета дна: доля тёмного ила растёт от SILT_FROM к SILT_TO
## доли перепада глубины юбки.
const SILT_FROM: float = 0.1
const SILT_TO: float = 0.85
## Насколько ил темнее глубинного тона палитры.
const SILT_DARKEN: float = 0.5

## Карта высот острова (цвет шва — краска дна карты на краю).
var _heights: PackedFloat32Array = PackedFloat32Array()
var _shelf: float = SHELF_M
var _far_depth: float = FAR_DEPTH_M


## Построение (IslandView._build_terrain): высоты острова и, при желании,
## нестандартный склон.
func setup(
	heights: PackedFloat32Array,
	shelf: float = SHELF_M,
	far_depth: float = FAR_DEPTH_M,
) -> void:
	_heights = heights
	name = "SeafloorSkirt"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = LowPolyMat.flat_or_vertex()
	set_slope(shelf, far_depth)


## Ползунки F3: новый склон — пересборка меша (~3 тыс. квадов).
func set_slope(shelf: float, far_depth: float) -> void:
	_shelf = maxf(shelf, 2.0)
	_far_depth = maxf(far_depth, 8.0)
	mesh = build_mesh(_heights, _shelf, _far_depth)


## Высота юбки в мировой точке: за краем карты глубина растёт по
## quintic smoothstep (C²: производные до второй нулевые на концах)
## от плоского дна карты (SEA_FLOOR, наклон 0 и кривизна 0) до
## −far_depth на расстоянии shelf от края, дальше ровно. Внутри карты
## (d < 0) ограничивается уровнем дна карты — шов совпадает с чанками
## по построению. Функция монотонна и без изломов.
static func height_at(
	x: float, z: float, shelf: float, far_depth: float
) -> float:
	var d: float = maxf(
		maxf(absf(x), absf(z)) - float(IslandGen.HALF), 0.0)
	var t: float = clampf(d / maxf(shelf, 0.001), 0.0, 1.0)
	var s: float = t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
	return IslandGen.SEA_FLOOR - (far_depth + IslandGen.SEA_FLOOR) * s


## Меш юбки: кольцо на решётку (см. RINGS), квады рамки между квадратами
## кольца, цвет вершины — краска шва → ил по глубине.
static func build_mesh(
	heights: PackedFloat32Array, shelf: float, far_depth: float
) -> ArrayMesh:
	# Цвет шва — краска дна карты на узле края (угол карты): той же
	# формулой, что TerrainBuilder.point_color, чтобы юбка и чанки у
	# стыка были одной краски.
	var seam: Color = TerrainBuilder.point_color(
		heights, {}, IslandGen.HALF, IslandGen.HALF)
	var silt: Color = PAL.water_deep.lerp(Color.BLACK, SILT_DARKEN)
	var drop: float = maxf(far_depth + IslandGen.SEA_FLOOR, 0.001)
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for ring: Array in RINGS:
		var b_in: float = ring[0]
		var b_out: float = ring[1]
		var cell: float = ring[2]
		var cells: int = roundi(b_out * 2.0 / cell)
		var side: int = cells + 1
		var base: int = verts.size()
		verts.resize(base + side * side)
		colors.resize(verts.size())
		for j: int in side:
			var z: float = -b_out + float(j) * cell
			for i: int in side:
				var x: float = -b_out + float(i) * cell
				var vi: int = base + j * side + i
				var h: float = height_at(x, z, shelf, far_depth)
				verts[vi] = Vector3(x, h, z)
				var share: float = clampf(
					(IslandGen.SEA_FLOOR - h) / drop, 0.0, 1.0)
				colors[vi] = seam.lerp(
					silt, smoothstep(SILT_FROM, SILT_TO, share))
		# Квады рамки: пропускаются клетки, чей ближайший к центру угол
		# лежит внутри внутреннего квадрата (границы кратны кваду — рамка
		# ложится ровно на контур стыка).
		for j: int in cells:
			var z0: float = -b_out + float(j) * cell
			for i: int in cells:
				var x0: float = -b_out + float(i) * cell
				if maxf(_min_abs(x0, x0 + cell),
						_min_abs(z0, z0 + cell)) < b_in - 0.01:
					continue
				var v0: int = base + j * side + i
				var v1: int = v0 + 1
				var v2: int = v0 + side + 1
				var v3: int = v0 + side
				# v0 (x,z), v1 (x+1,z), v2 (x+1,z+1), v3 (x,z+1); намотка —
				# как у чанков рельефа (см. TerrainBuilder._chunk_mesh):
				# (v0, v2, v3) и (v0, v1, v2).
				indices.append(v0)
				indices.append(v2)
				indices.append(v3)
				indices.append(v0)
				indices.append(v1)
				indices.append(v2)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Минимальное |x| на отрезке [a, b] (0, если отрезок содержит ноль).
static func _min_abs(a: float, b: float) -> float:
	if a >= 0.0:
		return a
	if b <= 0.0:
		return -b
	return 0.0
