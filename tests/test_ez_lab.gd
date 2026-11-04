# Тесты П18-ЛАБОРАТОРИЯ (п. 4 владельца): сцена ezTree-лаборатории
# (--ez-lab) и вкладка F3 «Свет» — ползунки живого рендера (LightTuner):
# работают и в лаборатории, и в мире, ничего не сохраняют, дефолты —
# свет мира днём (Balance/VisualPalette), «Сбросить» возвращает исходное,
# «Скопировать значения» содержит все параметры с числами.
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")
const VPAL: VisualPalette = preload("res://assets/visual_palette.tres")
const DevScript: GDScript = preload("res://autoload/dev.gd")


func before_each() -> void:
	# Значения LightTuner — статика на процесс: каждый тест начинает
	# с дефолтов (как после запуска игры).
	LightTuner.reset()


# --- Сцена-лаборатория по --ez-lab ---

func test_ez_lab_flag_parses_and_scene_loads() -> void:
	# --ez-lab разбирается и ведёт на существующую сцену лаборатории.
	var d: Dictionary = DevScript.parse_args(PackedStringArray(["--ez-lab"]))
	assert_true(d["ez_lab"], "--ez-lab разбирается")
	assert_eq(
		DevScript.EZ_LAB_SCENE, "res://scenes/ez_lab.tscn",
		"путь сцены лаборатории")
	assert_true(
		ResourceLoader.exists(DevScript.EZ_LAB_SCENE),
		"файл сцены лаборатории существует")


func test_ez_lab_scene_builds_demo_copy() -> void:
	# Инстанцирование сцены строит копию демо: земля, ясень в центре,
	# 100 деревьев леса (сумма инстансов MultiMesh), трава и свет.
	var scene: PackedScene = load(DevScript.EZ_LAB_SCENE)
	assert_not_null(scene, "сцена лаборатории грузится")
	var lab := scene.instantiate() as EzLab
	assert_not_null(lab, "корневой узел — EzLab")
	add_child_autofree(lab)
	assert_not_null(lab.get_node_or_null("LabGround"), "земля построена")
	assert_not_null(lab.get_node_or_null("LabTree"), "ясень в центре")
	var forest := lab.get_node_or_null("LabForest")
	assert_not_null(forest, "лес построен")
	var trees: int = 0
	for child: Node in forest.get_children():
		var instance := child as MultiMeshInstance3D
		assert_not_null(instance, "лес — MultiMesh-группы")
		trees += instance.multimesh.instance_count
	assert_eq(trees, lab.FOREST_COUNT, "деревьев в лесу — 100 (scene.js)")
	assert_not_null(lab.get_node_or_null("LabSun"), "солнце создано")
	assert_not_null(lab.get_node_or_null("LabCamera"), "камера-орбита создана")
	assert_not_null(
		lab.get_node_or_null("LabEnvironment"), "environment создан")
	# Трава лаборатории: пучки демо приняты полным составом.
	var layout: Dictionary = GrassField.lab_layout(lab.LAB_SEED + 1)
	assert_eq(
		(layout["tuft"]["transforms"] as Array).size(),
		GrassField.LAB_INSTANCE_COUNT,
		"пучков травы — 5000 (instanceCount демо)")


func test_ez_lab_layout_deterministic() -> void:
	# Картинка лаборатории детерминирована: одинаковый seed — одинаковые
	# раскладки травы и цветов, разный — разные (правило CLAUDE.md
	# про генерацию: только RandomNumberGenerator с фиксированным seed).
	var a: Dictionary = GrassField.lab_layout(7)
	var b: Dictionary = GrassField.lab_layout(7)
	var c: Dictionary = GrassField.lab_layout(8)
	assert_eq(
		(a["tuft"]["transforms"] as Array).size(),
		(b["tuft"]["transforms"] as Array).size(),
		"число пучков совпадает при том же seed")
	assert_eq(
		a["tuft"]["transforms"][0], b["tuft"]["transforms"][0],
		"первый пучок на том же месте")
	assert_ne(
		a["tuft"]["transforms"][0], c["tuft"]["transforms"][0],
		"другой seed — другая картинка")


# --- Вкладка «Свет»: контролы ---

func test_light_tab_builds_all_controls() -> void:
	# Вкладка создаёт все ползунки, цвета, опции и чекбокс тумана;
	# в lab-режиме видна только она, кнопка — «Вернуться в мир».
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	for def: Dictionary in panel.LIGHT_SLIDERS:
		assert_true(panel._light_sliders.has(def["id"]),
			"ползунок %s создан" % def["id"])
	for def: Dictionary in panel.LIGHT_COLORS:
		assert_true(panel._light_pickers.has(def["id"]),
			"пикер цвета %s создан" % def["id"])
	assert_true(panel._light_options.has(&"tonemap"), "опция тонмаппинга")
	assert_true(panel._light_options.has(&"ambient_sky"),
		"опция источника ambient")
	assert_not_null(panel._light_fog_check, "чекбокс тумана")
	# Lab-режим: эффекты и вода скрыты, вкладка «Свет» видна.
	panel.set_lab_mode(true)
	assert_true(panel._tabs.is_tab_hidden(
		panel._tabs.get_tab_idx_from_control(panel._effects_tab)),
		"эффекты скрыты в лаборатории")
	assert_true(panel._tabs.is_tab_hidden(
		panel._tabs.get_tab_idx_from_control(panel._water_tab)),
		"вода скрыты в лаборатории")
	assert_false(panel._tabs.is_tab_hidden(
		panel._tabs.get_tab_idx_from_control(panel._light_tab)),
		"вкладка «Свет» видна в лаборатории")
	assert_true(panel._tabs.visible, "контейнер вкладок не пуст")


func test_lab_buttons_signal() -> void:
	# Кнопка F3: в мире — enter_lab_requested, в лаборатории —
	# return_world_requested.
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	watch_signals(panel)
	panel._on_lab_button()
	assert_signal_emitted(panel, "enter_lab_requested",
		"в мире кнопка ведёт в лабораторию")
	panel.set_lab_mode(true)
	panel._on_lab_button()
	assert_signal_emitted(panel, "return_world_requested",
		"в лаборатории кнопка ведёт обратно в мир")


# --- Вкладка «Свет»: ползунки меняют живой рендер ---

## Стенд материалов деревьев: QuadMesh-поверхность с материалом canopy
## или bark (как в мешах острова), bind_scene собирает их в LightTuner.
func _tree_stand(canopy: ShaderMaterial, bark: ShaderMaterial) -> Node3D:
	var root := Node3D.new()
	for material: ShaderMaterial in [canopy, bark]:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
			Vector3(-1, 0, -1), Vector3(1, 0, -1),
			Vector3(1, 0, 1), Vector3(-1, 0, 1)])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		root.add_child(instance)
	add_child_autofree(root)
	return root


func _canopy_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = EzTreeMeshes.CANOPY_SHADER
	return material


func _bark_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = EzTreeMeshes.BARK_SHADER
	return material


func test_sliders_change_live_render() -> void:
	# Каждый ползунок вкладки меняет свой параметр живого рендера: слайдер
	# панели → LightTuner → env/солнце. Высота солнца в лаборатории (без
	# купола) двигает сам DirectionalLight3D.
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	add_child_autofree(sun)
	panel.watch_light(env, sun, null)
	var canopy := _canopy_material()
	var bark := _bark_material()
	LightTuner.bind_scene(_tree_stand(canopy, bark))
	# Числа ползунков — очевидно отличные от дефолтов (exposure 2 демо,
	# туман 0.01, AgX→Linear, солнце в зенит).
	panel._light_sliders[&"sun_energy"].value = 2.0
	assert_almost_eq(sun.light_energy, 2.0, 0.001,
		"сила солнца — на свет")
	panel._light_sliders[&"sun_elevation"].value = 90.0
	assert_almost_eq(
		sun.global_position.normalized().y, 1.0, 0.01,
		"высота 90° — солнце в зените")
	panel._light_sliders[&"ambient_energy"].value = 0.5
	assert_almost_eq(env.ambient_light_energy, 0.5, 0.001,
		"сила ambient — на environment")
	panel._light_sliders[&"exposure"].value = 2.0
	assert_almost_eq(env.tonemap_exposure, 2.0, 0.001,
		"экспозиция — на environment")
	panel._light_sliders[&"saturation"].value = 0.5
	assert_almost_eq(env.adjustment_saturation, 0.5, 0.001,
		"насыщенность — на environment")
	panel._light_sliders[&"contrast"].value = 1.5
	assert_almost_eq(env.adjustment_contrast, 1.5, 0.001,
		"контраст — на environment")
	panel._light_sliders[&"fog_density"].value = 0.01
	assert_almost_eq(env.fog_density, 0.01, 0.0005,
		"плотность тумана — на environment")
	# Деревья: ползунки пишут юниформы нейтральных шейдеров.
	panel._light_sliders[&"leaf_brightness"].value = 1.4
	assert_almost_eq(
		float(canopy.get_shader_parameter("leaf_brightness")), 1.4, 0.001,
		"яркость листвы — юниформ canopy")
	panel._light_sliders[&"leaf_glow"].value = 0.3
	assert_almost_eq(
		float(canopy.get_shader_parameter("leaf_glow")), 0.3, 0.001,
		"просвет листвы — юниформ canopy")
	# Цвета.
	panel._on_light_color_changed(Color(1.0, 0.5, 0.2), &"sun_color")
	assert_almost_eq(sun.light_color.r, 1.0, 0.001, "цвет солнца — на свет")
	assert_almost_eq(sun.light_color.g, 0.5, 0.001, "цвет солнца G")
	panel._on_light_color_changed(Color(0.2, 0.4, 0.6), &"ambient_color")
	assert_almost_eq(env.ambient_light_color.b, 0.6, 0.001,
		"цвет ambient — на environment")
	panel._on_light_color_changed(Color(0.9, 0.9, 1.0), &"fog_color")
	assert_almost_eq(env.fog_light_color.r, 0.9, 0.001,
		"цвет тумана — на environment")
	panel._on_light_color_changed(Color(0.6, 0.9, 0.3), &"leaf_color")
	assert_almost_eq(
		(canopy.get_shader_parameter("leaf_tint_mul") as Color).g, 0.9,
		0.001, "цвет листвы — юниформ canopy")
	panel._on_light_color_changed(Color(0.5, 0.35, 0.2), &"bark_color")
	assert_almost_eq(
		(bark.get_shader_parameter("bark_tint") as Color).r, 0.5, 0.001,
		"цвет коры — юниформ bark")
	# Опции и туман.
	panel._on_light_option_selected(0, &"tonemap")
	assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_LINEAR,
		"тонмаппинг переключается (AgX → Linear)")
	panel._on_light_option_selected(1, &"ambient_sky")
	assert_eq(env.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR,
		"ambient — ровный цвет вместо неба")
	panel._on_light_fog_toggled(false)
	assert_false(env.fog_enabled, "туман выключается")


func test_reset_returns_originals() -> void:
	# «Сбросить»: значения — в дефолты, сцена — к исходному свету
	# (лаборатория: дефолтная сборка env/солнца), материалы деревьев —
	# нейтральные множители; неактивные параметры снова ведёт DayCycle.
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	add_child_autofree(sun)
	panel.watch_light(env, sun, null)
	var canopy := _canopy_material()
	var bark := _bark_material()
	LightTuner.bind_scene(_tree_stand(canopy, bark))
	panel._light_sliders[&"sun_energy"].value = 2.0
	panel._light_sliders[&"exposure"].value = 2.5
	panel._light_sliders[&"fog_density"].value = 0.01
	panel._light_sliders[&"leaf_brightness"].value = 1.6
	panel._on_light_color_changed(Color(0.9, 0.1, 0.1), &"leaf_color")
	panel._on_light_color_changed(Color(0.2, 0.2, 0.2), &"bark_color")
	panel._on_light_option_selected(0, &"tonemap")
	panel._on_light_fog_toggled(false)
	panel._reset_light()
	assert_false(LightTuner.any_active(), "после сброса нет активных")
	assert_almost_eq(sun.light_energy,
		float(LightTuner.DEFS[&"sun_energy"]), 0.001,
		"сила солнца вернулась")
	assert_almost_eq(env.tonemap_exposure,
		float(LightTuner.DEFS[&"exposure"]), 0.001,
		"экспозиция вернулась")
	assert_almost_eq(env.fog_density,
		float(LightTuner.DEFS[&"fog_density"]), 0.0005,
		"плотность тумана вернулась")
	assert_eq(env.tonemap_mode,
		LightTuner.DEFS[&"tonemap"] as Environment.ToneMapper,
		"тонмаппинг вернулся (AgX)")
	assert_true(env.fog_enabled, "туман вернулся")
	assert_eq(panel._light_sliders[&"sun_energy"].value,
		float(LightTuner.DEFS[&"sun_energy"]),
		"ползунок переставлен на дефолт")
	assert_eq(canopy.get_shader_parameter("leaf_tint_mul"), Color.WHITE,
		"листва — нейтральный цвет")
	assert_almost_eq(
		float(canopy.get_shader_parameter("leaf_brightness")), 1.0, 0.001,
		"листва — нейтральная яркость")
	assert_eq(bark.get_shader_parameter("bark_tint"), Color.WHITE,
		"кора — нейтральный цвет")


func test_copy_values_contains_all_params() -> void:
	# «Скопировать значения»: текст содержит все параметры с числами —
	# владелец присылает его из игры, числа становятся светом мира.
	var text := LightTuner.build_values_text()
	for id: StringName in LightTuner.DEFS:
		assert_true(text.contains("%s = " % id),
			"параметр %s в тексте" % id)
	assert_true(text.contains("sun_energy = 0.3000"),
		"сила солнца — числом")
	assert_true(text.contains("tonemap = AgX (4)"),
		"тонмаппинг — именем и индексом")
	assert_true(text.contains("sun_color = Color(1.000, 0.945, 0.839)"),
		"цвет солнца — Color(r, g, b)")
	assert_true(text.contains("fog_on = true"), "туман — флагом")


# --- Дефолты мира не изменены ---

func test_defaults_are_world_day_light() -> void:
	# Дефолты ползунков = текущий свет мира днём (Balance/VisualPalette/
	# DayMath): «СЕЙЧАС МИР НЕ МЕНЯТЬ» — до подбора владельцем ползунки
	# не перекрашивают игру.
	assert_almost_eq(float(LightTuner.DEFS[&"sun_energy"]),
		B.sun_energy_noon, 0.0001, "сила солнца = Balance.sun_energy_noon")
	var sun_color: Color = LightTuner.DEFS[&"sun_color"]
	assert_almost_eq(sun_color.r, VPAL.day_sun.r, 0.001, "цвет солнца R")
	assert_almost_eq(sun_color.g, VPAL.day_sun.g, 0.001, "цвет солнца G")
	assert_almost_eq(sun_color.b, VPAL.day_sun.b, 0.001, "цвет солнца B")
	assert_almost_eq(float(LightTuner.DEFS[&"sun_elevation"]),
		rad_to_deg(B.sun_max_elevation), 0.01,
		"высота солнца = Balance.sun_max_elevation")
	var ambient: Color = LightTuner.DEFS[&"ambient_color"]
	assert_almost_eq(ambient.r, VPAL.day_ambient.r, 0.001, "ambient R")
	assert_almost_eq(ambient.g, VPAL.day_ambient.g, 0.001, "ambient G")
	assert_almost_eq(float(LightTuner.DEFS[&"ambient_energy"]),
		DayMath.ambient_energy_sky(B.day_cycle_sec * 0.3), 0.001,
		"сила ambient = полдень DayMath")
	assert_eq(LightTuner.DEFS[&"tonemap"], 4, "тонмаппинг — AgX мира")
	assert_almost_eq(float(LightTuner.DEFS[&"fog_density"]), B.fog_density,
		0.00001, "плотность тумана = Balance.fog_density")
	var fog: Color = LightTuner.DEFS[&"fog_color"]
	assert_almost_eq(fog.b, VPAL.day_fog.b, 0.001, "цвет тумана B")
	assert_eq(LightTuner.DEFS[&"leaf_color"], Color.WHITE,
		"листва — нейтральный цвет")
	assert_eq(LightTuner.DEFS[&"bark_color"], Color.WHITE,
		"кора — нейтральный цвет")


func test_inactive_params_do_not_touch_scene() -> void:
	# Параметр в дефолте «не активен»: DayCycle/сцена ведут свои значения
	# сами — ползунки не переписывают их за кадр.
	var env := Environment.new()
	env.ambient_light_energy = 0.5
	env.tonemap_exposure = 3.0
	env.fog_light_color = Color(0.1, 0.2, 0.3)
	var sun := DirectionalLight3D.new()
	add_child_autofree(sun)
	sun.light_energy = 1.7
	LightTuner.apply_scene(env, sun, null)
	assert_almost_eq(env.ambient_light_energy, 0.5, 0.001,
		"ambient не тронут (не активен)")
	assert_almost_eq(env.tonemap_exposure, 3.0, 0.001,
		"экспозиция не тронута (не активна)")
	assert_almost_eq(sun.light_energy, 1.7, 0.001,
		"солнце не тронуто (не активно)")
	assert_eq(env.fog_light_color, Color(0.1, 0.2, 0.3),
		"цвет тумана не тронут (не активен)")
