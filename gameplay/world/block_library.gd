# Библиотека блоков острова (раздел 6 SPEC): 13 типов из MeshLibrary, все меши
# и коллизии — из примитивов (BoxMesh → ArrayMesh через SurfaceTool), цвета —
# из assets/palette.tres. Меш ячейки GridMap центрирован в её центре: полный
# блок занимает [Y, Y + 1] (верх на Y + 1), полублок — нижнюю половину ячейки
# [Y, Y + 0.5]. Рельеф острова квантован к целым метрам (IslandGen), поэтому
# полублоки в мире — только декор (кольцо костра). Лёгкое затенение граней —
# вершинными цветами (верх светлее, низ темнее), материал умножает albedo на
# цвет вершин. Собирается кодом один раз и сохраняется в block_library.tres
# (tools/generate_island.gd); в рантайме только читается.
class_name BlockLibrary
extends RefCounted

const PAL: Palette = preload("res://assets/palette.tres")

## Идентификаторы блоков в MeshLibrary (id = индексу перечисления).
enum Block {
	GRASS = 1,
	DIRT = 2,
	STONE = 3,
	SAND = 4,
	SNOW = 5,
	TRUNK = 6,
	LEAVES = 7,
	PLANKS = 8,
	RUIN_BRICK = 9,
	RUIN_BRICK_DARK = 10,
	BEACON_GLOW = 11,
	GRASS_HALF = 12,
	STONE_HALF = 13,
}

## Затенение граней (множитель albedo): верх/бокX/бокZ/низ.
const SHADE_TOP: float = 1.0
const SHADE_SIDE_X: float = 0.94
const SHADE_SIDE_Z: float = 0.88
const SHADE_BOTTOM: float = 0.72

## Полублок: высота и смещение центра вниз от центра ячейки, м.
const HALF_HEIGHT: float = 0.5
const HALF_DROP: float = 0.25


## Собрать MeshLibrary со всеми блоками (детерминированно, без случайности).
static func build() -> MeshLibrary:
	var library := MeshLibrary.new()
	_full(library, Block.GRASS, "grass", PAL.grass)
	_full(library, Block.DIRT, "dirt", PAL.dirt)
	_full(library, Block.STONE, "stone", PAL.stone)
	_full(library, Block.SAND, "sand", PAL.sand)
	_full(library, Block.SNOW, "snow", PAL.snow)
	_full(library, Block.TRUNK, "trunk", PAL.trunk)
	_full(library, Block.LEAVES, "leaves", PAL.leaves)
	_full(library, Block.PLANKS, "planks", PAL.planks)
	_full(library, Block.RUIN_BRICK, "ruin_brick", PAL.ruin_brick)
	_full(library, Block.RUIN_BRICK_DARK, "ruin_brick_dark", PAL.ruin_brick_dark)
	_glow(library, Block.BEACON_GLOW, "beacon_glow", PAL.beacon_glow)
	_half(library, Block.GRASS_HALF, "grass_half", PAL.grass_half)
	_half(library, Block.STONE_HALF, "stone_half", PAL.stone_half)
	return library


## Полублоки занимают нижнюю половину ячейки (верх на целом Y).
static func is_half(block: int) -> bool:
	return block == Block.GRASS_HALF or block == Block.STONE_HALF


## Верхняя грань блока (для карты острова: цвет верхней поверхности).
static func block_color(block: int) -> Color:
	match block:
		Block.GRASS, Block.GRASS_HALF:
			return PAL.grass
		Block.DIRT:
			return PAL.dirt
		Block.STONE, Block.STONE_HALF:
			return PAL.stone
		Block.SAND:
			return PAL.sand
		Block.SNOW:
			return PAL.snow
		Block.TRUNK:
			return PAL.trunk
		Block.LEAVES:
			return PAL.leaves
		Block.PLANKS:
			return PAL.planks
		Block.RUIN_BRICK, Block.RUIN_BRICK_DARK:
			return PAL.ruin_brick
		Block.BEACON_GLOW:
			return PAL.beacon_glow
	return Color.WHITE


# --- Сборка ---

## Полный блок 1 × 1 × 1 (центр ячейки, верх на Y + 0.5).
static func _full(library: MeshLibrary, id: int, name: String, color: Color) -> void:
	library.create_item(id)
	library.set_item_name(id, name)
	library.set_item_mesh(id, _cube_mesh(Vector3.ONE, Vector3.ZERO, color, false))
	library.set_item_shapes(id, [_box_shape(Vector3.ONE), Transform3D.IDENTITY])


## Полублок 1 × 0.5 × 1 в нижней половине ячейки (верх на целом Y).
static func _half(library: MeshLibrary, id: int, name: String, color: Color) -> void:
	library.create_item(id)
	library.set_item_name(id, name)
	library.set_item_mesh(id, _cube_mesh(Vector3.ONE * Vector3(1.0, HALF_HEIGHT, 1.0), Vector3.DOWN * HALF_DROP, color, false))
	library.set_item_shapes(id, [
		_box_shape(Vector3(1.0, HALF_HEIGHT, 1.0)),
		Transform3D(Basis.IDENTITY, Vector3.DOWN * HALF_DROP),
	])


## Светящийся блок (маяк): материал с emission.
static func _glow(library: MeshLibrary, id: int, name: String, color: Color) -> void:
	library.create_item(id)
	library.set_item_name(id, name)
	library.set_item_mesh(id, _cube_mesh(Vector3.ONE, Vector3.ZERO, color, true))
	library.set_item_shapes(id, [_box_shape(Vector3.ONE), Transform3D.IDENTITY])


static func _box_shape(size: Vector3) -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return shape


## Куб с вершинными цветами граней: BoxMesh через SurfaceTool. Меш «сидит»
## на дне полублока через drop (смещение всех вершин).
static func _cube_mesh(size: Vector3, drop: Vector3, color: Color, glow: bool) -> ArrayMesh:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.vertex_color_use_as_albedo = true
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	# Квадры: четыре угла против часовой стрелки при взгляде снаружи.
	# base — сколько вершин уже добавлено (индексы у add_index абсолютные).
	var base := 0
	base = _face(st, [
		Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z),
		Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z),
	], Vector3.UP, SHADE_TOP, drop, base)                              # верх
	base = _face(st, [
		Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z),
	], Vector3.RIGHT, SHADE_SIDE_X, drop, base)                        # +X
	base = _face(st, [
		Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z),
	], Vector3.LEFT, SHADE_SIDE_X, drop, base)                         # −X
	base = _face(st, [
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z),
		Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	], Vector3.BACK, SHADE_SIDE_Z, drop, base)                         # +Z
	base = _face(st, [
		Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z),
		Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z),
	], Vector3.FORWARD, SHADE_SIDE_Z, drop, base)                      # −Z
	_face(st, [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
	], Vector3.DOWN, SHADE_BOTTOM, drop, base)                         # низ
	st.set_material(material)
	return st.commit()


static func _face(
	st: SurfaceTool, corners: Array[Vector3],
	normal: Vector3, shade: float, drop: Vector3, base: int,
) -> int:
	var color := Color(shade, shade, shade)
	for i: int in range(4):
		st.set_color(color)
		st.set_normal(normal)
		st.add_vertex(corners[i] + drop)
	# Два треугольника: 0-1-2 и 0-2-3 (со смещением на уже добавленные вершины).
	st.add_index(base + 0)
	st.add_index(base + 1)
	st.add_index(base + 2)
	st.add_index(base + 0)
	st.add_index(base + 2)
	st.add_index(base + 3)
	return base + 4
