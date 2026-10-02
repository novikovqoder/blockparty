# Главное меню (раздел 15 SPEC): «В мир» — вход в открытый мир. В dev-режиме
# ENet мир уже поднят и открыт постоянно (раздел 10): каждая копия входит
# независимо, ждать никого не нужно. «Мир для друзей» — этап П4 (Steam),
# «Встречи» — П7, «Гардероб» и «Настройки» — П8.
# Бот (--bot) входит в мир сам через секунду — headless-проверки этапа.
extends Control

const WORLD_SCENE: String = "res://scenes/world_scene.tscn"
const BOT_AUTO_ENTER_DELAY: float = 1.0

var _bot_wait: float = 0.0


func _ready() -> void:
	LocLabels.apply(self)
	EventBus.roster_changed.connect(_on_roster_changed)
	EventBus.host_lost.connect(func(_reason: String) -> void: _refresh_net_ui())
	_refresh_net_ui()


func _process(delta: float) -> void:
	if not Session.bot or Session.in_world:
		return
	_bot_wait += delta
	if _bot_wait >= BOT_AUTO_ENTER_DELAY:
		Log.info("Автостарт бота: вхожу в мир", "Menu")
		_enter_world()


func _on_enter_world_pressed() -> void:
	Log.info("MainMenu: «В мир»")
	_enter_world()


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
	# Мир всегда открыт (раздел 10): вход не зависит от остальных.
	if Net.is_host():
		status.text = tr("MENU_NET_HOST_STATUS") % [count, Protocol.MAX_PLAYERS]
	else:
		status.text = tr("MENU_NET_CLIENT_STATUS")
