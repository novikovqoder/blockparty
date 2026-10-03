# Главное меню (разделы 11, 15 SPEC): «В мир» — быстрый вход в Steam-мир
# (поиск публичного, иначе свой; раздел 11), «Мир для друзей» — лобби только
# для друзей с приглашением через оверлей. Вход по приглашению (lobby_invite)
# и по +connect_lobby из командной строки запускается отсюда сам. Как только
# транспорт мира поднят — EventBus.steam_world_ready — меню грузит остров.
# В dev-режиме ENet мир поднят с самого старта: «В мир» просто открывает
# сцену. «Встречи» — П7, «Гардероб» и «Настройки» — П8.
# Бот (--bot) входит в мир сам через секунду — headless-проверки этапа.
extends Control

const WORLD_SCENE: String = "res://scenes/world_scene.tscn"
const BOT_AUTO_ENTER_DELAY: float = 1.0

var _bot_wait: float = 0.0


func _ready() -> void:
	LocLabels.apply(self)
	EventBus.roster_changed.connect(_on_roster_changed)
	EventBus.host_lost.connect(_on_host_lost)
	_refresh_net_ui()
	if SteamService.available:
		$Menu/FriendsWorld.disabled = false
		EventBus.steam_world_ready.connect(_on_steam_world_ready)
		SteamService.lobby_joined.connect(_on_steam_lobby_joined)
		SteamService.lobby_join_failed.connect(_on_steam_lobby_join_failed)
		SteamService.invite_received.connect(_on_steam_invite)
		# Раздел 11: вход в мир по +connect_lobby при закрытой игре.
		var invited_lobby: int = SteamService.consume_pending_connect_lobby()
		if invited_lobby != 0:
			Log.info("MainMenu: вход по приглашению +connect_lobby %d" % invited_lobby, "Menu")
			_flow_status(tr("MENU_NET_JOINING"), true)
			SteamService.join_lobby(invited_lobby)


func _process(delta: float) -> void:
	if not Session.bot or Session.in_world:
		return
	_bot_wait += delta
	if _bot_wait >= BOT_AUTO_ENTER_DELAY:
		Log.info("Автостарт бота: вхожу в мир", "Menu")
		_enter_world()


func _on_enter_world_pressed() -> void:
	if Net.is_networked():
		# Dev-режим ENet: мир уже поднят и открыт (раздел 10).
		Log.info("MainMenu: «В мир» (dev ENet)", "Menu")
		_enter_world()
		return
	if SteamService.available:
		# Раздел 11: быстрый вход — самый населённый публичный мир или свой.
		Log.info("MainMenu: «В мир» (Steam)", "Menu")
		_flow_status(tr("MENU_NET_SEARCHING"), true)
		SteamService.quick_join_public()
		return
	_enter_world()  # локальный мир без Steam и без сети


## «Мир для друзей» (раздел 11): лобби «только для друзей», приглашение —
## кнопкой «Пригласить» (оверлей) после входа.
func _on_friends_world_pressed() -> void:
	Log.info("MainMenu: «Мир для друзей» (Steam)", "Menu")
	_flow_status(tr("MENU_NET_CREATING"), true)
	SteamService.create_world(SteamService.LOBBY_MODE_FRIENDS)


# --- Steam-поток входа (раздел 11) ---

## Лобби достигнуто: хосту мир уже готов (steam_world_ready придёт сразу),
## клиент ждёт подключения транспорта к хосту.
func _on_steam_lobby_joined(_lobby_id: int, as_owner: bool) -> void:
	if as_owner:
		return
	_flow_status(tr("MENU_NET_JOINING"), true)


func _on_steam_lobby_join_failed(reason: String) -> void:
	_flow_status(tr("MENU_NET_JOIN_FAILED") % reason, false)


## Транспорт мира поднят (хост или клиент): грузим остров.
func _on_steam_world_ready() -> void:
	_flow_status("", false)
	_enter_world()


## Друг приглашает через оверлей, пока мы в меню (раздел 11). В мире
## приглашение не прерывает игру — уведомления, П7.
func _on_steam_invite(_inviter_id: int, lobby_id: int) -> void:
	if Session.in_world or Net.is_networked():
		return
	Log.info("MainMenu: приглашение в лобби %d — вхожу" % lobby_id, "Menu")
	_flow_status(tr("MENU_NET_JOINING"), true)
	SteamService.join_lobby(lobby_id)


## Статус потока входа в строке сети; busy блокирует кнопки от двойных нажатий.
func _flow_status(text: String, busy: bool) -> void:
	$NetStatus.text = text
	$Menu/EnterWorld.disabled = busy
	$Menu/FriendsWorld.disabled = busy or not SteamService.available


func _on_host_lost(_reason: String) -> void:
	_flow_status("", false)
	_refresh_net_ui()


func _enter_world() -> void:
	if Session.in_world:
		return
	get_tree().call_deferred("change_scene_to_file", WORLD_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_roster_changed(count: int) -> void:
	_refresh_net_status(count)


func _refresh_net_ui() -> void:
	_refresh_net_status(Net.players.size())


func _refresh_net_status(count: int) -> void:
	var status: Label = $NetStatus
	if not Net.is_networked():
		status.text = ""
		return
	if Net.mode == "steam":
		# Статус Steam-потока ведёт _flow_status (поиск/создание/подключение).
		return
	# Мир всегда открыт (раздел 10): вход не зависит от остальных.
	if Net.is_host():
		status.text = tr("MENU_NET_HOST_STATUS") % [count, Protocol.MAX_PLAYERS]
	else:
		status.text = tr("MENU_NET_CLIENT_STATUS")
