# NetworkManager (раздел 10 SPEC): выбор транспорта (ENet для разработки,
# Steam — этап П4), ростер мира и синхронизация часов мира. Мир открыт для
# входа в любой момент: rpc_hello добавляет игрока, пока есть места, общего
# «старта» больше нет. Выход хоста закрывает мир у всех.
# Не делает: 3D-снапшоты и AOI (П3), world_state для вошедших позже (П3),
# голос (П6), Steam-лобби (П4).
extends Node

## Активный режим: "none" (локальный мир без сети) | "dev-host" | "dev-join" | "steam" (П4).
var mode: String = "none"

var transport: Transport = null
var clock := ClockSync.new()
## Свой peer id (без сети — 1).
var local_peer_id: int = 1
## Участники мира: peer_id -> {name: String}.
var players: Dictionary = {}

## Эпоха мира по часам хоста, мс (0 — мир ещё не создан).
## world_time = host_time − эпоха; хост создаёт мир вместе с сервером.
var world_epoch_msec: int = 0

var _net_log: bool = false
var _ping_accum: float = 0.0


func _ready() -> void:
	_net_log = Dev.log_net
	if Dev.host_mode and Dev.join_address != "":
		Log.warn("--dev-host и --dev-join вместе: клиентский режим проигнорирован", "Net")
	if Dev.host_mode:
		mode = "dev-host"
	elif Dev.join_address != "":
		mode = "dev-join"
	else:
		mode = "none"

	if mode != "none":
		var enet := EnetTransport.new()
		enet.setup(Dev.net_lag_ms, Dev.net_loss_percent)
		transport = enet
		add_child(transport)
		transport.wire_multiplayer(multiplayer)
		transport.peer_connected.connect(_on_peer_connected)
		transport.peer_disconnected.connect(_on_peer_disconnected)
		transport.server_disconnected.connect(_on_server_disconnected)
		transport.connection_failed.connect(_on_connection_failed)
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		if mode == "dev-host":
			var err: Error = transport.host_game(Dev.DEV_PORT)
			if err == OK:
				multiplayer.multiplayer_peer = transport.peer
				# Мир создан вместе с сервером: часы мира пошли (раздел 7).
				world_epoch_msec = Time.get_ticks_msec()
				Log.info(
					"Хост ENet на порту %d, мир создан (эмуляция: лаг %d мс, потеря %d%%)"
					% [Dev.DEV_PORT, Dev.net_lag_ms, Dev.net_loss_percent], "Net"
				)
		else:
			var err: Error = transport.join_game(Dev.join_address, Dev.DEV_PORT)
			if err == OK:
				multiplayer.multiplayer_peer = transport.peer
				Log.info("Клиент ENet: подключение к %s:%d" % [Dev.join_address, Dev.DEV_PORT], "Net")

	local_peer_id = multiplayer.get_unique_id()
	players[local_peer_id] = _new_slot(_display_name())
	if mode == "none":
		Log.info("Сеть не запущена: локальный мир (Steam-режим — этап П4)", "Net")


func _process(delta: float) -> void:
	# Часы мира (разделы 7, 10): клиент сверяется с хостом каждую секунду.
	if is_networked() and not is_host():
		_ping_accum += delta
		if _ping_accum >= Protocol.CLOCK_PING_INTERVAL:
			_ping_accum = 0.0
			var now: int = Time.get_ticks_msec()
			_send(func() -> void: rpc_id(1, "rpc_ping", now), true)


# --- Публичный интерфейс ---

func is_networked() -> bool:
	return transport != null


## Я я хост (в локальном мире — всегда: локальная роль хоста).
func is_host() -> bool:
	return not is_networked() or multiplayer.is_server()


## Число участников (включая себя).
func peer_count() -> int:
	if not is_networked():
		return 1
	return 1 + multiplayer.get_peers().size()


## Мой отображаемый ник: --dev-name, иначе persona name Steam, иначе «Player N».
func _display_name() -> String:
	if Dev.player_name != "":
		return Dev.player_name
	if SteamService.persona_name != "":
		return SteamService.persona_name
	return "Player%d" % local_peer_id


## Время мира, с (раздел 7): по часам хоста от эпохи мира.
func world_time_sec() -> float:
	if world_epoch_msec <= 0:
		return 0.0
	return maxf(0.0, float(host_time_now_msec() - world_epoch_msec) / 1000.0)


## Локальный мир без сети: запустить часы мира сейчас (вызывает Session).
func begin_world_clock() -> void:
	if not is_networked() and world_epoch_msec <= 0:
		world_epoch_msec = Time.get_ticks_msec()


## Время хоста в мс: локальные часы плюс сглаженное смещение.
func host_time_now_msec() -> int:
	if is_networked() and not multiplayer.is_server():
		return Time.get_ticks_msec() + int(round(clock.offset_msec()))
	return Time.get_ticks_msec()


## RTT до хоста, мс (для панели F3; −1 — замеров нет).
func ping_msec() -> int:
	if is_networked() and not multiplayer.is_server():
		return clock.last_rtt_msec()
	return -1


# --- RPC-протокол (раздел 10) ---

## Клиент представляется хосту после подключения: мир открыт, добавляем.
@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_hello(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if players.size() >= Protocol.MAX_PLAYERS:
		Log.warn("Пир %d отключён: мир заполнен" % sender, "Net")
		_kick(sender)
		return
	players[sender] = _new_slot(player_name.left(20))  # раздел 14: ник до 20 символов
	Log.info("Игрок подключился: %d «%s» (всего %d)" % [sender, player_name, players.size()], "Net")
	_broadcast_roster()
	# Часы мира новому игроку: у всех world_time одинаков (раздел 7).
	_send(func() -> void: rpc_id(sender, "rpc_world_clock", world_epoch_msec), false)


## Хост рассылает состав участников (и удаляет вышедших у клиентов).
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_roster_update(entries: Array) -> void:
	var fresh: Dictionary = {}
	for entry: Dictionary in entries:
		fresh[int(entry["peer_id"])] = _new_slot(str(entry["name"]))
	# Кого не стало — сообщить сценам (персонаж исчезает, раздел 10).
	for old_id: int in players.keys():
		if old_id != local_peer_id and not fresh.has(old_id):
			EventBus.peer_left.emit(old_id)
	players = fresh
	EventBus.roster_changed.emit(players.size())


## Эпоха мира по часам хоста — новому игроку (world_time одинаков у всех).
@rpc("authority", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_world_clock(epoch_msec: int) -> void:
	if multiplayer.is_server():
		return
	world_epoch_msec = epoch_msec
	Log.info("Часы мира синхронизированы: world_time=%.1f с" % world_time_sec(), "Net")


## Ping часов: клиент раз в секунду.
@rpc("any_peer", "call_remote", "unreliable_ordered", Protocol.CHANNEL_SNAPSHOT)
func rpc_ping(client_msec: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var host_msec: int = Time.get_ticks_msec()
	_send(func() -> void: rpc_id(sender, "rpc_pong", client_msec, host_msec), true)


## Pong часов: хост возвращает своё время.
@rpc("authority", "call_remote", "unreliable_ordered", Protocol.CHANNEL_SNAPSHOT)
func rpc_pong(client_msec: int, host_msec: int) -> void:
	var now: int = Time.get_ticks_msec()
	var rtt: int = now - client_msec
	clock.add_sample(host_msec, now, rtt)
	if _net_log:
		Log.debug("Часы: rtt=%d мс, offset=%.1f мс" % [rtt, clock.offset_msec()], "Net")


# --- Подключения (раздел 10: выход и выход хоста) ---

## Клиент успешно подключился к хосту: представляемся (rpc_hello).
func _on_connected_to_server() -> void:
	Log.info("Подключение к хосту установлено, peer id %d" % multiplayer.get_unique_id(), "Net")
	local_peer_id = multiplayer.get_unique_id()
	if not players.has(local_peer_id):
		players[local_peer_id] = _new_slot(_display_name())
	_send(func() -> void: rpc_hello.rpc(_display_name()), false)


func _on_peer_connected(peer_id: int) -> void:
	# Ждём rpc_hello от клиента: имя и место в ростере придут с ним.
	Log.info("Пир подключился: %d" % peer_id, "Net")


func _on_peer_disconnected(peer_id: int) -> void:
	Log.warn("Пир отключился: %d" % peer_id, "Net")
	if multiplayer.is_server():
		players.erase(peer_id)
		_broadcast_roster()
	else:
		# Клиенты соединены звездой с хостом: потеря хоста = мир закрылся.
		_on_host_lost("Пир %d покинул игру" % peer_id)


func _on_server_disconnected() -> void:
	_on_host_lost("Соединение с хостом потеряно")


func _on_connection_failed() -> void:
	Log.error("Не удалось подключиться к хосту %s" % Dev.join_address, "Net")
	_teardown_network()
	EventBus.host_lost.emit("Не удалось подключиться")


func _on_host_lost(reason: String) -> void:
	# Раздел 10: выход хоста закрывает мир у всех с сообщением.
	Log.warn("Хост мира вышел: %s" % reason, "Net")
	_teardown_network()
	Session.leave_world()
	EventBus.host_lost.emit(reason)


func _teardown_network() -> void:
	if transport != null:
		transport.close()
	multiplayer.multiplayer_peer = null
	transport = null
	mode = "none"
	# Без пира get_unique_id() ошибается; офлайн-режим — всегда id 1.
	local_peer_id = 1
	players.clear()
	players[local_peer_id] = _new_slot(_display_name())
	world_epoch_msec = 0
	clock.clear()


func _kick(peer_id: int) -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


# --- Вспомогательное ---

func _new_slot(player_name: String) -> Dictionary:
	return {"name": player_name}


func _roster_entries() -> Array:
	var entries: Array = []
	for peer_id: int in players.keys():
		entries.append({"peer_id": peer_id, "name": players[peer_id]["name"]})
	return entries


func _broadcast_roster() -> void:
	if is_networked():
		rpc_roster_update.rpc(_roster_entries())
	else:
		EventBus.roster_changed.emit(players.size())


## Отправка RPC через транспорт: единая точка эмуляции плохой сети.
func _send(call: Callable, unreliable: bool) -> void:
	if _net_log:
		Log.debug("rpc send (unreliable=%s)" % str(unreliable), "Net")
	if transport != null:
		transport.send(call, unreliable)
	else:
		call.call()
