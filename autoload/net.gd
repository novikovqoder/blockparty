# NetworkManager (раздел 10 SPEC): выбор транспорта (ENet для разработки,
# Steam — лобби-миры раздела 11: владелец лобби становится хостом),
# ростер мира и синхронизация часов мира. Мир открыт для входа в любой
# момент: rpc_hello добавляет игрока и сразу получает world_state (часы,
# игроки, мёртвые мобы, собранные монеты). Снапшоты движения идут 20 Гц
# через хост, хост пересылает их с AOI-фильтром по расстоянию; мобы и
# монеты решает хост (HostAuthority). Выход хоста закрывает мир у всех.
# В одиночной игре без сети Net сам исполняет роль хоста — те же события
# EventBus.
# Не делает: голос (П6).
extends Node

const B: Balance = preload("res://gameplay/balance.tres")

## Активный режим: "none" (локальный мир без сети) | "dev-host" | "dev-join" | "steam" (П4).
var mode: String = "none"

var transport: Transport = null
var clock := ClockSync.new()
## Свой peer id (без сети — 1).
var local_peer_id: int = 1
## Участники мира: peer_id -> {name: String, in_world: bool}.
var players: Dictionary = {}

## Эпоха мира по часам хоста, мс (0 — мир ещё не создан).
## world_time = host_time − эпоха; хост создаёт мир вместе с сервером.
var world_epoch_msec: int = 0
## Сдвиг часов мира, с: мир начинается утром (day_start_sec, раздел 7),
## а не на тёмном рассвете — иначе первые минуты земля едва видна.
## Передаётся в world_state: у гостей часы те же.
var world_time_offset_sec: float = 0.0

## Авторитет хоста: мёртвые мобы и собранные монеты с временем возрождения.
var authority := HostAuthority.new()
## Последнее состояние мира от хоста (клиент; применяется сценой мира).
var last_world_state: Dictionary = {}

## Счётчики снапшотов для панели F3: всего байт и скорость за последнюю секунду.
var snapshot_bytes_sent: int = 0
var snapshot_bytes_received: int = 0
var snapshot_out_bps: int = 0
var snapshot_in_bps: int = 0

var _local_player: Player = null
var _seq: int = 0
var _snap_accum: float = 0.0
var _aoi := AoiFilter.new()
## peer_id -> последняя позиция из снапшота (AOI на хосте, проверки ударов).
var _peer_pos: Dictionary = {}
var _traffic_accum: float = 0.0
var _traffic_sent_prev: int = 0
var _traffic_log_accum: int = 0
var _traffic_received_prev: int = 0
var _net_log: bool = false
var _ping_accum: float = 0.0


func _ready() -> void:
	_net_log = Dev.log_net
	# Лобби Steam (раздел 11): поднимаем транспорт мира, когда SteamService
	# вошёл в лобби (кнопки меню, приглашение, +connect_lobby).
	SteamService.lobby_joined.connect(_on_steam_lobby_joined)
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
		_wire_transport_signals()
		if mode == "dev-host":
			var err: Error = transport.host_game(Dev.DEV_PORT)
			if err == OK:
				multiplayer.multiplayer_peer = transport.peer
				# Мир создан вместе с сервером: часы мира пошли (раздел 7).
				_start_world_clock()
				authority.clear()
				_aoi.clear()
				_peer_pos.clear()
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
		Log.info("Сеть не запущена: локальный мир (Steam-режим — кнопки меню, раздел 11)", "Net")


## Сигналы транспорта и MultiplayerAPI — одинаково для ENet и Steam.
func _wire_transport_signals() -> void:
	if transport == null:
		return
	transport.wire_multiplayer(multiplayer)
	transport.peer_connected.connect(_on_peer_connected)
	transport.peer_disconnected.connect(_on_peer_disconnected)
	transport.server_disconnected.connect(_on_server_disconnected)
	transport.connection_failed.connect(_on_connection_failed)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)


# --- Steam-мир (раздел 11: лобби = мир, владелец лобби — хост) ---

## SteamService вошёл в лобби: владелец поднимает мир (хост), остальные
## подключаются к нему. Дальше — общий путь rpc_hello/world_state (раздел 10).
func _on_steam_lobby_joined(lobby_id: int, as_owner: bool) -> void:
	if mode == "steam" or transport != null:
		return  # уже в мире
	var steam := SteamTransport.new()
	steam.setup(lobby_id)
	transport = steam
	add_child(steam)
	_wire_transport_signals()
	mode = "steam"
	var err: Error = FAILED
	if as_owner:
		err = steam.host_lobby(lobby_id)
	else:
		err = steam.join_lobby(lobby_id)
	if err != OK:
		_teardown_network()
		EventBus.host_lost.emit("Не удалось подключиться к миру Steam")
		return
	multiplayer.multiplayer_peer = steam.peer
	if as_owner:
		local_peer_id = multiplayer.get_unique_id()
		# Мир создан вместе с хостом: часы мира пошли (раздел 7), как в dev-host.
		_start_world_clock()
		authority.clear()
		_aoi.clear()
		_peer_pos.clear()
		Log.info("Хост Steam-мира: лобби %d, мир создан" % lobby_id, "Net")
		EventBus.steam_world_ready.emit()
	else:
		Log.info("Клиент Steam-мира: подключение к лобби %d" % lobby_id, "Net")


## Полный выход из Steam-мира (Esc → «Выйти из мира», раздел 11): транспорт
## и лобби закрываются — игрок снова в меню и может войти в другой мир.
func leave_steam_world() -> void:
	if mode != "steam":
		return
	_teardown_network()


func _process(delta: float) -> void:
	# Часы мира (разделы 7, 10): клиент сверяется с хостом каждую секунду.
	if is_networked() and not is_host():
		_ping_accum += delta
		if _ping_accum >= Protocol.CLOCK_PING_INTERVAL:
			_ping_accum = 0.0
			var now: int = Time.get_ticks_msec()
			_send(func() -> void: rpc_id(1, "rpc_ping", now), true)
	_send_own_snapshot(delta)
	_update_traffic(delta)
	if is_host():
		# Возродившиеся выпадают из состояния — world_state остаётся компактным.
		authority.prune(world_time_sec())


# --- Публичный интерфейс ---

## Сцена мира регистрирует локального игрока: с него берутся снапшоты
## (20 Гц) и позиция для проверок хоста. Освобождается сама при выходе.
func register_local_player(player: Player) -> void:
	_local_player = player


## Сцена мира загружена и состояние применено: объявляем себя в мире.
## Клиент сообщает хосту (rpc_client_ready), хост объявляет всех.
func entered_world() -> void:
	if not players.has(local_peer_id):
		players[local_peer_id] = _new_slot(_display_name())
	players[local_peer_id]["in_world"] = true
	if is_networked():
		if multiplayer.is_server():
			_send(
				func() -> void: rpc_player_joined.rpc(
					local_peer_id, str(players[local_peer_id]["name"])
				), false
			)
		else:
			_send(func() -> void: rpc_id(1, "rpc_client_ready"), false)
	else:
		EventBus.roster_changed.emit(players.size())


## Выход из мира в меню (персонаж исчезает у всех, связь остаётся).
func left_world() -> void:
	if players.has(local_peer_id):
		players[local_peer_id]["in_world"] = false
	if is_networked():
		if multiplayer.is_server():
			_broadcast_roster()
		else:
			_send(func() -> void: rpc_id(1, "rpc_left_world"), false)


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


## Время мира, с (раздел 7): по часам хоста от эпохи мира плюс сдвиг утра.
func world_time_sec() -> float:
	if world_epoch_msec <= 0:
		return 0.0
	return maxf(0.0, float(host_time_now_msec() - world_epoch_msec) / 1000.0) \
		+ world_time_offset_sec


## Локальный мир без сети: запустить часы мира сейчас (вызывает Session).
func begin_world_clock() -> void:
	if not is_networked() and world_epoch_msec <= 0:
		_start_world_clock()


## Часы мира пошли: эпоха сейчас, старт со светлого утра (раздел 7).
func _start_world_clock() -> void:
	world_epoch_msec = Time.get_ticks_msec()
	world_time_offset_sec = B.day_start_sec


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

## Клиент представляется хосту после подключения: мир открыт, добавляем
## и сразу высылаем полное состояние (раздел 10: вход в любой момент).
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
	# Полное состояние мира одним пакетом: часы, ростер с флагами «в мире»,
	# мёртвые мобы и собранные монеты с временем возрождения (раздел 10).
	authority.prune(world_time_sec())
	var state := {
		"world_epoch_msec": world_epoch_msec,
		"world_time_offset_sec": world_time_offset_sec,
		"players": _roster_entries(),
		"dead_mobs": authority.dead_mob_entries(),
		"taken_coins": authority.taken_coin_entries(),
	}
	_send(func() -> void: rpc_id(sender, "rpc_world_state", WorldState.pack(state)), false)


## Хост рассылает состав участников (и удаляет вышедших у клиентов).
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_roster_update(entries: Array) -> void:
	var fresh: Dictionary = {}
	for entry: Dictionary in entries:
		var slot := _new_slot(str(entry["name"]))
		slot["in_world"] = bool(entry.get("in_world", false))
		fresh[int(entry["peer_id"])] = slot
	# Кого не стало или кто вышел из мира — сообщить сценам (персонаж
	# исчезает, раздел 10).
	for old_id: int in players.keys():
		if old_id == local_peer_id:
			continue
		if not fresh.has(old_id):
			EventBus.peer_left.emit(old_id, str(players[old_id]["name"]))
		elif bool(players[old_id].get("in_world", false)) \
				and not bool(fresh[old_id].get("in_world", false)):
			EventBus.peer_left.emit(old_id, str(players[old_id]["name"]))
	players = fresh
	EventBus.roster_changed.emit(players.size())


## Полное состояние мира новому игроку (раздел 10): применяет часы, ростер
## и расписание мобов/монет. Сцена мира, если уже загружена, применит его
## сразу; иначе — по готовности через replay_world_state().
@rpc("authority", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_world_state(data: PackedByteArray) -> void:
	if multiplayer.is_server():
		return
	var state := WorldState.unpack(data)
	world_epoch_msec = int(state["world_epoch_msec"])
	# Пакеты без поля (старые прогоны тестов) — без сдвига.
	world_time_offset_sec = float(state.get("world_time_offset_sec", 0.0))
	last_world_state = state
	var fresh: Dictionary = {}
	for entry: Dictionary in state["players"]:
		var slot := _new_slot(str(entry["name"]))
		slot["in_world"] = bool(entry["in_world"])
		fresh[int(entry["peer_id"])] = slot
	players = fresh
	var dead: Array = state["dead_mobs"]
	var taken: Array = state["taken_coins"]
	Log.info(
		"Состояние мира получено: world_time=%.1f с, игроков=%d, мёртвых мобов=%d, собранных монет=%d"
		% [world_time_sec(), players.size(), dead.size(), taken.size()], "Net"
	)
	if Session.in_world:
		EventBus.world_state_applied.emit(dead, taken)


## Повторно применить последнее состояние мира (вызывает сцена мира в
## _ready — пакет мог прийти, пока игрок был ещё в меню).
func replay_world_state() -> void:
	if last_world_state.is_empty():
		return
	EventBus.world_state_applied.emit(last_world_state["dead_mobs"], last_world_state["taken_coins"])


## Клиент загрузил остров и применил состояние — объявляем его всем
## (раздел 10: новый игрок появляется с эффектом; эффект — П5).
@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_client_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	players[sender]["in_world"] = true
	Log.info("Игрок %d «%s» в мире" % [sender, players[sender]["name"]], "Net")
	_send(
		func() -> void: rpc_player_joined.rpc(sender, str(players[sender]["name"])),
		false,
	)


## Игрок вошёл в мир: у всех появляется его персонаж (rpc_client_ready
## или вход самого хоста).
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_player_joined(peer_id: int, player_name: String) -> void:
	if peer_id != local_peer_id and players.has(peer_id):
		players[peer_id]["in_world"] = true
	if peer_id != local_peer_id:
		EventBus.peer_joined_world.emit(peer_id, player_name)


## Клиент вышел из мира (в меню), оставшись на связи: персонаж исчезает
## у всех, место освобождается.
@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_left_world() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if players.has(sender):
		players[sender]["in_world"] = false
	_broadcast_roster()


# --- Снапшоты движения (раздел 10: 20 Гц, unreliable ordered, AOI на хосте) ---

## Снапшот своего персонажа клиент шлёт хосту; хост обновляет позицию
## игрока, показывает его себе и пересылает остальным по AOI-фильтру.
@rpc("any_peer", "call_remote", "unreliable_ordered", Protocol.CHANNEL_SNAPSHOT)
func rpc_snapshot(data: PackedByteArray) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_apply_peer_snapshot(sender, data)
	if not _peer_in_world(sender):
		return
	var from_pos: Vector3 = _peer_pos.get(sender, Vector3.ZERO)
	for peer_id: int in multiplayer.get_peers():
		if peer_id == sender or not _peer_in_world(peer_id):
			continue
		_forward_snapshot(sender, data, from_pos, peer_id)


## Хост переслал снапшот чужого игрока (после AOI-фильтра).
@rpc("authority", "call_remote", "unreliable_ordered", Protocol.CHANNEL_SNAPSHOT)
func rpc_peer_snapshot(from_peer: int, data: PackedByteArray) -> void:
	if multiplayer.is_server() or from_peer == local_peer_id:
		return
	_apply_peer_snapshot(from_peer, data)


func _apply_peer_snapshot(peer_id: int, data: PackedByteArray) -> void:
	snapshot_bytes_received += data.size()
	var snap := Snapshot.unpack(data)
	_peer_pos[peer_id] = Vector3(float(snap["x"]), float(snap["y"]), float(snap["z"]))
	if _net_log:
		Log.debug("rpc_snapshot от %d: %d байт" % [peer_id, data.size()], "Net")
	EventBus.peer_snapshot.emit(peer_id, snap, Time.get_ticks_msec())


## Пересылка снапшока одному получателю с учётом AOI (раздел 10): рядом —
## все 20 Гц, в 60–150 м — 4 Гц, дальше — 1 Гц для карты и ников.
## Позиция получателя неизвестна (нет ни одного снапшота) — шлём полностью.
func _forward_snapshot(from_peer: int, data: PackedByteArray, from_pos: Vector3, to_peer: int) -> void:
	var distance: float = 0.0
	if _peer_pos.has(to_peer):
		var to_pos: Vector3 = _peer_pos[to_peer]
		distance = from_pos.distance_to(to_pos)
	if not _aoi.allow(from_peer, to_peer, distance, Time.get_ticks_msec()):
		return
	snapshot_bytes_sent += data.size()
	_send(func() -> void: rpc_id(to_peer, "rpc_peer_snapshot", from_peer, data), true)


## Отправка снапшотов своего персонажа (раздел 10): 20 Гц, пока жив
## указатель на локального игрока (сцена мира регистрирует его).
func _send_own_snapshot(delta: float) -> void:
	if _local_player == null or not is_instance_valid(_local_player):
		return
	_snap_accum += delta
	var interval: float = 1.0 / Protocol.SNAPSHOT_HZ
	if _snap_accum < interval:
		return
	_snap_accum = 0.0
	var pos: Vector3 = _local_player.global_position
	var data := Snapshot.pack(
		_seq, pos.x, pos.y, pos.z, _local_player.model_yaw(),
		_local_player.velocity.x, _local_player.velocity.y, _local_player.velocity.z,
		_local_player.anim_state(), _local_player.snapshot_flags()
	)
	_seq = (_seq + 1) & 0xFFFF
	if not is_networked():
		return  # локальный мир: пересылать некому
	if is_host():
		for peer_id: int in multiplayer.get_peers():
			if not _peer_in_world(peer_id):
				continue
			_forward_snapshot(local_peer_id, data, pos, peer_id)
	else:
		snapshot_bytes_sent += data.size()
		_send(func() -> void: rpc_id(1, "rpc_snapshot", data), true)


# --- Авторитет хоста: мобы и монеты (разделы 8, 10) ---

## Удар по мобу (раздел 8): клиент видит попадание, хост проверяет
## дистанцию до 2.5 м с допуском на пинг, перезарядку и что моб жив.
func request_mob_hit(spawn_id: int, client_world_time: float) -> void:
	if is_host():
		_handle_mob_hit(local_peer_id, spawn_id, client_world_time)
	else:
		_send(
			func() -> void: rpc_id(1, "rpc_hit_mob", spawn_id, client_world_time), false
		)


@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_hit_mob(spawn_id: int, client_world_time: float) -> void:
	if not multiplayer.is_server():
		return
	_handle_mob_hit(multiplayer.get_remote_sender_id(), spawn_id, client_world_time)


func _handle_mob_hit(killer_peer: int, spawn_id: int, client_world_time: float) -> void:
	var mob := _find_mob(spawn_id)
	if mob == null:
		Log.warn("Удар по неизвестному мобу %d отклонён" % spawn_id, "Net")
		return
	if not mob.is_killable():
		return  # светлячок «на двоих» — П5
	var killer_pos: Vector3 = _peer_position(killer_peer)
	if killer_pos == _POS_UNKNOWN:
		Log.warn("Удар по мобу %d отклонён: нет позиции игрока %d" % [spawn_id, killer_peer], "Net")
		return
	var event := authority.try_kill_mob(
		spawn_id, killer_peer, client_world_time,
		mob.position_at(client_world_time), killer_pos, mob.respawn_sec(), B
	)
	if event.is_empty():
		return
	Log.info(
		"Моб %d убит игроком %d, возрождение %.0f с"
		% [spawn_id, killer_peer, float(event["respawn_at"]) - client_world_time], "Net"
	)
	_broadcast_mob_killed(spawn_id, killer_peer, mob.reward(), float(event["respawn_at"]))


## Хост подтвердил убийство моба всем (раздел 8): killers/coins расширятся
## на светлячка на П5.
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_mob_killed(spawn_id: int, killer_peer: int, coins: int, respawn_at: float) -> void:
	EventBus.mob_killed.emit(spawn_id, killer_peer, respawn_at)
	if killer_peer == local_peer_id:
		Session.add_world_coins(coins)


## Касание монеты (раздел 10: «кто первый — того и монета»).
func request_coin_collect(spawn_id: int, client_world_time: float) -> void:
	if is_host():
		_handle_coin_collect(local_peer_id, spawn_id, client_world_time)
	else:
		_send(
			func() -> void: rpc_id(1, "rpc_collect_coin", spawn_id, client_world_time), false
		)


@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_collect_coin(spawn_id: int, client_world_time: float) -> void:
	if not multiplayer.is_server():
		return
	_handle_coin_collect(multiplayer.get_remote_sender_id(), spawn_id, client_world_time)


func _handle_coin_collect(collector_peer: int, spawn_id: int, world_time: float) -> void:
	var event := authority.try_take_coin(spawn_id, collector_peer, world_time, B.coin_respawn_sec)
	if event.is_empty():
		return
	_broadcast_coin_taken(spawn_id, collector_peer, B.coin_reward, float(event["respawn_at"]))


## Хост подтвердил подбор монеты всем (раздел 10).
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_coin_taken(spawn_id: int, collector_peer: int, coins: int, respawn_at: float) -> void:
	EventBus.coin_collected.emit(spawn_id, collector_peer, respawn_at)
	if collector_peer == local_peer_id:
		Session.add_world_coins(coins)


func _broadcast_mob_killed(spawn_id: int, killer_peer: int, coins: int, respawn_at: float) -> void:
	if is_networked():
		_send(
			func() -> void: rpc_mob_killed.rpc(spawn_id, killer_peer, coins, respawn_at), false
		)
	else:
		rpc_mob_killed(spawn_id, killer_peer, coins, respawn_at)


func _broadcast_coin_taken(spawn_id: int, collector_peer: int, coins: int, respawn_at: float) -> void:
	Log.info(
		"Монета %d собрана (peer %d, +%d, возрождение %.0f с)"
		% [spawn_id, collector_peer, coins, respawn_at], "Net"
	)
	if is_networked():
		_send(
			func() -> void: rpc_coin_taken.rpc(spawn_id, collector_peer, coins, respawn_at), false
		)
	else:
		rpc_coin_taken(spawn_id, collector_peer, coins, respawn_at)


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
	if mode == "steam":
		# Лобби подключено и хост ответил — можно загружать остров (раздел 11).
		EventBus.steam_world_ready.emit()


func _on_peer_connected(peer_id: int) -> void:
	# Ждём rpc_hello от клиента: имя и место в ростере придут с ним.
	Log.info("Пир подключился: %d" % peer_id, "Net")


func _on_peer_disconnected(peer_id: int) -> void:
	Log.warn("Пир отключился: %d" % peer_id, "Net")
	_peer_pos.erase(peer_id)
	if multiplayer.is_server():
		players.erase(peer_id)
		_broadcast_roster()
	elif peer_id == 1:
		# Клиенты соединены звездой с хостом: потеря хоста = мир закрылся.
		# Отключение чужого клиента релеем не считается — ростер обновит хост.
		_on_host_lost("Пир %d покинул игру" % peer_id)


func _on_server_disconnected() -> void:
	_on_host_lost("Соединение с хостом потеряно")


func _on_connection_failed() -> void:
	Log.error(
		"Не удалось подключиться к хосту %s" % ("(Steam-лобби)" if mode == "steam" else Dev.join_address),
		"Net",
	)
	_teardown_network()
	EventBus.host_lost.emit("Не удалось подключиться")


func _on_host_lost(reason: String) -> void:
	# Раздел 10: выход хоста закрывает мир у всех с сообщением.
	Log.warn("Хост мира вышел: %s" % reason, "Net")
	_teardown_network()
	Session.leave_world()
	EventBus.host_lost.emit(reason)


func _teardown_network() -> void:
	var was_steam: bool = mode == "steam"
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
	_peer_pos.clear()
	_aoi.clear()
	_seq = 0
	last_world_state = {}
	authority.clear()
	if was_steam:
		# Раздел 11: выход из мира — выход из лобби (Rich Presence очищается).
		SteamService.leave_lobby()


func _kick(peer_id: int) -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


# --- Вспомогательное ---

## Сентинел «позиция игрока неизвестна» (снапшотов ещё не было).
const _POS_UNKNOWN := Vector3(INF, INF, INF)


func _new_slot(player_name: String) -> Dictionary:
	return {"name": player_name, "in_world": false}


func _peer_in_world(peer_id: int) -> bool:
	var slot: Variant = players.get(peer_id)
	return slot != null and bool(slot.get("in_world", false))


## Сколько игроков сейчас в мире (включая себя) — панель F3.
func in_world_count() -> int:
	var count: int = 1 if _peer_in_world(local_peer_id) else 0
	for peer_id: int in players.keys():
		if peer_id != local_peer_id and _peer_in_world(peer_id):
			count += 1
	return count


## Позиция игрока для проверок хоста: свой — из сцены, чужой — последний
## снапшот (устарел на пинг — это допускает mob_hit_slack, раздел 8).
func _peer_position(peer_id: int) -> Vector3:
	if peer_id == local_peer_id:
		if _local_player != null and is_instance_valid(_local_player):
			return _local_player.global_position
		return _POS_UNKNOWN
	if _peer_pos.has(peer_id):
		return _peer_pos[peer_id]
	return _POS_UNKNOWN


## Моб по spawn_id из группы (остров у всех одинаковый, раздел 6).
func _find_mob(spawn_id: int) -> Mob:
	for node: Node in get_tree().get_nodes_in_group(Mob.GROUP):
		if node is Mob and (node as Mob).spawn_id == spawn_id:
			return node
	return null


## Скорость снапшотов за последнюю секунду для панели F3 (раздел 10: бюджет).
func _update_traffic(delta: float) -> void:
	_traffic_accum += delta
	if _traffic_accum < 1.0:
		return
	_traffic_accum = 0.0
	snapshot_out_bps = snapshot_bytes_sent - _traffic_sent_prev
	snapshot_in_bps = snapshot_bytes_received - _traffic_received_prev
	_traffic_sent_prev = snapshot_bytes_sent
	_traffic_received_prev = snapshot_bytes_received
	# Раз в 10 с хост напоминает про бюджет (раздел 10: 200/40 КБ/с).
	_traffic_log_accum += 1
	if is_networked() and _traffic_log_accum >= 10:
		_traffic_log_accum = 0
		Log.info(
			"Трафик снапшотов: ↑%.1f ↓%.1f КБ/с (бюджет 200/40)"
			% [snapshot_out_bps / 1024.0, snapshot_in_bps / 1024.0], "Net"
		)


func _roster_entries() -> Array:
	var entries: Array = []
	for peer_id: int in players.keys():
		entries.append({
			"peer_id": peer_id,
			"name": players[peer_id]["name"],
			"in_world": bool(players[peer_id].get("in_world", false)),
		})
	return entries


func _broadcast_roster() -> void:
	# Хост держит данные лобби свежими: «players» из раздела 11 (видно в поиске).
	if mode == "steam" and multiplayer.is_server():
		SteamService.set_lobby_players(players.size())
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
