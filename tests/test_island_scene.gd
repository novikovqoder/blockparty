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
	for child: Node in island.get_children():
		if child is WaterArea:
			water += 1
		elif child is HangArea:
			markers = (child as HangArea).point_positions().size()
	assert_eq(water, 2, "море и озеро")
	assert_gt(markers, 0, "в расщелине есть HangPoint")
	assert_eq(island.zones.size(), 6, "шесть зон")
	assert_eq(
		island.spawn_zones.size(), 6,
		"точки появления всех зон (--dev-spawn)",
	)


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


## Доработка-2 П5.13, П3; П14 4: вода — свой шейдер water_bu (Boujie
## больше не используется). Море — нода Ocean аддона как сетка (кольца
## LOD, следует за камерой), озеро — плоскость тем же шейдером спокойнее
## (волны меньше) и на LAKE_LIFT выше моря: копланарное мерцание двух
## полупрозрачных поверхностей (vfx-fix, баг 4) исчезает вместе с дыркой
## в море.
func test_water_is_shared_ocean_and_lake() -> void:
	# Шейдерные материалы воды строит только текстурный режим (headless
	# без флага отдаёт плоские заглушки) — включаем, как тест аудита.
	WorldMaterials.textured_headless = true
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	WorldMaterials.textured_headless = false
	var sea_material: ShaderMaterial = null
	var lake_material: ShaderMaterial = null
	var lake_surface: MeshInstance3D = null
	for child: Node in island.get_children():
		var area := child as WaterArea
		if area == null:
			continue
		if area.name == "SeaWater":
			# Море — Ocean аддона как сетка LOD-колец, материал water_bu.
			var ocean := area.get_node_or_null("Ocean") as Ocean
			assert_not_null(ocean, "море — нода Ocean аддона (LOD-кольца)")
			if ocean == null:
				continue
			assert_gt(ocean.levels_of_detail, 1, "у океана есть уровни LOD")
			assert_gt(ocean.far_edge, 500, "дальняя плоскость у горизонта")
			var follower := ocean.get_node_or_null(
				"CameraFollower3D") as CameraFollower3D
			assert_not_null(follower, "LOD-центр следует за камерой")
			sea_material = ocean.material as ShaderMaterial
		else:
			# Озеро — одна плоскость тем же шейдером.
			var planes := 0
			for node: Node in area.get_children():
				if node is MeshInstance3D \
						and (node as MeshInstance3D).mesh is PlaneMesh:
					planes += 1
					lake_surface = node as MeshInstance3D
			assert_eq(planes, 1, "озеро — одна плоскость")
			if lake_surface != null:
				lake_material = lake_surface.material_override as ShaderMaterial
				# Зеркало озера выше моря (нет копланарного мерцания).
				var local_top: float = area.water_level - area.position.y \
					+ WaterArea.LAKE_LIFT
				assert_almost_eq(lake_surface.position.y, local_top, 0.001,
					"озеро на LAKE_LIFT выше уровня воды")
	assert_not_null(sea_material, "материал моря — ShaderMaterial")
	assert_not_null(lake_material, "материал озера — ShaderMaterial")
	if sea_material == null or lake_material == null:
		return
	# Один и тот же шейдер water_bu у моря и озера («одна поверхность»).
	assert_eq(sea_material.shader, lake_material.shader,
		"море и озеро — один шейдер water_bu")
	# Озеро спокойнее: амплитуда первой (самой длинной) волны спектра
	# меньше морской (waves_a[i].w — амплитуда).
	var sea_waves := sea_material.get_shader_parameter(
		"waves_a") as PackedVector4Array
	var lake_waves := lake_material.get_shader_parameter(
		"waves_a") as PackedVector4Array
	assert_gt(sea_waves.size(), 0, "спектр моря не пуст")
	assert_gt(lake_waves.size(), 0, "спектр озера не пуст")
	if sea_waves.size() > 0 and lake_waves.size() > 0:
		assert_lt(lake_waves[0].w, sea_waves[0].w * 0.5,
			"волны озера заметно спокойнее морских (%.3f < %.3f)" % [
				lake_waves[0].w, sea_waves[0].w])
	# Вода процедурная (П14 4.5): назначенных текстур нет вовсе — пена
	# и рябь шумом, текстур Boujie в материалах не осталось. П15 9.3 —
	# единственное исключение: SDF-карта расстояния до берега, запечённая
	# из карты высот острова на генерации (не ассет).
	for material: ShaderMaterial in [sea_material, lake_material]:
		for u: Dictionary in material.shader.get_shader_uniform_list():
			if u["name"] == "shore_sdf":
				assert_true(
					material.get_shader_parameter(u["name"]) is Texture2D,
					"SDF-карта берега назначена (П15 9.3)")
				continue
			assert_false(material.get_shader_parameter(u["name"])
				is Texture2D, "у воды нет текстур (%s)" % u["name"])
	# Цвет по глубине: глубокая темнее мелководья (прозрачность — Бером
	# по каналам в композите, альфа цветов не используется).
	var deep: Color = sea_material.get_shader_parameter("color_deep")
	var shallow: Color = sea_material.get_shader_parameter("color_shallow")
	assert_lt(deep.get_luminance(), shallow.get_luminance(),
		"глубокая вода темнее мелководья")


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
