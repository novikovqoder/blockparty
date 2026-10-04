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
		color = color.lerp(IslandGen.zone_blend(Vector2(x, z), PAL.zone_ground), ZONE_MIX)
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
## диагональ (x, z)–(x+1, z+1); цвет всей грани — от точки (x, z).
static func _chunk_mesh(
	heights: PackedFloat32Array, face_colors: PackedColorArray,
	cx: int, cz: int,
) -> ArrayMesh:
	var half: int = IslandGen.HALF
	var x_begin: int = -half + cx * CHUNK
	var z_begin: int = -half + cz * CHUNK
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(CHUNK * CHUNK * 4)
	colors.resize(CHUNK * CHUNK * 4)
	indices.resize(CHUNK * CHUNK * 6)
	var vi: int = 0
	var ii: int = 0
	for z: int in range(z_begin, z_begin + CHUNK):
		for x: int in range(x_begin, x_begin + CHUNK):
			var color: Color = face_colors[(z + half) * FACES + (x + half)]
			# v0 (x,z), v1 (x,z+1), v2 (x+1,z+1), v3 (x+1,z) — против часовой
			# стрелки при взгляде сверху (нормаль +Y).
			verts[vi] = Vector3(x, heights[_idx(x, z)], z)
			verts[vi + 1] = Vector3(x, heights[_idx(x, z + 1)], z + 1)
			verts[vi + 2] = Vector3(x + 1, heights[_idx(x + 1, z + 1)], z + 1)
			verts[vi + 3] = Vector3(x + 1, heights[_idx(x + 1, z)], z)
			colors[vi] = color
			colors[vi + 1] = color
			colors[vi + 2] = color
			colors[vi + 3] = color
			indices[ii] = vi
			indices[ii + 1] = vi + 1
			indices[ii + 2] = vi + 2
			indices[ii + 3] = vi
			indices[ii + 4] = vi + 2
			indices[ii + 5] = vi + 3
			vi += 4
			ii += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
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
