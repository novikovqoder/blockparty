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
## чанками 32 × 32 м (вершины на целых координатах −128..128).
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
	for chunk: Mesh in art.chunks:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = chunk
		mesh_instance.material_override = material
		body.add_child(mesh_instance)
	add_child(body)


## Предметы: MultiMesh из ресурса, дальность видимости — по типу.
func _build_props() -> void:
	var material := LowPolyMat.flat_or_vertex()
	for key: String in art.prop_multimeshes:
		var type := String(key.split(":")[0])
		var instance := MultiMeshInstance3D.new()
		instance.name = "Props_" + key.replace(":", "_")
		instance.multimesh = art.prop_multimeshes[key]
		instance.material_override = material
		var range: float = PropMeshes.visibility_range(StringName(type))
		if range > 0.0:
			instance.visibility_range_end = range
			_base_ranges[type] = range
		add_child(instance)
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


## «Простая графика» (раздел 15): без травы, мелкие предметы ближе.
func set_simple_graphics(simple: bool) -> void:
	if _props_by_type.has("grass_tuft"):
		(_props_by_type["grass_tuft"] as MultiMeshInstance3D).visible = not simple
	for type: String in _base_ranges:
		var instance: MultiMeshInstance3D = _props_by_type[type]
		instance.visibility_range_end = maxf(25.0, float(_base_ranges[type]) * 0.6) \
			if simple else float(_base_ranges[type])
