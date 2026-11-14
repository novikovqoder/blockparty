# Природа района (постапокалипсис): лиственные деревья и кусты ez-tree
# (те же меши и материалы, что в лесу Born Unblessed — берутся из
# запечённого острова island_art.res: сами GLB генератора лежат под
# .gdignore и в сборку не попадают) и поле травы и цветов
# вокруг игрока (пучки GrassField). Раскладка детерминирована (seed).
# Деревья: на каждый вид три MultiMesh — ближний, средний и дальний уровень;
# экземпляры раскладываются по уровням по расстоянию до зрителя.
# Трава: чанки 8×8 м строятся по мере подхода (как в мире), её нет в воде
# и под постройками, на асфальте и во дворе — редкая («сквозь трещины»).
class_name DistrictNature
extends Node3D

const SEED: int = 20261110
## Запечённый остров: меши деревьев (PropGroup.mesh + lods) по ключам «тип:вариант».
const ART_PATH: String = "res://gameplay/world/island_art.res"
## Вариантов каждого вида в запечённом острове (etree_oak:0..4 и т. д.).
const ART_VARIANTS: int = 5
## Попытки посадки деревьев и кустов (часть отбраковывается).
const TREE_TRIES: int = 2600
const BUSH_TRIES: int = 900
## Лес растёт и за границей участка — на столько метров.
const FOREST_MARGIN: float = 55.0
## Минимум между стволами, м.
const TREE_GAP: float = 4.0
## Границы уровней деревьев, м (мир: 70 и 150; район плотнее застроен —
## база 60/130). PERF_DISTRICT п. 6: на HIGH и ниже пороги ближе (35/80) —
## деревья раньше уходят на дешёвые меши, а кастеров тени меньше (тень
## отбрасывает только ближний уровень). ULTRA — база, красиво как было.
const LOD1_M_BASE: float = 60.0
const LOD2_M_BASE: float = 130.0
const LOD1_M_CHEAP: float = 35.0
const LOD2_M_CHEAP: float = 80.0
## Пересчёт уровней — при сдвиге зрителя на столько метров.
const LOD_STEP_M: float = 2.0
## Чанков травы за один кадр (остальное достроится следующими).
const GRASS_CHUNK_BUDGET: int = 10
## PERF_DISTRICT п. 5: поле травы района на HIGH теснее и реже островного
## (55 м / 6 пучков на м²): район плотно застроен — луг читается и в 30 м
## от игрока, а пучков на встройке много (alpha-scissor + ветер в вершинном
## шейдере). Радиус 55 → 40 м (×0.73), плотность 6 → 4 пучка/м² (×0.67) —
## примерно половина пучков круга. ULTRA — островные 75 м / 8 пучков.
const GRASS_RADIUS_HIGH: float = 40.0
const GRASS_DENSITY_HIGH: float = 4.0
## Плотность травы по покрытию (доля от луговой).
const GRASS_FACTOR: Dictionary = {
	DistrictLayout.Surface.GRASS: 1.0,
	DistrictLayout.Surface.YARD: 0.45,
	DistrictLayout.Surface.PATH: 0.1,
	DistrictLayout.Surface.ASPHALT: 0.04,
}

var _tier: int = GraphicsQuality.Tier.HIGH
## Границы уровней деревьев [LOD1, LOD2], м — по тиру (см. lod_limits).
var _lod1_m: float = LOD1_M_BASE
var _lod2_m: float = LOD2_M_BASE
## Группы деревьев: {transforms, colors, nodes: [MMI ×3], counts}.
var _groups: Array[Dictionary] = []
var _lod_center := Vector2(INF, INF)
var _grass_nodes: Dictionary = {}
var _grass_chunks: Dictionary = {}
var _grass_radius: float = 0.0
var _grass_center := Vector2i(999999, 999999)
var _grass_done: bool = false
var _tree_points: Array[Vector2] = []


func setup(tier: int) -> void:
	_tier = tier
	var limits := lod_limits(tier)
	_lod1_m = limits.x
	_lod2_m = limits.y
	_build_trees()
	if GrassField.is_field_enabled(tier):
		_grass_radius = grass_radius(tier)
		_grass_nodes = GrassField.make_nodes(tier, _grass_radius)
		for type: String in _grass_nodes:
			add_child(_grass_nodes[type])


## Границы уровней деревьев [LOD1, LOD2], м, по тиру (PERF_DISTRICT п. 6).
static func lod_limits(tier: int) -> Vector2:
	if tier == GraphicsQuality.Tier.ULTRA:
		return Vector2(LOD1_M_BASE, LOD2_M_BASE)
	return Vector2(LOD1_M_CHEAP, LOD2_M_CHEAP)


## Радиус поля травы района, м, по тиру (PERF_DISTRICT п. 5).
static func grass_radius(tier: int) -> float:
	return GrassField.RADIUS_ULTRA if tier == GraphicsQuality.Tier.ULTRA \
		else GRASS_RADIUS_HIGH


## Базовая плотность пучков травы района на 1 м² по тиру (PERF_DISTRICT п. 5).
static func grass_density(tier: int) -> float:
	return GrassField.DENSITY_ULTRA if tier == GraphicsQuality.Tier.ULTRA \
		else GRASS_DENSITY_HIGH


## Точки стволов деревьев (X/Z) — для тестов и коллизий.
func tree_points() -> Array[Vector2]:
	return _tree_points


## Раскладка деревьев и кустов: чистая функция seed.
## Возврат: «тип:вариант» -> Array[Transform3D].
static func tree_layout(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var reach: float = DistrictLayout.HALF + FOREST_MARGIN
	var start := Vector2(DistrictLayout.START.x, DistrictLayout.START.z)
	var result: Dictionary = {}
	var grid: Dictionary = {}
	for i: int in TREE_TRIES + BUSH_TRIES:
		var bush: bool = i >= TREE_TRIES
		var p := Vector2(rng.randf_range(-reach, reach), rng.randf_range(-reach, reach))
		var roll: float = rng.randf()
		var pick: float = rng.randf()
		var yaw: float = rng.randf_range(0.0, TAU)
		var size: float = rng.randf_range(0.85, 1.15)
		var thin: float = rng.randf()
		var inside: bool = absf(p.x) < DistrictLayout.HALF and absf(p.y) < DistrictLayout.HALF
		var surface: int = DistrictLayout.surface_at(p)
		if surface == DistrictLayout.Surface.YARD:
			if roll > 0.12:
				continue
		# Внутри района деревьев реже, чем в лесу вокруг: дома видны
		# сквозь деревья, улицы и двор не превращаются в чащу.
		elif inside and not bush and thin > 0.45:
			continue
		elif surface != DistrictLayout.Surface.GRASS:
			continue
		if DistrictLayout.in_footprint(p, 1.0 if bush else 2.5):
			continue
		if p.distance_to(start) < (4.0 if bush else 14.0):
			continue
		# Кусты — только внутри района и у его кромки.
		if bush and (absf(p.x) > DistrictLayout.HALF + 15.0 \
				or absf(p.y) > DistrictLayout.HALF + 15.0):
			continue
		var cell := Vector2i(int(floorf(p.x / TREE_GAP)), int(floorf(p.y / TREE_GAP)))
		if not bush:
			var busy: bool = false
			for dz: int in range(-1, 2):
				for dx: int in range(-1, 2):
					if grid.has(cell + Vector2i(dx, dz)) and (
							grid[cell + Vector2i(dx, dz)] as Vector2).distance_to(p) < TREE_GAP:
						busy = true
			if busy:
				continue
			grid[cell] = p
		# Виды запечённого острова: etree_pine — высокие (дуб/ясень/осина
		# 19–26 м), etree_oak — средние, etree_bush — кусты.
		var type: StringName = &"etree_bush"
		if not bush:
			if inside:
				type = &"etree_oak" if pick < 0.55 else &"etree_pine"
			else:
				type = &"etree_pine" if pick < 0.6 else &"etree_oak"
		var variant: int = int(floorf(roll * 997.0)) % ART_VARIANTS
		var key := "%s:%d" % [type, variant]
		if not result.has(key):
			result[key] = []
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size)
		(result[key] as Array).append(Transform3D(
			basis, Vector3(p.x, DistrictLayout.ground_height(p) - 0.05, p.y)))
	return result


## Меши уровней дерева [ближний, средний, дальний] по ключу «тип:вариант»:
## из запечённого острова; запасной путь — генератор (только в редакторе,
## где GLB доступны).
static func tree_meshes(key: String) -> Array[Mesh]:
	var art := load(ART_PATH) as IslandArt
	if art != null and art.prop_groups.has(key):
		var group: PropGroup = art.prop_groups[key]
		if group.mesh != null and group.lods.size() >= 2:
			return [group.mesh, group.lods[0], group.lods[1]] as Array[Mesh]
	push_warning("Район: дерева %s нет в island_art.res — генератор" % key)
	var type := StringName(key.get_slice(":", 0))
	var tree_set: Dictionary = EzTreeMeshes.build_set(type, key.get_slice(":", 1).to_int())
	return [tree_set["mesh"], tree_set["lods"][0], tree_set["lods"][1]] as Array[Mesh]


func _build_trees() -> void:
	var layout: Dictionary = tree_layout(SEED)
	var trunks := StaticBody3D.new()
	trunks.name = "TreeTrunks"
	trunks.collision_layer = 1
	trunks.collision_mask = 0
	add_child(trunks)
	var keys: Array = layout.keys()
	keys.sort()
	for key: String in keys:
		var type := StringName(key.get_slice(":", 0))
		var variant: int = key.get_slice(":", 1).to_int()
		var transforms: Array = layout[key]
		var meshes: Array[Mesh] = tree_meshes(key)
		# Тинт коры пресета ez-tree (как в мире, IslandView._build_tree_lods).
		var bark_tint: Color = EzTreeMeshes.bark_tint_for(type, variant)
		for m: Mesh in meshes:
			for si: int in m.get_surface_count():
				var mat := m.surface_get_material(si) as ShaderMaterial
				if mat != null and mat.shader == EzTreeMeshes.BARK_SHADER:
					mat.set_shader_parameter("preset_tint", bark_tint)
		var colors := PackedColorArray()
		for xform: Transform3D in transforms:
			colors.append(IslandArt.crown_tone(Color.WHITE, xform.origin))
		var nodes: Array[MultiMeshInstance3D] = []
		for lod: int in 3:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = meshes[lod]
			mm.instance_count = transforms.size()
			mm.visible_instance_count = 0
			var instance := MultiMeshInstance3D.new()
			instance.name = "Trees_%s_lod%d" % [key.replace(":", "_"), lod]
			instance.multimesh = mm
			# Экземпляры переезжают между уровнями — отсечение по общему боксу.
			instance.custom_aabb = AABB(
				Vector3(-400.0, -10.0, -400.0), Vector3(800.0, 80.0, 800.0))
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
				if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(instance)
			nodes.append(instance)
		_groups.append({"transforms": transforms, "colors": colors, "nodes": nodes})
		if type != &"etree_bush":
			for xform: Transform3D in transforms:
				_tree_points.append(Vector2(xform.origin.x, xform.origin.z))
				var shape := CylinderShape3D.new()
				shape.radius = 0.3
				shape.height = 5.0
				var collision := CollisionShape3D.new()
				collision.shape = shape
				collision.position = xform.origin + Vector3(0.0, 2.5, 0.0)
				trunks.add_child(collision)
	update_viewer(DistrictLayout.START)


## Число экземпляров по уровням [ближний, средний, дальний] — для тестов.
func lod_counts() -> Array[int]:
	var counts: Array[int] = [0, 0, 0]
	for group: Dictionary in _groups:
		for lod: int in 3:
			counts[lod] += ((group["nodes"] as Array)[lod] as MultiMeshInstance3D) \
				.multimesh.visible_instance_count
	return counts


## Зритель сдвинулся: уровни деревьев и поле травы.
func update_viewer(pos: Vector3) -> void:
	var center := Vector2(pos.x, pos.z)
	if center.distance_to(_lod_center) >= LOD_STEP_M:
		_lod_center = center
		for group: Dictionary in _groups:
			_assign_lods(group, center)
	if _grass_nodes.is_empty():
		return
	var chunk := Vector2i(
		int(floorf(center.x / GrassField.CHUNK)),
		int(floorf(center.y / GrassField.CHUNK)))
	if chunk != _grass_center or not _grass_done:
		_grass_center = chunk
		_grass_done = _refresh_grass(center)


func _assign_lods(group: Dictionary, center: Vector2) -> void:
	var transforms: Array = group["transforms"]
	var colors: PackedColorArray = group["colors"]
	var nodes: Array = group["nodes"]
	var fill: Array[int] = [0, 0, 0]
	for i: int in transforms.size():
		var xform: Transform3D = transforms[i]
		var dist: float = Vector2(xform.origin.x, xform.origin.z).distance_to(center)
		var lod: int = 0 if dist < _lod1_m else (1 if dist < _lod2_m else 2)
		var mm: MultiMesh = (nodes[lod] as MultiMeshInstance3D).multimesh
		mm.set_instance_transform(fill[lod], xform)
		mm.set_instance_color(fill[lod], colors[i])
		fill[lod] += 1
	for lod: int in 3:
		(nodes[lod] as MultiMeshInstance3D).multimesh.visible_instance_count = fill[lod]


## Чанк травы 8×8 м на ровной земле района: раскладка — чистая функция
## мировых клеток (формат GrassField.build_chunk).
static func build_grass_chunk(tier: int, cx: int, cz: int) -> Dictionary:
	var groups: Dictionary = {
		"tuft": {"transforms": Array(), "colors": PackedColorArray()},
	}
	var tuft_colors: PackedColorArray = groups["tuft"]["colors"]
	for kind: String in GrassField.FLOWER_SCENES:
		groups["flower_%s" % kind] = {"transforms": Array()}
	var per_tuft: float = grass_density(tier) / float(GrassField.TUFTS_PER_CELL)
	var size: int = int(GrassField.CHUNK)
	var rng := RandomNumberGenerator.new()
	rng.seed = GrassField.cell_seed(cx, cz)
	var limit: float = DistrictLayout.HALF + FOREST_MARGIN
	for z: int in range(cz * size, cz * size + size):
		for x: int in range(cx * size, cx * size + size):
			if absf(float(x)) > limit or absf(float(z)) > limit:
				continue
			var cell := Vector2(float(x), float(z))
			var factor: float = GRASS_FACTOR.get(DistrictLayout.surface_at(cell), 0.0)
			# Пятнистость: в «проплешинах» шума травы меньше.
			var patch: float = 1.0 if GrassField.lab_patch(cell.x, cell.y) < 0.64 else 0.3
			var keep: float = per_tuft * factor * patch
			for _t: int in GrassField.TUFTS_PER_CELL:
				var roll: float = rng.randf()
				var scale3 := Vector3(
					rng.randf_range(GrassField.SIZE.x, GrassField.SIZE.x + GrassField.SIZE_VAR.x),
					rng.randf_range(GrassField.SIZE.y, GrassField.SIZE.y + GrassField.SIZE_VAR.y),
					rng.randf_range(GrassField.SIZE.z, GrassField.SIZE.z + GrassField.SIZE_VAR.z))
				var cr: float = 0.25 + rng.randf() * 0.1
				var cg: float = 0.3 + rng.randf() * 0.3
				var yaw: float = rng.randf_range(0.0, TAU)
				var jitter := Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
				if roll >= keep:
					continue
				var p: Vector2 = cell + jitter
				(groups["tuft"]["transforms"] as Array).append(Transform3D(
					Basis(Vector3.UP, yaw) * Basis().scaled(scale3),
					Vector3(p.x, DistrictLayout.ground_height(p) - GrassField.SINK, p.y)))
				tuft_colors.append(Color(cr, cg, 0.1, 1.0))
			var flower_roll: float = rng.randf()
			var flower_scale: float = rng.randf_range(
				GrassField.FLOWER_SCALE_FROM, GrassField.FLOWER_SCALE_TO)
			var flower_yaw: float = rng.randf_range(0.0, TAU)
			if factor >= 0.45 and patch >= 1.0 \
					and flower_roll < GrassField.FLOWER_DENSITY * 0.5:
				var kind: String = GrassField.flower_kind_for(x, z)
				(groups["flower_%s" % kind]["transforms"] as Array).append(Transform3D(
					Basis(Vector3.UP, flower_yaw) * Basis().scaled(Vector3.ONE * flower_scale),
					Vector3(cell.x, -GrassField.SINK, cell.y)))
	groups["tuft"]["colors"] = tuft_colors
	return groups


func _refresh_grass(center: Vector2) -> bool:
	var alive: Dictionary = {}
	var missing: Array[Vector2i] = []
	for key: Vector2i in GrassField.chunk_keys(_tier, center, _grass_radius):
		alive[key] = true
		if not _grass_chunks.has(key):
			missing.append(key)
	for key: Vector2i in _grass_chunks.keys():
		if not alive.has(key):
			_grass_chunks.erase(key)
	if missing.is_empty():
		return true
	missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) + Vector2(0.5, 0.5)).distance_to(center / GrassField.CHUNK) \
			< (Vector2(b) + Vector2(0.5, 0.5)).distance_to(center / GrassField.CHUNK))
	var budget: int = GRASS_CHUNK_BUDGET
	for key: Vector2i in missing:
		if budget <= 0:
			break
		budget -= 1
		_grass_chunks[key] = build_grass_chunk(_tier, key.x, key.y)
	GrassField.apply_field(_grass_nodes, GrassField.gather_from(_grass_chunks), center)
	return missing.size() <= GRASS_CHUNK_BUDGET
