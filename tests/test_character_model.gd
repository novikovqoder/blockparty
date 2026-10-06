# Тесты модели персонажа (раздел 16 SPEC, шаг 2 замены персонажей):
# все три модели KayKit строятся, ступни на y = 0 (±0.02), макушка головы
# подогнана под коллизию игрока, у каждого меша — контурный близнец
# (обратная оболочка, непрозрачный чёрный), у каждого персонажа — свой
# фирменный убор; цветовой индекс по хэшу id детерминирован, все 6 цветов
# достижимы, номер вне диапазона даёт 0.
extends GutTest

const MODEL: PackedScene = preload("res://gameplay/player/character_model.tscn")
const OUTLINE_SHADER_PATH: String = "res://assets/shaders/outline.gdshader"


func _make(character: int) -> CharacterModel:
	var model := MODEL.instantiate() as CharacterModel
	add_child_autofree(model)
	model.setup(character)
	return model


func test_all_three_characters_build() -> void:
	for character: int in CharacterModel.count():
		var model := _make(character)
		assert_eq(model.character, character, "персонаж %d: номер зафиксирован" % character)
		var skeleton := model.find_children("*", "Skeleton3D", true, false)
		assert_eq(skeleton.size(), 1, "персонаж %d: один скелет" % character)
		assert_eq(
			(skeleton[0] as Skeleton3D).get_bone_count(), 23,
			"персонаж %d: риг Rig_Medium" % character,
		)


func test_feet_at_zero_and_head_under_collision() -> void:
	# Раздел 16: точка опоры — у ступней, рост подогнан под коллизию
	# (HEAD_TOP_Y 1.65 у player.tscn и remote_player.gd).
	for character: int in CharacterModel.count():
		var model := _make(character)
		assert_between(
			model.lowest_point(), -0.02, 0.02,
			"персонаж %d: нижняя точка y=0" % character,
		)
		assert_between(
			model.head_top_height(), 1.60, 1.70,
			"персонаж %d: макушка головы ~1.65 (факт %.3f)"
			% [character, model.head_top_height()],
		)


func test_outline_twin_for_every_mesh() -> void:
	for character: int in CharacterModel.count():
		var model := _make(character)
		var meshes := 0
		var twins := 0
		for node in model.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if (mi.name as String).ends_with("Outline"):
				twins += 1
				assert_not_null(mi.material_override, "контур с материалом")
				assert_true(
					mi.material_override is ShaderMaterial,
					"контур — шейдер обратной оболочки",
				)
				continue
			meshes += 1
			assert_not_null(
				mi.get_parent().get_node_or_null(String(mi.name) + "Outline"),
				"у меша %s есть контурный близнец" % mi.name,
			)
		assert_gt(meshes, 5, "у модели есть меши (не один меш)")
		assert_eq(twins, meshes, "персонаж %d: близнец у каждого меша" % character)


func test_outline_shader_is_opaque_black_shell() -> void:
	# «Мультяшный чёрный контур без прозрачности»: шейдер рисует задние
	# грани (cull_front), чистый чёрный и не трогает альфу.
	var text: String = FileAccess.get_file_as_string(OUTLINE_SHADER_PATH)
	assert_false(text.is_empty(), "шейдер контура читается")
	assert_true(text.contains("cull_front"), "задние грани (обратная оболочка)")
	assert_true(text.contains("ALBEDO = vec3(0.0)"), "чистый чёрный")
	assert_false(text.contains("ALPHA"), "без прозрачности")


func test_each_character_has_own_hat() -> void:
	var kinds: Array[int] = []
	for character: int in CharacterModel.count():
		var model := _make(character)
		var hat := model.hat()
		assert_not_null(hat, "персонаж %d: убор закреплён" % character)
		var kind: int = hat.get_meta("kind")
		assert_false(kinds.has(kind), "убор не повторяется между персонажами")
		kinds.append(kind)
		var parts := hat.find_children("*", "MeshInstance3D", true, false)
		assert_gt(parts.size(), 0, "персонаж %d: в уборe есть меши" % character)


func test_palette_index_deterministic_and_complete() -> void:
	# Один id — один цвет (Steam id / peer id, включая отрицательные),
	# все 6 вариантов достижимы (раздел 16, «Цвета»).
	var seen: Array[int] = []
	for id: int in [-7654321, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 11, 7654321]:
		var index := CharacterModel.palette_index(id)
		assert_eq(
			CharacterModel.palette_index(id), index,
			"id %d: цвет не меняется между вызовами" % id,
		)
		assert_between(index, 0, 5, "id %d: индекс в диапазоне" % id)
		seen.push_back(index)
	for expected: int in 6:
		assert_has(seen, expected, "цвет %d достижим каким-то id" % expected)
	# Отрицательный peer id не даёт отрицательного индекса.
	assert_eq(CharacterModel.palette_index(-13), 13 % 6, "absi для peer id")


func test_character_out_of_range_gives_first() -> void:
	assert_eq(CharacterModel.valid_index(-1), 0, "отрицательный → 0")
	assert_eq(CharacterModel.valid_index(99), 0, "за диапазоном → 0")
	assert_eq(CharacterModel.valid_index(1), 1, "валидный проходит как есть")
	var model := _make(42)
	assert_eq(model.character, 0, "setup с неверным номером строит первого")
