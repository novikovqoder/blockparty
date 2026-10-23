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
	# Первый запуск («Продолжить» скрыт): 5 пунктов + «Назад» в Авторах и Главах.
	assert_eq(buttons.size(), 7, "кнопки меню на месте, «Продолжить» скрыт")
	assert_false(_menu.has_node("Btn_continue_path"), "пункта «Продолжить» нет")
	assert_eq(_menu._first_button.name, "Btn_new", "фокус на «Новой игре»")
	assert_eq(_menu.section, MainMenuBU.Section.MAIN)


## «Продолжить» появляется по флагу сессии: до входа в мир пункта нет,
## после «начал игру → вышел в меню» (Session.played) — есть.
func test_continue_item_follows_session_played_flag() -> void:
	var was_played: bool = Session.played
	# Комплект сам по себе показывает пункт только с has_save=true.
	var kit: MainMenuBU = (load(SCENE) as PackedScene).instantiate() as MainMenuBU
	kit.has_save = true
	add_child_autofree(kit)
	await wait_physics_frames(2)
	assert_eq(kit.find_children("Btn_continue", "MenuButtonBU", true, false).size(), 1,
		"с has_save=true пункт «Продолжить» есть")
	# Обвязка игры читает флаг сессии.
	Session.played = false
	var wrap_fresh: MainMenuGame = (load("res://scenes/main_menu_game.tscn") as PackedScene).instantiate() as MainMenuGame
	add_child_autofree(wrap_fresh)
	await wait_physics_frames(2)
	assert_eq(wrap_fresh._menu.find_children("Btn_continue", "MenuButtonBU", true, false).size(), 0,
		"первый запуск: «Продолжить» скрыт")
	Session.played = true
	var wrap_back: MainMenuGame = (load("res://scenes/main_menu_game.tscn") as PackedScene).instantiate() as MainMenuGame
	add_child_autofree(wrap_back)
	await wait_physics_frames(2)
	assert_eq(wrap_back._menu.find_children("Btn_continue", "MenuButtonBU", true, false).size(), 1,
		"после возврата из мира: «Продолжить» есть")
	Session.played = was_played


## Session.enter_world() поднимает флаг для «Продолжить».
func test_session_enter_world_sets_played() -> void:
	var was_played: bool = Session.played
	var was_in_world: bool = Session.in_world
	Session.played = false
	Session.in_world = false
	Session.enter_world()
	assert_true(Session.played, "вход в мир поднимает флаг сессии")
	Session.played = was_played
	Session.in_world = was_in_world


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


# --- Раскладка (доработка после приёмки П9): подсказки не наезжают ----------
# Канва меню при stretch canvas_items всегда 1280×720 (keep_height):
# подсказки внизу каждого раздела не должны пересекать пункты и контент.
# Проверяются фактические глобальные прямоугольники после показа раздела
# (твин показа ~0.6 с — ждём секунду).


## Все видимые Control-текстовые узлы поддерева (кроме самой полосы подсказок).
func _visible_texts(node: Node, skip: Array[Control], out: Array[Control]) -> void:
	for child in node.get_children():
		_visible_texts(child, skip, out)
	var c := node as Control
	if c == null or not c.is_visible_in_tree():
		return
	if not (c is Button or c is Label or c is SettingsRowBU):
		return
	for s in skip:
		if c == s or s.is_ancestor_of(c):
			return
	out.append(c)


func _assert_no_overlap(hints: Control, content: Array[Control], where: String) -> void:
	var hrect: Rect2 = hints.get_global_rect()
	for c in content:
		var r: Rect2 = c.get_global_rect()
		assert_false(hrect.intersects(r, true),
			"%s: подсказки [%s] не пересекают %s [%s]" % [
				where, hrect, c.name, r])


func _hints_of(panel: Control) -> Control:
	var found: Array[Node] = panel.find_children("BarHints", "HBoxContainer", true, false)
	assert_eq(found.size(), 1, "%s: полоса подсказок одна" % panel.name)
	return found[0] as Control


func test_main_menu_hints_do_not_overlap_items() -> void:
	await wait_seconds(1.0)
	var hints: Control = _hints_of(_menu._main_panel)
	var items: Array[Control] = []
	for b in _menu.find_children("Btn_*", "MenuButtonBU", true, false):
		var btn := b as Control
		if btn.is_visible_in_tree():
			items.append(btn)
	assert_gte(items.size(), 5, "пункты главного меню на месте")
	_assert_no_overlap(hints, items, "главное меню")


func test_settings_panel_layout_within_canvas() -> void:
	_menu.open_section(MainMenuBU.Section.SETTINGS)
	await wait_seconds(1.2)
	var settings: SettingsPanelBU = _menu.find_children("*", "SettingsPanelBU", true, false)[0] as SettingsPanelBU
	var hints: Control = _hints_of(settings)
	var desc: Control = settings.find_children("Desc", "VBoxContainer", true, false)[0] as Control
	var scroll: Control = settings.find_children("RowsScroll", "ScrollContainer", true, false)[0] as Control
	# Описание вернулось на экран канвы 720 и не залезает под полосу подсказок.
	assert_lt(desc.get_global_rect().end.y, hints.get_global_rect().position.y,
		"описание выше полосы подсказок")
	var content: Array[Control] = [scroll, desc]
	_assert_no_overlap(hints, content, "настройки")


func test_credits_panel_hints_do_not_overlap_entries() -> void:
	_menu.open_section(MainMenuBU.Section.CREDITS)
	await wait_seconds(1.2)
	var hints: Control = _hints_of(_menu._credits_panel)
	var col: Control = _menu._credits_panel.find_children("CreditsCol", "VBoxContainer", true, false)[0] as Control
	var entries: Array[Control] = []
	for child in col.get_children():
		if child is Label:
			entries.append(child as Control)
	# Все 7 записей (роль + имя) полностью над полосой «Esc — назад».
	assert_gte(entries.size(), 14, "записи авторов на месте")
	for e in entries:
		assert_lt(e.get_global_rect().end.y, hints.get_global_rect().position.y,
			"%s: запись выше полосы подсказок" % e.text)


func test_chapters_panel_layout_no_overlaps() -> void:
	_menu.open_section(MainMenuBU.Section.CHAPTERS)
	await wait_seconds(1.2)
	var hints: Control = _hints_of(_menu._chapters_panel)
	var row: Control = _menu._chapters_panel.find_children("ChaptersRow", "HBoxContainer", true, false)[0] as Control
	var head: Control = _menu._chapters_panel.find_children("ChaptersHead", "VBoxContainer", true, false)[0] as Control
	_assert_no_overlap(hints, [row], "главы: карточки против полосы")
	assert_false(head.get_global_rect().intersects(row.get_global_rect(), true),
		"главы: заголовок не пересекает карточки")
