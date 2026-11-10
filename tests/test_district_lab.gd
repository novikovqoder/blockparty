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
