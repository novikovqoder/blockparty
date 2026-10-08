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
## Авторитет хоста: активности и социальные механики П5 (разделы 7, 9).
var activity := ActivityAuthority.new()
## Связи «за руку» (раздел 9.5): leader → follower; заполняется rpc_hand_link
## у всех одинаково — для скорости цепочки (раздел 17) и HUD.
var hand_links: Dictionary = {}
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
## peer_id -> флаги последнего снапшота (висит/сидит/за руку — проверки хоста П5).
var _peer_flags: Dictionary = {}
var _traffic_accum: float = 0.0
var _traffic_sent_prev: int = 0
var _traffic_log_accum: int = 0
var _traffic_received_prev: int = 0
var _net_log: bool = false
var _ping_accum: float = 0.0
## Накопитель тика активностей хоста (плиты, зоны; разделы 9.2+).
var _activity_accum: float = 0.0


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
				activity.clear()
				hand_links.clear()
				_aoi.clear()
				_peer_pos.clear()
				_peer_flags.clear()
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
	players[local_peer_id] = _new_local_slot()
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
		activity.clear()
		hand_links.clear()
		_aoi.clear()
		_peer_pos.clear()
		_peer_flags.clear()
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
		# Активности П5 (раздел 9): плиты и зоны — по снапшотам игроков.
		_activity_accum += delta
		if _activity_accum >= B.activity_tick:
			_activity_accum = 0.0
			_tick_activities()


# --- Публичный интерфейс ---

## Сцена мира регистрирует локального игрока: с него берутся снапшоты
## (20 Гц) и позиция для проверок хоста. Освобождается сама при выходе.
func register_local_player(player: Player) -> void:
	_local_player = player


## Сцена мира загружена и состояние применено: объявляем себя в мире.
## Клиент сообщает хосту (rpc_client_ready), хост объявляет всех.
func entered_world() -> void:
	if not players.has(local_peer_id):
		players[local_peer_id] = _new_local_slot()
	players[local_peer_id]["in_world"] = true
	if is_networked():
		if multiplayer.is_server():
			_send(
				func() -> void: rpc_player_joined.rpc(
					local_peer_id,
					str(players[local_peer_id]["name"]),
					int(players[local_peer_id]["character"]),
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
## character — выбранный на экране «Персонаж» номер (раздел 16): хост
## проверяет его и вне диапазона ставит 0 — клиенту не доверяем.
@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_hello(player_name: String, character: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if players.size() >= Protocol.MAX_PLAYERS:
		Log.warn("Пир %d отключён: мир заполнен" % sender, "Net")
		_kick(sender)
		return
	if character < 0 or character >= CharacterModel.count():
		Log.warn("Пир %d прислал персонажа %d — вне диапазона, ставлю 0" % [sender, character], "Net")
		character = 0
	players[sender] = _new_slot(player_name.left(20), character)  # раздел 14: ник до 20 символов
	Log.info("Игрок подключился: %d «%s», персонаж %d (всего %d)" % [sender, player_name, character, players.size()], "Net")
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
		"activities": {
			"ruins": activity.ruins_state(),
			"ladders": activity.ladders_state(),
			"beacons": activity.beacons_state(),
			"stars_taken": activity.stars_taken_state(),
			"seats": activity.seats_state(),
		},
	}
	_send(func() -> void: rpc_id(sender, "rpc_world_state", WorldState.pack(state)), false)


## Хост рассылает состав участников (и удаляет вышедших у клиентов).
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_roster_update(entries: Array) -> void:
	var fresh: Dictionary = {}
	for entry: Dictionary in entries:
		var slot := _new_slot(str(entry["name"]), int(entry.get("character", 0)))
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
		var slot := _new_slot(str(entry["name"]), int(entry.get("character", 0)))
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
		_apply_activities(state)


## Повторно применить последнее состояние мира (вызывает сцена мира в
## _ready — пакет мог прийти, пока игрок был ещё в меню).
func replay_world_state() -> void:
	if last_world_state.is_empty():
		return
	EventBus.world_state_applied.emit(last_world_state["dead_mobs"], last_world_state["taken_coins"])
	_apply_activities(last_world_state)


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
		func() -> void: rpc_player_joined.rpc(
			sender, str(players[sender]["name"]), int(players[sender]["character"])
		),
		false,
	)


## Игрок вошёл в мир: у всех появляется его персонаж (rpc_client_ready
## или вход самого хоста). character — номер персонажа из раздела 16,
## проверенный хостом на входе (rpc_hello).
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_player_joined(peer_id: int, player_name: String, character: int) -> void:
	if peer_id != local_peer_id and players.has(peer_id):
		players[peer_id]["in_world"] = true
	if peer_id != local_peer_id:
		EventBus.peer_joined_world.emit(peer_id, player_name, character)


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
	_peer_flags[peer_id] = int(snap["flags"])
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
	var killer_pos: Vector3 = _peer_position(killer_peer)
	if killer_pos == _POS_UNKNOWN:
		Log.warn("Удар по мобу %d отклонён: нет позиции игрока %d" % [spawn_id, killer_peer], "Net")
		return
	# Светлячок «на двоих» (раздел 8): окно двух разных игроков — отдельно.
	if mob is GoldenFirefly:
		_handle_firefly_hit(killer_peer, mob as GoldenFirefly, client_world_time, killer_pos)
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
	_broadcast_mob_killed(spawn_id, [killer_peer], mob.reward(), float(event["respawn_at"]))


## Удар по золотому светлячку (раздел 8): дистанцию и перезарядку проверяет
## authority.hit_allowed, пару ударов — activity.try_firefly_hit. Первый
## удар открывает окно (событие ослабления), второй от другого игрока
## в окне убивает: 8 монет каждому из двоих.
func _handle_firefly_hit(
	killer_peer: int, mob: GoldenFirefly, world_time: float, killer_pos: Vector3
) -> void:
	if not authority.hit_allowed(
		mob.spawn_id, killer_peer, world_time, mob.position_at(world_time), killer_pos, B
	):
		return
	var event := activity.try_firefly_hit(
		mob.spawn_id, killer_peer, world_time, mob.respawn_sec(), B
	)
	if event.is_empty():
		return
	if event.has("killed"):
		var killers: Array = event["killed"]
		var respawn_at: float = float(event["respawn_at"])
		authority.mark_mob_dead(mob.spawn_id, respawn_at)
		Log.info(
			"Светлячок %d убит парой (%d и %d), по %d монет, возрождение %.0f с"
			% [mob.spawn_id, int(killers[0]), int(killers[1]), B.firefly_reward,
				respawn_at - world_time], "Net"
		)
		_broadcast_mob_killed(mob.spawn_id, killers, B.firefly_reward, respawn_at)
		return
	Log.info(
		"Светлячок %d ослаблен игроком %d на %.0f с" % [mob.spawn_id, killer_peer, B.firefly_window],
		"Net",
	)
	_broadcast_firefly_weakened(mob.spawn_id, int(event["weakened"]), float(event["until"]))


## Хост подтвердил убийство моба всем (раздел 8): killers — кому награда
## (светлячка убивают двое), монеты — каждому из списка.
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_mob_killed(spawn_id: int, killers: Array, coins: int, respawn_at: float) -> void:
	EventBus.mob_killed.emit(spawn_id, killers, respawn_at)
	if killers.has(local_peer_id):
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


func _broadcast_mob_killed(spawn_id: int, killers: Array, coins: int, respawn_at: float) -> void:
	if is_networked():
		_send(
			func() -> void: rpc_mob_killed.rpc(spawn_id, killers, coins, respawn_at), false
		)
	else:
		rpc_mob_killed(spawn_id, killers, coins, respawn_at)


## Хост разослал ослабление светлячка (раздел 8): узел мигает ярче,
## второй игрок видит, что окно открыто.
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_firefly_weakened(spawn_id: int, peer: int, until: float) -> void:
	EventBus.firefly_weakened.emit(spawn_id, peer, until)


func _broadcast_firefly_weakened(spawn_id: int, peer: int, until: float) -> void:
	if is_networked():
		_send(func() -> void: rpc_firefly_weakened.rpc(spawn_id, peer, until), false)
	else:
		rpc_firefly_weakened(spawn_id, peer, until)


# --- Подсадка на голову: событие для «Встреч» (разделы 5, 13) ---

## Прыжок с головы другого игрока (раздел 5): прыгнувший клиент сообщает
## хосту, с чьей головы прыгнул (meta узла HeadTop) — хост рассылает факт
## всем, очки «подсадил меня / я подсадил его» считает каждый клиент
## (Interactions, раздел 13). Хост проверяет только, что оба в мире.
func request_boost(base_peer: int) -> void:
	if is_host():
		_broadcast_boosted(local_peer_id, base_peer)
	else:
		_send(func() -> void: rpc_id(1, "rpc_boost", base_peer), false)


@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_boost(base_peer: int) -> void:
	if not multiplayer.is_server():
		return
	_broadcast_boosted(multiplayer.get_remote_sender_id(), base_peer)


func _broadcast_boosted(jumper_peer: int, base_peer: int) -> void:
	if base_peer == jumper_peer or not _peer_in_world(jumper_peer) or not _peer_in_world(base_peer):
		return
	if is_networked():
		_send(func() -> void: rpc_boosted.rpc(jumper_peer, base_peer), false)
	else:
		rpc_boosted(jumper_peer, base_peer)


## Хост разослал факт подсадки (раздел 13): jumper прыгнул с головы base.
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_boosted(jumper_peer: int, base_peer: int) -> void:
	EventBus.player_boosted.emit(base_peer, jumper_peer)


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


# --- Кооп-механики П5 (раздел 9; исходы подтверждает хост) ---

## Помощник удержал E у точки, где висит target (раздел 9.1): просим хост
## подтвердить вытягивание.
func request_pull(target_peer: int) -> void:
	if is_host():
		_handle_pull(local_peer_id, target_peer)
	else:
		_send(func() -> void: rpc_id(1, "rpc_request_pull", target_peer), false)


@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_request_pull(target_peer: int) -> void:
	if not multiplayer.is_server():
		return
	_handle_pull(multiplayer.get_remote_sender_id(), target_peer)


## Проверка хоста (раздел 9.1): target висит (флаг снапшота), helper рядом
## (дистанция с допуском на пинг). Подтверждение — всем.
func _handle_pull(helper_peer: int, target_peer: int) -> void:
	var target_pos: Vector3 = _peer_position(target_peer)
	var helper_pos: Vector3 = _peer_position(helper_peer)
	if target_pos == _POS_UNKNOWN or helper_pos == _POS_UNKNOWN:
		Log.warn("Вытягивание %d → %d отклонено: нет позиций" % [helper_peer, target_peer], "Net")
		return
	var target_hanging: bool = (
		(int(_peer_flags.get(target_peer, 0)) & Protocol.FLAG_HANGING) != 0
		if target_peer != local_peer_id
		else (_local_player != null and _local_player.is_hanging())
	)
	var event := activity.try_pull(
		target_peer, helper_peer, world_time_sec(), target_hanging,
		target_pos.distance_to(helper_pos), B,
	)
	if event.is_empty():
		return
	Log.info(
		"Вытягивание подтверждено: %d вытащил %d" % [helper_peer, target_peer], "Net"
	)
	_broadcast_pulled(helper_peer, target_peer)


## Хост подтвердил вытягивание (раздел 9.1): анимации у обоих, монеты
## помощнику, событие для Interactions (у каждого клиента свои очки).
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_pulled(helper_peer: int, target_peer: int) -> void:
	EventBus.player_pulled.emit(helper_peer, target_peer)
	if target_peer == local_peer_id and _local_player != null:
		_local_player.pulled_up()
	if helper_peer == local_peer_id:
		Session.add_world_coins(B.pull_reward)


func _broadcast_pulled(helper_peer: int, target_peer: int) -> void:
	if is_networked():
		_send(func() -> void: rpc_pulled.rpc(helper_peer, target_peer), false)
	else:
		rpc_pulled(helper_peer, target_peer)


# --- «За руку» (раздел 9.5; хост рассылает факт, движение — клиент ведомого) ---

## Игрок нажал F рядом с другим (раздел 9.5): просим хост переслать
## приглашение («F — принять» на 5 с).
func request_hand_link(target_peer: int) -> void:
	if is_host():
		_handle_hand_invite(local_peer_id, target_peer)
	else:
		_send(func() -> void: rpc_id(1, "rpc_hand_invite", target_peer), false)


@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_hand_invite(target_peer: int) -> void:
	if not multiplayer.is_server():
		return
	_handle_hand_invite(multiplayer.get_remote_sender_id(), target_peer)


## Релей приглашения: имя инициатора знает ростер хоста. Дистанцию и прочее
## проверит логика при согласии — приглашение просто доходит.
func _handle_hand_invite(from_peer: int, target_peer: int) -> void:
	if from_peer == target_peer \
			or not _peer_in_world(from_peer) or not _peer_in_world(target_peer):
		return
	var from_name := str(players[from_peer]["name"])
	if is_networked() and target_peer != local_peer_id:
		_send(func() -> void: rpc_id(target_peer, "rpc_hand_invited", from_peer, from_name), false)
	else:
		rpc_hand_invited(from_peer, from_name)


## Приглашение дошло до адресата: подсказка «F — принять» (HUD, раздел 9.5).
@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_hand_invited(from_peer: int, from_name: String) -> void:
	EventBus.hand_invite.emit(from_peer, from_name)


## Приглашённый согласился (F в ответ, раздел 9.5).
func accept_hand_invite(from_peer: int) -> void:
	if is_host():
		_handle_hand_accept(local_peer_id, from_peer)
	else:
		_send(func() -> void: rpc_id(1, "rpc_hand_accept", from_peer), false)


@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_hand_accept(from_peer: int) -> void:
	if not multiplayer.is_server():
		return
	_handle_hand_accept(multiplayer.get_remote_sender_id(), from_peer)


## Проверка хоста: инициатор ведёт (leader), согласившийся ведомый (follower);
## дистанция с допуском на пинг, роли и длина цепочки — в ActivityAuthority.
func _handle_hand_accept(follower_peer: int, leader_peer: int) -> void:
	var leader_pos := _peer_position(leader_peer)
	var follower_pos := _peer_position(follower_peer)
	if leader_pos == _POS_UNKNOWN or follower_pos == _POS_UNKNOWN:
		return
	var event := activity.try_hand_link(
		leader_peer, follower_peer, leader_pos.distance_to(follower_pos), B
	)
	if event.is_empty():
		return
	Log.info(
		"За руку: %d ведёт %d" % [int(event["leader"]), int(event["follower"])], "Net"
	)
	_broadcast_hand_link(int(event["leader"]), int(event["follower"]), true)


## Отпустить (F любого из двоих, раздел 9.5).
func request_hand_release() -> void:
	if is_host():
		_handle_hand_release(local_peer_id)
	else:
		_send(func() -> void: rpc_id(1, "rpc_hand_release"), false)


@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_hand_release() -> void:
	if not multiplayer.is_server():
		return
	_handle_hand_release(multiplayer.get_remote_sender_id())


func _handle_hand_release(peer: int) -> void:
	var event := activity.try_hand_release(peer)
	if event.is_empty():
		return
	Log.info(
		"За руку: %d и %d расцепились" % [int(event["leader"]), int(event["follower"])], "Net"
	)
	_broadcast_hand_link(int(event["leader"]), int(event["follower"]), false)


## Хост разослал факт связи (раздел 9.5): клиент ведомого начинает следование,
## оба игрока — анимации и скорость более медленного из цепочки (раздел 17).
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_hand_link(leader_peer: int, follower_peer: int, on: bool) -> void:
	if on:
		hand_links[leader_peer] = follower_peer
	else:
		hand_links.erase(leader_peer)
	EventBus.hand_link.emit(leader_peer, follower_peer, on)


func _broadcast_hand_link(leader: int, follower: int, on: bool) -> void:
	if is_networked():
		_send(func() -> void: rpc_hand_link.rpc(leader, follower, on), false)
	else:
		rpc_hand_link(leader, follower, on)


## Цепочка связей вниз от игрока (сам + ведомые; раздел 9.5: цепочки до 4):
## ведущий сбавляет бег до более медленного из всей цепочки (раздел 17).
func hand_chain_below(peer_id: int) -> Array[int]:
	var chain: Array[int] = [peer_id]
	var current := peer_id
	while hand_links.has(current) and chain.size() < Protocol.MAX_PLAYERS_HARD:
		current = int(hand_links[current])
		if chain.has(current):
			break  # страховка от цикла в испорченном состоянии
		chain.append(current)
	return chain


# --- Места у костра (раздел 9.6) ---

## Нажали E у свободной лавки (раздел 9.6): просим хоста подтвердить место.
func request_sit(seat_index: int) -> void:
	if is_host():
		_handle_sit(local_peer_id, seat_index)
	else:
		_send(func() -> void: rpc_id(1, "rpc_sit", seat_index), false)


@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_sit(seat_index: int) -> void:
	if not multiplayer.is_server():
		return
	_handle_sit(multiplayer.get_remote_sender_id(), seat_index)


## Проверка хоста (раздел 9.6): индекс места существует, игрок в радиусе
## лавки (расстояние по горизонтали и окно высоты). Занятость решает
## ActivityAuthority; подтверждение — всем одним состоянием.
func _handle_sit(peer: int, seat_index: int) -> void:
	var seats := _campfire_seats()
	if seat_index < 0 or seat_index >= seats.size():
		return
	var peer_pos: Vector3 = _peer_position(peer)
	if peer_pos == _POS_UNKNOWN:
		return
	var seat := seats[seat_index]
	var flat := peer_pos - seat.global_position
	flat.y = 0.0
	if flat.length() > B.campfire_seat_radius + B.mob_hit_slack \
			or absf(peer_pos.y - seat.global_position.y) > B.campfire_use_window:
		return
	if activity.try_sit(peer, seat_index, flat.length(), B).is_empty():
		return
	Log.info("Игрок %d сел у костра (место %d)" % [peer, seat_index + 1], "Net")
	_broadcast_seats()


## Игрок пошевелился сидя (раздел 9.6: любое движение — встать).
func request_stand_up() -> void:
	if is_host():
		_handle_stand_up(local_peer_id)
	else:
		_send(func() -> void: rpc_id(1, "rpc_stand_up"), false)


@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_stand_up() -> void:
	if not multiplayer.is_server():
		return
	_handle_stand_up(multiplayer.get_remote_sender_id())


func _handle_stand_up(peer: int) -> void:
	if activity.stand_up(peer).is_empty():
		return
	_broadcast_seats()


## Хост разослал занятость мест (раздел 9.6): узлы молчат у занятых лавок,
## игроки садятся/встают, костёр видит компанию.
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_campfire_seats(seats: Array) -> void:
	EventBus.campfire_seats.emit(seats)


func _broadcast_seats() -> void:
	var state := activity.seats_state()
	if is_networked():
		_send(func() -> void: rpc_campfire_seats.rpc(state), false)
	else:
		rpc_campfire_seats(state)


## Места у костра в порядке имени узла (Seat1..Seat8 — как benches IslandGen).
func _campfire_seats() -> Array[CampfireSeat]:
	var seats: Array[CampfireSeat] = []
	for node in get_tree().get_nodes_in_group(CampfireSeat.SEAT_GROUP):
		if node is CampfireSeat:
			seats.append(node as CampfireSeat)
	seats.sort_custom(
		func(a: CampfireSeat, b: CampfireSeat) -> bool: return a.name.naturalcasecmp_to(b.name) < 0
	)
	return seats


# --- Лестницы смотровых (раздел 9.3) ---

## Поднявшийся жмёт E у края смотровой (раздел 9.3): просим хост
## подтвердить сброс лестницы.
func request_drop_ladder(index: int) -> void:
	if is_host():
		_handle_drop_ladder(local_peer_id, index)
	else:
		_send(func() -> void: rpc_id(1, "rpc_request_ladder", index), false)


@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_request_ladder(index: int) -> void:
	if not multiplayer.is_server():
		return
	_handle_drop_ladder(multiplayer.get_remote_sender_id(), index)


## Проверка хоста (раздел 9.3): просящий стоит на площадке этой смотровой
## (окно высоты и радиус — от узла лестницы). Подтверждение — всем.
func _handle_drop_ladder(peer: int, index: int) -> void:
	var ladders := _lookout_ladders()
	if index < 0 or index >= ladders.size():
		return
	var peer_pos: Vector3 = _peer_position(peer)
	var ladder := ladders[index]
	if peer_pos != _POS_UNKNOWN:
		var flat := peer_pos - ladder.global_position
		flat.y = 0.0
		var on_top := flat.length() <= B.ladder_top_radius \
			and absf(peer_pos.y - ladder.global_position.y) <= B.ladder_top_window
		var event := activity.try_drop_ladder(index, world_time_sec(), on_top, B)
		if event.is_empty():
			return
		Log.info(
			"Лестница смотровой %d сброшена (peer %d, до %.0f с)"
			% [index + 1, peer, float(event["until"])], "Net"
		)
		_broadcast_ladder(index, true, float(event["until"]))


## Хост разослал состояние лестницы (раздел 9.3): узел рисует её
## или убирает; expires_at — время скрытия по world_time (−1 — не висит).
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_ladder(index: int, active: bool, expires_at: float) -> void:
	EventBus.ladder_state.emit(index, active, expires_at)


func _broadcast_ladder(index: int, active: bool, expires_at: float) -> void:
	if is_networked():
		_send(func() -> void: rpc_ladder.rpc(index, active, expires_at), false)
	else:
		rpc_ladder(index, active, expires_at)


# --- Маяки и Звездопад (раздел 7) ---

## Нажатие E у маяка (раздел 7): пара зажигает в пределах 3 с, одиночке
## (один в мире) хватает удержания 8 с — клиент уже держал E.
func request_beacon_light(index: int) -> void:
	if is_host():
		_handle_beacon_light(local_peer_id, index)
	else:
		_send(func() -> void: rpc_id(1, "rpc_beacon_light", index), false)


@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_beacon_light(index: int) -> void:
	if not multiplayer.is_server():
		return
	_handle_beacon_light(multiplayer.get_remote_sender_id(), index)


## Проверка хоста (раздел 7): просящий стоит у этого маяка (радиус узла
## и окно высоты). Зажигание — событие всем; очки и монеты — на клиентах.
func _handle_beacon_light(peer: int, index: int) -> void:
	var beacons := _beacon_nodes()
	if index < 0 or index >= beacons.size():
		return
	var peer_pos: Vector3 = _peer_position(peer)
	var beacon := beacons[index]
	if peer_pos != _POS_UNKNOWN:
		var flat := peer_pos - beacon.global_position
		flat.y = 0.0
		var near := flat.length() <= beacon.use_radius + B.mob_hit_slack \
			and absf(peer_pos.y - beacon.global_position.y) <= B.beacon_use_window
		if not near:
			return
	var event := activity.try_beacon_light(index, peer, world_time_sec(), in_world_count(), B)
	if event.is_empty():
		return
	var lighters: Array[int] = event["lighters"]
	Log.info(
		"Маяк %d зажжён (peer %s)%s"
		% [
			index + 1,
			", ".join(lighters.map(func(p: int) -> String: return str(p))),
			" — Звездопад!" if event.has("starfall_started_at") else "",
		],
		"Net",
	)
	_broadcast_beacons(lighters, float(event.get("starfall_started_at", -1.0)))


## Хост разослал состояние маяков (раздел 7): узлы рисуют лучи, доска —
## прогресс, монеты и очки — зажёгшим последний (Interactions).
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_beacons(lit: Array, lighters: Array, starfall_started_at: float) -> void:
	EventBus.beacons_state.emit(lit, lighters, starfall_started_at)
	if starfall_started_at >= 0.0:
		EventBus.toast_requested.emit("TOAST_STARFALL")
	if lighters.has(local_peer_id):
		Session.add_world_coins(B.beacon_reward)


func _broadcast_beacons(lighters: Array, starfall_started_at: float) -> void:
	var state := activity.beacons_state()
	if starfall_started_at >= 0.0:
		state["starfall_started_at"] = starfall_started_at
	var lit: Array = state["lit"]
	if is_networked():
		_send(
			func() -> void: rpc_beacons.rpc(lit, lighters, float(state["starfall_started_at"])),
			false,
		)
	else:
		rpc_beacons(lit, lighters, float(state["starfall_started_at"]))


## Касание звезды Звездопада (раздел 7): «кто первый» — решает хост.
func request_star_collect(index: int) -> void:
	if is_host():
		_handle_star_collect(local_peer_id, index)
	else:
		_send(func() -> void: rpc_id(1, "rpc_collect_star", index), false)


@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_collect_star(index: int) -> void:
	if not multiplayer.is_server():
		return
	_handle_star_collect(multiplayer.get_remote_sender_id(), index)


func _handle_star_collect(peer: int, index: int) -> void:
	var event := activity.try_take_star(index, peer, world_time_sec(), B)
	if event.is_empty():
		return
	Log.info("Звезда %d подобрана (peer %d)" % [index, peer], "Net")
	_broadcast_star_taken(index, peer)


## Хост подтвердил подбор звезды: звезда исчезает у всех, монета — собравшему.
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_star_taken(index: int, collector_peer: int) -> void:
	EventBus.star_taken.emit(index, collector_peer)
	if collector_peer == local_peer_id:
		Session.add_world_coins(B.star_reward)


func _broadcast_star_taken(index: int, collector_peer: int) -> void:
	if is_networked():
		_send(func() -> void: rpc_star_taken.rpc(index, collector_peer), false)
	else:
		rpc_star_taken(index, collector_peer)


# --- Тик активностей хоста (раздел 9: плиты и зоны по снапшотам) ---

## Периодическая проверка активностей хостом: кто стоит на плитах руин,
## есть ли игрок у закрытых ворот (запасной путь, раздел 9.2), истекли ли
## лестницы смотровых (раздел 9.3). Узлы берёт из групп — остров у всех
## одинаковый (раздел 6).
func _tick_activities() -> void:
	if not Session.in_world:
		return
	var entries := _world_player_entries()
	var plates := _ruin_plates()
	var plate_peers: Array[int] = []
	for plate: RuinPlate in plates:
		plate_peers.append(_peer_on_plate(plate, entries))
	var gate := _first_node(RuinGate.GROUP)
	var anyone_at_gate := false
	if gate != null:
		anyone_at_gate = _anyone_in_radius(entries, gate.global_position, B.gate_near_radius)
	var event := activity.update_ruins_gate(
		plate_peers, in_world_count(), anyone_at_gate, world_time_sec(), B
	)
	if not event.is_empty():
		_open_ruins_event(event, entries)
	# «За руку» (раздел 9.5): связь рвётся при расстоянии больше 4 м и когда
	# кто-то из пары вышел из мира (событие — всем, как разрыв по F).
	var hand_event := activity.update_hand_links(entries, B)
	if not hand_event.is_empty():
		Log.info(
			"За руку: %d и %d расцепились (расстояние/выход из мира)"
			% [int(hand_event["leader"]), int(hand_event["follower"])], "Net"
		)
		_broadcast_hand_link(int(hand_event["leader"]), int(hand_event["follower"]), false)
	# Места у костра (раздел 9.6): вышедший из мира освобождает лавку.
	activity.setup_seats(_campfire_seats().size())
	var seat_event := activity.update_seats(entries)
	if not seat_event.is_empty():
		Log.info(
			"Игрок %d вышел из мира — место %d у костра свободно"
			% [int(seat_event["peer"]), int(seat_event["seat"]) + 1], "Net"
		)
		_broadcast_seats()
	# Лестницы смотровых (раздел 9.3): считаем один раз за тик, скрытие —
	# событием всем (узлы убирают лестницу, сброс возможен снова).
	activity.setup_ladders(_lookout_ladders().size())
	var ladder_event := activity.update_ladders(world_time_sec())
	if not ladder_event.is_empty():
		Log.info("Лестница смотровой %d скрылась (60 с истекли)" % [int(ladder_event["index"]) + 1], "Net")
		_broadcast_ladder(int(ladder_event["index"]), false, -1.0)
	# Цикл маяков (раздел 7): конец Звездопада и гашение через 15 минут —
	# маяки тухнут всем, цикл можно начинать снова.
	activity.setup_beacons(_beacon_nodes().size())
	var beacon_event := activity.update_beacons(world_time_sec(), B)
	if not beacon_event.is_empty():
		if beacon_event.has("starfall_ended"):
			Log.info("Звездопад закончился (маяки погаснут через %d с)" % int(B.beacon_reset_sec), "Net")
		else:
			Log.info("Маяки погасли (15 минут после Звездопада) — цикл заново", "Net")
			_broadcast_beacons([], -1.0)


## Событие ворот руин от authority: лог, награда сундука в момент открытия
## и рассылка состояния всем.
func _open_ruins_event(event: Dictionary, entries: Array[Dictionary]) -> void:
	var openers: Array[int] = event.get("openers", [])
	var reward_peers: Array[int] = []
	if event.has("opened"):
		# Награда сундука — в момент открытия ворот (раздел 8): каждому
		# в радиусе 10 м от сундука.
		var chest := _first_node(RuinChest.GROUP)
		if chest != null:
			reward_peers = ActivityAuthority.peers_in_radius(
				entries, chest.global_position, B.chest_radius
			)
		Log.info(
			"Ворота руин открыты (%s), сундук: награда %d игрокам"
			% ["плиты" if not openers.is_empty() else "запасной путь", reward_peers.size()],
			"Net",
		)
	elif event.has("closed"):
		Log.info("Ворота руин закрылись (10 минут истекли), сундук сброшен", "Net")
	var state := activity.ruins_state()
	_broadcast_ruins(bool(state["gate_open"]), state["plates"], openers, reward_peers)


## Все игроки в мире: {peer, pos, floor} — позиции и флаг «на земле»
## (снапшот или свой персонаж).
func _world_player_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for peer_id: int in players.keys():
		if not _peer_in_world(peer_id):
			continue
		var pos := _peer_position(peer_id)
		if pos == _POS_UNKNOWN:
			continue
		var on_floor := false
		if peer_id == local_peer_id:
			on_floor = _local_player != null and _local_player.is_on_floor()
		else:
			on_floor = (int(_peer_flags.get(peer_id, 0)) & Protocol.FLAG_ON_FLOOR) != 0
		entries.append({"peer": peer_id, "pos": pos, "floor": on_floor})
	return entries


## Peer игрока, стоящего на плите (раздел 9.2): в радиусе по горизонтали,
## в окне высоты и на земле; 0 — плита свободна.
func _peer_on_plate(plate: RuinPlate, entries: Array[Dictionary]) -> int:
	for entry: Dictionary in entries:
		if not bool(entry["floor"]):
			continue
		var pos: Vector3 = entry["pos"]
		if absf(pos.y - plate.global_position.y) > B.plate_height_window:
			continue
		var flat := pos - plate.global_position
		flat.y = 0.0
		if flat.length() <= B.plate_radius:
			return int(entry["peer"])
	return 0


func _anyone_in_radius(entries: Array[Dictionary], center: Vector3, radius: float) -> bool:
	for entry: Dictionary in entries:
		var flat: Vector3 = entry["pos"] - center
		flat.y = 0.0
		if flat.length() <= radius:
			return true
	return false


## Плиты у ворот в порядке имени узла (Plate1..Plate3 генерирует остров).
func _ruin_plates() -> Array[RuinPlate]:
	var plates: Array[RuinPlate] = []
	for node in get_tree().get_nodes_in_group(RuinPlate.GROUP):
		if node is RuinPlate:
			plates.append(node as RuinPlate)
	plates.sort_custom(
		func(a: RuinPlate, b: RuinPlate) -> bool: return a.name.naturalcasecmp_to(b.name) < 0
	)
	return plates


## Лестницы смотровых в порядке имени узла (LookoutLadder1..4 — как LOOKOUTS).
func _lookout_ladders() -> Array[LookoutLadder]:
	var ladders: Array[LookoutLadder] = []
	for node in get_tree().get_nodes_in_group(LookoutLadder.LADDER_GROUP):
		if node is LookoutLadder:
			ladders.append(node as LookoutLadder)
	ladders.sort_custom(
		func(a: LookoutLadder, b: LookoutLadder) -> bool: return a.name.naturalcasecmp_to(b.name) < 0
	)
	return ladders


## Маяки в порядке имени узла (Beacon1..5 — как _beacons у IslandGen).
func _beacon_nodes() -> Array[Beacon]:
	var beacons: Array[Beacon] = []
	for node in get_tree().get_nodes_in_group(Beacon.BEACON_GROUP):
		if node is Beacon:
			beacons.append(node as Beacon)
	beacons.sort_custom(
		func(a: Beacon, b: Beacon) -> bool: return a.name.naturalcasecmp_to(b.name) < 0
	)
	return beacons


func _first_node(group: StringName) -> Node3D:
	for node in get_tree().get_nodes_in_group(group):
		if node is Node3D:
			return node as Node3D
	return null


## Хост разослал состояние ворот руин (раздел 9.2): узлы рисуют плиту/плиты/
## крышку сундука, очки Interactions — участникам плит, монеты — reward_peers.
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_ruins(open: bool, plates: Array, openers: Array, reward_peers: Array) -> void:
	EventBus.ruins_state.emit(open, plates, openers, reward_peers)
	if reward_peers.has(local_peer_id):
		Session.add_world_coins(B.chest_reward)


func _broadcast_ruins(
	open: bool, plates: Array, openers: Array, reward_peers: Array
) -> void:
	if is_networked():
		_send(func() -> void: rpc_ruins.rpc(open, plates, openers, reward_peers), false)
	else:
		rpc_ruins(open, plates, openers, reward_peers)


## Применить активности из world_state (вход в любой момент, раздел 10):
## открытые ворота и сундук — без повторной награды и очков, висящие
## лестницы — узлы рисуют сразу.
func _apply_activities(state: Dictionary) -> void:
	var activities: Dictionary = state.get("activities", {})
	if activities.is_empty():
		return
	var ruins: Dictionary = activities.get("ruins", {})
	if not ruins.is_empty():
		EventBus.ruins_state.emit(
			bool(ruins.get("gate_open", false)),
			ruins.get("plates", []),
			[],
			[],
		)
	for ladder: Dictionary in activities.get("ladders", []):
		EventBus.ladder_state.emit(
			int(ladder.get("index", -1)), true, float(ladder.get("until", -1.0))
		)
	var beacons: Dictionary = activities.get("beacons", {})
	if not beacons.is_empty():
		EventBus.beacons_state.emit(
			beacons.get("lit", []), [], float(beacons.get("starfall_started_at", -1.0))
		)
	for index: int in activities.get("stars_taken", []):
		EventBus.star_taken.emit(index, 0)
	var seats: Array = activities.get("seats", [])
	if not seats.is_empty():
		EventBus.campfire_seats.emit(seats)


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
		players[local_peer_id] = _new_local_slot()
	_send(func() -> void: rpc_hello.rpc(_display_name(), Save.load_character()), false)
	if mode == "steam":
		# Лобби подключено и хост ответил — можно загружать остров (раздел 11).
		EventBus.steam_world_ready.emit()


func _on_peer_connected(peer_id: int) -> void:
	# Ждём rpc_hello от клиента: имя и место в ростере придут с ним.
	Log.info("Пир подключился: %d" % peer_id, "Net")


func _on_peer_disconnected(peer_id: int) -> void:
	Log.warn("Пир отключился: %d" % peer_id, "Net")
	_peer_pos.erase(peer_id)
	_peer_flags.erase(peer_id)
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
	players[local_peer_id] = _new_local_slot()
	world_epoch_msec = 0
	clock.clear()
	_peer_pos.clear()
	_peer_flags.clear()
	_aoi.clear()
	_seq = 0
	last_world_state = {}
	hand_links.clear()
	authority.clear()
	activity.clear()
	_activity_accum = 0.0
	if was_steam:
		# Раздел 11: выход из мира — выход из лобби (Rich Presence очищается).
		SteamService.leave_lobby()


func _kick(peer_id: int) -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


# --- Вспомогательное ---

## Сентинел «позиция игрока неизвестна» (снапшотов ещё не было).
const _POS_UNKNOWN := Vector3(INF, INF, INF)


func _new_slot(player_name: String, character: int = 0) -> Dictionary:
	return {"name": player_name, "in_world": false, "character": character}


## Слот локального игрока: персонаж — выбранный на экране «Персонаж»
## (раздел 16, сохранение в user://, дефолт — первый).
func _new_local_slot() -> Dictionary:
	return _new_slot(_display_name(), Save.load_character())


## Номер персонажа игрока в ростере (раздел 16): им сцены ставят модель.
func peer_character(peer_id: int) -> int:
	var slot: Variant = players.get(peer_id)
	if slot == null:
		return 0
	return int(slot.get("character", 0))


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
			"character": int(players[peer_id].get("character", 0)),
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
