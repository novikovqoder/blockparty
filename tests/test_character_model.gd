# Тесты модели персонажа (П5.8, часть B): модель собирается из запечённых
# сцен UBC+MCO — оба пола строятся, риг 65 костей, точки крепления в кистях
# и на спине; ступни на y = 0 (±0.02), макушка головы подогнана под
# коллизию игрока; у каждой части есть _LOD-копия с раскладкой по дистанции
# видимости; палитры внешности тонируют кожу/волосы/брови и перекрашивают
# радужку; цвет игрока красит только верхнюю одежду; номер персонажа вне
# диапазона даёт 0, цветовой индекс по хэшу id детерминирован и полон.
extends GutTest

const MODEL: PackedScene = preload("res://gameplay/player/character_model.tscn")
## Риг Universal Base Characters (Quaternius): 65 костей.
const BONES_UBC: int = 65


func _make(gender: int) -> CharacterModel:
	var model := MODEL.instantiate() as CharacterModel
	add_child_autofree(model)
	model.setup_appearance(Appearance.default_for(gender))
	return model


func test_both_genders_build() -> void:
	for gender: int in Appearance.GENDERS:
		var model := _make(gender)
		assert_eq(model.appearance.gender, gender,
			"пол %d: внешность зафиксирована" % gender)
		var skeleton := model.find_children("*", "Skeleton3D", true, false)
		assert_eq(skeleton.size(), 1, "пол %d: один скелет" % gender)
		assert_eq(
			(skeleton[0] as Skeleton3D).get_bone_count(), BONES_UBC,
			"пол %d: риг Universal Base Characters" % gender,
		)


func test_attachment_points_on_skeleton() -> void:
	# Задел на бой после MVP (раздел «Этап П5.8» SPEC): точки крепления
	# предметов в обеих кистях и на спине.
	for gender: int in Appearance.GENDERS:
		var model := _make(gender)
		for point: String in ["HandL", "HandR", "Back"]:
			var attach := model.attach_point(point)
			assert_not_null(attach, "пол %d: точка крепления %s" % [gender, point])
			assert_true(attach is BoneAttachment3D,
				"пол %d: %s — крепление к кости" % [gender, point])


func test_feet_at_zero_and_head_under_collision() -> void:
	# Точка опоры — у ступней, рост подогнан под коллизию
	# (HEAD_TOP_Y 1.65 у player.tscn).
	for gender: int in Appearance.GENDERS:
		var model := _make(gender)
		assert_between(
			model.lowest_point(), -0.02, 0.02,
			"пол %d: нижняя точка y=0" % gender,
		)
		assert_between(
			model.head_top_height(), 1.60, 1.70,
			"пол %d: макушка головы ~1.65 (факт %.3f)"
			% [gender, model.head_top_height()],
		)


func test_lod_twin_for_every_body_mesh() -> void:
	# Каждая часть (голова, одежда, причёска, капюшон) имеет _LOD-копию;
	# рядом играют полные меши, дальше — облегчённые.
	var model := _make(0)
	assert_gt(model.lod_pairs(), 5, "LOD-пар несколько")
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var is_lod := (mi.name as String).ends_with("_LOD")
		if is_lod:
			assert_true(
				mi.get_parent().has_node(
					String(mi.name).substr(0, String(mi.name).length() - 4)),
				"у %s есть полная версия" % mi.name,
			)
			assert_almost_eq(
				mi.visibility_range_begin, model.lod_distance, 0.01,
				"%s включается с дистанции LOD" % mi.name,
			)
			assert_eq(mi.visibility_range_end, 0.0,
				"%s виден до бесконечности" % mi.name)
		else:
			assert_true(
				mi.get_parent().has_node(String(mi.name) + "_LOD"),
				"у меша %s есть LOD-копия" % mi.name,
			)
			assert_almost_eq(
				mi.visibility_range_end, model.lod_distance, 0.01,
				"%s гаснет на дистанции LOD" % mi.name,
			)


func test_set_lod_distance_updates_ranges() -> void:
	# Уровни качества (П5.7 блок 7): «Простая» графика приближает
	# переключение.
	var model := _make(1)
	model.set_lod_distance(7.0)
	var checked := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if (mi.name as String).ends_with("_LOD"):
			assert_almost_eq(mi.visibility_range_begin, 7.0, 0.01,
				"LOD-копия переключилась на 7 м")
			checked += 1
	assert_gt(checked, 5, "проверено несколько LOD-копий")


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
	var model := MODEL.instantiate() as CharacterModel
	add_child_autofree(model)
	model.setup(42)
	assert_eq(model.character, 0, "setup с неверным номером строит первый")


func test_setup_palette_tints_only_top_cloth() -> void:
	# П5.8: цвет игрока красит заметную часть верхней одежды (материалы
	# cloth_* верха и рук, полная версия и LOD); кожа, волосы, глаза,
	# обувь и низ цвет игрока не получают.
	const PAL: Palette = preload("res://assets/palette.tres")
	var model := _make(0)
	var id := 7654321
	model.setup_palette(id)
	var expected: Color = PAL.player_colors[CharacterModel.palette_index(id)]
	var tinted := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var part := String(mi.name)
		for surface: int in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(surface) as StandardMaterial3D
			var override := mi.get_surface_override_material(surface)
			if base == null:
				continue
			if part.begins_with("top_") or part.begins_with("arms_"):
				if base.resource_name.begins_with("cloth_"):
					tinted += 1
					assert_true(override is StandardMaterial3D,
						"%s surface %d тонирован цветом игрока"
						% [mi.name, surface])
					assert_true(
						(override as StandardMaterial3D).albedo_color.is_equal_approx(expected),
						"%s цвет варианта игрока" % mi.name,
					)
					assert_null((override as StandardMaterial3D).albedo_texture,
						"%s текстура снята — цвет читается издалека" % mi.name)
			elif part.begins_with("legs_") or part.begins_with("feet_"):
				assert_null(override,
					"%s surface %d не тронут цветом игрока"
					% [mi.name, surface])
	assert_gt(tinted, 1, "верх и руки тонированы (полная версия и LOD)")


func test_appearance_tints_skin_and_hair() -> void:
	# Палитры внешности: кожа (включая открытые участки рук) и волосы/брови
	# тонируются цветами выбранных индексов.
	var ap := Appearance.default_for(Appearance.GENDER_MALE)
	ap.skin = 5
	ap.hair_color = 8
	ap.hair = 4
	var model := MODEL.instantiate() as CharacterModel
	add_child_autofree(model)
	model.setup_appearance(ap)
	var skin_expected := Appearance.SKIN_COLORS[5]
	var hair_expected := Appearance.HAIR_COLORS[8]
	var skin_found := 0
	var hair_found := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		for surface: int in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(surface) as StandardMaterial3D
			var override := mi.get_surface_override_material(surface)
			if base == null or override == null:
				continue
			if base.resource_name.begins_with("skin_"):
				skin_found += 1
				assert_true(
					(override as StandardMaterial3D).albedo_color.is_equal_approx(skin_expected),
					"%s: тон кожи палитры" % mi.name,
				)
			elif base.resource_name.begins_with("hair_"):
				hair_found += 1
				assert_true(
					(override as StandardMaterial3D).albedo_color.is_equal_approx(hair_expected),
					"%s: тон волос палитры" % mi.name,
				)
	assert_gt(skin_found, 1, "кожа головы и рук затонирована")
	assert_gt(hair_found, 1, "причёска и брови затонированы")


func test_eye_colors_recolor_iris_only() -> void:
	# Все 6 цветов глаз дают разные текстуры, радужка перекрашивается.
	var textures: Array[ImageTexture] = []
	for index: int in Appearance.EYE_COLORS.size():
		var texture := CharacterModel._eye_texture(index)
		assert_not_null(texture, "цвет %d: текстура построена" % index)
		textures.append(texture)
	for index: int in range(1, textures.size()):
		assert_ne(textures[index].get_rid(), textures[0].get_rid(),
			"цвет %d отличается от 0" % index)
	# Радужка меняется: хотя бы один пиксель отличается между цветами.
	var img0 := textures[0].get_image()
	var img1 := textures[3].get_image()
	var diff := 0
	for y: int in range(0, img0.get_height(), 8):
		for x: int in range(0, img0.get_width(), 8):
			var a := img0.get_pixel(x, y)
			var b := img1.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.1:
				diff += 1
	assert_gt(diff, 0, "радужка перекрашивается между цветами")


func test_validated_clamps_and_filters() -> void:
	# Диапазоны индексов clamp; неподходящая полу причёска (борода у
	# женского тела) заменяется ближайшей допустимой.
	var ap := Appearance.new()
	ap.gender = Appearance.GENDER_FEMALE
	ap.hair = 5  # борода — только мужская
	ap.top = 99
	ap.hat = -3
	ap.skin = 100
	var fixed := ap.validated()
	assert_eq(fixed.top, Appearance.OUTFITS.size() - 1, "верх зажат в диапазон")
	assert_eq(fixed.hat, 0, "убор зажат в диапазон")
	assert_eq(fixed.skin, Appearance.SKIN_COLORS.size() - 1, "кожа зажата")
	var female_hairs: Array = []
	female_hairs.append_array(Appearance.hair_variants(Appearance.GENDER_FEMALE))
	assert_has(female_hairs, fixed.hair, "причёска допустима для пола")
	assert_ne(fixed.hair, 5, "борода не досталась женскому телу")
	# Сеть (B3): байты туда-обратно без потерь.
	var from_net := Appearance.from_bytes(fixed.to_bytes())
	assert_true(from_net.same(fixed), "внешность переживает байты сети")
