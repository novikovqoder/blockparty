extends GutTest
## Интеграция меню Born Unblessed (П9): обвязка main_menu_game строит сцену
## комплекта, переводы BU_* подключены, аудиошины из default_bus_layout.tres
## на месте, старт в GUT-окружении идёт напрямую в мир (нет Steam/сети).

const WRAPPER_SCENE: String = "res://scenes/main_menu_game.tscn"


func before_each() -> void:
	if FileAccess.file_exists(MenuSettingsBU.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MenuSettingsBU.SAVE_PATH))


func test_wrapper_builds_kit_scene() -> void:
	# Доработка П9: «Продолжить» строится только по флагу сессии — счёт
	# кнопок проверяем в обоих состояниях (детерминированно, независимо
	# от порядка прогонов других тестов).
	var was_played: bool = Session.played
	Session.played = false
	var fresh: MainMenuGame = (load(WRAPPER_SCENE) as PackedScene).instantiate() as MainMenuGame
	assert_not_null(fresh, "обвязка создаётся")
	add_child_autofree(fresh)
	await wait_physics_frames(2)
	var menu: MainMenuBU = fresh.get_node_or_null("MainMenuBU") as MainMenuBU
	assert_not_null(menu, "сцена комплекта инстанцирована")
	assert_eq(menu.section, MainMenuBU.Section.MAIN, "после загрузки — главный раздел")
	assert_eq(menu.find_children("Btn_*", "MenuButtonBU", true, false).size(), 7,
		"первый запуск: 7 кнопок, «Продолжить» скрыт")
	Session.played = true
	var back: MainMenuGame = (load(WRAPPER_SCENE) as PackedScene).instantiate() as MainMenuGame
	assert_not_null(back, "обвязка создаётся")
	add_child_autofree(back)
	await wait_physics_frames(2)
	var menu_back: MainMenuBU = back.get_node_or_null("MainMenuBU") as MainMenuBU
	assert_eq(menu_back.find_children("Btn_*", "MenuButtonBU", true, false).size(), 8,
		"после возврата из мира: все 8 кнопок меню на месте")
	Session.played = was_played


func test_start_goes_direct_without_steam() -> void:
	var packed: PackedScene = load(WRAPPER_SCENE) as PackedScene
	var wrapper: MainMenuGame = packed.instantiate() as MainMenuGame
	add_child_autofree(wrapper)
	await wait_physics_frames(2)
	assert_false(Net.is_networked(), "в тестах сети нет")
	assert_false(SteamService.available, "в тестах Steam нет")
	assert_true(wrapper._start_goes_direct(), "офлайн-старт ведёт сразу в мир")


func test_bu_translations_loaded() -> void:
	var prev_locale: String = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	assert_eq(tr("BU_MENU_NEW"), "НОВАЯ ИГРА", "русский перевод BU есть")
	assert_eq(tr("BU_CH_2"), "Собор Святого Ордена")
	TranslationServer.set_locale("en")
	assert_eq(tr("BU_MENU_NEW"), "NEW GAME", "английский перевод BU есть")
	TranslationServer.set_locale(prev_locale)


func test_audio_buses_for_menu_settings() -> void:
	# Громкости меню (П9) крутят Master/Music/SFX/Ambient/Voice — шины должны
	# существовать и сливаться в Master.
	for bus_name: String in ["Master", "Music", "SFX", "Ambient", "Voice"]:
		assert_true(AudioServer.get_bus_index(bus_name) >= 0, "шина %s есть" % bus_name)
	for bus_name: String in ["Music", "SFX", "Ambient", "Voice"]:
		var idx: int = AudioServer.get_bus_index(bus_name)
		assert_eq(AudioServer.get_bus_send(idx), "Master", "%s выводится в Master" % bus_name)


# --- «Выход» (фикс после приёмки П9): цепочка не должна обрываться -----------


## Обвязка слушает quit_requested кита: раньше сигнал никто не слушал, выход
## держался только на твине кита и обрывался (пауза дерева, гибель твина).
func test_wrapper_listens_quit_requested() -> void:
	var wrapper: MainMenuGame = (load(WRAPPER_SCENE) as PackedScene).instantiate() as MainMenuGame
	add_child_autofree(wrapper)
	await wait_physics_frames(2)
	var heard: bool = false
	for c: Dictionary in wrapper._menu.quit_requested.get_connections():
		if c["callable"].get_object() == wrapper:
			heard = true
	assert_true(heard, "quit_requested подключён к самой обвязке (_on_quit_requested)")


## Полный путь «Выход → процесс закрылся»: отдельный headless-прогон с
## настоящим get_tree().quit() и кодом возврата (tools/probe_quit_menu.gd).
## Кейсы: обычное встроенное меню и меню при паузе дерева («вышел из мира,
## пауза осталась»). Steam-ветку (steamShutdown перед quit) здесь проверить
## нельзя — Steam-клиента нет, см. STATUS.md «что проверить вручную».
func test_quit_button_closes_process_in_headless_run() -> void:
	var godot_path: String = OS.get_executable_path()
	var project: String = ProjectSettings.globalize_path("res://")
	for mode: Array in [["--embedded"], ["--embedded", "--paused"]]:
		var args: PackedStringArray = PackedStringArray(
			["--headless", "--path", project, "-s", "res://tools/probe_quit_menu.gd", "--"] + mode)
		var output: Array = []
		var code: int = OS.execute(godot_path, args, output)
		assert_eq(code, 0, "режим %s: процесс завершился сам — quit сработал" % str(mode))
