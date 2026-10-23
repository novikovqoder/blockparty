extends GutTest
## Тесты главного меню Born Unblessed: загрузка сцены, переходы между разделами,
## настройки (сохранение/сброс), строки перевода и запуск игры.

const SCENE: String = "res://scenes/menu_bu/main_menu_bu.tscn"
const CSV: String = "res://i18n/strings_bu.csv"

var _menu: MainMenuBU


func before_each() -> void:
	if FileAccess.file_exists(MenuSettingsBU.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MenuSettingsBU.SAVE_PATH))
	var packed: PackedScene = load(SCENE) as PackedScene
	_menu = packed.instantiate() as MainMenuBU
	add_child_autofree(_menu)
	await wait_physics_frames(2)


func after_all() -> void:
	if FileAccess.file_exists(MenuSettingsBU.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MenuSettingsBU.SAVE_PATH))


func test_scene_builds_layers_and_menu() -> void:
	assert_not_null(_menu, "сцена создаётся")
	assert_not_null(_menu.bg_texture, "фон назначен")
	assert_not_null(_menu.knight_texture, "рыцарь назначен")
	var buttons: Array[Node] = _menu.find_children("Btn_*", "MenuButtonBU", true, false)
	# 6 пунктов главного меню + «Назад» в Авторах и Главах.
	assert_eq(buttons.size(), 8, "все кнопки меню на месте")
	assert_eq(_menu.section, MainMenuBU.Section.MAIN)


func test_every_section_has_a_camera_shot() -> void:
	for k: StringName in [&"intro", &"main", &"settings", &"credits", &"chapters", &"knight"]:
		assert_true(_menu.shots.has(k), "есть кадр камеры: %s" % k)


func test_open_sections_and_back() -> void:
	_menu.open_section(MainMenuBU.Section.SETTINGS)
	await wait_seconds(1.2)
	assert_eq(_menu.current_shot_name(), &"settings")
	var settings: SettingsPanelBU = _menu.find_children("*", "SettingsPanelBU", true, false)[0] as SettingsPanelBU
	assert_true(settings.visible, "панель настроек видна")
	_menu.open_section(MainMenuBU.Section.CREDITS)
	await wait_seconds(1.2)
	assert_eq(_menu.current_shot_name(), &"credits")
	assert_false(settings.visible, "настройки скрыты в Авторах")
	_menu.open_section(MainMenuBU.Section.MAIN)
	assert_eq(_menu.section, MainMenuBU.Section.MAIN)


func test_settings_store_roundtrip_and_reset() -> void:
	var s: MenuSettingsBU = MenuSettingsBU.new()
	s.set_value(&"music", 25)
	s.set_value(&"gore", 0)
	assert_true(s.dirty)
	assert_eq(s.save_to_disk(), OK)
	var s2: MenuSettingsBU = MenuSettingsBU.new()
	s2.load_from_disk()
	assert_eq(s2.get_int(&"music"), 25)
	assert_eq(s2.get_int(&"gore"), 0)
	s2.reset_keys([&"music"])
	assert_eq(s2.get_int(&"music"), int(MenuSettingsBU.DEFAULTS[&"music"]))
	assert_eq(s2.get_int(&"gore"), 0, "сброс раздела не трогает чужие ключи")


func test_settings_rows_cycle_values() -> void:
	var settings: SettingsPanelBU = _menu.find_children("*", "SettingsPanelBU", true, false)[0] as SettingsPanelBU
	settings.show_tab(&"game")
	var rows: Array[Node] = settings.find_children("*", "SettingsRowBU", true, false)
	assert_eq(rows.size(), SettingsPanelBU.SCHEMA[&"game"].size(), "строк столько же, сколько в схеме")
	var diff: SettingsRowBU = rows[0] as SettingsRowBU
	assert_eq(diff.key, &"diff")
	var before: int = _menu.settings_store.get_int(&"diff")
	diff.step(1)
	assert_eq(_menu.settings_store.get_int(&"diff"), (before + 1) % 3)
	diff.step(-1)
	diff.step(-1)
	assert_eq(_menu.settings_store.get_int(&"diff"), posmod(before - 1, 3), "значения листаются по кругу")


func test_all_schema_keys_are_translated() -> void:
	var f: FileAccess = FileAccess.open(CSV, FileAccess.READ)
	assert_not_null(f, "файл строк есть")
	var keys: Dictionary[String, bool] = {}
	f.get_csv_line()
	while not f.eof_reached():
		var line: PackedStringArray = f.get_csv_line()
		if line.size() >= 3 and line[0] != "":
			keys[line[0]] = true
			assert_ne(line[1], "", "есть русский текст для %s" % line[0])
			assert_ne(line[2], "", "есть английский текст для %s" % line[0])
	var used: Array[String] = []
	for tab: StringName in SettingsPanelBU.SCHEMA.keys():
		used.append(SettingsPanelBU.TAB_LABELS[tab])
		for d: Variant in SettingsPanelBU.SCHEMA[tab]:
			var def: Dictionary = d as Dictionary
			for field: String in ["label", "desc", "warn", "value"]:
				used.append(String(def.get(field, "")))
			for list_field: String in ["opts", "descs"]:
				var arr: Array = def.get(list_field, [])
				for v: Variant in arr:
					used.append(String(v))
	for k: String in used:
		if k.begins_with("BU_"):
			assert_true(keys.has(k), "ключ перевода есть в CSV: %s" % k)


func test_continue_zooms_to_knight_and_emits_start() -> void:
	watch_signals(_menu)
	_menu.call("_start", &"continue")
	assert_eq(_menu.section, MainMenuBU.Section.STARTING)
	await wait_seconds(3.3)
	assert_signal_emitted_with_parameters(_menu, "start_requested", [&"continue"])
