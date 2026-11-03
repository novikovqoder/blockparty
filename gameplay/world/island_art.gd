# Запечённый визуал острова (Resource, коммитится как island_art.res):
# карта высот, меши чанков рельефа, группы предметов PropGroup (трансформы
# и тона — чистые массивы, MultiMesh собирает island_view в рантайме)
# и боксы коллизий. По сети не передаётся — файл одинаков у всех.
# Собирает tools/generate_island.gd через build(); в сцену ставит
# island_view.gd: ресурс — чистые данные, нод в нём нет.
class_name IslandArt
extends Resource

## Карта высот 257 × 257, м (та же, что в коллизии HeightMapShape3D).
@export var heights: PackedFloat32Array = PackedFloat32Array()
## Меши чанков рельефа 32 × 32 м (TerrainBuilder), вершины с цветом грани.
@export var chunks: Array[Mesh] = []
## Группы предметов по ключу "type:variant" — трансформы и тоны
## (PropGroup); MultiMesh собирается в рантайме (PropGroup.to_multimesh).
@export var prop_groups: Dictionary = {}
## Коллизии предметов: {"pos": Vector3, "yaw": float, "size": Vector3} —
## бокс с нижней гранью в pos (модели стоят «ногами» в начале координат).
@export var colliders: Array[Dictionary] = []

## П17 п.2 «Вариация тона по дереву»: лёгкий jitter тона кроны per-instance
## (±6 % яркости и сдвиг оттенка зелёнее/жёлтее по R-каналу) — печёная
## величина, детерминирована сидом от мировой позиции дерева (мир общий
## у всех, в рантайме ничего не считается). Действует на всё дерево:
## instance color умножает и кору, и листву (canopy.gdshader/tree_bark).
const TONE_BRIGHTNESS: float = 0.06
const TONE_HUE: float = 0.06


## Тон дерева с вариацией: базовый тон зоны × (1 ± TONE_BRIGHTNESS),
## оттенок — сдвиг R-канала ±TONE_HUE (>0 зеленее, <0 жёлтее; G и B
## не трогаются — сдвиг в пределах «зелёный ↔ жёлтый»).
static func crown_tone(base: Color, pos: Vector3) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pos)
	var brightness: float = 1.0 \
		+ rng.randf_range(-TONE_BRIGHTNESS, TONE_BRIGHTNESS)
	var shift: float = rng.randf_range(-1.0, 1.0)
	return Color(
		base.r * brightness * (1.0 - TONE_HUE * shift),
		base.g * brightness,
		base.b * brightness,
	)


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
		var baked := PropGroup.new()
		baked.mesh = PropMeshes.mesh(group["type"], group["variant"])
		# Деревья Леса (П5.9, переделка): дальние уровни детализации —
		# LOD самого ez-tree (прореживание секций и листьев), меши
		# кэширует EzTreeMeshes.
		if EzTreeMeshes.is_tree(group["type"]):
			var set: Dictionary = EzTreeMeshes.build_set(
				group["type"], group["variant"])
			baked.lods = set["lods"]
		for prop: Dictionary in group["props"]:
			var scale: Vector3 = prop["scale"]
			var basis := Basis(Vector3.UP, float(prop["yaw"])) * Basis().scaled(scale)
			baked.transforms.append(Transform3D(basis, prop["pos"]))
			# П17 п.2: деревьям — вариация тона кроны per-instance.
			var tone: Color = prop["tint"]
			if String(group["type"]).begins_with("etree_"):
				tone = crown_tone(tone, prop["pos"])
			baked.colors.append(tone)
		art.prop_groups[key] = baked

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
