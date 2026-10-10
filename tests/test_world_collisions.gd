# Тесты физических коллизий мира (vfx-fix, баг 2): каждый тип предмета
# раскладки либо имеет коллизию (PropMeshes.collision_size), либо числится
# в IslandGen.PASS_THROUGH_TYPES; интерактивные узлы, которые не проходят
# через IslandGen (костёр, мята, вехи, квестовые маяки, сундук, камни
# духа), имеют StaticBody3D на слое 1 — его чувствует маска игрока.
extends GutTest

const EPS: float = 0.01


func test_every_prop_type_is_solid_or_excepted() -> void:
	# Аудит раскладки: собираем типы из данных острова и сверяем каждый
	# с рецептом коллизии или списком исключений.
	var data: Dictionary = IslandGen.generate()
	var types: Dictionary = {}
	for prop: Dictionary in data["props"]:
		types[String(prop["type"])] = true
	assert_gt(types.size(), 10, "в раскладке есть предметы")
	for type: String in types:
		var solid: bool = PropMeshes.collision_size(StringName(type), Vector3.ONE) \
			!= Vector3.ZERO
		var excepted: bool = IslandGen.PASS_THROUGH_TYPES.has(type)
		assert_true(
			solid != excepted,
			"тип %s: либо коллизия, либо в PASS_THROUGH_TYPES (не оба и не никак)"
			% type,
		)


func test_solid_types_have_collision_shape() -> void:
	# Всё, что заявлено твёрдым, даёт ненулевой бокс коллизии.
	for type: String in IslandGen.SOLID_TYPES:
		var size: Vector3 = PropMeshes.collision_size(
			StringName(type), Vector3.ONE
		)
		assert_true(
			size.x > EPS and size.y > EPS and size.z > EPS,
			"твёрдый тип %s даёт положительный бокс коллизии" % type,
		)


func test_pass_through_and_solid_do_not_overlap() -> void:
	assert_false(_overlap(), "PASS_THROUGH и SOLID не пересекаются")


func _overlap() -> bool:
	for type: String in IslandGen.PASS_THROUGH_TYPES:
		if IslandGen.SOLID_TYPES.has(type):
			return true
	return false


func test_pass_through_types_have_no_shape() -> void:
	for type: String in IslandGen.PASS_THROUGH_TYPES:
		assert_eq(
			PropMeshes.collision_size(StringName(type), Vector3.ONE),
			Vector3.ZERO,
			"исключение %s действительно без коллизии" % type,
		)


func test_campfire_blocks_player() -> void:
	# Костёр — не призрак: цилиндр по габариту очага на слое 1.
	var fire := Campfire.new()
	add_child_autofree(fire)
	_assert_solid_body(fire, "костёр", Campfire.HEARTH_RADIUS)


func test_mint_patch_solid_while_visible() -> void:
	# Мята: коллизия есть, собранный пучок её выключает.
	var mint := MintPatch.new()
	add_child_autofree(mint)
	_assert_solid_body(mint, "мята", MintPatch.MINT_RADIUS)
	mint._on_quest_state({
		Protocol.QUEST_THYME: {
			"stage": QuestAuthority.ACTIVE, "steps": [0, 0, 0, 0, 0],
		},
	})
	assert_true(mint.visible, "активное задание: мята видна")
	mint._on_quest_state({
		Protocol.QUEST_THYME: {
			"stage": QuestAuthority.ACTIVE, "steps": [1, 0, 0, 0, 0],
		},
	})
	assert_false(mint.visible, "собранный пучок скрыт")


func test_trail_flag_pole_is_solid() -> void:
	var flag := TrailFlag.new()
	add_child_autofree(flag)
	_assert_solid_body(flag, "веха", TrailFlag.POLE_RADIUS)


func test_quest_beacon_pole_is_solid() -> void:
	var beacon := QuestBeacon.new()
	add_child_autofree(beacon)
	_assert_solid_body(beacon, "квестовый маяк", QuestBeacon.POLE_RADIUS)


func test_ruin_chest_is_solid() -> void:
	var chest := RuinChest.new()
	add_child_autofree(chest)
	_assert_solid_body(chest, "сундук", RuinChest.BODY_SIZE.x * 0.5)


func test_respawn_stone_is_solid() -> void:
	var stone := RespawnStone.new()
	add_child_autofree(stone)
	_assert_solid_body(stone, "камень духа", RespawnStone.SOLID_SIZE.x * 0.5)


## У узла есть StaticBody3D на слое 1 с формой радиуса не меньше expected.
func _assert_solid_body(node: Node3D, what: String, expected: float) -> void:
	var bodies: Array = node.find_children("*", "StaticBody3D", false, false)
	assert_eq(bodies.size(), 1, "у %s один StaticBody3D" % what)
	var body := bodies[0] as StaticBody3D
	assert_true(body.get_collision_layer_value(1), "%s: тело на слое 1" % what)
	var shape := body.get_child(0) as CollisionShape3D
	assert_not_null(shape.shape, "%s: форма задана" % what)
	var radius: float = 0.0
	if shape.shape is CapsuleShape3D:
		radius = (shape.shape as CapsuleShape3D).radius
	elif shape.shape is CylinderShape3D:
		radius = (shape.shape as CylinderShape3D).radius
	elif shape.shape is BoxShape3D:
		radius = (shape.shape as BoxShape3D).size.x * 0.5
	assert_almost_eq(radius, expected, EPS, "%s: радиус формы по габариту" % what)
	# Форма стоит «ногами» в origin узла — как модели (высота положительна).
	assert_gt(
		(shape.transform.origin.y + _shape_height(shape)) * 0.5, 0.0,
		"%s: форма над землёй" % what,
	)


func _shape_height(shape: CollisionShape3D) -> float:
	if shape.shape is CapsuleShape3D:
		return (shape.shape as CapsuleShape3D).height
	if shape.shape is CylinderShape3D:
		return (shape.shape as CylinderShape3D).height
	if shape.shape is BoxShape3D:
		return (shape.shape as BoxShape3D).size.y
	return 0.0
