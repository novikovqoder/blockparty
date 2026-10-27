# Тесты П13 «Оптимизированное Высокое»: рецепт HIGH по константам SPEC
# (лёгкий SDFGI, SSIL Low, SSR 32 шага, без MSAA — SMAA, атласы 4096,
# туман 128×64, трава ×0.85, параллакс 10–15 м, лампы с distance_fade),
# «Разрешение 3D» (BILINEAR/FSR, первый запуск на встройке), растворение
# воды 46–66 м только на SIMPLE (баг-фикс п. 5) и панель замера F3
# (галочки выключают/возвращают эффекты, отчёт). Сервер — без рендера:
# глобальные вызовы RenderingServer геттеров не имеют, поэтому проверяются
# константы рецепта и свойства env/viewport; сами вызовы выполняются
# без ошибок при прогоне apply().
extends GutTest

const ART: IslandArt = preload("res://gameplay/world/island_art.res")
const CSV: String = "res://i18n/strings_bu.csv"


# --- П13 1: рецепт HIGH ---

func test_high_recipe_constants_match_spec() -> void:
	# П13 1.1: лёгкий SDFGI — 4 каскада (3–4), 8 лучей, сходимость 30
	# кадров, обновление света 16 кадров, без окклюзии, GI половинный.
	assert_between(
		GraphicsQuality.HIGH_SDFGI_CASCADES, 3, 4,
		"каскады SDFGI — 3–4 (П13 1.1)")
	assert_eq(
		GraphicsQuality.HIGH_SDFGI_RAY_COUNT,
		RenderingServer.ENV_SDFGI_RAY_COUNT_8,
		"лучей SDFGI — 8")
	assert_eq(
		GraphicsQuality.HIGH_SDFGI_FRAMES_TO_CONVERGE,
		RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES,
		"сходимость SDFGI — 30 кадров")
	assert_eq(
		GraphicsQuality.HIGH_SDFGI_FRAMES_TO_UPDATE_LIGHT,
		RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_16_FRAMES,
		"обновление света SDFGI — 16 кадров")
	# П13 1.2: SSIL — качество Low (половинное ставится в apply).
	assert_eq(
		GraphicsQuality.HIGH_SSIL_QUALITY,
		RenderingServer.ENV_SSIL_QUALITY_LOW,
		"качество SSIL — Low")
	# П13 1.3: SSR включён, шагов 24–32.
	assert_between(
		GraphicsQuality.HIGH_SSR_MAX_STEPS, 24, 32,
		"шагов SSR — 24–32")
	# П13 1.6 (П16 п. 1: атлас точечных теней 2048): тени — направленный
	# атлас 4096, Soft Medium, полутень чуть уже ULTRA, дальность ~120 м.
	assert_eq(
		GraphicsQuality.HIGH_SHADOW_ATLAS_SIZE, 4096,
		"атлас направленных теней — 4096")
	assert_eq(
		GraphicsQuality.HIGH_POSITIONAL_ATLAS_SIZE, 2048,
		"атлас точечных теней — 2048 (П16)")
	assert_eq(
		GraphicsQuality.HIGH_SOFT_SHADOW_QUALITY,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
		"мягкий фильтр теней — Soft Medium")
	assert_almost_eq(
		GraphicsQuality.HIGH_LIGHT_ANGULAR_DISTANCE, 0.4, 0.001,
		"угловое расхождение светила — 0.4°")
	assert_almost_eq(
		GraphicsQuality.HIGH_SHADOW_MAX_DISTANCE, 120.0, 0.001,
		"дальность теней — ~120 м")
	assert_lt(
		GraphicsQuality.HIGH_LIGHT_ANGULAR_DISTANCE,
		GraphicsQuality.ULTRA_LIGHT_ANGULAR_DISTANCE,
		"полутень HIGH чуть уже ULTRA")
	# П13 1.7: объёмный туман — сетка 128×64, между базой и ULTRA.
	assert_eq(GraphicsQuality.HIGH_VF_WIDTH, 128, "ширина сетки тумана — 128")
	assert_eq(GraphicsQuality.HIGH_VF_DEPTH, 64, "глубина сетки тумана — 64")
	assert_lt(
		GraphicsQuality.HIGH_VF_WIDTH * GraphicsQuality.HIGH_VF_DEPTH,
		GraphicsQuality.ULTRA_VF_WIDTH * GraphicsQuality.ULTRA_VF_DEPTH,
		"туман HIGH дешевле ULTRA")
	# П13 1.9: трава-буст спадает ближе ULTRA, параллакс до ~15 м.
	assert_almost_eq(
		GraphicsQuality.HIGH_GRASS_FADE_MULT, 0.85, 0.001,
		"спад травы-буста — ×0.85")
	assert_almost_eq(
		GraphicsQuality.HIGH_PARALLAX_NEAR, 10.0, 0.001,
		"параллакс начинается с 10 м")
	assert_almost_eq(
		GraphicsQuality.HIGH_PARALLAX_FAR, 15.0, 0.001,
		"параллакс до ~15 м")
	assert_lt(
		GraphicsQuality.HIGH_PARALLAX_FAR, GraphicsQuality.PARALLAX_FAR_BASE,
		"параллакс HIGH ближе базы ULTRA")
	# П13 1.6 (П16 п. 1): тени ламп срубов гаснут дальше ~12 м.
	assert_almost_eq(
		GraphicsQuality.HIGH_LAMP_FADE_SHADOW, 12.0, 0.001,
		"тени ламп гаснут с ~12 м")


func test_high_recipe_applied_to_env_and_viewport() -> void:
	# П13 1: применённый HIGH — эффекты включены, числа — константы
	# рецепта; MSAA выключен, SMAA включён (1.5), TAA нет.
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	var moon := DirectionalLight3D.new()
	var viewport := SubViewport.new()
	GraphicsQuality.apply(
		env, sun, GraphicsQuality.Tier.HIGH, viewport, moon)
	assert_true(env.sdfgi_enabled, "HIGH: SDFGI включён (лёгкий)")
	assert_eq(
		env.sdfgi_cascades, GraphicsQuality.HIGH_SDFGI_CASCADES,
		"HIGH: каскады SDFGI — 4")
	assert_false(
		env.sdfgi_use_occlusion, "HIGH: без окклюзии SDFGI (самый дорогой проход)")
	assert_true(
		env.sdfgi_read_sky_light, "HIGH: SDFGI читает свет неба")
	assert_almost_eq(
		env.sdfgi_energy, GraphicsQuality.ULTRA_SDFGI_ENERGY, 0.001,
		"HIGH: энергия SDFGI — дневная константа (ночь ведёт DayCycle)")
	assert_true(env.ssil_enabled, "HIGH: SSIL включён")
	assert_almost_eq(
		env.ssil_intensity, GraphicsQuality.HIGH_SSIL_INTENSITY, 0.001,
		"HIGH: интенсивность SSIL")
	assert_almost_eq(
		env.ssil_radius, GraphicsQuality.HIGH_SSIL_RADIUS, 0.001,
		"HIGH: радиус SSIL — 3")
	assert_true(env.ssr_enabled, "HIGH: SSR включён")
	assert_eq(
		env.ssr_max_steps, GraphicsQuality.HIGH_SSR_MAX_STEPS,
		"HIGH: шаги SSR — 32")
	assert_almost_eq(
		env.ssr_fade_in, GraphicsQuality.HIGH_SSR_FADE_IN, 0.001,
		"HIGH: fade_in SSR")
	assert_almost_eq(
		env.ssr_fade_out, GraphicsQuality.HIGH_SSR_FADE_OUT, 0.001,
		"HIGH: fade_out SSR")
	assert_true(env.ssao_enabled, "HIGH: SSAO включён (Medium, половинное)")
	assert_true(env.glow_enabled, "HIGH: glow включён")
	assert_true(env.volumetric_fog_enabled, "HIGH: объёмный туман включён")
	assert_true(sun.shadow_enabled, "HIGH: тени включены")
	assert_almost_eq(
		sun.directional_shadow_max_distance,
		GraphicsQuality.HIGH_SHADOW_MAX_DISTANCE, 0.001,
		"HIGH: дальность теней — 120 м")
	assert_almost_eq(
		sun.directional_shadow_fade_start,
		GraphicsQuality.HIGH_SHADOW_FADE_START, 0.001,
		"HIGH: fade_start сплитов — 0.85")
	assert_true(
		sun.directional_shadow_blend_splits,
		"HIGH: сплиты смешиваются")
	assert_true(moon.shadow_enabled, "HIGH: тени луны включены")
	assert_almost_eq(
		moon.directional_shadow_max_distance,
		GraphicsQuality.HIGH_SHADOW_MAX_DISTANCE, 0.001,
		"HIGH: дальность теней луны — как у солнца")
	assert_eq(
		viewport.msaa_3d, Viewport.MSAA_DISABLED,
		"HIGH: MSAA выключен (общая память встройки)")
	assert_eq(
		viewport.screen_space_aa, Viewport.SCREEN_SPACE_AA_SMAA,
		"HIGH: сглаживание — SMAA")
	assert_false(viewport.use_taa, "HIGH: TAA выключен (резкие звёзды)")
	assert_eq(
		viewport.positional_shadow_atlas_size,
		GraphicsQuality.HIGH_POSITIONAL_ATLAS_SIZE,
		"HIGH: атлас точечных теней — 4096")
	assert_almost_eq(
		viewport.mesh_lod_threshold, GraphicsQuality.MESH_LOD_THRESHOLD_BASE,
		0.001, "HIGH: порог LOD — 1.0")
	sun.free()
	moon.free()
	viewport.free()


func test_high_grass_parallax_in_ground_material() -> void:
	# П13 1.9: материал земли на HIGH получает параллакс 10–15 м
	# (uniform шейдера); на прочих уровнях uniform не ставится — живут
	# дефолты шейдера 15–25 (база ULTRA), их проверяем исходником.
	var high_material := ForestGround.make_material(
		ART, GraphicsQuality.Tier.HIGH)
	assert_almost_eq(
		float(high_material.get_shader_parameter("parallax_near")),
		GraphicsQuality.HIGH_PARALLAX_NEAR, 0.001,
		"HIGH: параллакс от 10 м")
	assert_almost_eq(
		float(high_material.get_shader_parameter("parallax_far")),
		GraphicsQuality.HIGH_PARALLAX_FAR, 0.001,
		"HIGH: параллакс до 15 м")
	assert_almost_eq(
		GraphicsQuality.PARALLAX_NEAR_BASE, 15.0, 0.001,
		"база параллакса (ULTRA) — от 15 м")
	assert_almost_eq(
		GraphicsQuality.PARALLAX_FAR_BASE, 25.0, 0.001,
		"база параллакса (ULTRA) — до 25 м")
	var shader_text: String = load(
		"res://assets/shaders/forest_ground.gdshader").code
	assert_true(
		shader_text.contains("uniform float parallax_near = 15.0;"),
		"ULTRA/база: дефолт шейдера — параллакс от 15 м")
	assert_true(
		shader_text.contains("uniform float parallax_far = 25.0;"),
		"ULTRA/база: дефолт шейдера — параллакс до 25 м")


func test_cabin_high_shadows_and_probes() -> void:
	# П13 1.6/1.8 (П16 п. 1 — поведение теней ламп на HIGH изменилось):
	# на HIGH пробы комнат есть (UPDATE_ONCE дёшевы), тени ламп настроены
	# (маска кастеров, dual paraboloid, fade ~12 м) и включаются НЕ всем,
	# а 1-2 ближайшим к камере лампам (LampShadows.update_nearest);
	# на ULTRA distance_fade выключен, тень у всех; уход ниже HIGH
	# убирает пробы и тени.
	var cabin := CabinHouse.new()
	add_child_autofree(cabin)
	var lights: Array[OmniLight3D] = []
	cabin.set_quality(GraphicsQuality.Tier.HIGH)
	assert_not_null(
		cabin.get_node_or_null("WingProbe"), "HIGH: проба крыла есть")
	assert_not_null(
		cabin.get_node_or_null("HallProbe"), "HIGH: проба зала есть")
	for child: Node in cabin.get_children():
		var light := child as OmniLight3D
		if light != null:
			lights.append(light)
	assert_eq(lights.size(), 3, "у сруба три лампы-«факела»")
	for light: OmniLight3D in lights:
		assert_false(
			light.shadow_enabled,
			"HIGH: до апдейта тень у %s выключена (включит менеджер)"
			% light.name)
		assert_true(
			light.distance_fade_enabled,
			"HIGH: тени лампы %s гаснут по дальности" % light.name)
		assert_almost_eq(
			light.distance_fade_shadow,
			GraphicsQuality.HIGH_LAMP_FADE_SHADOW, 0.001,
			"HIGH: тени лампы %s гаснут с ~12 м" % light.name)
		assert_eq(
			light.shadow_caster_mask, GraphicsQuality.LAMP_CASTER_MASK,
			"HIGH: у %s маска кастеров (постройки/персонажи)" % light.name)
	# Менеджер ближайших: у одной лампы — тень, у прочих нет.
	LampShadows.enabled = true
	LampShadows.update_nearest(
		cabin, Vector3(0.0, 2.4, -5.0), 1)
	var shadowed: int = 0
	for light: OmniLight3D in lights:
		shadowed += 1 if light.shadow_enabled else 0
	assert_eq(shadowed, 1, "HIGH: тень ровно у 1 ближайшей лампы")
	cabin.set_quality(GraphicsQuality.Tier.ULTRA)
	for light: OmniLight3D in lights:
		assert_false(
			light.distance_fade_enabled,
			"ULTRA: distance_fade у %s выключен" % light.name)
		assert_true(
			light.shadow_enabled, "ULTRA: тени лампы %s включены" % light.name)
		assert_eq(
			light.shadow_caster_mask, 0xFFFFFFFF,
			"ULTRA: маска кастеров не ограничена (ULTRA не тронут)")
	cabin.set_quality(GraphicsQuality.Tier.NORMAL)
	assert_null(
		cabin.get_node_or_null("WingProbe"), "ниже HIGH: пробы крыла нет")
	for light: OmniLight3D in lights:
		assert_false(
			light.shadow_enabled,
			"ниже HIGH: тени лампы %s выключены" % light.name)
	# П13 3.2 (П16 п. 1): точечное выключение теней ламп (панель F3)
	# глушит всех и менеджер; возврат на ULTRA включает всех сразу,
	# на HIGH — вернёт менеджер ближайших.
	cabin.set_quality(GraphicsQuality.Tier.HIGH)
	cabin.set_lamp_shadows(false)
	LampShadows.update_nearest(
		cabin, Vector3(0.0, 2.4, -5.0), 1)
	for light: OmniLight3D in lights:
		assert_false(
			light.shadow_enabled,
			"F3: тени лампы %s выключены (менеджер погашен)" % light.name)
	cabin.set_lamp_shadows(true)
	assert_true(
		LampShadows.enabled,
		"F3: возврат включает менеджер ближайших ламп")


# --- П13 2: «Разрешение 3D» ---

func test_res3d_scale_and_fsr_by_menu_item() -> void:
	# П13 2.1–2.2: 100 % — полный рендер (BILINEAR, scale 1.0); ниже —
	# пониженный рендер с апскейлом FSR 1.0 и умеренной резкостью.
	var store := MenuSettingsBU.new()
	var viewport := SubViewport.new()
	add_child_autofree(viewport)
	assert_eq(
		MenuSettingsBU.RES3D_STEPS, [1.0, 0.85, 0.75, 0.67],
		"ступени разрешения: 100/85/75/67 %")
	var pairs: Array = [
		[0, 1.0, Viewport.SCALING_3D_MODE_BILINEAR],
		[1, 0.85, Viewport.SCALING_3D_MODE_FSR],
		[2, 0.75, Viewport.SCALING_3D_MODE_FSR],
		[3, 0.67, Viewport.SCALING_3D_MODE_FSR],
	]
	for pair: Array in pairs:
		store.set_value(&"res3d", pair[0])
		store.apply_render_scale(viewport)
		assert_almost_eq(
			viewport.scaling_3d_scale, pair[1], 0.001,
			"пункт %d: масштаб 3D %.2f" % [pair[0], pair[1]])
		assert_eq(
			viewport.scaling_3d_mode, pair[2],
			"пункт %d: апскейл по SPEC (FSR 1.0, не FSR 2)" % pair[0])
		if pair[1] < 1.0:
			assert_between(
				viewport.fsr_sharpness, 0.2, 0.4,
				"пункт %d: резкость FSR 0.2–0.4" % pair[0])


func test_res3d_first_run_integrated_gpu() -> void:
	# П13 2.3: первый запуск без cfg на встроенной графике — 85 %,
	# на прочих адаптерах — 100 %.
	assert_eq(
		MenuSettingsBU.first_run_res3d(
			RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU), 1,
		"встроенная графика — пункт 85 %")
	assert_eq(
		MenuSettingsBU.first_run_res3d(
			RenderingDevice.DEVICE_TYPE_DISCRETE_GPU), 0,
		"дискретная графика — пункт 100 %")
	assert_eq(
		MenuSettingsBU.first_run_res3d(
			RenderingDevice.DEVICE_TYPE_CPU), 0,
		"софтверный рендер (llvmpipe) — пункт 100 %")


# --- П13 п. 5: растворение воды 46–66 м — только SIMPLE ---

func test_water_fade_simple_only() -> void:
	# Баг-фикс П13 п. 5: растворение 46–66 м принадлежит «Простой графике»
	# (камера far 70); прочие уровни — базовая дальность 700–1400 м.
	WorldMaterials.textured_headless = true
	var area := WaterArea.new()
	add_child_autofree(area)
	var material := area._surface_material(true) as ShaderMaterial
	area.set_tier_fade(GraphicsQuality.Tier.SIMPLE)
	assert_almost_eq(
		float(material.get_shader_parameter("distance_fade_min")),
		WaterArea.FADE_SIMPLE_MIN, 0.001, "SIMPLE: растворение с 46 м")
	assert_almost_eq(
		float(material.get_shader_parameter("distance_fade_max")),
		WaterArea.FADE_SIMPLE_MAX, 0.001, "SIMPLE: растворение до 66 м")
	for tier: int in [
		GraphicsQuality.Tier.NORMAL,
		GraphicsQuality.Tier.HIGH,
		GraphicsQuality.Tier.ULTRA,
	]:
		area.set_tier_fade(tier)
		assert_almost_eq(
			float(material.get_shader_parameter("distance_fade_min")),
			WaterArea.FADE_BASE_MIN, 0.001,
			"Tier.%d: базовая дальность растворения" % tier)
		assert_almost_eq(
			float(material.get_shader_parameter("distance_fade_max")),
			WaterArea.FADE_BASE_MAX, 0.001,
			"Tier.%d: вода уходит за горизонт" % tier)
	# П14 4.2: преломление на лету (панель F3) — сила смещения выборки
	# экрана в 0 и обратно, шейдер не меняется (экранная текстура —
	# только полная версия на HIGH/ULTRA).
	area.set_refraction(false)
	assert_almost_eq(
		float(material.get_shader_parameter("refraction_amount")),
		0.0, 0.001, "F3: без преломления — смещение выборки в 0")
	area.set_refraction(true)
	assert_almost_eq(
		float(material.get_shader_parameter("refraction_amount")),
		1.0, 0.001, "F3: преломление вернулось")
	# П14 4.3: рябь на лету (панель F3) — 0 слоёв и номинал уровня.
	area.set_ripple(false)
	assert_almost_eq(
		float(material.get_shader_parameter("ripple_layers")),
		0.0, 0.001, "F3: без ряби — 0 слоёв")
	area.set_ripple(true)
	assert_almost_eq(
		float(material.get_shader_parameter("ripple_layers")),
		float(WaterArea.ripple_layers_for_tier(
			GraphicsQuality.tier_from_settings())), 0.001,
		"F3: рябь вернулась — номинал уровня")
	WorldMaterials.textured_headless = false


# --- П13 3: панель замера F3 ---

func test_f3_panel_toggles_effects() -> void:
	# П13 3.2 + П14 5.2: 14 галочек; П15 7 — ещё «Каустика» и «Круги
	# на воде» (16). Снятая выключает эффект, повторная возвращает
	# состояние уровня (не «всё включено»); повторное применение
	# качества сбрасывает галочки.
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	panel.watch_graphics(env, null, GraphicsQuality.Tier.HIGH)
	assert_eq(
		panel._boxes.size(), panel.EFFECTS.size(),
		"галочек столько же, сколько эффектов (16)")
	var checks: Array[CheckBox] = []
	for id: StringName in panel.EFFECTS:
		assert_true(
			panel._boxes[id].button_pressed,
			"галочка %s включена после применения уровня" % id)
		checks.append(panel._boxes[id])
	assert_eq(checks.size(), 16, "эффектов — 16")
	var env_props: Dictionary[StringName, String] = {
		&"sdfgi": "sdfgi_enabled", &"ssil": "ssil_enabled",
		&"ssr": "ssr_enabled", &"ssao": "ssao_enabled",
		&"vfog": "volumetric_fog_enabled", &"glow": "glow_enabled",
	}
	for id: StringName in env_props.keys():
		panel._boxes[id].button_pressed = false
		assert_false(
			env.get(env_props[id]), "галочка %s выключила эффект" % id)
		panel._boxes[id].button_pressed = true
		assert_true(
			env.get(env_props[id]), "галочка %s вернула эффект" % id)
	# AA: снятая галочка гасит SMAA на viewport сцены. Уровень мир применяет
	# к корневому viewport — в тесте ставим SMAA так же, как apply(HIGH).
	var root_viewport := get_viewport()
	root_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
	panel._boxes[&"aa"].button_pressed = false
	assert_eq(
		root_viewport.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED,
		"галочка aa выключила SMAA")
	panel._boxes[&"aa"].button_pressed = true
	assert_eq(
		root_viewport.screen_space_aa, Viewport.SCREEN_SPACE_AA_SMAA,
		"галочка aa вернула SMAA")
	root_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	# Повторное применение качества миром (apply + watch_graphics) включает
	# эффекты заново и сбрасывает галочки.
	panel._boxes[&"sdfgi"].button_pressed = false
	assert_false(env.sdfgi_enabled, "галочка sdfgi выключила SDFGI")
	GraphicsQuality.apply(env, sun, GraphicsQuality.Tier.HIGH)
	panel.watch_graphics(env, null, GraphicsQuality.Tier.HIGH)
	assert_true(
		panel._boxes[&"sdfgi"].button_pressed,
		"повторное применение сбросило галочку sdfgi")
	assert_true(env.sdfgi_enabled, "повторное применение вернуло SDFGI")
	sun.free()


func test_f3_panel_restores_tier_not_everything() -> void:
	# Возврат галочки возвращает состояние УРОВНЯ: на SIMPLE повторная
	# галочка SDFGI не включает его (уровень его не хочет).
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	var env := Environment.new()
	panel.watch_graphics(env, null, GraphicsQuality.Tier.SIMPLE)
	env.sdfgi_enabled = false
	panel._boxes[&"sdfgi"].button_pressed = true
	assert_false(
		env.sdfgi_enabled,
		"SIMPLE: повторная галочка не включает SDFGI (не уровень)")


func test_f3_panel_p14_effect_hooks() -> void:
	# П14 5.2: пять новых галочек замера — «Детальная сетка земли», «POM»,
	# «Мелочь на земле», «Преломление воды», «Рябь воды» — каждая дергает
	# свой метод выключения (IslandView/WaterArea). Поведение самих методов
	# (видимость кольца/мелочи, parallax_scale, refraction_amount,
	# ripple_layers) проверяют тесты блоков 3–4; здесь — связка
	# «галочка → метод» и уровневая логика возврата.
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	var code := FileAccess.get_file_as_string("res://ui/debug_panel.gd")
	var hooks: Dictionary[StringName, String] = {
		&"detail": "_view.set_detail_ring_visible(value)",
		&"pom": "_view.set_parallax(value)",
		&"clutter": "_view.set_clutter_visible(value)",
		&"refr": "WaterArea).set_refraction(value)",
		&"ripple": "WaterArea).set_ripple(value)",
	}
	for id: StringName in hooks:
		assert_true(panel.EFFECTS.has(id), "галочка %s есть в панели" % id)
		assert_true(code.contains(hooks[id]),
			"галочка %s выключает свой эффект" % id)
	# Возврат галочки возвращает состояние уровня: земляные эффекты и
	# преломление — только HIGH/ULTRA, рябь есть на всех (1 слой ниже HIGH).
	panel.watch_graphics(Environment.new(), null, GraphicsQuality.Tier.HIGH)
	for id: StringName in hooks:
		assert_true(panel._tier_effect_on(id), "HIGH: %s — уровень" % id)
	panel.watch_graphics(Environment.new(), null, GraphicsQuality.Tier.SIMPLE)
	for id: StringName in [&"detail", &"pom", &"clutter", &"refr"]:
		assert_false(panel._tier_effect_on(id),
			"SIMPLE: %s — не уровень, возврат не включает" % id)
	assert_true(panel._tier_effect_on(&"ripple"),
		"SIMPLE: рябь возвращается (1 слой — уровень)")


func test_f3_report_contents() -> void:
	# П13 3.4: отчёт содержит видеокарту, уровень, разрешение 3D,
	# средние FPS/GPU за окно и список выключенного.
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	var env := Environment.new()
	panel.watch_graphics(env, null, GraphicsQuality.Tier.HIGH)
	var report := panel.build_report()
	for part: String in [
		"GPU:", "Quality:", "3D resolution:", "FPS avg", "GPU ms avg",
		"Disabled:", "—",
	]:
		assert_true(
			report.contains(part), "в отчёте есть «%s»" % part)
	panel._boxes[&"glow"].button_pressed = false
	assert_true(
		panel.build_report().contains(tr("BU_DBG_GLOW")),
		"выключенный glow попадает в отчёт (локализованное имя)")


func test_f3_and_menu_texts_translated() -> void:
	# П13 4/3: все новые ключи перевода есть в CSV с русским и английским
	# текстом — подписи галочек, кнопка отчёта, заголовок, «Разрешение 3D»
	# и описания уровней качества.
	var keys: Array[String] = [
		"BU_DBG_EFFECTS", "BU_DBG_COPY", "BU_DBG_SDFGI", "BU_DBG_SSIL",
		"BU_DBG_SSR", "BU_DBG_SSAO", "BU_DBG_VFOG", "BU_DBG_GLOW",
		"BU_DBG_AA", "BU_DBG_LAMPS", "BU_DBG_GRASS",
		# П14 5.2: пять новых галочек панели замера.
		"BU_DBG_DETAIL", "BU_DBG_POM", "BU_DBG_CLUTTER",
		"BU_DBG_REFRACTION", "BU_DBG_RIPPLE",
		"BU_SET_RES3D", "BU_DESC_RES3D_0", "BU_DESC_RES3D_1",
		"BU_DESC_RES3D_2", "BU_DESC_RES3D_3", "BU_DESC_QUALITY_0",
		"BU_DESC_QUALITY_1", "BU_DESC_QUALITY_2", "BU_DESC_QUALITY_3",
	]
	var csv: Dictionary[String, PackedStringArray] = {}
	var file := FileAccess.open(CSV, FileAccess.READ)
	assert_not_null(file, "файл строк есть")
	if file == null:
		return
	file.get_csv_line()  # заголовок keys,ru,en
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() >= 3 and line[0] != "":
			csv[line[0]] = line
	file.close()
	for key: String in keys:
		assert_true(
			csv.has(key), "ключ %s есть в CSV" % key)
		if csv.has(key):
			assert_ne(
				csv[key][1], "", "ключ %s: есть русский текст" % key)
			assert_ne(
				csv[key][2], "", "ключ %s: есть английский текст" % key)
	# П13 4: формулировка про «Высокое» — почти та же картинка, встройка
	# (русский текст из CSV, регистронезависимо — фраза в начале предложения).
	assert_true(
		String(csv["BU_DESC_QUALITY_2"][1]).to_lower()
			.contains("почти та же картинка"),
		"описание «Высокого» — из SPEC")
	assert_true(
		String(csv["BU_DESC_QUALITY_3"][1]).to_lower()
			.contains("максимальное качество"),
		"описание «Ультра» — из SPEC")
