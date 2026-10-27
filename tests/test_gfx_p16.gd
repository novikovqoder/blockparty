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
