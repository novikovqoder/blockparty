# Тесты района (постапокалипсис, этап 1 графики): флаг --district, состав
# сцены, раскладка по карте (покрытия, озеро, пятна построек), панельный дом,
# детерминированные деревья с уровнями детализации и чанки травы.
extends GutTest

const DevScript: GDScript = preload("res://autoload/dev.gd")
const L: GDScript = preload("res://gameplay/district/district_layout.gd")


func _make_lab() -> DistrictLab:
	var scene: PackedScene = load(DevScript.DISTRICT_SCENE)
	var lab := scene.instantiate() as DistrictLab
	# Без игрока и уровня графики: тест проверяет раскладку, а не героя.
	lab.spawn_player = false
	add_child_autofree(lab)
	return lab


func test_district_flag_parses_and_scene_exists() -> void:
	var d: Dictionary = DevScript.parse_args(PackedStringArray(["--district"]))
	assert_true(d["district"], "--district разбирается")
	assert_false(
		DevScript.parse_args(PackedStringArray([]))["district"],
		"без аргумента район не включается")
	assert_true(
		ResourceLoader.exists(DevScript.DISTRICT_SCENE),
		"файл сцены района существует")


func test_district_builds_map_objects() -> void:
	var lab: DistrictLab = _make_lab()
	for node_name: String in [
		"Env", "Ground", "Surfaces", "Lake", "Houses", "Ruins", "Buildings",
		"Garages", "Blocks", "Cars", "Borders", "Tower", "Nature",
	]:
		assert_not_null(lab.get_node_or_null(node_name), "узел %s" % node_name)
	assert_eq(lab.get_node("Houses").get_child_count(), 4, "четыре пятиэтажки")
	assert_eq(lab.get_node("Ruins").get_child_count(), L.RUINS.size(), "руины")
	assert_eq(lab.get_node("Garages").get_child_count(), L.GARAGE_COUNT, "гаражи")
	assert_eq(lab.get_node("Cars").get_child_count(), L.CARS.size(), "машины")
	for path: String in ["Buildings/Shop", "Buildings/Transformer", "Blocks/Bus", "Blocks/Pier"]:
		assert_not_null(lab.get_node_or_null(path), "постройка %s" % path)
	assert_true(lab.get_node("Lake") is WaterArea, "озеро — вода мира")


func test_district_single_open_entrance_in_north_house() -> void:
	var lab: DistrictLab = _make_lab()
	var open_count: int = 0
	var total: int = 0
	for house: Node in lab.get_node("Houses").get_children():
		for child: Node in house.get_children():
			if child.is_in_group(PanelHouse.GROUP_ENTRANCE):
				total += 1
				if child.name == &"EntranceOpen":
					open_count += 1
					assert_eq(String(house.name), L.OPEN_HOUSE, "открыт северный дом")
	assert_eq(open_count, 1, "открытый подъезд один")
	assert_eq(total, 13, "подъездов всего 4 + 3 + 3 + 3")


func test_layout_surfaces_match_map() -> void:
	assert_eq(L.surface_at(Vector2(-40.0, 6.1)), L.Surface.ASPHALT, "дорога")
	assert_eq(L.surface_at(Vector2(13.0, -38.0)), L.Surface.YARD, "двор")
	assert_eq(L.surface_at(Vector2(12.4, -72.9)), L.Surface.BUILDING, "северный дом")
	assert_eq(L.surface_at(Vector2(-21.5, -30.0)), L.Surface.BUILDING, "западный дом (повёрнут)")
	assert_eq(L.surface_at(Vector2(-60.0, 80.0)), L.Surface.WATER, "озеро")
	assert_eq(L.surface_at(Vector2(60.0, -90.0)), L.Surface.GRASS, "луг за домами")
	var start := Vector2(L.START.x, L.START.z)
	assert_false(L.in_lake(start), "старт не в озере")
	assert_false(L.in_footprint(start, 1.0), "старт не в постройке")
	assert_true(absf(start.x) < L.HALF and absf(start.y) < L.HALF, "старт внутри участка")


func test_layout_lake_bowl() -> void:
	assert_eq(L.ground_height(Vector2(0.0, 0.0)), 0.0, "суша ровная")
	assert_almost_eq(
		L.ground_height(Vector2(-60.0, 75.0)), -L.LAKE_MAX_DEPTH, 0.01,
		"середина озера — полная глубина")
	var shore: float = L.ground_height(Vector2(-28.0, 57.0))
	assert_true(shore < 0.0 and shore > -1.0, "у берега мелко (%.2f)" % shore)
	assert_true(-L.LAKE_MAX_DEPTH < L.WATER_LEVEL, "вода выше дна")


func test_panel_house_structure() -> void:
	assert_eq(PanelHouse.bay_count(56.5), 18, "секций в северном доме")
	var stairs: Array[int] = PanelHouse.stair_bays(18, 4)
	assert_eq(stairs.size(), 4, "четыре подъезда")
	assert_eq(stairs, [2, 6, 11, 15] as Array[int], "подъезды по секциям")
	var house: Node3D = PanelHouse.build("T", 56.5, 13.4, 5, 4, 1, 7)
	add_child_autofree(house)
	var mesh: Mesh = (house.get_node("Mesh") as MeshInstance3D).mesh
	assert_gt(mesh.get_surface_count(), 6, "поверхности по материалам")
	var top: float = mesh.get_aabb().end.y
	assert_almost_eq(top, PanelHouse.wall_top(5) + 1.2, 0.3, "высота с будками на крыше")
	var triangles: int = house.get_meta(&"triangles")
	assert_between(triangles, 3000, 60000, "треугольников в доме в бюджете")
	# Та же сборка — тот же дом (детерминизм по seed).
	var again: Node3D = PanelHouse.build("T", 56.5, 13.4, 5, 4, 1, 7)
	add_child_autofree(again)
	assert_eq(again.get_meta(&"triangles"), triangles, "детерминирован")


## Владелец 11.11.2026: стартовая атмосфера района — пасмурный день, не
## золотой час ef99e84. Что проверяемо headless: флаг пресета, стартовые
## часы (солнце высоко, время суток без тёплых краёв), поднятая облачность,
## холодно-нейтральный свет и дымка без тёплого золотого оттенка, слабые
## прямые лучи, объёмные лучи едва заметны (по константам пресета).
func test_district_starts_overcast_day() -> void:
	var saved: float = Session.world_time
	var lab: DistrictLab = _make_lab()
	assert_eq(
		DistrictLab.MOOD, DistrictLab.Mood.OVERCAST,
		"стартовый пресет района — пасмурный день")
	assert_almost_eq(
		Session.world_time, DistrictLab.TIME_SEC_OVERCAST, 0.001,
		"стартовые часы — полдень мира")
	assert_gt(
		DayMath.sun_direction(DistrictLab.TIME_SEC_OVERCAST).y, 0.5,
		"солнце высоко: день, не вечер (у золотого часа 680 с — ~0.17)")
	assert_almost_eq(
		DayMath.warmth(DistrictLab.TIME_SEC_OVERCAST), 0.0, 0.001,
		"время суток не подмешивает тёплых краёв")
	# Купол — на стартовые часы (цикл дня), затем стартовый пресет поверх.
	lab._day_cycle._process(0.0)
	lab._apply_atmosphere()
	var dome: SkyDome = lab._dome
	assert_gt(
		dome.cumulus_coverage, 0.6,
		"небо серо-облачное: облачность поднята (у мира 0.38)")
	assert_lte(
		dome.sun_light_color.r - dome.sun_light_color.b, 0.02,
		"тёплый золотой оттенок света выключен (холодно-нейтральный)")
	var env: Environment = lab._world_env.environment
	assert_lt(
		env.fog_light_color.r - env.fog_light_color.b, 0.06,
		"дымка нейтральная сероватая (у золотой r−b = 0.34)")
	assert_almost_eq(
		lab._sun.light_energy, DistrictLab.OVERCAST_SUN_ENERGY, 0.001,
		"прямые лучи слабые")
	assert_lt(
		DistrictLab.OVERCAST_SUN_FOG_ENERGY, 0.5,
		"объёмные лучи едва заметны (у золотого часа 2.6)")
	assert_lt(
		DistrictLab.OVERCAST_VOLUME_ANISOTROPY, 0.3,
		"объёмный туман почти изотропный — без «лучей»")
	Session.world_time = saved


func test_trees_deterministic_and_clear() -> void:
	var a: Dictionary = DistrictNature.tree_layout(5)
	var b: Dictionary = DistrictNature.tree_layout(5)
	var c: Dictionary = DistrictNature.tree_layout(6)
	assert_eq(a.keys(), b.keys(), "те же виды")
	var total: int = 0
	var same_as_c: bool = a.keys() == c.keys()
	for key: String in a:
		var list: Array = a[key]
		total += list.size()
		assert_eq(list, b[key], "те же места (%s)" % key)
		if same_as_c and c.has(key) and c[key] != list:
			same_as_c = false
		for xform: Transform3D in list:
			var p := Vector2(xform.origin.x, xform.origin.z)
			var surface: int = L.surface_at(p)
			assert_true(
				surface == L.Surface.GRASS or surface == L.Surface.YARD,
				"дерево на траве или во дворе")
			if surface != L.Surface.GRASS and surface != L.Surface.YARD:
				return
	assert_gt(total, 300, "деревьев и кустов достаточно (%d)" % total)
	assert_false(same_as_c, "другой seed — другая раскладка")


func test_tree_keys_baked_in_island_art() -> void:
	# GLB генератора ez-tree лежат под .gdignore и в сборку не попадают —
	# каждое дерево района обязано быть в запечённом острове (иначе в
	# Windows-сборке деревьев нет: 10.11.2026 так и было).
	var art := load(DistrictNature.ART_PATH) as IslandArt
	assert_not_null(art, "island_art.res грузится")
	for key: String in DistrictNature.tree_layout(DistrictNature.SEED):
		assert_true(art.prop_groups.has(key), "дерево %s запечено в острове" % key)
		var meshes: Array[Mesh] = DistrictNature.tree_meshes(key)
		assert_eq(meshes.size(), 3, "три уровня у %s" % key)
		for m: Mesh in meshes:
			assert_gt(m.get_surface_count(), 0, "у меша %s есть поверхности" % key)


func test_houses_have_ivy() -> void:
	var house: Node3D = PanelHouse.build("T", 44.5, 12.0, 5, 3, -1, 3)
	add_child_autofree(house)
	var mesh: ArrayMesh = (house.get_node("Mesh") as MeshInstance3D).mesh
	var found: bool = false
	for i: int in mesh.get_surface_count():
		if mesh.surface_get_name(i) == "ivy":
			found = true
			assert_gt(mesh.surface_get_array_len(i), 600, "листьев плюща достаточно")
	assert_true(found, "на доме есть плющ")


func test_nature_lods_cover_all_trees() -> void:
	var nature := DistrictNature.new()
	add_child_autofree(nature)
	nature.setup(GraphicsQuality.Tier.HIGH)
	var total: int = 0
	var layout: Dictionary = DistrictNature.tree_layout(DistrictNature.SEED)
	for key: String in layout:
		total += (layout[key] as Array).size()
	var counts: Array[int] = nature.lod_counts()
	assert_eq(counts[0] + counts[1] + counts[2], total, "каждое дерево на одном уровне")
	assert_gt(counts[0], 0, "рядом со стартом есть ближние деревья")
	assert_gt(counts[2], 0, "дальние деревья — на дальнем уровне")
	nature.update_viewer(Vector3(80.0, 0.0, -80.0))
	var moved: Array[int] = nature.lod_counts()
	assert_eq(moved[0] + moved[1] + moved[2], total, "после сдвига сумма та же")


func test_grass_chunks_follow_surfaces() -> void:
	var tier: int = GraphicsQuality.Tier.HIGH
	# Луг за домами (чанк с клетками X 56..63, Z −96..−89).
	var meadow: Dictionary = DistrictNature.build_grass_chunk(tier, 7, -12)
	var again: Dictionary = DistrictNature.build_grass_chunk(tier, 7, -12)
	var tufts: Array = meadow["tuft"]["transforms"]
	assert_gt(tufts.size(), 40, "на лугу трава есть (%d)" % tufts.size())
	assert_eq(tufts, again["tuft"]["transforms"], "чанк детерминирован")
	assert_eq(
		(meadow["tuft"]["colors"] as PackedColorArray).size(), tufts.size(),
		"цвет на каждый пучок")
	# Середина озера (X −64..−57, Z 72..79) и середина северного дома.
	var lake: Dictionary = DistrictNature.build_grass_chunk(tier, -8, 9)
	assert_eq((lake["tuft"]["transforms"] as Array).size(), 0, "в озере травы нет")
	var house: Dictionary = DistrictNature.build_grass_chunk(tier, 1, -10)
	var in_house: int = 0
	for xform: Transform3D in house["tuft"]["transforms"]:
		if L.surface_at(Vector2(roundf(xform.origin.x), roundf(xform.origin.z))) \
				== L.Surface.BUILDING:
			in_house += 1
	assert_eq(in_house, 0, "под домом травы нет")
	# Дорога: редкая трава «сквозь трещины» — заметно реже луга.
	var road: Dictionary = DistrictNature.build_grass_chunk(tier, -6, 0)
	assert_lt(
		(road["tuft"]["transforms"] as Array).size(), tufts.size() / 3,
		"на асфальте трава редкая")


# --- Оптимизация района (PERF_DISTRICT, 780M): «Высокое» срезает
# --- тяжёлые полнокадровые эффекты, вид пасмурного дня несёт
# --- дистанционный туман; ULTRA — всё как было.

func test_district_high_cuts_heavy_effects() -> void:
	var lab: DistrictLab = _make_lab()
	lab._apply_graphics(GraphicsQuality.Tier.HIGH)
	var env: Environment = lab._world_env.environment
	assert_false(env.volumetric_fog_enabled, "HIGH: объёмного тумана нет (п. 1)")
	assert_false(env.sdfgi_enabled, "HIGH: SDFGI нет (п. 2)")
	assert_false(env.ssil_enabled, "HIGH: SSIL нет (п. 3)")
	assert_false(env.ssr_enabled, "HIGH: SSR нет (п. 3)")
	assert_true(env.ssao_enabled, "HIGH: SSAO остаётся — контактные тени")
	assert_true(env.glow_enabled, "HIGH: glow остаётся")
	# Вид пасмурного дня несёт дистанционный туман мира: включён, цвет
	# и плотность прежние (п. 1 — серая дымка жива без vfog).
	lab._apply_atmosphere()
	assert_true(env.fog_enabled, "дистанционный туман включён")
	assert_eq(env.fog_light_color, DistrictLab.OVERCAST_HAZE_COLOR,
		"цвет дымки прежний")
	assert_almost_eq(
		env.fog_density, DistrictLab.OVERCAST_HAZE_DENSITY, 0.0001,
		"плотность дымки прежняя")
	# Параметры объёмного тумана пишутся и при выключенном: галочка F3
	# включает его с пресетом пасмурности, а не с дефолтами сцены.
	assert_eq(env.volumetric_fog_albedo, DistrictLab.OVERCAST_VOLUME_ALBEDO,
		"пресет vfog готов даже когда он выключен")
	# Тени 70 → 50 м (п. 7): у солнца и луны.
	assert_almost_eq(
		lab._sun.directional_shadow_max_distance,
		DistrictLab.SHADOW_DISTANCE_HIGH, 0.1, "тени солнца 50 м")
	var moon: DirectionalLight3D = \
		lab._world_env.get_node_or_null("MoonLight") as DirectionalLight3D
	assert_almost_eq(
		moon.directional_shadow_max_distance,
		DistrictLab.SHADOW_DISTANCE_HIGH, 0.1, "тени луны 50 м")
	# Облака: марш по уровню (п. 4), не дефолтные 10 шагов на любом уровне.
	assert_almost_eq(
		float(lab._dome.sky_material.get_shader_parameter("cumulus_steps")),
		6.0, 0.1, "HIGH: марш облаков района 6 шагов")
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED


func test_district_ultra_keeps_heavy_effects() -> void:
	var lab: DistrictLab = _make_lab()
	lab._apply_graphics(GraphicsQuality.Tier.ULTRA)
	var env: Environment = lab._world_env.environment
	assert_true(env.volumetric_fog_enabled, "ULTRA: объёмный туман как было")
	assert_true(env.sdfgi_enabled, "ULTRA: SDFGI как было")
	assert_true(env.ssil_enabled, "ULTRA: SSIL как было")
	assert_true(env.ssr_enabled, "ULTRA: SSR как было")
	assert_almost_eq(
		lab._sun.directional_shadow_max_distance,
		GraphicsQuality.ULTRA_SHADOW_MAX_DISTANCE, 0.1,
		"ULTRA: тени уровня, район их не режет")
	assert_almost_eq(
		float(lab._dome.sky_material.get_shader_parameter("cumulus_steps")),
		float(GraphicsQuality.CLOUD_STEPS_ULTRA), 0.1,
		"ULTRA: марш облаков островной")
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED


func test_district_cloud_steps_by_tier() -> void:
	assert_eq(
		GraphicsQuality.district_cloud_steps(GraphicsQuality.Tier.SIMPLE), 4,
		"SIMPLE: 4 шага")
	assert_eq(
		GraphicsQuality.district_cloud_steps(GraphicsQuality.Tier.NORMAL), 6,
		"NORMAL: 6 шагов")
	assert_eq(
		GraphicsQuality.district_cloud_steps(GraphicsQuality.Tier.HIGH), 6,
		"HIGH: 6 шагов")
	assert_eq(
		GraphicsQuality.district_cloud_steps(GraphicsQuality.Tier.ULTRA),
		GraphicsQuality.CLOUD_STEPS_ULTRA, "ULTRA: 14, красиво как было")
	assert_lt(
		GraphicsQuality.district_cloud_steps(GraphicsQuality.Tier.HIGH),
		GraphicsQuality.CLOUD_STEPS_HIGH,
		"район на HIGH дешевле острова (10)")


func test_district_grass_cheaper_on_high() -> void:
	assert_almost_eq(
		DistrictNature.grass_radius(GraphicsQuality.Tier.HIGH), 40.0, 0.1,
		"HIGH: радиус поля 40 м (×0.73 островного)")
	assert_eq(
		DistrictNature.grass_radius(GraphicsQuality.Tier.ULTRA),
		GrassField.RADIUS_ULTRA, "ULTRA: островной радиус")
	assert_almost_eq(
		DistrictNature.grass_density(GraphicsQuality.Tier.HIGH), 4.0, 0.1,
		"HIGH: плотность 4 пучка/м² (×0.67 островной)")
	assert_eq(
		DistrictNature.grass_density(GraphicsQuality.Tier.ULTRA),
		GrassField.DENSITY_ULTRA, "ULTRA: островная плотность")
	# Тот же чанк на HIGH реже, чем на ULTRA (раскладка детерминирована).
	var hi: Dictionary = DistrictNature.build_grass_chunk(
		GraphicsQuality.Tier.HIGH, 7, -12)
	var ultra: Dictionary = DistrictNature.build_grass_chunk(
		GraphicsQuality.Tier.ULTRA, 7, -12)
	assert_gt(
		(ultra["tuft"]["transforms"] as Array).size(),
		(hi["tuft"]["transforms"] as Array).size(),
		"HIGH реже ULTRA на том же чанке")
	# Радиус района проходит в кромку шейдера и ключи чанков — граница
	# поля совпадает с кромкой (без «ступеньки» на краю).
	WorldMaterials.textured_headless = true
	var nodes: Dictionary = GrassField.make_nodes(
		GraphicsQuality.Tier.HIGH, DistrictNature.grass_radius(
			GraphicsQuality.Tier.HIGH))
	var material := (nodes["grass_tuft"] as MultiMeshInstance3D) \
		.material_override as ShaderMaterial
	assert_almost_eq(float(material.get_shader_parameter("fade_end")),
		DistrictNature.GRASS_RADIUS_HIGH, 0.1,
		"кромка шейдера на радиусе района")
	WorldMaterials.textured_headless = false
	var keys: Array[Vector2i] = GrassField.chunk_keys(
		GraphicsQuality.Tier.HIGH, Vector2.ZERO,
		DistrictNature.grass_radius(GraphicsQuality.Tier.HIGH))
	assert_lt(keys.size(),
		GrassField.chunk_keys(GraphicsQuality.Tier.HIGH, Vector2.ZERO).size(),
		"чанков меньше островного радиуса")
	for key: Vector2i in keys:
		var center_world := Vector2(
			(float(key.x) + 0.5) * GrassField.CHUNK,
			(float(key.y) + 0.5) * GrassField.CHUNK)
		assert_lt(center_world.length(),
			DistrictNature.GRASS_RADIUS_HIGH + GrassField.CHUNK * 0.71,
			"чанк внутри радиуса района")


func test_district_tree_lod_thresholds_by_tier() -> void:
	var cheap: Vector2 = DistrictNature.lod_limits(GraphicsQuality.Tier.HIGH)
	assert_almost_eq(cheap.x, 35.0, 0.1, "HIGH: LOD1 с 35 м (было 60)")
	assert_almost_eq(cheap.y, 80.0, 0.1, "HIGH: LOD2 с 80 м (было 130)")
	for tier: int in [
		GraphicsQuality.Tier.SIMPLE,
		GraphicsQuality.Tier.NORMAL,
	]:
		assert_eq(
			DistrictNature.lod_limits(tier), cheap,
			"ниже HIGH — те же ближние пороги, не дороже HIGH")
	var ultra: Vector2 = DistrictNature.lod_limits(GraphicsQuality.Tier.ULTRA)
	assert_almost_eq(ultra.x, 60.0, 0.1, "ULTRA: LOD1 прежний")
	assert_almost_eq(ultra.y, 130.0, 0.1, "ULTRA: LOD2 прежний")
	# Раскладка живёт на новых порогах: на HIGH деревья в 50 м от зрителя —
	# уже средний уровень (не ближний), на ULTRA — ближний.
	var nature := DistrictNature.new()
	add_child_autofree(nature)
	nature.setup(GraphicsQuality.Tier.HIGH)
	nature.update_viewer(Vector3(1000.0, 0.0, 1000.0))
	var far: Array[int] = nature.lod_counts()
	var layout: Dictionary = DistrictNature.tree_layout(DistrictNature.SEED)
	var total: int = 0
	for key: String in layout:
		total += (layout[key] as Array).size()
	assert_eq(far[0], 0, "в 1 км от леса ближнего уровня нет")
	assert_eq(far[1] + far[2], total, "все деревья на дальних уровнях")


func test_f3_panel_reflects_district_state() -> void:
	# Район стартово вырубает эффекты и не имеет IslandView: галочки
	# показывают фактическое состояние, авто-замер не «вернёт» вырубленное
	# включённым (шаг «выключить» ничего не меняет, возврат включил бы).
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	var env := Environment.new()
	panel.watch_graphics(env, null, GraphicsQuality.Tier.HIGH)
	assert_true(panel._boxes[&"sdfgi"].button_pressed,
		"после применения уровня галочки включены (остров)")
	for id: StringName in DebugPanel.VIEW_EFFECTS:
		panel.set_effect_enabled(id, false)
		assert_false(panel._boxes[id].button_pressed,
			"эффект вида %s без IslandView выключен" % id)
	panel.set_effect_enabled(&"sdfgi", false)
	assert_false(panel._boxes[&"sdfgi"].button_pressed,
		"вырубленный стартом эффект показан выключенным")
	# Вырубленный не входит в очередь авто-замера: база — уровень целиком.
	panel.start_auto_measure(0.001, 0.0)
	assert_false(panel._auto_queue.has(&"sdfgi"),
		"вырубленный эффект не в очереди авто-замера")
	assert_false(panel._auto_queue.has(&"grass"),
		"эффект вида не в очереди без IslandView")
	panel._auto_finish(true)
	# Ручная галочка включает эффект — уровень позволяет (замер цены).
	panel.set_effect_enabled(&"sdfgi", false)
	panel._boxes[&"sdfgi"].button_pressed = true
	assert_true(env.sdfgi_enabled,
		"ручная галочка включила SDFGI (HIGH позволяет)")
