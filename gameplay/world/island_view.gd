# Визуал острова (раздел 6 SPEC): строит в _ready статичный мир из
# запечённого ресурса IslandArt — StaticBody3D рельефа с HeightMapShape3D
# и мешами чанков, MultiMeshInstance3D предметов (по одному на тип и
# вариант; трава и цветы исчезают вдали — раздел 16) и боксы коллизий
# предметов. Логики нет: остров генерируется одинаково у всех, по сети не
# передаётся. «Простая графика» (set_simple_graphics) прячет траву
# и приближает дальность прорисовки мелких предметов.
class_name IslandView
extends Node3D

## Запечённый остров (island_art.res): высоты, меши чанков, MultiMesh.
@export var art: IslandArt

## MultiMesh предметов по типу (для «Простой графики»).
var _props_by_type: Dictionary = {}
## Базовая дальность видимости типов (для «Простой графики»).
var _base_ranges: Dictionary = {}


func _ready() -> void:
	_build_terrain()
	_build_props()
	_build_colliders()


## Рельеф: одна карта высот и на коллизию (HeightMapShape3D), и на меш
## чанками 32 × 32 м (вершины на целых координатах −128..128). Сектор Леса
## [−128..0)² с П5.7 красится реалистичным материалом ForestGround: те же
## чанки и та же коллизия — меняется только материал.
func _build_terrain() -> void:
	var body := StaticBody3D.new()
	body.name = "Terrain"
	var collision := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = IslandGen.POINTS
	shape.map_depth = IslandGen.POINTS
	shape.map_data = art.heights
	collision.shape = shape
	body.add_child(collision)
	var material := LowPolyMat.flat_or_vertex()
	var forest_material := ForestGround.make_material(art)
	for chunk: Mesh in art.chunks:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = chunk
		mesh_instance.material_override = (
			forest_material if _in_forest_sector(chunk.get_aabb()) else material)
		body.add_child(mesh_instance)
	add_child(body)


## Чанк целиком в секторе Леса (границы кратны 32 — пересечений нет).
## Вершины чанков в мировых координатах, нод без transform — AABB готов.
static func _in_forest_sector(aabb: AABB) -> bool:
	return aabb.position.x >= -128.0 and aabb.end.x <= 0.0 \
		and aabb.position.z >= -128.0 and aabb.end.z <= 0.0


## Предметы: MultiMesh собирается в рантайме из групп ресурса (инстанс-данные
## MultiMesh не сериализуются при headless-запекании — PropGroup), дальность
## видимости — по типу.
func _build_props() -> void:
	var material := LowPolyMat.flat_or_vertex()
	for key: String in art.prop_groups:
		var type := String(key.split(":")[0])
		var group: PropGroup = art.prop_groups[key]
		# Деревья Леса (П5.9, переделка): уровни детализации ez-tree —
		# отдельные MultiMesh на дистанционных диапазонах; материалы
		# запечены в меши (кора + листва), override не ставится.
		if not group.lods.is_empty():
			_build_tree_lods(key, type, group)
			continue
		var instance := MultiMeshInstance3D.new()
		instance.name = "Props_" + key.replace(":", "_")
		instance.multimesh = group.to_multimesh()
		# Растительность Леса (П5.9) — материалы ForestMat (градиент травы,
		# ветер, спад густоты от камеры, мох камней); остальная растительность
		# качается на ветру (vfx-fix, блок б); прочие предметы — статичный.
		var type_name := StringName(type)
		if ForestMat.handles(type_name):
			instance.material_override = ForestMat.for_type(type_name)
		elif not PropMeshes.wind_params(type_name).is_empty():
			instance.material_override = LowPolyMat.wind_or_vertex(type_name)
		else:
			instance.material_override = material
		var range: float = PropMeshes.visibility_range(type_name)
		if range > 0.0:
			instance.visibility_range_end = range
			_base_ranges[type] = range
		add_child(instance)
		_props_by_type[type] = instance


## Деревья по уровням дальности (раздел 16): полная модель до 45 м, LOD1 —
## до 90, LOD2 (как в демо ez-tree — прореженные секции и одиночные
## карточки листьев) — до 220 м: практически всегда виден, но дальше
## растворяется в дымке. Диапазоны перекрываются загибом (margin 6 м) —
## переключения без «мигания».
func _build_tree_lods(key: String, type: String, group: PropGroup) -> void:
	var levels: Array = [
		{"mesh": group.mesh, "begin": 0.0, "end": 45.0, "shadow": true},
		{"mesh": group.lods[0], "begin": 45.0, "end": 90.0, "shadow": true},
		{"mesh": group.lods[1], "begin": 90.0, "end": 220.0, "shadow": false},
	]
	for index: int in levels.size():
		var level: Dictionary = levels[index]
		var instance := MultiMeshInstance3D.new()
		instance.name = "Props_%s_%s_lod%d" % [
			type, key.get_slice(":", 1), index]
		instance.multimesh = group.to_multimesh(level["mesh"])
		instance.visibility_range_begin = float(level["begin"])
		instance.visibility_range_end = float(level["end"])
		instance.visibility_range_begin_margin = 6.0
		instance.visibility_range_end_margin = 6.0
		instance.cast_shadow = \
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
			if level["shadow"] \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		if index == 0:
			_props_by_type[type] = instance


## Коллизии предметов: бокс с нижней гранью в точке предмета.
func _build_colliders() -> void:
	if art.colliders.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "PropsCollision"
	for collider: Dictionary in art.colliders:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = collider["size"]
		shape.shape = box
		var transform := Transform3D(
			Basis(Vector3.UP, float(collider["yaw"])), collider["pos"]
		)
		transform.origin += transform.basis * Vector3(0.0, float(collider["size"].y) * 0.5, 0.0)
		shape.transform = transform
		body.add_child(shape)
	add_child(body)


## «Простая графика» (раздел 15): без травы (включая пучки Леса, П5.9),
## мелкие предметы ближе.
func set_simple_graphics(simple: bool) -> void:
	for type: String in ["rgrass", "rflower", "riris", "reed"]:
		if _props_by_type.has(type):
			(_props_by_type[type] as MultiMeshInstance3D).visible = not simple
	for type: String in _base_ranges:
		var instance: MultiMeshInstance3D = _props_by_type[type]
		instance.visibility_range_end = maxf(25.0, float(_base_ranges[type]) * 0.6) \
			if simple else float(_base_ranges[type])
