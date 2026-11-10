# Тесты района-заготовки (постапокалипсис, шаг 1): сцена из серых коробок
# по согласованной карте (--district) — флаг, состав сцены, открытый подъезд,
# детерминированные деревья, старт на суше и внутри границ.
extends GutTest

const DevScript: GDScript = preload("res://autoload/dev.gd")


func _make_lab() -> DistrictLab:
	var scene: PackedScene = load(DevScript.DISTRICT_SCENE)
	var lab := scene.instantiate() as DistrictLab
	# Без игрока: тест проверяет раскладку, а не модель героя.
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
		"Ground", "Surfaces", "Lake", "Houses", "Boxes", "Garages", "Cars",
		"Borders", "Trees", "Tower", "Sun", "Environment",
	]:
		assert_not_null(lab.get_node_or_null(node_name), "узел %s" % node_name)
	assert_eq(lab.get_node("Houses").get_child_count(), 4, "четыре пятиэтажки")
	assert_eq(
		lab.get_node("Garages").get_child_count(), lab.GARAGE_COUNT, "гаражи")
	assert_eq(lab.get_node("Cars").get_child_count(), lab.CARS.size(), "машины")
	for box_name: String in ["Shop", "Bus", "Pier", "Transformer", "RuinA"]:
		assert_not_null(
			lab.get_node_or_null("Boxes/%s" % box_name), "постройка %s" % box_name)


func test_district_single_open_entrance_in_north_house() -> void:
	var lab: DistrictLab = _make_lab()
	var open_count: int = 0
	var total: int = 0
	for house: Node in lab.get_node("Houses").get_children():
		for child: Node in house.get_children():
			if child.is_in_group(&"district_entrance"):
				total += 1
				if child.name == "EntranceOpen":
					open_count += 1
					assert_eq(house.name, &"HouseNorth", "открыт северный дом")
	assert_eq(open_count, 1, "открытый подъезд один")
	assert_eq(total, 13, "подъездов всего 4 + 3 + 3 + 3")


func test_district_start_on_land_inside_borders() -> void:
	var lab: DistrictLab = _make_lab()
	var start := Vector2(lab.START.x, lab.START.z)
	assert_false(
		Geometry2D.is_point_in_polygon(start, PackedVector2Array(lab.LAKE)),
		"старт не в озере")
	assert_true(
		absf(start.x) < lab.HALF and absf(start.y) < lab.HALF,
		"старт внутри участка")


func test_district_trees_deterministic_and_clear_of_houses() -> void:
	var a: DistrictLab = _make_lab()
	var b: DistrictLab = _make_lab()
	var mm_a: MultiMesh = (a.get_node("Trees/Trunks") as MultiMeshInstance3D).multimesh
	var mm_b: MultiMesh = (b.get_node("Trees/Trunks") as MultiMeshInstance3D).multimesh
	assert_gt(mm_a.instance_count, 100, "деревьев достаточно")
	assert_eq(mm_a.instance_count, mm_b.instance_count, "раскладка детерминирована")
	for i: int in mm_a.instance_count:
		var p: Vector3 = mm_a.get_instance_transform(i).origin
		assert_eq(p, mm_b.get_instance_transform(i).origin, "те же места")
		for house: Array in lab_houses(a):
			var inside: bool = (
				absf(p.x - float(house[1])) < float(house[3]) * 0.5
				and absf(p.z - float(house[2])) < float(house[4]) * 0.5)
			assert_false(inside, "дерево не внутри дома")
			if inside:
				return


func lab_houses(lab: DistrictLab) -> Array:
	return lab.HOUSES
