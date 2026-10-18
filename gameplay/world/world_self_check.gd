# Самопроверка мира (доработка П5.13): класс бага «объекты висят в небе /
# под ногами вода» — рельеф-визуал не совпадал с картой высот, по которой
# расставлены объекты. Теперь весь остров рисуют те же чанки из карты
# высот, и проверка держит это инвариантом:
#  1) каждый чанк несёт массив ARRAY_TANGENT (нормал-мап земли требует
#     тангентов — без них Forward+ роняет warning на каждый чанк);
#  2) все чанки острова (все зоны) — с материалом ForestGround (текстурная
#     земля) и есть HeightMapShape3D по всей карте высот;
#  3) ни один предмет не висит над землёй и не стоит под водой: позиция
#     каждого экземпляра каждой группы — у билинейной высоты рельефа
#     в его точке и выше уровня воды;
#  4) вода — только море вокруг и озеро в своей чаше: две WaterArea,
#     озеро накрывает чашу (d < 16), море с дыркой по озеру;
#  5) ни одного «белого квадрата»: у каждой поверхности каждого меша
#     острова есть материал, и ни один BaseMaterial3D не является
#     заглушкой — белый албедо без текстуры, вершинных цветов и свечения
#     (доработка П5.13, дочистка).
# Используется тестом GUT (test_world_ground) и ключом --selftest-world
# в запущенной игре (включая экспортированную сборку).
class_name WorldSelfCheck
extends RefCounted

## Предмет выше этой высоты рельефа — «висит», м (по умолчанию; типам
## с легальным возвышением — настилы, сваи, мост, стены — допуск шире).
const HOVER_M: float = 1.0
## Допуск |dy| по типам: стены расщелины врезаны в склон по кромкам,
## настил мостков идёт над водой, сваи стоят в дне, мост — над оврагом,
## трава и цветы сажаются на клетчатых склонах с интерполяцией.
const TYPE_TOLERANCE: Dictionary = {
	"rock_wall": 8.0,
	"plank_deck": 6.0,
	"rgrass": 3.0,
	"rflower": 3.0,
	"pier_post": 3.0,
	"log_bridge": 2.0,
	"pebble": 1.6,
	"boat": 1.5,
}
## Типы, которым разрешено стоять в воде: сваи мостков — в дне озера.
const WATER_TYPES: Array = ["pier_post"]
## Под уровнем моря предмет стоять не может (море и озеро), м запаса.
const SEA_MARGIN: float = 0.05


## Прогнать проверку на острове (статичные данные — без ожидания кадров).
## Возвращает {ok, reasons, metrics}; reasons пустой — всё хорошо.
static func run(island: Island, verbose: bool = false) -> Dictionary:
	var reasons: PackedStringArray = PackedStringArray()
	var metrics := {}
	var view := island.get_node("IslandView") as IslandView
	var art: IslandArt = view.art

	# 1) Тангенты у каждого чанка: размер 4 float на вершину, w = +1
	# (бинормаль движка cross(TANGENT, NORMAL)·w — вдоль dP/dv при UV-росте
	# по X; знак сверен с SurfaceTool.generate_tangents).
	var chunks: int = art.chunks.size()
	var no_tangent := 0
	var bad_w := 0
	for chunk: Mesh in art.chunks:
		var arrays: Array = (chunk as ArrayMesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		if tangents.size() != verts.size() * 4:
			no_tangent += 1
			continue
		for i: int in range(3, tangents.size(), 4):
			if not is_equal_approx(tangents[i], 1.0):
				bad_w += 1
				break
	metrics["chunks"] = chunks
	metrics["chunks_no_tangent"] = no_tangent
	metrics["chunks_bad_tangent_w"] = bad_w
	if no_tangent > 0:
		reasons.append("чанков без массива ARRAY_TANGENT: %d из %d"
			% [no_tangent, chunks])
	if bad_w > 0:
		reasons.append("чанков с тангентом w != +1: %d" % bad_w)

	# 2) В сцене: все чанки с текстурной землёй ForestGround, коллизия —
	# вся карта высот.
	var terrain := view.get_node("Terrain") as StaticBody3D
	var painted := 0
	for child: Node in terrain.get_children():
		if child is MeshInstance3D \
				and (child as MeshInstance3D).material_override is ShaderMaterial:
			var shader: Shader = (
				(child as MeshInstance3D).material_override as ShaderMaterial
			).shader
			if shader != null and shader.resource_path == ForestGround.SHADER.resource_path:
				painted += 1
	metrics["chunks_painted"] = painted
	if painted != chunks:
		reasons.append("чанков с материалом ForestGround: %d из %d" % [painted, chunks])
	var height_shape: HeightMapShape3D = null
	for child: Node in terrain.get_children():
		if child is CollisionShape3D \
				and (child as CollisionShape3D).shape is HeightMapShape3D:
			height_shape = (child as CollisionShape3D).shape
	if height_shape == null:
		reasons.append("нет HeightMapShape3D — рельефа без коллизии нет")
	elif height_shape.map_width != IslandGen.POINTS \
			or height_shape.map_depth != IslandGen.POINTS \
			or height_shape.map_data.size() != IslandGen.POINTS * IslandGen.POINTS:
		reasons.append("коллизия рельефа не покрывает карту высот целиком")
	metrics["collision_points"] = (
		height_shape.map_data.size() if height_shape != null else 0)

	# 3) Предметы на земле и не под воде: допуск по типу (стены, мостки,
	# мост и трава склонов легально возвышаются над рельефом).
	var hovered := 0
	var sunk := 0
	var underwater := 0
	var checked_props := 0
	var worst_hover := 0.0
	var worst_sink := 0.0
	for key: String in art.prop_groups:
		var type := String(key.split(":")[0])
		var group: PropGroup = art.prop_groups[key]
		var tol: float = TYPE_TOLERANCE.get(type, HOVER_M)
		for transform: Transform3D in group.transforms:
			var pos: Vector3 = transform.origin
			var ground := ground_y(art.heights, pos.x, pos.z)
			var dy := pos.y - ground
			checked_props += 1
			if dy > tol:
				hovered += 1
				worst_hover = maxf(worst_hover, dy)
			if dy < -tol:
				sunk += 1
				worst_sink = maxf(worst_sink, -dy)
			if pos.y <= IslandGen.SEA_LEVEL - SEA_MARGIN \
					and not WATER_TYPES.has(type):
				underwater += 1
	metrics["props_checked"] = checked_props
	metrics["props_hovering"] = hovered
	metrics["props_sunk"] = sunk
	metrics["props_underwater"] = underwater
	metrics["worst_hover_m"] = worst_hover
	metrics["worst_sink_m"] = worst_sink
	if hovered > 0:
		reasons.append("предметов висит над землёй: %d (макс +%.2f м)"
			% [hovered, worst_hover])
	if sunk > 0:
		reasons.append("предметов утоплено в землю: %d (макс %.2f м)"
			% [sunk, worst_sink])
	if underwater > 0:
		reasons.append("предметов под водой: %d" % underwater)

	# 4) Вода: только море вокруг и озеро в чаше.
	var waters: Array[WaterArea] = []
	for child: Node in island.get_children():
		if child is WaterArea:
			waters.append(child as WaterArea)
	metrics["water_areas"] = waters.size()
	if waters.size() != 2:
		reasons.append("вода: ожидаемое море + озеро, найдено %d" % waters.size())
	else:
		var lake: WaterArea = null
		for water: WaterArea in waters:
			if water.name == "LakeWater":
				lake = water
			elif water.name != "SeaWater":
				reasons.append("неизвестная вода: %s" % water.name)
			elif not water.surface_hole.has_area():
				reasons.append("у моря нет дырки под озеро")
		if lake == null:
			reasons.append("нет озера LakeWater")
		else:
			# Чаша озера (IslandGen.LAKE_*): плоскость обязана накрывать её,
			# за чашей берег выше уровня прячет излишек под рельефом.
			var lake_center := Vector2(lake.position.x, lake.position.z)
			if lake_center.distance_to(IslandGen.LAKE_CENTER) > 0.5:
				reasons.append("озеро не в чаше: центр %s" % lake_center)
			if lake.surface_size.x < IslandGen.LAKE_BASIN_R * 2.0 + 1.0 \
					or lake.surface_size.y < IslandGen.LAKE_BASIN_R * 2.0 + 1.0:
				reasons.append("озеро меньше чаши: %s" % lake.surface_size)
			if absf(lake.level() - IslandGen.SEA_LEVEL) > 0.01:
				reasons.append("уровень озера не SEA_LEVEL")
	# Море не выходит за карту острова.
	for water: WaterArea in waters:
		if water.name == "SeaWater":
			var half := water.surface_size * 0.5
			var center := Vector2(water.position.x, water.position.z)
			if absf(center.x) > 0.01 or absf(center.y) > 0.01 \
					or half.x > IslandGen.HALF + 0.01 \
					or half.y > IslandGen.HALF + 0.01:
				reasons.append("море шире карты острова")

	# 5) Материалы: каждый меш острова (включая дочерние сцены — костёр,
	# жители, вода, частицы) рисуется материалом, и ни один BaseMaterial3D
	# не выглядит неокрашенной заглушкой (белый албедо без текстуры,
	# вершинных цветов и свечения — «белый квадрат»).
	var bare := 0
	var placeholders := 0
	var surfaces := 0
	var offenders: PackedStringArray = PackedStringArray()
	var meshes: Array = island.find_children("*", "MeshInstance3D", true, false) \
		+ island.find_children("*", "MultiMeshInstance3D", true, false) \
		+ island.find_children("*", "GPUParticles3D", true, false)
	for node: Node in meshes:
		for mesh: Mesh in _node_meshes(node):
			for surface: int in mesh.get_surface_count():
				surfaces += 1
				var material: Material = (node as GeometryInstance3D).material_override
				if material == null:
					material = mesh.surface_get_material(surface)
				if material == null:
					bare += 1
					if offenders.size() < 8:
						offenders.append("%s: поверхность %d без материала"
							% [node.get_path(), surface])
				elif material is BaseMaterial3D and _is_placeholder(material):
					placeholders += 1
					if offenders.size() < 8:
						offenders.append("%s: белый албедо без текстуры"
							% node.get_path())
	metrics["surfaces_checked"] = surfaces
	metrics["surfaces_bare"] = bare
	metrics["surfaces_placeholder"] = placeholders
	if bare > 0 or placeholders > 0:
		reasons.append("мешей без материала/текстуры: %d (+%d заглушек): %s"
			% [bare, placeholders, ", ".join(offenders)])

	if verbose:
		for line: String in metrics:
			print("  %s: %s" % [line, str(metrics[line])])
	return {"ok": reasons.is_empty(), "reasons": reasons, "metrics": metrics}


## Все меши узла-рисователя: сама сетка у MeshInstance3D, multimesh.mesh —
## у MultiMesh, пассы частиц — у GPUParticles3D.
static func _node_meshes(node: Node) -> Array[Mesh]:
	var result: Array[Mesh] = []
	if node is MultiMeshInstance3D:
		var multi: MultiMesh = (node as MultiMeshInstance3D).multimesh
		if multi != null and multi.mesh != null:
			result.append(multi.mesh)
	elif node is GPUParticles3D:
		var fx := node as GPUParticles3D
		for index: int in fx.draw_passes:
			var mesh: Mesh = fx.get("draw_pass_%d" % (index + 1)) as Mesh
			if mesh != null:
				result.append(mesh)
	elif node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			result.append(mesh)
	return result


## Стандартный материал-заглушка: белый албедо без текстуры, вершинных
## цветов и свечения — именно так выглядит «белый квадрат». Цветной албедо
## и шейдеры low-poly — легальная раскраска мира.
static func _is_placeholder(material: BaseMaterial3D) -> bool:
	if material.albedo_texture != null:
		return false
	if material.vertex_color_use_as_albedo:
		return false
	if material.emission_enabled:
		return false
	var color := material.albedo_color
	return color.r > 0.92 and color.g > 0.92 and color.b > 0.92


## Высота рельефа билинейно из карты (вершины на целых координатах,
## шаг 1 м); за краем карты — кламп (у ограждений предметов нет).
static func ground_y(heights: PackedFloat32Array, x: float, z: float) -> float:
	var fx: float = clampf(x, -IslandGen.HALF, IslandGen.HALF - 0.001)
	var fz: float = clampf(z, -IslandGen.HALF, IslandGen.HALF - 0.001)
	var x0: int = floori(fx)
	var z0: int = floori(fz)
	var tx: float = fx - x0
	var tz: float = fz - z0
	var h00: float = heights[(z0 + IslandGen.HALF) * IslandGen.POINTS + x0 + IslandGen.HALF]
	var h10: float = heights[(z0 + IslandGen.HALF) * IslandGen.POINTS + x0 + 1 + IslandGen.HALF]
	var h01: float = heights[(z0 + 1 + IslandGen.HALF) * IslandGen.POINTS + x0 + IslandGen.HALF]
	var h11: float = heights[(z0 + 1 + IslandGen.HALF) * IslandGen.POINTS + x0 + 1 + IslandGen.HALF]
	return lerpf(
		lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
