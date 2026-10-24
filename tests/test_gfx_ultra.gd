# Тесты П11 «Графика на максимум»: каркас «меню → мир» (пункт меню 0–3
# задаёт уровень мира, dev-флаги имеют приоритет, старый cfg без ключа
# quality даёт «Высокое») и ULTRA-рендер ветки bu-gfx (SDFGI, SSIL, SSR,
# тени 8192, качество SSAO/SSIL/тумана, MSAA 4x + SMAA, mesh_lod_threshold
# 0, пробы отражений срубов). Сервер — Compatibility-рендерер: эффекты
# не рисуются, проверяются значения свойств, а не картинка. Глобальные
# настройки RenderingServer (атласы, фильтры, качество SSAO/SSIL, объём
# тумана) геттеров не имеют — их чистое выключение проверяется свойствами
# env/viewport и кодом apply() (ставит и базу, и ULTRA при каждом вызове).
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")

var _had_cfg: bool = false
var _saved_cfg: PackedByteArray = PackedByteArray()
var _saved_simple: bool = false
var _saved_high: bool = false
var _saved_ultra: bool = false


func before_all() -> void:
	# «Качество графики» читается из cfg меню (user://settings_bu.cfg):
	# настоящий файл сохраняем и возвращаем после тестов.
	if FileAccess.file_exists(MenuSettingsBU.SAVE_PATH):
		_had_cfg = true
		var f := FileAccess.open(MenuSettingsBU.SAVE_PATH, FileAccess.READ)
		_saved_cfg = f.get_buffer(f.get_length())
		f.close()


func after_all() -> void:
	if _had_cfg:
		var f := FileAccess.open(MenuSettingsBU.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_saved_cfg)
		f.close()
	elif FileAccess.file_exists(MenuSettingsBU.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MenuSettingsBU.SAVE_PATH))


func before_each() -> void:
	_saved_simple = Settings.simple_graphics
	_saved_high = Settings.high_quality
	_saved_ultra = Settings.ultra_quality
	Settings.simple_graphics = false
	Settings.high_quality = false
	Settings.ultra_quality = false


func after_each() -> void:
	Settings.simple_graphics = _saved_simple
	Settings.high_quality = _saved_high
	Settings.ultra_quality = _saved_ultra


## Записать cfg меню с данным пунктом качества (как MenuSettingsBU.save_to_disk);
## null — cfg без ключа quality (старый файл, других настроек ещё не было).
func _write_menu_quality(item: Variant) -> void:
	if item == null:
		var old := ConfigFile.new()
		old.set_value(MenuSettingsBU.SECTION, "vsync", true)
		old.save(MenuSettingsBU.SAVE_PATH)
		return
	var store := MenuSettingsBU.new()
	store.set_value(&"quality", int(item))
	store.save_to_disk()


func test_menu_items_map_to_tiers() -> void:
	# П11 1.1: пункты меню «Качество графики» 0–3 (Низкое / Среднее /
	# Высокое / Ультра) дают уровни мира SIMPLE / NORMAL / HIGH / ULTRA.
	var expected: Array[int] = [
		GraphicsQuality.Tier.SIMPLE,
		GraphicsQuality.Tier.NORMAL,
		GraphicsQuality.Tier.HIGH,
		GraphicsQuality.Tier.ULTRA,
	]
	for item: int in expected.size():
		_write_menu_quality(item)
		assert_eq(
			GraphicsQuality.tier_from_settings(), expected[item],
			"пункт меню %d должен давать уровень %d" % [item, expected[item]],
		)


func test_dev_flags_override_menu() -> void:
	# П11 1.2: --simple-graphics / --high-quality / --ultra-quality (Settings)
	# перекрывают пункт меню — какой бы ни был выбран.
	_write_menu_quality(3)
	Settings.simple_graphics = true
	assert_eq(
		GraphicsQuality.tier_from_settings(), GraphicsQuality.Tier.SIMPLE,
		"--simple-graphics перекрывает меню «Ультра»",
	)
	Settings.simple_graphics = false

	_write_menu_quality(0)
	Settings.high_quality = true
	assert_eq(
		GraphicsQuality.tier_from_settings(), GraphicsQuality.Tier.HIGH,
		"--high-quality перекрывает меню «Низкое»",
	)

	Settings.ultra_quality = true
	assert_eq(
		GraphicsQuality.tier_from_settings(), GraphicsQuality.Tier.ULTRA,
		"--ultra-quality сильнее --high-quality",
	)
	Settings.high_quality = false
	assert_eq(
		GraphicsQuality.tier_from_settings(), GraphicsQuality.Tier.ULTRA,
		"--ultra-quality перекрывает меню «Низкое»",
	)


func test_old_cfg_without_quality_is_high() -> void:
	# П11 1.4: старый cfg без ключа quality — «Высокое», как в DEFAULTS меню.
	_write_menu_quality(null)
	assert_eq(
		GraphicsQuality.menu_tier(), GraphicsQuality.Tier.HIGH,
		"cfg без ключа quality — «Высокое»",
	)
	# Некорректное значение (не int) не ломает выбор — тоже «Высокое».
	var broken := ConfigFile.new()
	broken.set_value(
		MenuSettingsBU.SECTION, GraphicsQuality.MENU_KEY_QUALITY, "high")
	broken.save(MenuSettingsBU.SAVE_PATH)
	assert_eq(
		GraphicsQuality.menu_tier(), GraphicsQuality.Tier.HIGH,
		"нечисловой quality — «Высокое»",
	)
	# Отсутствующий cfg — то же «Высокое» (DEFAULTS меню).
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MenuSettingsBU.SAVE_PATH))
	assert_eq(
		GraphicsQuality.menu_tier(), GraphicsQuality.Tier.HIGH,
		"нет cfg — «Высокое»",
	)


func test_ultra_tier_reaches_world() -> void:
	# П11, каркас: выбранный в меню «Ультра» доезжает до мира как Tier.ULTRA
	# (полный «Ультра»-рендер применит к нему свои эффекты в bu-gfx).
	_write_menu_quality(3)
	assert_eq(
		GraphicsQuality.tier_from_settings(), GraphicsQuality.Tier.ULTRA,
		"меню «Ультра» даёт уровень ULTRA",
	)


func test_ultra_applies_as_high_for_now() -> void:
	# П11 раздел 2, ветка bu-gfx: HIGH и ULTRA различаются только
	# «Ультра»-набором (SDFGI, SSIL, SSR, SMAA, тени 8192) — общая для
	# уровней картинка (постобработка, туман, MSAA) совпадает.
	_write_menu_quality(3)
	var envs: Array[Environment] = [Environment.new(), Environment.new()]
	var suns: Array[DirectionalLight3D] = [DirectionalLight3D.new(), DirectionalLight3D.new()]
	var moons: Array[DirectionalLight3D] = [
		DirectionalLight3D.new(), DirectionalLight3D.new(),
	]
	var viewports: Array[Viewport] = [SubViewport.new(), SubViewport.new()]
	GraphicsQuality.apply(envs[0], suns[0], GraphicsQuality.Tier.HIGH,
		viewports[0], moons[0])
	GraphicsQuality.apply(envs[1], suns[1], GraphicsQuality.Tier.ULTRA,
		viewports[1], moons[1])
	var props: Array[String] = [
		"ssao_enabled", "ssao_intensity", "ssao_radius",
		"glow_enabled", "glow_intensity", "glow_strength", "glow_bloom",
		"glow_blend_mode", "volumetric_fog_enabled", "volumetric_fog_density",
	]
	for p: String in props:
		assert_eq(
			envs[1].get(p), envs[0].get(p),
			"ULTRA: env.%s как в HIGH (общая картинка)" % p,
		)
	assert_eq(
		suns[1].shadow_enabled, suns[0].shadow_enabled,
		"ULTRA: тени солнца как в HIGH",
	)
	assert_eq(
		suns[1].light_volumetric_fog_energy, suns[0].light_volumetric_fog_energy,
		"ULTRA: вклад солнца в туман как в HIGH",
	)
	assert_eq(
		moons[1].shadow_enabled, moons[0].shadow_enabled,
		"ULTRA: тени луны как в HIGH",
	)
	assert_eq(
		viewports[1].msaa_3d, viewports[0].msaa_3d,
		"ULTRA: MSAA как в HIGH",
	)
	assert_eq(
		viewports[1].texture_mipmap_bias, viewports[0].texture_mipmap_bias,
		"ULTRA: смещение мипов как в HIGH",
	)
	for i: int in envs.size():
		# Environment — RefCounted, освобождается сам; чистим только ноды.
		suns[i].free()
		moons[i].free()
		viewports[i].free()


func test_ultra_enables_gi_and_reflections() -> void:
	# П11 2.1–2.3: на ULTRA включаются SDFGI (глобальное освещение),
	# SSIL (отражённый свет) и SSR (отражения), числа — константы
	# graphics_quality.gd («подбирает владелец»).
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	var moon := DirectionalLight3D.new()
	var viewport := SubViewport.new()
	GraphicsQuality.apply(env, sun, GraphicsQuality.Tier.ULTRA, viewport, moon)
	# SDFGI (2.1).
	assert_true(env.sdfgi_enabled, "ULTRA: SDFGI включён")
	assert_between(
		env.sdfgi_cascades, 4, 6, "ULTRA: каскады SDFGI 4–6 (2.1)")
	assert_true(env.sdfgi_use_occlusion, "ULTRA: окклюзия SDFGI")
	assert_true(env.sdfgi_read_sky_light, "ULTRA: SDFGI читает свет неба")
	assert_almost_eq(
		env.sdfgi_bounce_feedback, GraphicsQuality.ULTRA_SDFGI_BOUNCE_FEEDBACK,
		0.001, "ULTRA: отскок SDFGI ≈ 0.5")
	assert_almost_eq(
		env.sdfgi_energy, GraphicsQuality.ULTRA_SDFGI_ENERGY, 0.001,
		"ULTRA: энергия SDFGI (день; ночь ведёт DayCycle)")
	# SSIL (2.2).
	assert_true(env.ssil_enabled, "ULTRA: SSIL включён")
	assert_almost_eq(
		env.ssil_intensity, GraphicsQuality.ULTRA_SSIL_INTENSITY, 0.001,
		"ULTRA: интенсивность SSIL ≈ 1.0")
	assert_almost_eq(
		env.ssil_radius, GraphicsQuality.ULTRA_SSIL_RADIUS, 0.001,
		"ULTRA: радиус SSIL ≈ 5")
	# SSR (2.3).
	assert_true(env.ssr_enabled, "ULTRA: SSR включён")
	assert_eq(
		env.ssr_max_steps, 64, "ULTRA: шаги трассировки SSR 64")
	assert_almost_eq(
		env.ssr_fade_in, GraphicsQuality.ULTRA_SSR_FADE_IN, 0.001,
		"ULTRA: fade_in SSR умеренный")
	assert_almost_eq(
		env.ssr_fade_out, GraphicsQuality.ULTRA_SSR_FADE_OUT, 0.001,
		"ULTRA: fade_out SSR умеренный")
	sun.free()
	moon.free()
	viewport.free()


func test_ultra_shadows_aa_and_lod() -> void:
	# П11 2.5 (светила), 2.7 (сглаживание) и 2.8 (детализация): 4 сплита
	# PSSM, угловое расхождение 0.5°, дальность теней 200 м; MSAA 4x
	# плюс SMAA (TAA выключен); модели полной детализации; атлас теней
	# точечных источников — 8192.
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	var moon := DirectionalLight3D.new()
	var viewport := SubViewport.new()
	GraphicsQuality.apply(env, sun, GraphicsQuality.Tier.ULTRA, viewport, moon)
	for light: DirectionalLight3D in [sun, moon]:
		assert_eq(
			light.directional_shadow_mode,
			DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
			"ULTRA: солнце/луна — 4 сплита PSSM")
		assert_almost_eq(
			light.light_angular_distance,
			GraphicsQuality.ULTRA_LIGHT_ANGULAR_DISTANCE, 0.001,
			"ULTRA: угловое расхождение светила ≈ 0.5° (мягкий полутон)")
		assert_almost_eq(
			light.directional_shadow_max_distance,
			GraphicsQuality.ULTRA_SHADOW_MAX_DISTANCE, 0.001,
			"ULTRA: дальность теней светил 200 м")
	assert_true(sun.shadow_enabled, "ULTRA: тени солнца включены")
	assert_true(moon.shadow_enabled, "ULTRA: тени луны включены")
	assert_eq(
		viewport.msaa_3d, Viewport.MSAA_4X, "ULTRA: MSAA 4x")
	assert_eq(
		viewport.screen_space_aa, Viewport.SCREEN_SPACE_AA_SMAA,
		"ULTRA: screen-space AA — SMAA")
	assert_false(viewport.use_taa, "ULTRA: TAA выключен (резкое небо)")
	assert_almost_eq(
		viewport.mesh_lod_threshold, 0.0, 0.001,
		"ULTRA: порог LOD 0 — полная детализация моделей")
	assert_eq(
		viewport.positional_shadow_atlas_size,
		GraphicsQuality.ULTRA_POSITIONAL_ATLAS_SIZE,
		"ULTRA: атлас теней точечных источников 8192")
	sun.free()
	moon.free()
	viewport.free()


func test_switching_levels_disables_ultra() -> void:
	# П11 2.10: уход с ULTRA выключает «Ультра»-набор начисто — на HIGH
	# возвращаются базовые (движковые) значения, на SIMPLE дополнительно
	# гаснут тени, MSAA и постобработка.
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	var moon := DirectionalLight3D.new()
	var viewport := SubViewport.new()
	GraphicsQuality.apply(env, sun, GraphicsQuality.Tier.ULTRA, viewport, moon)
	GraphicsQuality.apply(env, sun, GraphicsQuality.Tier.HIGH, viewport, moon)
	assert_false(env.sdfgi_enabled, "ULTRA→HIGH: SDFGI выключен")
	assert_false(env.ssil_enabled, "ULTRA→HIGH: SSIL выключен")
	assert_false(env.ssr_enabled, "ULTRA→HIGH: SSR выключен")
	assert_almost_eq(
		env.sdfgi_energy, GraphicsQuality.SDFGI_ENERGY_BASE, 0.001,
		"ULTRA→HIGH: энергия SDFGI — база")
	assert_almost_eq(
		sun.light_angular_distance,
		GraphicsQuality.LIGHT_ANGULAR_DISTANCE_BASE, 0.001,
		"ULTRA→HIGH: угловое расхождение светила — база")
	assert_almost_eq(
		sun.directional_shadow_max_distance,
		GraphicsQuality.SHADOW_MAX_DISTANCE_BASE, 0.001,
		"ULTRA→HIGH: дальность теней — база")
	assert_almost_eq(
		viewport.mesh_lod_threshold, GraphicsQuality.MESH_LOD_THRESHOLD_BASE,
		0.001, "ULTRA→HIGH: порог LOD — база")
	assert_eq(
		viewport.positional_shadow_atlas_size,
		GraphicsQuality.POSITIONAL_ATLAS_SIZE_BASE,
		"ULTRA→HIGH: атлас точечных теней — база (2048)")
	assert_eq(
		viewport.screen_space_aa, Viewport.SCREEN_SPACE_AA_FXAA,
		"ULTRA→HIGH: screen-space AA — FXAA, как был до «Ультра»")
	GraphicsQuality.apply(env, sun, GraphicsQuality.Tier.SIMPLE, viewport, moon)
	assert_false(env.sdfgi_enabled, "ULTRA→SIMPLE: SDFGI выключен")
	assert_false(env.ssil_enabled, "ULTRA→SIMPLE: SSIL выключен")
	assert_false(env.ssr_enabled, "ULTRA→SIMPLE: SSR выключен")
	assert_false(sun.shadow_enabled, "ULTRA→SIMPLE: тени выключены")
	assert_false(moon.shadow_enabled, "ULTRA→SIMPLE: тени луны выключены")
	assert_eq(
		viewport.msaa_3d, Viewport.MSAA_DISABLED, "ULTRA→SIMPLE: MSAA выключен")
	assert_eq(
		viewport.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED,
		"ULTRA→SIMPLE: screen-space AA выключен")
	sun.free()
	moon.free()
	viewport.free()


func test_taa_disabled_on_all_levels() -> void:
	# П11 2.7: TAA не включается ни на одном уровне — владелец утвердил
	# резкое небо и звёзды (test_sky_stays_sharp).
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	var viewport := SubViewport.new()
	for tier: int in [
		GraphicsQuality.Tier.SIMPLE, GraphicsQuality.Tier.NORMAL,
		GraphicsQuality.Tier.HIGH, GraphicsQuality.Tier.ULTRA,
	]:
		GraphicsQuality.apply(env, sun, tier, viewport)
		assert_false(
			viewport.use_taa, "уровень %d: TAA выключен" % tier)
	sun.free()
	viewport.free()


func test_sdfgi_energy_dimmer_at_night() -> void:
	# П11 2.1: ночь остаётся тёмной — на ULTRA DayCycle приглушает
	# sdfgi_energy по dayness (как экспозицию): днём полная, глубокой
	# ночью — NIGHT_ENERGY; без SDFGI энергия не трогается.
	var sky := Sky3D.new()
	add_child(sky)
	var cycle := DayCycle.new()
	cycle.setup(sky.sun, sky)
	var saved := Session.world_time
	sky.environment.sdfgi_enabled = true
	sky.environment.sdfgi_energy = GraphicsQuality.ULTRA_SDFGI_ENERGY
	Session.world_time = 0.3 * B.day_cycle_sec  # полдень
	cycle._process(0.0)
	var day_energy: float = sky.environment.sdfgi_energy
	Session.world_time = 0.8 * B.day_cycle_sec  # глубокая ночь
	cycle._process(0.0)
	var night_energy: float = sky.environment.sdfgi_energy
	assert_almost_eq(
		day_energy, GraphicsQuality.ULTRA_SDFGI_ENERGY, 0.001,
		"днём энергия SDFGI полная")
	assert_almost_eq(
		night_energy, GraphicsQuality.ULTRA_SDFGI_NIGHT_ENERGY, 0.001,
		"ночью энергия SDFGI приглушена (тёмная ночь)")
	assert_lt(
		night_energy, day_energy * 0.5,
		"ночь с SDFGI заметно темнее дня")
	# Не-ULTRA: SDFGI выключен — цикл не трогает энергию.
	sky.environment.sdfgi_enabled = false
	sky.environment.sdfgi_energy = 1.0
	cycle._process(0.0)
	assert_almost_eq(
		sky.environment.sdfgi_energy, 1.0, 0.001,
		"без SDFGI цикл энергию не меняет")
	Session.world_time = saved
	cycle.free()
	sky.free()


func test_cabin_ultra_probes_and_torch_shadows() -> void:
	# П11 2.5/2.9: на ULTRA у сруба включаются тени ламп-«факелов»
	# (крыльцо, крыло, зал) и в комнатах появляются пробы отражений
	# (UPDATE_ONCE, коробочная проекция); уход с «Ультра» выключает
	# всё начисто (2.10) — проб в дереве нет, тени выключены.
	var cabin := CabinHouse.new()
	add_child(cabin)  # _ready → _build грузит модель и ставит лампы
	assert_true(
		cabin.is_in_group(CabinHouse.GROUP),
		"сруб регистрируется в группе для применения уровня миром")
	cabin.set_ultra(true)
	var wing := cabin.get_node_or_null("WingProbe") as ReflectionProbe
	var hall := cabin.get_node_or_null("HallProbe") as ReflectionProbe
	assert_not_null(wing, "ULTRA: проба отражений в крыле у входа")
	assert_not_null(hall, "ULTRA: проба отражений в зале")
	for probe: ReflectionProbe in [wing, hall]:
		assert_eq(
			probe.update_mode, ReflectionProbe.UPDATE_ONCE,
			"%s: печётся один раз (интерьер статичен)" % probe.name)
		assert_true(
			probe.box_projection,
			"%s: коробочная проекция (отражение внутри стен)" % probe.name)
	var lights: Array[OmniLight3D] = []
	for child: Node in cabin.get_children():
		var light := child as OmniLight3D
		if light != null:
			lights.append(light)
	assert_eq(lights.size(), 3, "у сруба три лампы-«факела»")
	for light: OmniLight3D in lights:
		assert_true(
			light.shadow_enabled,
			"ULTRA: тени лампы %s включены" % light.name)
	cabin.set_ultra(false)
	assert_null(
		cabin.get_node_or_null("WingProbe"), "уход с ULTRA: пробы крыла нет")
	assert_null(
		cabin.get_node_or_null("HallProbe"), "уход с ULTRA: пробы зала нет")
	for light: OmniLight3D in lights:
		assert_false(
			light.shadow_enabled,
			"уход с ULTRA: тени лампы %s выключены" % light.name)
	# Возвращение на ULTRA после выключения снова ставит пробы.
	cabin.set_ultra(true)
	assert_not_null(
		cabin.get_node_or_null("WingProbe"),
		"повторный ULTRA: проба крыла возвращается")
	cabin.free()
