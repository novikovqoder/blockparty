# Boot-экран: ждёт результата инициализации Steam и решает, куда идти —
# в главное меню или в окно офлайн-режима (раздел 13 SPEC, экран Boot).
# В dev-режиме (--dev-host/--dev-join) Steam не используется вовсе — сразу в меню.
# Меню — Born Unblessed (П9); прежнее меню Blockparty вычищено (born-unblessed).
# Вид — BootScreenBU (П10): прежние «Blockparty» и серый фон ушли, логика
# проверки Steam не меняется — кит показывает статус и окно «Steam не запущен».
extends Control

@onready var _screen: BootScreenBU = $BootScreenBU


func _ready() -> void:
	# П10: заголовок окна — Born Unblessed. application/config/name не трогаем:
	# от него зависят пути user:// (app_userdata/Blockparty) — меняется только титул.
	DisplayServer.window_set_title("Born Unblessed")
	Log.info("Boot: экран загрузки")
	_screen.offline_requested.connect(_on_play_offline_pressed)
	_screen.quit_requested.connect(_on_quit_pressed)
	if Dev.host_mode or Dev.join_address != "":
		Log.info("Boot: режим разработки ENet — Steam не нужен, вхожу в меню", "Boot")
		_go_to_menu()
	elif SteamService.available:
		_go_to_menu()
	elif Session.bot or Session.selftest_anim or Session.selftest_world:
		# Headless-бот без Steam: кнопки жать некому — продолжаем офлайн.
		# Самопроверки (--selftest-anim, --selftest-world) — тот же случай.
		Log.info("Boot: Steam нет, бот/самопроверка продолжает офлайн", "Boot")
		_go_to_menu()
	else:
		# SteamService уже выяснил причину и залогировал её.
		_screen.show_steam_missing()


func _go_to_menu() -> void:
	# Отложенно: из _ready дерево занято добавлением детей.
	get_tree().call_deferred("change_scene_to_file", Dev.MENU_SCENE)


func _on_play_offline_pressed() -> void:
	Log.info("Boot: выбран офлайн-режим (разработка, ENet)")
	_go_to_menu()


func _on_quit_pressed() -> void:
	get_tree().quit()
