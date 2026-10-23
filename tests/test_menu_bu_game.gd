extends GutTest
## Интеграция меню Born Unblessed (П9): обвязка main_menu_game строит сцену
## комплекта, переводы BU_* подключены, аудиошины из default_bus_layout.tres
## на месте, старт в GUT-окружении идёт напрямую в мир (нет Steam/сети).

const WRAPPER_SCENE: String = "res://scenes/main_menu_game.tscn"


func before_each() -> void:
	if FileAccess.file_exists(MenuSettingsBU.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MenuSettingsBU.SAVE_PATH))


func test_wrapper_builds_kit_scene() -> void:
	var packed: PackedScene = load(WRAPPER_SCENE) as PackedScene
	assert_not_null(packed, "сцена-обвязка есть")
	var wrapper: MainMenuGame = packed.instantiate() as MainMenuGame
	assert_not_null(wrapper, "обвязка создаётся")
	add_child_autofree(wrapper)
	await wait_physics_frames(2)
	var menu: MainMenuBU = wrapper.get_node_or_null("MainMenuBU") as MainMenuBU
	assert_not_null(menu, "сцена комплекта инстанцирована")
	assert_eq(menu.section, MainMenuBU.Section.MAIN, "после загрузки — главный раздел")
	var buttons: Array[Node] = menu.find_children("Btn_*", "MenuButtonBU", true, false)
	assert_eq(buttons.size(), 8, "все кнопки меню на месте")


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
