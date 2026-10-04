# Запечённый визуал острова (Resource, коммитится как island_art.res):
# карта высот, меши чанков рельефа, MultiMesh предметов (трансформы и
# instance-цвета готовы) и боксы коллизий. По сети не передаётся — файл
# одинаков у всех. Собирает tools/generate_island.gd через build();
# в сцену ставит island_view.gd: ресурс — чистые данные, нод в нём нет.
class_name IslandArt
extends Resource

## Карта высот 257 × 257, м (та же, что в коллизии HeightMapShape3D).
@export var heights: PackedFloat32Array = PackedFloat32Array()
## Меши чанков рельефа 32 × 32 м (TerrainBuilder), вершины с цветом грани.
@export var chunks: Array[Mesh] = []
## MultiMesh по ключу "type:variant" — предмет уже с трансформой и тоном.
@export var prop_multimeshes: Dictionary = {}
## Коллизии предметов: {"pos": Vector3, "yaw": float, "size": Vector3} —
## бокс с нижней гранью в pos (модели стоят «ногами» в начале координат).
@export var colliders: Array[Dictionary] = []


## Собрать визуал из данных IslandGen.generate(): рельеф, предметы
## (группировка по типу и варианту — один MultiMesh на группу), коллизии
## только для IslandGen.SOLID_TYPES.
static func build(data: Dictionary) -> IslandArt:
	var art := IslandArt.new()
	art.heights = data["heights"]
	art.chunks = TerrainBuilder.build_chunks(data)

	# Предметы → группы (type, variant).
	var groups: Dictionary = {}
	for prop: Dictionary in data["props"]:
		var type := String(prop["type"])
		var key := "%s:%d" % [type, int(prop["variant"])]
		if not groups.has(key):
			groups[key] = {"type": StringName(type), "variant": int(prop["variant"]), "props": []}
		groups[key]["props"].append(prop)
	for key: String in groups:
		var group: Dictionary = groups[key]
		var mesh := PropMeshes.mesh(group["type"], group["variant"])
		var props: Array = group["props"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = props.size()
		for i: int in props.size():
			var prop: Dictionary = props[i]
			var scale: Vector3 = prop["scale"]
			var basis := Basis(Vector3.UP, float(prop["yaw"])) * Basis().scaled(scale)
			mm.set_instance_transform(i, Transform3D(basis, prop["pos"]))
			mm.set_instance_color(i, prop["tint"])
		art.prop_multimeshes[key] = mm

	for prop: Dictionary in data["props"]:
		var type := StringName(prop["type"])
		var size := PropMeshes.collision_size(type, prop["scale"])
		if size == Vector3.ZERO:
			continue
		art.colliders.append({
			"pos": prop["pos"],
			"yaw": float(prop["yaw"]),
			"size": size,
		})
	return art
