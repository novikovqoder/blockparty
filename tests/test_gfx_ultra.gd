# Тесты П11 «Графика на максимум», первая часть — каркас «меню → мир»:
# пункт меню «Качество графики» (0–3) задаёт уровень мира, dev-флаги имеют
# приоритет над меню, старый cfg без ключа quality даёт «Высокое», а уровень
# «Ультра» пока применяется как «Высокое» (полный «Ультра»-рендер — SDFGI,
# SSIL, SSR, тени 8192, SMAA — следующий этап, ветка bu-gfx; эти тесты
# дополнятся там).
extends GutTest

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
	# П11, каркас: на этом этапе «Ультра» применяется как «Высокое» — все
	# свойства, которыми различаются уровни, у ULTRA совпадают с HIGH
	# (SDFGI/SSIL/SSR/SMAA добавит ULTRA-рендер в ветке bu-gfx).
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
			"ULTRA: env.%s как в HIGH (пока)" % p,
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
		viewports[1].screen_space_aa, viewports[0].screen_space_aa,
		"ULTRA: screen-space AA как в HIGH",
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
