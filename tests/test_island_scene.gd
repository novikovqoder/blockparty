# Интеграционные тесты сцены острова (этапы П2/П4.5): island.tscn
# соответствует данным IslandGen — рельеф и предметы из запечённого
# island_art.res (IslandView), в сцене три жителя, персонаж стоит
# на земле во всех зонах (--dev-spawn). Мобы удалены в доработке П5.13.
# Сцена коммитится — по сети не передаётся.
extends GutTest

const ISLAND: PackedScene = preload("res://gameplay/world/island.tscn")
const PLAYER: PackedScene = preload("res://gameplay/player/player.tscn")

## Кэш данных генератора между тестами (generate() дорогой, ~10 с).
static var _gen_cache: Dictionary = {}


func _island_data() -> Dictionary:
	if _gen_cache.is_empty():
		_gen_cache = IslandGen.generate()
	return _gen_cache


func test_baked_art_matches_generator() -> void:
	# П4.5: сцена строится из запечённого island_art.res — карта высот
	# и предметы совпадают с данными генератора, остров не перегенерирован
	# молча (IslandView._ready уже построил рельеф и коллизии из ресурса).
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	var view := island.get_node("IslandView") as IslandView
	assert_not_null(view, "в сцене есть IslandView")
	var data: Dictionary = _island_data()
	var heights: PackedFloat32Array = view.art.heights
	assert_eq(
		heights.size(), IslandGen.POINTS * IslandGen.POINTS, "карта высот 257 × 257",
	)
	assert_eq(heights, data["heights"], "высоты совпадают с генератором")
	assert_eq(
		view.art.chunks.size(),
		TerrainBuilder.CHUNKS_PER_SIDE * TerrainBuilder.CHUNKS_PER_SIDE,
		"8 × 8 чанков рельефа",
	)
	var instanced := 0
	for key: String in view.art.prop_groups:
		instanced += (view.art.prop_groups[key] as PropGroup).transforms.size()
	assert_eq(instanced, (data["props"] as Array).size(), "все предметы в группах ресурса")
	assert_not_null(view.get_node_or_null("Terrain"), "рельеф построен в _ready")
	assert_not_null(view.get_node_or_null("PropsCollision"), "коллизии предметов построены")
	var terrain := view.get_node("Terrain") as StaticBody3D
	var shape := (terrain.get_child(0) as CollisionShape3D).shape as HeightMapShape3D
	assert_eq(shape.map_width, IslandGen.POINTS, "коллизия рельефа — карта высот")
	assert_eq(shape.map_data, data["heights"], "коллизия из той же карты")


func test_scene_contents() -> void:
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	var water := 0
	var markers := 0
	var folk := 0
	var seats := 0
	for child: Node in island.get_children():
		if child is WaterArea:
			water += 1
		elif child is HangArea:
			markers = (child as HangArea).point_positions().size()
		elif child is Townsfolk:
			folk += 1
		elif child is CampfireSeat:
			seats += 1
	assert_eq(water, 2, "море и озеро")
	assert_gt(markers, 0, "в расщелине есть HangPoint")
	assert_eq(folk, 3, "три жителя (Финн, Луми, Тимьян)")
	assert_eq(seats, 8, "восемь мест у костра (раздел 9.6)")
	assert_eq(island.zones.size(), 6, "шесть зон")
	assert_eq(
		island.spawn_zones.size(), 6,
		"точки появления всех зон (--dev-spawn)",
	)


## Костёр (доработка П5.13, живой огонь): каменное кострище и поленья —
## CC0-модели Poly Haven (децимированные .res с вершинным цветом), пламя —
## шейдер с анимированным шумом, над ним искры и дым, тёплый мерцающий свет.
func test_campfire_assembly() -> void:
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	var fires: Array[Node] = []
	for child: Node in island.get_children():
		if child is Campfire:
			fires.append(child)
	assert_eq(fires.size(), 1, "костёр на площади один")
	var fire := fires[0] as Campfire
	var pit := fire.get_node("FirePit") as MeshInstance3D
	assert_not_null(pit, "кострище-модель на месте")
	assert_true(pit.mesh is ArrayMesh
			and (pit.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
					is PackedColorArray,
		"кострище — вершинно-цветный .res (Poly Haven stone_fire_pit)")
	var logs := fire.get_node("Logs")
	assert_eq(
		logs.get_child_count(), 3,
		"шатёр из трёх поленьев (Poly Haven dry_branches)")
	for log: Node in logs.get_children():
		assert_true((log as MeshInstance3D).mesh is ArrayMesh,
			"полено — .res-меш")
	var flame := fire.get_node("Flame") as MeshInstance3D
	assert_not_null(flame, "пламя на месте")
	assert_true((flame.material_override as ShaderMaterial).shader
			.resource_path.ends_with("fire.gdshader"),
		"пламя — шейдер огня")
	assert_not_null(fire.get_node("Smoke"), "дым над огнём")
	assert_not_null(fire.get_node("Sparks"), "искры над углями")
	var light := fire.find_children("*", "OmniLight3D", true, false)
	assert_eq(light.size(), 1, "тёплый свет костра")


func test_water_surfaces_configured() -> void:
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	for child: Node in island.get_children():
		if child is WaterArea:
			var area := child as WaterArea
			assert_gt(area.surface_size.x, 0.0, "размер задан")
			assert_almost_eq(
				area.level(), IslandGen.SEA_LEVEL, 0.01, "уровень воды из генератора",
			)


## Море не накрывает озеро (vfx-fix, баг 4): у моря дырка по озеру,
## поверхность — несколько мешей вне дырки, суммарная площадь равна
## площади моря минус дырка; у озера — один меш без дырки.
func test_sea_hole_removes_lake_overlap() -> void:
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	var sea_hole := Rect2()
	var lake_world := Rect2()
	for child: Node in island.get_children():
		var area := child as WaterArea
		if area == null:
			continue
		var meshes := 0
		var total := 0.0
		for node: Node in area.get_children():
			if node is not MeshInstance3D:
				continue
			var plane := (node as MeshInstance3D).mesh as PlaneMesh
			if plane == null:
				continue
			meshes += 1
			var rect := Rect2(
				(node as Node3D).position.x - plane.size.x * 0.5,
				(node as Node3D).position.z - plane.size.y * 0.5,
				plane.size.x, plane.size.y)
			# Ни один кусок поверхности не заходит в дырку (касание кромки
			# стыком — не пересечение: strict). Пустая дырка — проверять нечего.
			if area.surface_hole.has_area():
				assert_false(
					rect.intersects(area.surface_hole),
					"%s: меш вне дырки" % area.name)
			total += rect.size.x * rect.size.y
		if area.name == "SeaWater":
			assert_true(area.surface_hole.has_area(), "у моря есть дырка — озеро")
			sea_hole = area.surface_hole
			assert_gt(meshes, 1, "море с дыркой — не один меш")
			assert_almost_eq(
				total,
				area.surface_size.x * area.surface_size.y \
					- area.surface_hole.size.x * area.surface_hole.size.y,
				1.0, "суммарная площадь: море минус дырка")
		else:
			assert_false(area.surface_hole.has_area(), "у озера дырки нет")
			assert_eq(meshes, 1, "озеро — один меш")
			lake_world = Rect2(
				area.position.x - area.surface_size.x * 0.5,
				area.position.z - area.surface_size.y * 0.5,
				area.surface_size.x, area.surface_size.y)
	# Дырка моря — прямоугольник озера в локальных координатах моря
	# (центр моря в мировых XZ вычитается).
	assert_almost_eq(
		sea_hole.position.x + island.get_node("SeaWater").position.x,
		lake_world.position.x, 0.01, "дырка по кромке озера (x)")
	assert_almost_eq(
		sea_hole.position.y + island.get_node("SeaWater").position.z,
		lake_world.position.y, 0.01, "дырка по кромке озера (z)")
	assert_almost_eq(
		sea_hole.size.x, lake_world.size.x, 0.01, "размер дырки — озеро (x)")
	assert_almost_eq(
		sea_hole.size.y, lake_world.size.y, 0.01, "размер дырки — озеро (z)")


func test_player_stands_in_every_spawn_zone() -> void:
	# Коллизия рельефа (HeightMapShape3D) работает: персонаж не проваливается
	# ни в одной зоне.
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	var player := PLAYER.instantiate() as Player
	island.add_child(player)
	for zone: String in island.spawn_zones:
		var spawn: Vector3 = island.spawn_point(zone)
		player.global_position = spawn
		await get_tree().physics_frame
		var settled := false
		for i: int in range(60):
			await get_tree().physics_frame
			if player.is_on_floor():
				settled = true
				break
		assert_true(settled, "в зоне %s персонаж встал на землю" % zone)
		# Допуск 0.6: на крутом склоне (кромка расщелины) капсула сползает
		# на пару десятков сантиметров к подножию — это не провал под землю.
		assert_almost_eq(
			player.global_position.y,
			spawn.y, 0.6,
			"в зоне %s стоит на поверхности, а не падает" % zone,
		)
	player.queue_free()
