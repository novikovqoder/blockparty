# Рельеф острова вне сектора Леса через Terrain3D (П5.13, блок 3).
# Два узла, каждый — один регион 256 × 256 от локального нуля (единственный
# паттерн импорта, надёжно работающий в v1.0.2: карта обязана заполнять
# регион целиком, см. пробы совместимости):
#   East — position (-16, 0, -128): мир x ∈ [0..128), z ∈ [-128..128];
#   West — position (-128, 0, -16): мир x ∈ [-128..0], z ∈ [0..128).
# Лес (x < 0, z < 0) не рисует никто: там прежние чанки с ForestGround.
# Стык узлов и кромка Леса — по линиям x = 0 / z = 0: полоса клетки
# world [0..1) на West оставлена без дырки, чтобы общий стык-вершина
# world 0 жила, а треугольники правее гасли дыркой соседнего текселя —
# ни зазора, ни наложения на любом LOD (вершины кратны 1 м, границы
# кратны 2). 16-метровые поля реальных высот за кромкой (под дырками)
# нужны центральным разностям нормалей: швов освещения на границах нет.
# Коллизия выключена: физика остаётся на HeightMapShape3D рельефа —
# механики и детерминизм сети не зависят от визуализатора.
# Цвета — terrain.gd point_color по тем же картам высот и подсказкам
# террас, запечённые в color-карту 1 тексел/м (как цвет граней чанков);
# шейдер terrain3d_ground.gdshader добавляет макро-вариацию пятнами.
class_name Terrain3DIsland
extends RefCounted

const SHADER: Shader = preload("res://gameplay/world/terrain3d_ground.gdshader")

## Сторона карты узла, текселов (= регион по умолчанию, не менять:
## region_size в v1.0.2 затрагивает баг молчаливой потери данных импорта).
const REGION: int = 256

## Высота-заполнитель дырок пустоты за краем карты острова, м.
const VOID_H: float = -6.0


## Собрать оба узла и повесить на parent (добавление в дерево раньше
## обращения к material/data — обязательный порядок v1.0.2).
static func spawn(parent: Node3D, heights: PackedFloat32Array) -> void:
	var tint: Dictionary = IslandGen.tint_hints()
	_spawn_node(parent, heights, tint, Vector3(-16.0, 0.0, -128.0))
	_spawn_node(parent, heights, tint, Vector3(-128.0, 0.0, -16.0))


## Один узел: смещение node_pos задаёт соответствие локальных текселей
## мировым клеткам (world = local + node_pos.xz).
static func _spawn_node(
	parent: Node3D, heights: PackedFloat32Array, tint: Dictionary,
	node_pos: Vector3,
) -> void:
	var terrain: Terrain3D = Terrain3D.new()
	terrain.name = "Terrain3D" + ("East" if node_pos.x > -100.0 else "West")
	terrain.position = node_pos
	parent.add_child(terrain, true)
	terrain.material.world_background = Terrain3DMaterial.NONE
	terrain.collision.mode = Terrain3DCollision.DISABLED
	terrain.material.shader_override_enabled = true
	terrain.material.shader_override = SHADER

	var height_img := Image.create(REGION, REGION, false, Image.FORMAT_RF)
	var color_img := Image.create(REGION, REGION, false, Image.FORMAT_RGBA8)
	# Control-карта: RGBAF, в битах float R упакован uint32 (бит 2 — дырка).
	var hole_bytes := PackedInt32Array([4]).to_byte_array()
	var flat_bytes := PackedInt32Array([0]).to_byte_array()
	var zero4 := PackedFloat32Array([0.0]).to_byte_array()
	var one4 := PackedFloat32Array([1.0]).to_byte_array()
	var control := PackedByteArray()
	control.resize(REGION * REGION * 16)
	var points: int = IslandGen.POINTS
	for py: int in REGION:
		var wz: int = py + int(node_pos.z) + IslandGen.HALF
		for px: int in REGION:
			var wx: int = px + int(node_pos.x) + IslandGen.HALF
			var in_map: bool = wx >= 0 and wx < points and wz >= 0 and wz < points
			var world_x: int = wx - IslandGen.HALF
			var world_z: int = wz - IslandGen.HALF
			if in_map:
				height_img.set_pixel(px, py, Color(
					heights[wz * points + wx], 0.0, 0.0, 1.0))
				# Грань (x, z) занимает клетку [x..x+1): последняя колонка 127.
				var face_ok: bool = world_x < IslandGen.HALF \
					and world_z < IslandGen.HALF
				color_img.set_pixel(px, py, TerrainBuilder.point_color(
					heights, tint, world_x, world_z) if face_ok else Color.BLACK)
			else:
				height_img.set_pixel(
					px, py, Color(VOID_H, 0.0, 0.0, 1.0))
				color_img.set_pixel(px, py, Color.BLACK)
			var offset: int = (py * REGION + px) * 16
			var head: PackedByteArray = hole_bytes \
				if _hole(node_pos, world_x, world_z) else flat_bytes
			for b: int in 4:
				control.encode_u8(offset + b, head.decode_u8(b))
				control.encode_u8(offset + 4 + b, zero4.decode_u8(b))
				control.encode_u8(offset + 8 + b, zero4.decode_u8(b))
				control.encode_u8(offset + 12 + b, one4.decode_u8(b))
	var control_img := Image.create_from_data(
		REGION, REGION, false, Image.FORMAT_RGBAF, control)
	terrain.data.import_images(
		[height_img, control_img, color_img], Vector3.ZERO, 0.0, 1.0)


## Дырка рендера в мировом текселе (origin клетки) узла со смещением
## node_pos: East не рисует Лес (x < 0) и пустоту за краем карты (x ≥ 128);
## West не рисует восток (x ≥ 1; тексель x = 0 держит общий стык-вершину),
## Лес (z < 0) и пустоту (z ≥ 128).
static func _hole(node_pos: Vector3, world_x: int, world_z: int) -> bool:
	if node_pos.x > -100.0:
		return world_x < 0 or world_x >= IslandGen.HALF
	return world_x >= 1 or world_z < 0 or world_z >= IslandGen.HALF
