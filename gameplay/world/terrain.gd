# Меш рельефа и коллизия из карты высот IslandGen (раздел 6 SPEC): чанки
# 32 × 32 м (отсечение по видимости), по два треугольника на квадрат —
# нормали не пишем, шейдер lowpoly.gdshader считает их сам через
# производные; цвет — на грань (все вершины квадрата одной краски,
# соседние квадраты чуть разные — классический low-poly фасет). Материал
# по высоте и склону (песок у воды, трава, камень на крутых склонах, снег
# на вершинах) с примесью тона зоны; подсказки tint из генератора
# перекрывают материал на террасах и площадках. Коллизия —
# HeightMapShape3D по той же карте: 257 вершин на 256 м, вершина i
# на x = −128 + i, ровно сетка генератора.
# Тангенты (доработка П5.13): печёные чанки несут фасетные тангенты —
# квад высот с UV-ростом вдоль мировых X/Z имеет dP/du = (1, dh/dx, 0),
# T = normalize(1, dy, 0), w = +1 (знак сверен с SurfaceTool,
# тест test_world_ground). Доработка-2 П5.13 (П1) перевела нормали грунта
# в forest_ground.gdshader в мировой базис — NORMAL_MAP больше не
# используется, warning «requires tangents» ушёл; тангенты у печёных
# чанков оставлены как сверка конвенции движка, ближние чанки (0.5 м)
# их не пишут.
class_name TerrainBuilder
extends RefCounted

const PAL: Palette = preload("res://assets/palette.tres")

## Точек на сторону карты (сокращение до IslandGen.POINTS).
const POINTS: int = IslandGen.POINTS
## Квадратов на сторону (граней рельефа).
const FACES: int = IslandGen.POINTS - 1
## Размер чанка, м (раздел 16).
const CHUNK: int = 32
## Чанков на сторону: 256 / 32 = 8 (карта целиком, включая дно моря).
const CHUNKS_PER_SIDE: int = IslandGen.HALF * 2 / CHUNK

## Материал: камень на склоне круче этого перепада, м на 1 м.
const STONE_SLOPE: float = 1.2
## Снег выше этой высоты, м (вершины холмов ~15 м — шапки небольшие).
const SNOW_H: float = 14.5
## Песок ниже этой высоты, м.
const SAND_H: float = 0.95
## Доля зонального тона в цвете травы/камня рельефа.
const ZONE_MIX: float = 0.35
## Доля выбеленного верхнего слоя (холмы читаются на карте и в игре).
const HEIGHT_LIGHT: float = 0.18


## Шаг ближней тесселяции (доработка-2 П5.13, П1): чанки вокруг игрока
## делятся на подквады NEAR_STEP м — рельеф вблизи читается гладким.
const NEAR_STEP: float = 0.5


## Билинейная высота рельефа в произвольной точке (та же арифметика, что у
## WorldSelfCheck.ground_y — здесь своя копия, чтобы не завести цикл
## компиляции terrain → self_check → island_art → terrain): вершины ближних
## чанков и нормали берутся из одной функции — на стыке уровней
## детализации трещин нет.
static func height_at(heights: PackedFloat32Array, x: float, z: float) -> float:
	var fx: float = clampf(x, -IslandGen.HALF, IslandGen.HALF - 0.001)
	var fz: float = clampf(z, -IslandGen.HALF, IslandGen.HALF - 0.001)
	var x0: int = floori(fx)
	var z0: int = floori(fz)
	var tx: float = fx - float(x0)
	var tz: float = fz - float(z0)
	var h00: float = heights[_idx(x0, z0)]
	var h10: float = heights[_idx(x0 + 1, z0)]
	var h01: float = heights[_idx(x0, z0 + 1)]
	var h11: float = heights[_idx(x0 + 1, z0 + 1)]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Карты производных рельефа (доработка-2 П5.13, П1): центральные разности
## карты высот по узлам 1 м (края — clamp). Нормаль в произвольной точке —
## билинейная интерполяция узловых производных: гладкое поле, непрерывное
## через границы чанков и уровней тесселяции; строится один раз на остров,
## перестройка ближнего чанка обходится двумя интерполяциями на вершину.
static func slope_maps(heights: PackedFloat32Array) -> Dictionary:
	var dx := PackedFloat32Array()
	var dz := PackedFloat32Array()
	dx.resize(POINTS * POINTS)
	dz.resize(POINTS * POINTS)
	for z: int in range(-IslandGen.HALF, IslandGen.HALF + 1):
		for x: int in range(-IslandGen.HALF, IslandGen.HALF + 1):
			var west: float = heights[_idx(clampi(x - 1, -IslandGen.HALF, IslandGen.HALF), z)]
			var east: float = heights[_idx(clampi(x + 1, -IslandGen.HALF, IslandGen.HALF), z)]
			var north: float = heights[_idx(x, clampi(z - 1, -IslandGen.HALF, IslandGen.HALF))]
			var south: float = heights[_idx(x, clampi(z + 1, -IslandGen.HALF, IslandGen.HALF))]
			var i: int = _idx(x, z)
			dx[i] = (east - west) * 0.5
			dz[i] = (south - north) * 0.5
	return {"dx": dx, "dz": dz}


## Нормаль рельефа в точке из карт производных (см. slope_maps).
static func normal_from_maps(
	maps: Dictionary, x: float, z: float,
) -> Vector3:
	var dx_map: PackedFloat32Array = maps["dx"]
	var dz_map: PackedFloat32Array = maps["dz"]
	var fx: float = clampf(x, -IslandGen.HALF, IslandGen.HALF - 0.001)
	var fz: float = clampf(z, -IslandGen.HALF, IslandGen.HALF - 0.001)
	var x0: int = floori(fx)
	var z0: int = floori(fz)
	var tx: float = fx - float(x0)
	var tz: float = fz - float(z0)
	var base: int = _idx(x0, z0)
	var right: int = base + 1
	var below: int = base + POINTS
	var below_right: int = below + 1
	var dh_dx: float = lerpf(
		lerpf(dx_map[base], dx_map[right], tx),
		lerpf(dx_map[below], dx_map[below_right], tx), tz)
	var dh_dz: float = lerpf(
		lerpf(dz_map[base], dz_map[right], tx),
		lerpf(dz_map[below], dz_map[below_right], tx), tz)
	return Vector3(-dh_dx, 1.0, -dh_dz).normalized()


## Ближний чанк (доработка-2 П5.13, П1): подквады NEAR_STEP м (по умолчанию
## 0.5), вершины — сеткой (уникальные, без дублей), высоты — билинейная
## выборка карты, нормали — из карт производных (гладкие, непрерывные через
## границы чанков и уровней), цвет — фасет квада 1 м из печёного меша (тон
## подсказок tint сохраняется). Ребро печёного квада делится ровно
## пополам: середина лежит на отрезке ребра, стык 0.5↔1 м без щелей.
static func build_near_chunk(
	heights: PackedFloat32Array, maps: Dictionary, baked: ArrayMesh,
	cx: int, cz: int, step: float = NEAR_STEP,
) -> ArrayMesh:
	var half: int = IslandGen.HALF
	var x_begin: float = float(-half + cx * CHUNK)
	var z_begin: float = float(-half + cz * CHUNK)
	var squares_per_side: int = roundi(float(CHUNK) / step)
	var side: int = squares_per_side + 1
	var baked_colors: PackedColorArray = baked.surface_get_arrays(0)[
		Mesh.ARRAY_COLOR]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(side * side)
	normals.resize(verts.size())
	colors.resize(verts.size())
	indices.resize(squares_per_side * squares_per_side * 6)
	for j: int in side:
		var z: float = z_begin + float(j) * step
		for i: int in side:
			var x: float = x_begin + float(i) * step
			var vi: int = j * side + i
			verts[vi] = Vector3(x, height_at(heights, x, z), z)
			normals[vi] = normal_from_maps(maps, x, z)
	# Цвет вершины — фасет: цвет квада 1 м, в котором лежит подквад.
	# Вершина на внутреннем ребре печёных квадратов берёт цвет нижнего-левого.
	for j: int in side:
		for i: int in side:
			var vi: int = j * side + i
			var baked_square: int = clampi(
				int(floorf(z_begin + float(j) * step) - z_begin) * CHUNK
				+ int(floorf(x_begin + float(i) * step) - x_begin),
				0, CHUNK * CHUNK - 1)
			colors[vi] = baked_colors[baked_square * 4]
	var ii: int = 0
	for j: int in squares_per_side:
		for i: int in squares_per_side:
			var v00: int = j * side + i
			var v10: int = v00 + 1
			var v01: int = v00 + side
			var v11: int = v01 + 1
			# Намотка та же, что у печёного чанка (см. _chunk_mesh):
			# (v00, v11, v01) и (v00, v10, v11).
			indices[ii] = v00
			indices[ii + 1] = v11
			indices[ii + 2] = v01
			indices[ii + 3] = v00
			indices[ii + 4] = v10
			indices[ii + 5] = v11
			ii += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Меши чанков рельефа (CHUNKS_PER_SIDE² штук), вершины с цветом грани.
static func build_chunks(data: Dictionary) -> Array[Mesh]:
	var heights: PackedFloat32Array = data["heights"]
	var face_colors := _face_colors(heights, data["tint"])
	var meshes: Array[Mesh] = []
	meshes.resize(CHUNKS_PER_SIDE * CHUNKS_PER_SIDE)
	for cz: int in CHUNKS_PER_SIDE:
		for cx: int in CHUNKS_PER_SIDE:
			meshes[cz * CHUNKS_PER_SIDE + cx] = _chunk_mesh(
				heights, face_colors, cx, cz
			)
	return meshes


## Форма коллизии рельефа: карта высот один в один (вершины на целых
## координатах от −128 до 128).
static func build_collision(data: Dictionary) -> HeightMapShape3D:
	var shape := HeightMapShape3D.new()
	shape.map_width = POINTS
	shape.map_depth = POINTS
	shape.map_data = (data["heights"] as PackedFloat32Array).duplicate()
	return shape


## Цвет точки рельефа (для граней и отрисовки карты): материал по высоте
## и склону + зональный тон, подсказки tint перекрывают всё.
static func point_color(
	heights: PackedFloat32Array, tint: Dictionary, x: int, z: int
) -> Color:
	var h: float = heights[_idx(x, z)]
	var hint: Dictionary = tint.get(Vector2i(x, z), {})
	if not hint.is_empty():
		# Террасы и площадки: камень своей зоны, чуть светлее с высотой.
		var stone: Color = PAL.zone_stone[int(hint["zone"])]
		return stone.lerp(Color.WHITE, clampf(h / 24.0, 0.0, 1.0) * 0.25)
	var color: Color
	if h < SAND_H:
		# Пляж; глубже уровня воды песок темнеет ко дну.
		var depth: float = clampf((IslandGen.SEA_LEVEL - h) / 3.5, 0.0, 1.0)
		color = PAL.sand.lerp(PAL.water_deep, depth * 0.55)
	elif h >= SNOW_H:
		color = PAL.snow
	elif _slope_at(heights, x, z) >= STONE_SLOPE:
		# Скальный склон; выше — чуть светлее (выветренный камень).
		color = PAL.stone.lerp(Color.WHITE, clampf((h - 8.0) / 14.0, 0.0, 1.0) * 0.2)
	else:
		# Луг высыхает с высотой — к битой земле, не к камню.
		color = PAL.grass.lerp(PAL.dirt, clampf((h - 8.0) / 10.0, 0.0, 1.0) * 0.4)
		# Зональный тон с силой зоны (П5.13, блок 4): вне охвата зон луг
		# чистый, к краю охвата тон растворяется — шва «зона кончилась» нет.
		color = color.lerp(IslandGen.zone_blend(Vector2(x, z), PAL.zone_ground),
			ZONE_MIX * IslandGen.zone_color_strength(Vector2(x, z)))
	# Лёгкое высветление высот — холмы читаются на карте.
	return color.lerp(Color.WHITE, clampf(h / 26.0, 0.0, 1.0) * HEIGHT_LIGHT)


## Цвет грани — цвет точки-основания квадрата (все 4 вершины одной краски).
static func _face_colors(heights: PackedFloat32Array, tint: Dictionary) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(FACES * FACES)
	var i: int = 0
	for z: int in range(-IslandGen.HALF, IslandGen.HALF):
		for x: int in range(-IslandGen.HALF, IslandGen.HALF):
			colors[i] = point_color(heights, tint, x, z)
			i += 1
	return colors


## Меш одного чанка: квадраты (x, z)–(x+1, z+1) двумя треугольниками,
## диагональ (x, z)–(x+1, z+1); цвет всей грани — от точки (x, z),
## тангент — фасетный на квадрат (см. шапку класса).
static func _chunk_mesh(
	heights: PackedFloat32Array, face_colors: PackedColorArray,
	cx: int, cz: int,
) -> ArrayMesh:
	var half: int = IslandGen.HALF
	var x_begin: int = -half + cx * CHUNK
	var z_begin: int = -half + cz * CHUNK
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var tangents := PackedFloat32Array()
	var indices := PackedInt32Array()
	verts.resize(CHUNK * CHUNK * 4)
	colors.resize(CHUNK * CHUNK * 4)
	tangents.resize(CHUNK * CHUNK * 4 * 4)
	indices.resize(CHUNK * CHUNK * 6)
	var vi: int = 0
	var ii: int = 0
	for z: int in range(z_begin, z_begin + CHUNK):
		for x: int in range(x_begin, x_begin + CHUNK):
			var color: Color = face_colors[(z + half) * FACES + (x + half)]
			# v0 (x,z), v1 (x,z+1), v2 (x+1,z+1), v3 (x+1,z). Godot считает
			# лицевой грань, намотанную ПО часовой стрелке при взгляде со
			# стороны зрителя: у видимых сверху граней движка (PlaneMesh,
			# BoxMesh) «правовинтовая» нормаль смотрит вниз — индексы идут
			# (v0, v2, v1) и (v0, v3, v2), см. tools/winding_probe.gd.
			verts[vi] = Vector3(x, heights[_idx(x, z)], z)
			verts[vi + 1] = Vector3(x, heights[_idx(x, z + 1)], z + 1)
			verts[vi + 2] = Vector3(x + 1, heights[_idx(x + 1, z + 1)], z + 1)
			verts[vi + 3] = Vector3(x + 1, heights[_idx(x + 1, z)], z)
			colors[vi] = color
			colors[vi + 1] = color
			colors[vi + 2] = color
			colors[vi + 3] = color
			# Тангент квадрата: dh/dx по четырём углам (две колонки сетки),
			# одна краска на все 4 вершины — фасет, без скачка интерполяции.
			var dy: float = (
				heights[_idx(x + 1, z)] + heights[_idx(x + 1, z + 1)]
				- heights[_idx(x, z)] - heights[_idx(x, z + 1)]) * 0.5
			var inv_len: float = 1.0 / sqrt(1.0 + dy * dy)
			var ti: int = vi * 4
			for k: int in 4:
				tangents[ti + k * 4] = inv_len
				tangents[ti + k * 4 + 1] = dy * inv_len
				tangents[ti + k * 4 + 2] = 0.0
				tangents[ti + k * 4 + 3] = 1.0
			indices[ii] = vi
			indices[ii + 1] = vi + 2
			indices[ii + 2] = vi + 1
			indices[ii + 3] = vi
			indices[ii + 4] = vi + 3
			indices[ii + 5] = vi + 2
			vi += 4
			ii += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _idx(x: int, z: int) -> int:
	return (z + IslandGen.HALF) * POINTS + (x + IslandGen.HALF)


## Максимальный перепад высоты к соседним точкам, м.
static func _slope_at(heights: PackedFloat32Array, x: int, z: int) -> float:
	var h: float = heights[_idx(x, z)]
	var steepest: float = 0.0
	for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + dir.x
		var nz: int = z + dir.y
		if absi(nx) > IslandGen.HALF or absi(nz) > IslandGen.HALF:
			continue
		steepest = maxf(steepest, absf(heights[_idx(nx, nz)] - h))
	return steepest
