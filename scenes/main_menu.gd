# Главное меню (раздел 13 SPEC): «Играть» — одиночный забег; в dev-режиме
# хост запускает сетевой забег кнопкой, клиенты ждут rpc_start_run.
# Хост-бот (--bot) стартует забег сам: когда представились (rpc_hello) минимум
# MIN_PLAYERS_TO_START игроков и 3 с не было новых — для headless-нагрузочных
# прогонов (раздел 16), где копии игры стартуют с разбросом в секунды.
extends Control

const RUN_SCENE: String = "res://scenes/run.tscn"
const BOT_START_MIN_WAIT: float = 5.0   # минимум ожидания перед стартом, с
const BOT_JOIN_QUIET: float = 3.0       # тишина после последнего подключения, с

var _auto_started: bool = false
var _auto_wait: float = 0.0
var _quiet_wait: float = 0.0
var _last_roster_count: int = 1


func _ready() -> void:
	LocLabels.apply(self)
	EventBus.roster_changed.connect(_on_roster_changed)
	EventBus.host_lost.connect(func(_reason: String) -> void: _refresh_net_ui())
	_refresh_net_ui()


func _process(delta: float) -> void:
	# Автостарт хоста-бота: считаем только сказавших rpc_hello (peer_count
	# видит и недоподключившихся — старт раньше времени закрыл бы лобби).
	if _auto_started or not (Session.bot and Net.is_networked() and Net.is_host()):
		return
	if Session.run_active or Net.go_scheduled():
		return
	_auto_wait += delta
	var count: int = Net.players.size()
	if count != _last_roster_count:
		_last_roster_count = count
		_quiet_wait = 0.0
	else:
		_quiet_wait += delta
	var enough: bool = count >= Protocol.MIN_PLAYERS_TO_START
	if enough and _auto_wait >= BOT_START_MIN_WAIT and _quiet_wait >= BOT_JOIN_QUIET:
		_auto_started = true
		Log.info("Автостарт забега хоста-бота (игроков: %d)" % count, "Menu")
		Net.start_run_as_host()


func _on_roster_changed(count: int) -> void:
	_refresh_net_status(count)


func _on_play_pressed() -> void:
	if Net.is_networked():
		if Net.is_host():
			Net.start_run_as_host()
		return
	Log.info("MainMenu: «Играть» — одиночный забег")
	get_tree().change_scene_to_file(RUN_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _refresh_net_ui() -> void:
	_refresh_net_status(Net.players.size())


func _refresh_net_status(count: int) -> void:
	var status: Label = $NetStatus
	var play: Button = $Menu/Play
	if not Net.is_networked():
		play.disabled = false
		status.text = ""
		return
	if Net.is_host():
		play.disabled = count < Protocol.MIN_PLAYERS_TO_START
		status.text = tr("MENU_NET_HOST_STATUS") % [count, Protocol.MAX_PLAYERS]
	else:
		play.disabled = true
		status.text = tr("MENU_NET_CLIENT_WAIT")
