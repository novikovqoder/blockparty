# Тесты П16 «Оптимизированное Высокое» (SPEC раздел П16): тени ламп
# Тесты П16 «Оптимизированное Высокое» (SPEC раздел П16): тени ламп
# (маска кастеров без травы/мелочи, тень максимум у 2 ближайших ламп,
# distance_fade ~12 м, атлас 2048, dual paraboloid), тени солнца/луны
# (трава/мелочь/детальная сетка без тени на HIGH, дальность 60–80 м),
# детальная сетка (радиус 12 м, сдвиг реже), трава-буст/мелочь (дальность
# меньше ULTRA, fade, alpha scissor без blend), occlusion culling
# (настройка + окклюдеры срубов/руин/валунов), SDFGI 3 каскада и туман
# 96×48 на HIGH, gi_mode излучателей (оранжевый пересвет), F3 (авто-замер,
# галочка окклюзии). Рецепт ULTRA не менялся — его держит test_gfx_ultra.
extends GutTest


# --- П16 п. 1: тени ламп ---

func test_lamp_shadow_constants_match_spec() -> void:
	assert_between(
		GraphicsQuality.HIGH_LAMP_FADE_SHADOW, 10.0, 14.0,
		"distance_fade тени ламп ~12 м")
	assert_eq(
		GraphicsQuality.HIGH_POSITIONAL_ATLAS_SIZE, 2048,
		"атлас точечных теней на HIGH — 2048")
	assert_between(
		GraphicsQuality.HIGH_LAMP_SHADOW_COUNT, 1, 2,
		"тень максимум у 1-2 ближайших ламп")
	assert_eq(
		GraphicsQuality.LAMP_CASTER_MASK, 1 << 19,
		"маска кастеров — слой 20")
	assert_eq(
		GraphicsQuality.LAMP_CASTER_LAYER, 20,
		"слой кастеров — 20 (свободен)")


func test_lamp_caster_mask_excludes_grass_and_clutter() -> void:
	# Маска кастеров лампы на HIGH не пересекается со слоями травы и
	# мелочи: их ноды строятся со слоями по умолчанию (без бита 20) —
	# значит, тень от них не ищется. Кастер (меш сруба/персонаж) бит имеет.
	var light := OmniLight3D.new()
	add_child_autofree(light)
	LampShadows.setup_light(light, true)
	assert_eq(
		light.shadow_caster_mask, GraphicsQuality.LAMP_CASTER_MASK,
		"на HIGH тень лампы видит только слой кастеров")
	assert_eq(
		light.omni_shadow_mode, OmniLight3D.SHADOW_DUAL_PARABOLOID,
		"на HIGH dual paraboloid (1 карта вместо 6)")
	assert_almost_eq(
		light.distance_fade_shadow,
		GraphicsQuality.HIGH_LAMP_FADE_SHADOW, 0.001,
		"тень лампы гаснет дальше ~12 м")
	# Трава/мелочь слоя не имеют (дефолт 1|2 не пересекается с битом 20).
	var grass := MultiMeshInstance3D.new()
	add_child_autofree(grass)
	assert_false(
		(grass.layers & GraphicsQuality.LAMP_CASTER_MASK) != 0,
		"трава/мелочь не в маске кастеров")
	# Пометка кастера ставит бит: постройки и персонажи.
	var house := Node3D.new()
	var mesh := MeshInstance3D.new()
	house.add_child(mesh)
	add_child_autofree(house)
	LampShadows.mark_caster(house)
	assert_true(
		(mesh.layers & GraphicsQuality.LAMP_CASTER_MASK) != 0,
		"меш постройки/персонажа — кастер тени ламп")
	# Уход с HIGH возвращает дефолт маски и куб.
	LampShadows.setup_light(light, false)
	assert_eq(
		light.shadow_caster_mask, 0xFFFFFFFF,
		"не-HIGH: маска кастеров — дефолт движка (ULTRA не тронут)")
	assert_eq(
		light.omni_shadow_mode, OmniLight3D.SHADOW_CUBE,
		"не-HIGH: тень лампы — куб, как на ULTRA")


func test_lamp_shadows_only_two_nearest() -> void:
	# П16 п. 1: в группе больше двух ламп тень включена максимум у
	# count ближайших к камере (спецификация: 1-2). Сруб с тремя лампами
	# + одиночная лампа: ближе всех — PorchLight и одиночная.
	var cabin := CabinHouse.new()
	add_child_autofree(cabin)
	var extra := OmniLight3D.new()
	extra.add_to_group(LampShadows.LIGHT_GROUP)
	extra.position = Vector3(3.0, 2.0, 0.0)
	add_child_autofree(extra)
	cabin.set_quality(GraphicsQuality.Tier.HIGH)
	var lights: Array[OmniLight3D] = [extra]
	for child: Node in cabin.get_children():
		var light := child as OmniLight3D
		if light != null:
			lights.append(light)
	assert_eq(lights.size(), 4, "4 лампы в группе (3 сруба + 1)")
	# До апдейта менеджера на HIGH тени выключены у всех (включит ближайшим).
	for light: OmniLight3D in lights:
		assert_false(
			light.shadow_enabled,
			"HIGH: до апдейта тень у %s выключена" % light.name)
	LampShadows.enabled = true
	LampShadows.update_nearest(
		self, Vector3(0.0, 2.0, -2.0), GraphicsQuality.HIGH_LAMP_SHADOW_COUNT)
	var shadowed: Array[String] = []
	for light: OmniLight3D in lights:
		if light.shadow_enabled:
			shadowed.append(light.name)
	assert_eq(
		shadowed.size(), GraphicsQuality.HIGH_LAMP_SHADOW_COUNT,
		"тень максимум у 2 ближайших ламп")
	# Тень ровно у двух ближайших по фактической дистанции — сравниваем
	# с сортировкой, а не с хардкодом имён.
	var by_dist: Array[OmniLight3D] = lights.duplicate()
	by_dist.sort_custom(func(a: OmniLight3D, b: OmniLight3D) -> bool:
		return a.global_position.distance_squared_to(Vector3(0.0, 2.0, -2.0)) \
			< b.global_position.distance_squared_to(Vector3(0.0, 2.0, -2.0)))
	var nearest: Array[String] = []
	for i: int in GraphicsQuality.HIGH_LAMP_SHADOW_COUNT:
		nearest.append(by_dist[i].name)
	for name: String in nearest:
		assert_true(
			shadowed.has(name),
			"тень у ближайшей лампы %s" % name)
	var porch: OmniLight3D = cabin.get_node("PorchLight")
	# Далёкая камера — тень у других (менеджер переключает, не копит).
	LampShadows.update_nearest(
		self, Vector3(0.0, 2.0, 12.0), GraphicsQuality.HIGH_LAMP_SHADOW_COUNT)
	assert_false(
		porch.shadow_enabled,
		"уехали от крыльца — тень у PorchLight выключилась")
	# Галочка F3 «Тени ламп» выключает всех и менеджер.
	cabin.set_lamp_shadows(false)
	LampShadows.update_nearest(
		self, Vector3(0.0, 2.0, -2.0), GraphicsQuality.HIGH_LAMP_SHADOW_COUNT)
	for light: OmniLight3D in lights:
		assert_false(
			light.shadow_enabled,
			"F3: тени ламп выключены у всех (%s)" % light.name)
	# Возврат галочки на ULTRA — тень всем сразу, менеджер не нужен.
	cabin.set_quality(GraphicsQuality.Tier.ULTRA)
	cabin.set_lamp_shadows(true)
	# extra — чужая лампа (вне сруба): на ULTRA менеджер не работает,
	# тень ей возвращает владелец (как сруб своим).
	extra.shadow_enabled = true
	for light: OmniLight3D in lights:
		assert_true(
			light.shadow_enabled,
			"ULTRA: тень у всех ламп (%s)" % light.name)
		assert_false(
			light.distance_fade_enabled,
			"ULTRA: distance_fade выключен (%s)" % light.name)


func test_cabin_meshes_marked_as_lamp_casters() -> void:
	# Меши сруба несут слой кастеров тени ламп (тень фонаря от стен).
	var cabin := CabinHouse.new()
	add_child_autofree(cabin)
	var marked := 0
	var model: Node = cabin.get_node("Cabin")
	for child: Node in model.get_children():
		var mi := child as MeshInstance3D
		if mi != null and (mi.layers & GraphicsQuality.LAMP_CASTER_MASK) != 0:
			marked += 1
	assert_gt(marked, 4, "у сруба помечено больше 4 мешей-кастеров")


# --- П16 п. 2: тени солнца/луны ---

func test_sun_shadow_distance_and_small_types() -> void:
	assert_between(
		GraphicsQuality.HIGH_SHADOW_MAX_DISTANCE, 60.0, 80.0,
		"дальность теней солнца/луны на HIGH — 60-80 м")
	assert_eq(
		GraphicsQuality.ULTRA_SHADOW_MAX_DISTANCE, 200.0,
		"ULTRA: дальность теней не тронута")
	# Трава и мелкие типы (<0.5 м) — без тени солнца на HIGH, с тенью на ULTRA.
	for type: String in [
		"rgrass", "rflower", "riris", "reed", "fern",
		"mrock", "pebble", "etree_bush",
	]:
		assert_true(
			PropMeshes.small_shadowless(StringName(type), GraphicsQuality.Tier.HIGH),
			"%s на HIGH без тени солнца" % type)
		assert_false(
			PropMeshes.small_shadowless(StringName(type), GraphicsQuality.Tier.ULTRA),
			"%s на ULTRA с тенью, как раньше" % type)
	# Деревья, валуны и постройки — с тенью на любом уровне.
	for type: String in [
		"etree_pine", "etree_oak", "etree_giant", "dead_log",
		"boulder", "rock_pillar", "ruin_block", "bench",
	]:
		assert_false(
			PropMeshes.small_shadowless(StringName(type), GraphicsQuality.Tier.HIGH),
			"%s остаётся с тенью на HIGH" % type)


func test_grass_boost_shadowless_on_high() -> void:
	# Трава-буст (gd_grass_*) на HIGH строится без тени солнца/луны,
	# на ULTRA — с тенью. Раскладка та же (тот же seed) — тени решает
	# уровень входа, а не пересборка.
	var nodes: Dictionary = GroundDetails._build_grass(
		_dummy_art(), GraphicsQuality.Tier.HIGH)
	for node: Variant in nodes["nodes"]:
		var mi := node as MultiMeshInstance3D
		if mi != null:
			assert_eq(
				mi.cast_shadow,
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"%s на HIGH без тени солнца" % mi.name)
	var ultra: Dictionary = GroundDetails._build_grass(
		_dummy_art(), GraphicsQuality.Tier.ULTRA)
	for node: Variant in ultra["nodes"]:
		var mi := node as MultiMeshInstance3D
		if mi != null:
			assert_eq(
				mi.cast_shadow,
				GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
				"%s на ULTRA с тенью" % mi.name)


## Минимальный art для _build_grass: нужна только карта высот (клетка
## проходима при 1.0 < h <= 15.0) — плоский «остров» на высоте 2 м.
func _dummy_art() -> IslandArt:
	var art := IslandArt.new()
	art.heights = PackedFloat32Array()
	art.heights.resize(IslandGen.POINTS * IslandGen.POINTS)
	art.heights.fill(2.0)
	return art


# --- П16 п. 4: трава-буст и мелочь — дальность и мягкое исчезновение ---

func test_grass_and_clutter_ranges_on_high() -> void:
	# П16 п. 4: на HIGH трава-буст (gd_grass_*) видна ближе базы (×0.85),
	# лёгкая мелочь наполнения — ×0.8, крупное наполнение и печёные
	# пучки — база; исчезновение мягкое (fade self). ULTRA — ×1.5 всем
	# и без fade (рецепт не менялся), NORMAL — база без fade.
	# View — вне дерева: _ready строит мир по art, тут проверяется только
	# таблица дальностей set_quality.
	var view := IslandView.new()
	var grass := MultiMeshInstance3D.new()
	var stones := MultiMeshInstance3D.new()
	var roots := MultiMeshInstance3D.new()
	var rgrass := MultiMeshInstance3D.new()
	view._base_ranges = {
		"gd_grass_0": 60.0, "gd_stones": 60.0, "gd_roots": 90.0,
		"rgrass": 60.0,
	}
	view._props_by_type = {
		"gd_grass_0": [grass] as Array[MultiMeshInstance3D],
		"gd_stones": [stones] as Array[MultiMeshInstance3D],
		"gd_roots": [roots] as Array[MultiMeshInstance3D],
		"rgrass": [rgrass] as Array[MultiMeshInstance3D],
	}
	view.set_quality(GraphicsQuality.Tier.HIGH)
	assert_almost_eq(
		grass.visibility_range_end, 60.0 * 0.85, 0.001,
		"HIGH: трава-буст видна ближе базы (×0.85)")
	assert_almost_eq(
		stones.visibility_range_end, 60.0 * 0.8, 0.001,
		"HIGH: лёгкая мелочь видна ближе базы (×0.8)")
	assert_almost_eq(
		roots.visibility_range_end, 90.0, 0.001,
		"HIGH: крупное наполнение — дальность базы (силуэт)")
	assert_almost_eq(
		rgrass.visibility_range_end, 60.0, 0.001,
		"HIGH: печёные пучки — дальность базы")
	assert_eq(
		grass.visibility_range_fade_mode,
		GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF,
		"HIGH: мягкое исчезновение у травы-буста")
	assert_eq(
		stones.visibility_range_fade_mode,
		GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF,
		"HIGH: мягкое исчезновение у лёгкой мелочи")
	assert_eq(
		roots.visibility_range_fade_mode,
		GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED,
		"HIGH: резкая граница у крупного наполнения")
	assert_eq(
		rgrass.visibility_range_fade_mode,
		GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED,
		"HIGH: резкая граница у печёных пучков")
	view.set_quality(GraphicsQuality.Tier.ULTRA)
	# ULTRA: дальность ×1.5 всем и без fade — рецепт не менялся.
	assert_almost_eq(
		grass.visibility_range_end, 90.0, 0.001,
		"ULTRA: трава-буст ×1.5 (60 м), как раньше")
	assert_almost_eq(
		stones.visibility_range_end, 90.0, 0.001,
		"ULTRA: мелочь ×1.5 (60 м), как раньше")
	assert_almost_eq(
		roots.visibility_range_end, 135.0, 0.001,
		"ULTRA: крупное наполнение ×1.5 (90 м), как раньше")
	assert_almost_eq(
		rgrass.visibility_range_end, 90.0, 0.001,
		"ULTRA: печёные пучки ×1.5 (60 м), как раньше")
	for node: MultiMeshInstance3D in [grass, stones, roots, rgrass]:
		assert_eq(
			node.visibility_range_fade_mode,
			GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED,
			"ULTRA: fade выключен")
	view.set_quality(GraphicsQuality.Tier.NORMAL)
	assert_almost_eq(
		grass.visibility_range_end, 60.0, 0.001,
		"NORMAL: база у травы-буста (fade тоже выключен)")
	assert_eq(
		grass.visibility_range_fade_mode,
		GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED,
		"NORMAL: fade выключен, как в базе")
	view.free()
	for node: MultiMeshInstance3D in [grass, stones, roots, rgrass]:
		node.free()


func test_clutter_type_classification() -> void:
	# Лёгкая мелочь («light» в KINDS) — гасится на HIGH мягко и раньше;
	# крупные виды наполнения и трава-буст классифицируются отдельно.
	for type: String in ["gd_stones", "gd_root", "gd_branch", "gd_debris", "gd_fern"]:
		assert_true(
			GroundDetails.light_clutter(StringName(type)),
			"%s — лёгкая мелочь" % type)
	for type: String in [
		"gd_boulder02", "gd_boulder03", "gd_stump01", "gd_stump02", "gd_roots",
	]:
		assert_false(
			GroundDetails.light_clutter(StringName(type)),
			"%s — крупное наполнение" % type)
	assert_false(
		GroundDetails.light_clutter(&"gd_grass_0"),
		"трава-буст гасится по своему множителю, не как мелочь")
	assert_false(
		GroundDetails.light_clutter(&"rgrass"),
		"печёные пучки — не мелочь наполнения")
	assert_almost_eq(
		IslandView.range_mult("gd_grass_0", GraphicsQuality.Tier.HIGH), 0.85,
		0.001, "множитель травы-буста на HIGH")
	assert_almost_eq(
		IslandView.range_mult("gd_stones", GraphicsQuality.Tier.HIGH), 0.8,
		0.001, "множитель лёгкой мелочи на HIGH")
	assert_almost_eq(
		IslandView.range_mult("gd_roots", GraphicsQuality.Tier.HIGH), 1.0,
		0.001, "крупное наполнение на HIGH — база")
	assert_almost_eq(
		IslandView.range_mult("rgrass", GraphicsQuality.Tier.HIGH), 1.0,
		0.001, "печёные пучки на HIGH — база")


func test_plant_materials_no_alpha_blend() -> void:
	# П16 п. 4: материалы травы/мелочи непрозрачные (нет blend_mix и записи
	# ALPHA — полупрозрачность ломает сортировцию и бьёт по fill rate);
	# листва деревьев — alpha scissor с depth_draw_opaque.
	for path: String in [
		"res://assets/shaders/grass_field.gdshader",
		"res://assets/shaders/lowpoly.gdshader",
	]:
		var source := FileAccess.get_file_as_string(path)
		assert_false(
			source.contains("blend_mix"), "%s — без alpha blend" % path)
		assert_false(
			source.contains("ALPHA"), "%s — не пишет альфу" % path)
	var canopy := FileAccess.get_file_as_string(
		"res://assets/shaders/canopy.gdshader")
	assert_true(
		canopy.contains("ALPHA_SCISSOR_THRESHOLD"),
		"листва — alpha scissor, не blend")
	assert_true(
		canopy.contains("depth_draw_opaque"),
		"листва пишет глубину в opaque-проходе")
	assert_false(
		canopy.contains("blend_mix"), "листва — без alpha blend")


# --- П16 п. 5: occlusion culling ---

func test_occlusion_culling_enabled() -> void:
	# П16 п. 5: отсечение невидимого включено в настройках проекта;
	# окклюдеры (срубы, руины, валуны) при этом реально работают.
	assert_true(
		ProjectSettings.get_setting(
			"rendering/occlusion_culling/use_occlusion_culling"),
		"occlusion culling включён в настройках проекта")


func test_cabin_has_body_occluder() -> void:
	# У каждого сруба — OccluderInstance3D с BoxOccluder3D по габариту
	# корпуса (ужат по горизонтали, чтобы не съесть окна и дверной проём).
	var cabin := CabinHouse.new()
	add_child_autofree(cabin)
	var occl := cabin.get_node("Cabin/BodyOccluder") as OccluderInstance3D
	assert_not_null(occl, "у сруба есть окклюдер корпуса")
	var box := occl.occluder as BoxOccluder3D
	assert_not_null(box, "окклюдер сруба — бокс")
	# Габарит дома ~12×13×4.5 м, ужатие только по горизонтали (0.35 м).
	assert_gt(box.size.x, 8.0, "бокс по X — почти во всю ширину дома")
	assert_gt(box.size.z, 8.0, "бокс по Z — почти во всю глубину дома")
	assert_gt(box.size.y, 3.0, "бокс по Y — от земли до конька")


func test_occluder_classification_and_size() -> void:
	# Кладка руин и скальные стены окклюдируются; деревья, постройки,
	# трава и мелочь — нет (для них отсечение дороже пользы).
	for type: String in [
		"ruin_tower", "ruin_arch", "ruin_column", "rock_wall",
	]:
		assert_true(
			IslandView.prop_occluder(type), "%s — с окклюдером" % type)
	for type: String in [
		"bench", "boat", "dead_log", "log_bridge", "rgrass", "etree_pine",
		"boulder", "pebble",
	]:
		assert_false(
			IslandView.prop_occluder(type), "%s — без окклюдера" % type)
	# Валуны и пни наполнения — с окклюдером при масштабе ≥1.0.
	assert_true(
		IslandView.detail_occluder("gd_boulder02", 1.0),
		"валун масштаба 1.0 — окклюдер")
	assert_true(
		IslandView.detail_occluder("gd_stump01", 1.2),
		"пень масштаба 1.2 — окклюдер")
	assert_false(
		IslandView.detail_occluder("gd_boulder02", 0.9),
		"валун масштаба 0.9 — без окклюдера")
	assert_false(
		IslandView.detail_occluder("gd_stones", 1.5),
		"россыпь камней — без окклюдера")
	assert_false(
		IslandView.detail_occluder("gd_fern", 1.5),
		"папоротник — без окклюдера")
	# Размер бокса — AABB меша × масштаб трансформа; мелкий не ставится.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.9, 3.3, 2.0)
	var size := IslandView.occluder_size(mesh, Transform3D(
		Basis().scaled(Vector3.ONE * 1.2), Vector3.ZERO))
	assert_almost_eq(size.x, 1.9 * 1.2, 0.001, "размер — AABB × масштаб")
	assert_almost_eq(size.y, 3.3 * 1.2, 0.001, "высота — AABB × масштаб")
	var tiny := BoxMesh.new()
	tiny.size = Vector3(0.3, 0.4, 0.3)
	assert_eq(
		IslandView.occluder_size(tiny, Transform3D.IDENTITY),
		Vector3.ZERO, "мелкий предмет не окклюдируется")


func test_occluders_built_from_groups() -> void:
	# Окклюдеры строятся из данных запечённого острова (кладка, стены)
	# и наполнения (валуны): по одному на каждый крупный предмет, мелкие
	# и немасштабные отфильтрованы.
	var view := IslandView.new()
	var art := IslandArt.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.9, 3.3, 2.0)
	var tower := PropGroup.new()
	tower.mesh = mesh
	tower.transforms = [Transform3D(Basis(), Vector3(5.0, 2.0, 5.0))]
	var wall := PropGroup.new()
	wall.mesh = mesh
	wall.transforms = [
		Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)),
		Transform3D(Basis().scaled(Vector3.ONE * 0.2), Vector3(1.0, 0.0, 1.0)),
	]
	# bench — не окклюдируется, несмотря на группу.
	var bench := PropGroup.new()
	bench.mesh = mesh
	bench.transforms = [Transform3D(Basis(), Vector3(2.0, 0.0, 2.0))]
	art.prop_groups = {
		"ruin_tower:0": tower, "rock_wall:4": wall, "bench:0": bench,
	}
	view.art = art
	view._detail_transforms = {
		"gd_boulder02": [
			Transform3D(Basis().scaled(Vector3.ONE * 1.1), Vector3(8.0, 0.0, 8.0)),
			Transform3D(Basis().scaled(Vector3.ONE * 0.7), Vector3(9.0, 0.0, 9.0)),
		],
		"gd_stones": [Transform3D(Basis(), Vector3(1.0, 0.0, 1.0))],
	}
	view._build_occluders()
	assert_not_null(view.get_node_or_null("Occluders"), "узел окклюдеров есть")
	assert_eq(
		view.get_node("Occluders").get_child_count(), 3,
		"окклюдеры: башня, большая стена и валун 1.1 "
		+ "(малая стена, скамейка, валун 0.7 и камни отфильтрованы)")
	view.free()


func test_ruin_occluder_count_from_art() -> void:
	# По реальному запечённому острову окклюдеров руин и стен много
	# (башни, арки, колонны, кладка и скальные стены) — все крупнее
	# порога. Регресс раскладки (меньше 60) заметен здесь.
	var art: IslandArt = load("res://gameplay/world/island_art.res")
	var count: int = 0
	for key: String in art.prop_groups:
		var type := String(key.split(":")[0])
		if not IslandView.prop_occluder(type):
			continue
		var group: PropGroup = art.prop_groups[key]
		for xf: Transform3D in group.transforms:
			if IslandView.occluder_size(group.mesh, xf) != Vector3.ZERO:
				count += 1
	assert_gt(count, 60, "руинных окклюдеров больше 60 (фактически ~79)")


func test_small_prop_visibility_ranges() -> void:
	# П16 п. 5: у мелких предметов раскладки появилась дальность видимости
	# (раньше рисуясь всегда); деревья, постройки и валуны — как прежде.
	assert_almost_eq(
		PropMeshes.visibility_range(&"bench"), 70.0, 0.001,
		"скамейки видны до 70 м")
	assert_almost_eq(
		PropMeshes.visibility_range(&"dead_log"), 90.0, 0.001,
		"валежник — до 90 м")
	assert_almost_eq(
		PropMeshes.visibility_range(&"log_bridge"), 110.0, 0.001,
		"мостки — до 110 м")
	assert_almost_eq(
		PropMeshes.visibility_range(&"boat"), 120.0, 0.001,
		"лодка — до 120 м")
	for type: StringName in [&"etree_pine", &"boulder", &"ruin_tower", &"cabin"]:
		assert_almost_eq(
			PropMeshes.visibility_range(type), 0.0, 0.001,
			"%s — всегда видим (силуэт)" % type)


# --- П16 п. 3: детальная сетка ---

const ISLAND_SCENE: PackedScene = preload("res://gameplay/world/island.tscn")


func test_detail_ring_radius_and_lazy_move() -> void:
	# Радиус кольца на HIGH — 12 м (ULTRA 24 не тронут), кольцо не
	# двигается при сдвиге зрителя меньше RING_MOVE_MIN_M (1.5 м).
	assert_almost_eq(TerrainDetail.RADIUS_HIGH, 12.0, 0.001,
		"радиус детальной сетки на HIGH — 12 м")
	assert_almost_eq(TerrainDetail.RADIUS_ULTRA, 24.0, 0.001,
		"радиус на ULTRA не тронут")
	assert_almost_eq(IslandView.RING_MOVE_MIN_M, 1.5, 0.001,
		"порог сдвига кольца — 1.5 м")
	# Кольцо в сцене строится по tier_from_settings() (тесты — HIGH).
	var island := ISLAND_SCENE.instantiate() as Island
	add_child_autofree(island)
	var view := island.get_node("IslandView") as IslandView
	var ring := view.get_node_or_null("DetailRing") as MeshInstance3D
	if ring == null:
		# Настройки тестового прогона не HIGH/ULTRA — кольца нет,
		# проверять нечего (константы выше уже проверены).
		return
	island.update_viewer(Vector3(10.0, 2.0, 10.0))
	var placed: Vector3 = ring.position
	# Сдвиг 0.5 м (<1.5) — кольцо на месте.
	island.update_viewer(Vector3(10.5, 2.0, 10.0))
	assert_eq(
		ring.position, placed,
		"кольцо не двигается при сдвиге 0.5 м")
	# Сдвиг 2 м (>=1.5) — кольцо переехало под нового зрителя.
	island.update_viewer(Vector3(12.0, 2.0, 10.0))
	var ring_pos := ring.position
	assert_almost_eq(ring_pos.x, 12.0, 0.26,
		"кольцо переехало при сдвиге 2 м (снап 0.25 м)")
	assert_almost_eq(ring_pos.z, 10.0, 0.26,
		"кольцо под зрителем по Z")


# --- П16 п. 6/7: SDFGI и объёмный туман на HIGH ---

func test_sdfgi_and_fog_cheaper_on_high() -> void:
	# SDFGI: на HIGH 3 каскада (было 4), ULTRA не тронут; свет
	# обновляется реже (16 кадров — максимум в 4.7.2).
	assert_eq(
		GraphicsQuality.HIGH_SDFGI_CASCADES, 3,
		"каскады SDFGI на HIGH — 3")
	assert_eq(
		GraphicsQuality.ULTRA_SDFGI_CASCADES, 5,
		"каскады SDFGI на ULTRA не тронуты")
	assert_eq(
		GraphicsQuality.HIGH_SDFGI_FRAMES_TO_UPDATE_LIGHT,
		RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_16_FRAMES,
		"обновление света SDFGI — максимально редкое (16 кадров)")
	# Объёмный туман: сетка 96×48 — дешевле ULTRA (256×128),
	# но точнее базы (64×64); базы и ULTRA не тронуты.
	assert_eq(GraphicsQuality.HIGH_VF_WIDTH, 96, "ширина сетки тумана — 96")
	assert_eq(GraphicsQuality.HIGH_VF_DEPTH, 48, "глубина сетки тумана — 48")
	assert_eq(GraphicsQuality.VF_WIDTH_BASE, 64, "базовая сетка не тронута")
	assert_eq(
		GraphicsQuality.ULTRA_VF_WIDTH * GraphicsQuality.ULTRA_VF_DEPTH,
		256 * 128, "сетка ULTRA не тронута")
	assert_lt(
		GraphicsQuality.HIGH_VF_WIDTH * GraphicsQuality.HIGH_VF_DEPTH,
		GraphicsQuality.ULTRA_VF_WIDTH * GraphicsQuality.ULTRA_VF_DEPTH,
		"туман HIGH дешевле ULTRA")
	assert_gt(
		GraphicsQuality.HIGH_VF_WIDTH * GraphicsQuality.HIGH_VF_DEPTH,
		GraphicsQuality.VF_WIDTH_BASE * GraphicsQuality.VF_DEPTH_BASE,
		"туман HIGH точнее базы")
	# Применённый HIGH реально ставит 3 каскада и сетку 96×48
	# (объёмный туман RenderingServer — глобальная настройка,
	# проверяем константой выше). Environment — RefCounted, не фрится.
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	var moon := DirectionalLight3D.new()
	var viewport := SubViewport.new()
	GraphicsQuality.apply(
		env, sun, GraphicsQuality.Tier.HIGH, viewport, moon)
	assert_eq(
		env.sdfgi_cascades, 3, "env на HIGH: каскады SDFGI — 3")
	sun.free()
	moon.free()
	viewport.free()


# --- П16 п. 8: оранжевый пересвет у скамеек и тонких досок Площади ---

## Меши фонарей сруба (материал «lamp», светится emission).
func _cabin_lamp_meshes(cabin: CabinHouse) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for model: Node in cabin.get_children():
		for child: Node in model.get_children():
			var mi := child as MeshInstance3D
			if mi != null and mi.material_override != null \
					and mi.material_override.resource_name.begins_with("lamp"):
				found.append(mi)
	return found


func test_lamp_emission_out_of_sdfgi_on_high() -> void:
	# Причина пересвета — канал излучения: emission фонарей срубов
	# писался в SDFGI, а SDFGI на HIGH без окклюзии «оборачивает» свет
	# вокруг тонких досок (лавки, навесы Площади). На HIGH фонарь
	# не участвует в SDFGI (DISABLED); на ULTRA — как было (STATIC),
	# «Ультру» не трогаем.
	var cabin := CabinHouse.new()
	add_child_autofree(cabin)
	var lamps := _cabin_lamp_meshes(cabin)
	assert_gt(lamps.size(), 0, "в срубе есть фонарь крыльца (материал lamp)")
	for mi: MeshInstance3D in lamps:
		assert_eq(
			mi.gi_mode, GeometryInstance3D.GI_MODE_STATIC,
			"до применения уровня — дефолт (STATIC)")
	cabin.set_quality(GraphicsQuality.Tier.HIGH)
	for mi: MeshInstance3D in lamps:
		assert_eq(
			mi.gi_mode, GeometryInstance3D.GI_MODE_DISABLED,
			"HIGH: фонарь не пишет излучение в SDFGI")
	cabin.set_quality(GraphicsQuality.Tier.ULTRA)
	for mi: MeshInstance3D in lamps:
		assert_eq(
			mi.gi_mode, GeometryInstance3D.GI_MODE_STATIC,
			"ULTRA: фонарь в SDFGI как прежде (не тронуто)")
	# Ниже HIGH SDFGI нет вовсе — вернём базу ради чистоты переключений.
	cabin.set_quality(GraphicsQuality.Tier.NORMAL)
	for mi: MeshInstance3D in lamps:
		assert_eq(
			mi.gi_mode, GeometryInstance3D.GI_MODE_STATIC,
			"NORMAL: база (SDFGI выключен, gi_mode не важен)")


# --- П16 п. 9/10: авто-замер F3 и галочка окклюзии ---

func test_f3_occlusion_checkbox() -> void:
	# П16 п. 5 включил окклюзию проектом, п. 9/10 — галочка в панели:
	# эффект уровня на любом тире (окклюзия дешёвая), снятая галочка
	# снимает её с viewport сцены, возврат включает.
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	assert_true(panel.EFFECTS.has(&"occl"), "галочка «Окклюзия» есть")
	panel.watch_graphics(Environment.new(), null, GraphicsQuality.Tier.HIGH)
	assert_true(
		panel._tier_effect_on(&"occl"),
		"HIGH: окклюзия — эффект уровня (включена проектом)")
	panel.watch_graphics(Environment.new(), null, GraphicsQuality.Tier.SIMPLE)
	assert_true(
		panel._tier_effect_on(&"occl"),
		"SIMPLE: окклюзия тоже эффект уровня (дёшева)")
	# Выключение/возврат дёргает RenderingServer без ошибок (гетчера
	# у настройки нет — проверяем вызов и код панели).
	var code := FileAccess.get_file_as_string("res://ui/debug_panel.gd")
	assert_true(
		code.contains("viewport_set_use_occlusion_culling"),
		"галочка occl переключает окклюзию viewport")
	panel._on_effect_toggled(false, &"occl")
	panel._on_effect_toggled(true, &"occl")


func test_f3_auto_measure_runs_and_restores() -> void:
	# П16 п. 9: авто-замер — базовый шаг + по шагу на каждый активный
	# эффект; эффекты возвращаются уровнем, отчёт содержит базу и все
	# эффекты, отсортированные по экономии. Прогон ускоренный (параметры
	# start_auto_measure), в панели — константы по SPEC (4 с).
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	add_child_autofree(sun)
	GraphicsQuality.apply(env, sun, GraphicsQuality.Tier.HIGH)
	panel.watch_graphics(env, null, GraphicsQuality.Tier.HIGH)
	var pressed_before: int = 0
	for id: StringName in panel.EFFECTS:
		if panel._boxes[id].button_pressed:
			pressed_before += 1
	panel.start_auto_measure(0.05, 0.01)
	assert_true(panel._auto_running, "авто-замер запущен")
	# Тикаем _process сами (панель может быть закрыта) с таймаутом:
	# шаг 0.06 с × (16 эффектов HIGH + база) — до 500 кадров.
	var frames := 0
	while panel._auto_running and frames < 500:
		panel._process(0.016)
		frames += 1
	assert_false(panel._auto_running, "авто-замер завершился (%d кадров)" % frames)
	# По строке на каждый активный эффект уровня (на HIGH включены все).
	assert_eq(
		panel._auto_rows.size(), panel._auto_queue.size(),
		"строк отчёта — по числу эффектов очереди")
	assert_eq(
		panel._auto_queue.size(), pressed_before,
		"в очереди все эффекты уровня (все галочки стояли)")
	# Все галочки остались включёнными (замер их не двигает).
	for id: StringName in panel.EFFECTS:
		assert_true(
			panel._boxes[id].button_pressed,
			"галочка %s после замера включена" % id)
	# Эффекты уровня возвращены (замер выключал и вернул).
	assert_true(env.sdfgi_enabled, "SDFGI возвращён уровнем")
	assert_true(env.ssr_enabled, "SSR возвращён уровнем")
	assert_true(env.volumetric_fog_enabled, "туман возвращён уровнем")
	# Отчёт: база, каждый эффект, сортировка по убыванию экономии.
	var report := panel.build_auto_report()
	assert_true(report.contains("Auto measure:"), "в отчёте есть строка базы")
	assert_true(report.contains(tr("BU_DBG_SDFGI")), "в отчёте есть SDFGI")
	assert_true(report.contains(tr("BU_DBG_VFOG")), "в отчёте есть туман")
	var saved: Array[float] = []
	for row: Dictionary in panel._auto_rows:
		saved.append(panel._auto_base_ms - float(row["ms"]))
	for i: int in range(1, saved.size()):
		assert_true(
			saved[i - 1] >= saved[i],
			"отчёт отсортирован по экономии по убыванию")
	# Отмена: прогон не начат заново, повторный запуск и отмена на первом
	# эффектном шаге возвращают состояние уровня.
	panel.start_auto_measure(0.5, 0.01)
	assert_true(panel._auto_running, "второй прогон запущен")
	for i: int in 60:
		panel._process(0.016)  # база 0.51 с — уходим в первый эффект
	assert_true(panel._auto_index >= 0, "идёт эффектный шаг")
	panel._on_auto_button()  # повторный щелчок — отмена
	assert_false(panel._auto_running, "отмена остановила прогон")
	assert_true(env.sdfgi_enabled, "после отмены эффект уровня возвращён")
	assert_eq(
		panel._auto_button.text, tr("BU_DBG_AUTOM"),
		"после отмены кнопка в исходный текст")
