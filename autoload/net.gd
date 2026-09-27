# NetworkManager (раздел 8 SPEC): выбор транспорта (ENet для разработки, Steam —
# этап 4), подключение и хранение пиров, RPC-протокол, снапшоты 20 Гц с
# ретрансляцией через хост, синхронизация часов. Здесь же авторитет хоста
# (раздел 6): попадания по мобам, подбор монет «первый коснувшийся»,
# чекпоинты и возврат из «Висит». В одиночной игре (без сети) локально
# исполняет роль хоста — те же сигналы EventBus, что и в сетевом режиме.
# Не делает: голос (этап 5), Steam-лобби и данные лобби (этап 4).
extends Node

const B: Balance = preload("res://gameplay/balance.tres")
const RUN_SCENE: String = "res://scenes/run.tscn"

## Причина конца забега (rpc_run_ended).
enum RunEndReason {
	ALL_FINISHED = 0,   # все дошли до финиша
	FINISH_WAIT = 1,    # истёк отсчёт после первого финиша (раздел 7.6)
	TIME_LIMIT = 2,     # жёсткий лимит забега (раздел 5)
}

## Активный режим: "none" (одиночная игра) | "dev-host" | "dev-join" | "steam" (этап 4).
var mode: String = "none"

var transport: Transport = null
var clock := ClockSync.new()
## Свой peer id (в одиночной игре — 1).
var local_peer_id: int = 1
## Участники: peer_id -> {name: String, ready: bool, checkpoint: int, finished: bool}.
var players: Dictionary = {}

## Время GO по часам хоста, мс (0 — ещё не назначено).
var go_host_msec: int = 0

var _lobby_locked: bool = false
var _awaiting_go: bool = false
var _ready_deadline_msec: int = 0
var _first_finish_run_time: float = -1.0

# --- Хост-авторитет (раздел 6) ---

var _mobs: Dictionary = {}            # spawn_id -> Mob
var _checkpoints: Array[Vector2] = [] # [0] — стартовая точка, далее по index
var _picked_coins: Dictionary = {}    # spawn_id -> peer_id победителя
var _killed_mobs: Dictionary = {}     # spawn_id -> true
var _last_hit_msec: Dictionary = {}   # peer_id -> мс последнего подтверждённого удара

# --- Снапшоты и удалённые игроки ---

var _local_player: Player = null
var _remotes: Dictionary = {}  # peer_id -> RemotePlayer
var _seq: int = 0
var _send_accum: float = 0.0
var _ping_accum: float = 0.0
var _net_log: bool = false

## Счётчики снапшотного трафика, байт (для панели F3).
var bytes_sent: int = 0
var bytes_received: int = 0


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
				Log.info(
					"Хост ENet на порту %d (эмуляция: лаг %d мс, потеря %d%%)"
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
		Log.info("Сеть не запущена: одиночная игра (Steam-режим — этап 4)", "Net")

	# События геймплея уходят в сеть (или подтверждаются локально в одиночной игре).
	EventBus.coin_pickup_requested.connect(_on_coin_requested)
	EventBus.mob_hit_requested.connect(_on_mob_hit_requested)
	EventBus.checkpoint_reached.connect(_on_checkpoint_reached)
	EventBus.hang_started.connect(_on_hang_started)
	EventBus.hang_ended.connect(_on_hang_ended)
	EventBus.player_finished.connect(_on_player_finished)


func _process(delta: float) -> void:
	# Часы забега у всех — по часам хоста (раздел 8).
	if Session.run_active:
		Session.run_time = run_time_now()
		_check_run_end_conditions()
	if _awaiting_go and _ready_deadline_msec > 0 and Time.get_ticks_msec() >= _ready_deadline_msec:
		_send_go()  # раздел 8: старт не позже 15 с, даже если не все готовы
	if is_networked() and _local_player != null and Session.run_active:
		_send_accum += delta
		if _send_accum >= 1.0 / Protocol.SNAPSHOT_HZ:
			_send_accum -= 1.0 / Protocol.SNAPSHOT_HZ
			_send_own_snapshot()
	if is_networked() and not is_host():
		_ping_accum += delta
		if _ping_accum >= Protocol.CLOCK_PING_INTERVAL:
			_ping_accum = 0.0
			var now: int = Time.get_ticks_msec()
			_send(func() -> void: rpc_id(1, "rpc_ping", now), true)


# --- Публичный интерфейс ---

func is_networked() -> bool:
	return transport != null


## Я — хост (в одиночной игре — всегда true: локальная роль хоста).
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


## Запустить сетевой забег (кнопка «Играть» у хоста): фиксирует seed,
## закрывает лобби и рассылает rpc_start_run (раздел 8).
func start_run_as_host() -> void:
	if not is_host():
		return
	Session.begin_run()
	_reset_run_state()
	_lobby_locked = true
	Log.info("Старт сетевого забега: seed=%d, игроков=%d" % [Session.level_seed, players.size()], "Net")
	if is_networked():
		rpc_start_run.rpc(Session.level_seed, _roster_entries())
	_enter_run_scene()


## Сцена забега собрала уровень: хост включает отсчёт готовности, клиент
## сообщает rpc_client_ready (раздел 8, шаг 2).
func report_ready() -> void:
	if not is_networked():
		return
	if multiplayer.is_server():
		players[local_peer_id]["ready"] = true
		_awaiting_go = true
		if _ready_deadline_msec == 0:
			_ready_deadline_msec = Time.get_ticks_msec() + int(Protocol.START_READY_TIMEOUT * 1000.0)
		_try_send_go()
	else:
		_send(func() -> void: rpc_client_ready.rpc(), false)


## Сцена забега передаёт хосту мир для проверок: мобов и точки чекпоинтов.
func bind_world(mobs: Dictionary, checkpoints: Array[Vector2]) -> void:
	_mobs = mobs
	_checkpoints = checkpoints


## Свой персонаж (для снапшотов) и удалённые игроки (для доставки снапшотов).
func set_local_player(player: Player) -> void:
	_local_player = player


func register_remote(peer_id: int, remote: RemotePlayer) -> void:
	_remotes[peer_id] = remote


func clear_remotes() -> void:
	_remotes.clear()


## Локальный GO в одиночной игре: часы пошли сейчас.
func mark_go_now() -> void:
	go_host_msec = Time.get_ticks_msec()


## Время GO назначено хостом (есть ли отсчёт).
func go_scheduled() -> bool:
	return go_host_msec > 0


## Сколько секунд до GO по часам хоста; −1 — GO ещё не назначен.
func seconds_until_go() -> float:
	if go_host_msec <= 0:
		return -1.0
	return float(go_host_msec - host_time_now_msec()) / 1000.0


## Время хоста в мс: локальные часы плюс сглаженное смещение.
func host_time_now_msec() -> int:
	if is_networked() and not multiplayer.is_server():
		return Time.get_ticks_msec() + int(round(clock.offset_msec()))
	return Time.get_ticks_msec()


## run_time по часам хоста (раздел 6): одинаков у всех участников.
func run_time_now() -> float:
	if Session.go_host_msec <= 0:
		return 0.0
	return maxf(0.0, float(host_time_now_msec() - Session.go_host_msec) / 1000.0)


## RTT до хоста, мс (для панели F3; −1 — замеров нет).
func ping_msec() -> int:
	if is_networked() and not multiplayer.is_server():
		return clock.last_rtt_msec()
	return -1


## Последняя позиция удалённого игрока по снапшотам (для проверок хоста).
func remote_position(peer_id: int) -> Vector2:
	var remote: RemotePlayer = _remotes.get(peer_id)
	if remote == null:
		return Vector2.INF
	return remote.last_position()


# --- RPC-протокол (раздел 8) ---

## Клиент представляется хосту после подключения.
@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_hello(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if _lobby_locked or Session.run_active:
		# Раздел 8: подключение к уже идущему забегу запрещено.
		Log.warn("Пир %d отключён: забег уже идёт" % sender, "Net")
		_kick(sender)
		return
	if players.size() >= Protocol.MAX_PLAYERS:
		Log.warn("Пир %d отключён: лобби заполнено" % sender, "Net")
		_kick(sender)
		return
	players[sender] = _new_slot(player_name.left(20))  # раздел 12: ник до 20 символов
	Log.info("Игрок подключился: %d «%s» (всего %d)" % [sender, player_name, players.size()], "Net")
	_broadcast_roster()


## Хост рассылает состав участников (и удаляет вышедших у клиентов).
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_roster_update(entries: Array) -> void:
	var fresh: Dictionary = {}
	for entry: Dictionary in entries:
		fresh[int(entry["peer_id"])] = _new_slot(str(entry["name"]), bool(entry["finished"]))
	# Кого не стало — сообщить сценам (персонаж исчезает, раздел 8).
	for old_id: int in players.keys():
		if old_id != local_peer_id and not fresh.has(old_id):
			EventBus.peer_left.emit(old_id)
			_remotes.erase(old_id)
	players = fresh
	EventBus.roster_changed.emit(players.size())


## Хост начинает забег: seed и состав (раздел 8, шаг 1).
@rpc("authority", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_start_run(seed_value: int, roster: Array) -> void:
	Session.level_seed = seed_value
	_reset_run_state()
	_apply_roster(roster)
	Log.info("Хост начал забег: seed=%d, игроков=%d" % [seed_value, roster.size()], "Net")
	_enter_run_scene()


## Клиент собрал уровень и готов (раздел 8, шаг 2).
@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_client_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if players.has(sender):
		players[sender]["ready"] = true
		if Dev.log_net:
			Log.debug("rpc_client_ready от %d" % sender, "Net")
		_try_send_go()


## Хост назначает GO на 3 с позже своего времени (раздел 8, шаг 3).
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_go(go_host_time: int) -> void:
	go_host_msec = go_host_time
	EventBus.run_go_scheduled.emit()


## Снапшот игрока (раздел 8): клиент шлёт хосту (peer_id = 0), хост вписывает
## отправителя и пересылает остальным без изменений.
@rpc("any_peer", "call_remote", "unreliable_ordered", Protocol.CHANNEL_SNAPSHOT)
func rpc_snapshot(peer_id: int, data: PackedByteArray) -> void:
	if multiplayer.is_server():
		var sender: int = multiplayer.get_remote_sender_id()
		bytes_received += data.size()
		if _net_log:
			Log.debug("rpc_snapshot от %d: %d байт" % [sender, data.size()], "Net")
		_deliver_snapshot(sender, data)
		for pid: int in multiplayer.get_peers():
			if pid == sender:
				continue
			_send(func() -> void: rpc_id(pid, "rpc_snapshot", sender, data), true)
	else:
		if peer_id == local_peer_id:
			return
		bytes_received += data.size()
		_deliver_snapshot(peer_id, data)


## Ping часов (раздел 8): клиент раз в секунду.
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


## Клиент просит засчитать попадание по мобу (раздел 6, шаг 2).
@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_hit_mob(spawn_id: int, client_run_time: float) -> void:
	if not multiplayer.is_server():
		return
	_host_handle_hit(multiplayer.get_remote_sender_id(), spawn_id, client_run_time)


## Хост подтвердил смерть моба (раздел 6, шаг 4).
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_mob_killed(spawn_id: int, killer_ids: Array, coins: int) -> void:
	_apply_mob_killed(spawn_id, killer_ids, coins)


## Клиент просит забрать монету (раздел 6: первый коснувшийся).
@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_pickup_coin(spawn_id: int) -> void:
	if not multiplayer.is_server():
		return
	_host_handle_coin(multiplayer.get_remote_sender_id(), spawn_id)


## Хост подтвердил подбор монеты; достаётся одному — победителю.
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_coin_picked(spawn_id: int, winner_peer: int) -> void:
	_apply_coin_picked(spawn_id, winner_peer)


## Клиент дошёл до чекпоинта секции (точку возврата помнит хост).
@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_checkpoint(index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if players.has(sender):
		players[sender]["checkpoint"] = index


## Клиент упал в пропасть и висит (раздел 7.1).
@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_hang() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	players[sender]["hanging"] = true
	_broadcast_hang(sender, true)


## Состояние «Висит» игрока — всем (иконка и анимация у чужих персонажей).
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_hang_state(peer_id: int, hanging: bool) -> void:
	_apply_hang(peer_id, hanging)


## Клиент сдаётся или истёк таймаут 8 с — просит возврат на чекпоинт.
@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_give_up() -> void:
	if not multiplayer.is_server():
		return
	_host_respawn(multiplayer.get_remote_sender_id())


## Хост возвращает игрока на чекпоинт (раздел 7.1).
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_respawn(peer_id: int, position: Vector2) -> void:
	_apply_respawn(peer_id, position)


## Клиент финишировал (раздел 8: старт, финиш, конец забега решает хост).
@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_player_finished(run_time: float) -> void:
	if not multiplayer.is_server():
		return
	_host_handle_finished(multiplayer.get_remote_sender_id(), run_time)


## Хост завершил забег для всех.
@rpc("authority", "call_local", "reliable", Protocol.CHANNEL_RELIABLE)
func rpc_run_ended(reason: int) -> void:
	_apply_run_ended(reason)


# --- Обработка событий геймплея (единый путь для соло и сети) ---

func _on_coin_requested(spawn_id: int) -> void:
	if is_host():
		_host_handle_coin(local_peer_id, spawn_id)
	else:
		_send(func() -> void: rpc_pickup_coin.rpc(spawn_id), false)


func _on_mob_hit_requested(spawn_id: int, run_time: float, from_position: Vector2) -> void:
	if is_host():
		_host_handle_hit(local_peer_id, spawn_id, run_time, from_position)
	else:
		_send(func() -> void: rpc_hit_mob.rpc(spawn_id, run_time), false)


func _on_checkpoint_reached(index: int, _position: Vector2) -> void:
	if is_host():
		players[local_peer_id]["checkpoint"] = index
	else:
		_send(func() -> void: rpc_checkpoint.rpc(index), false)


func _on_hang_started() -> void:
	if not Session.run_active:
		return
	if is_host():
		players[local_peer_id]["hanging"] = true
		_broadcast_hang(local_peer_id, true)
	else:
		_send(func() -> void: rpc_hang.rpc(), false)


func _on_hang_ended() -> void:
	if not Session.run_active:
		return
	if is_host():
		_host_respawn(local_peer_id)
	else:
		_send(func() -> void: rpc_give_up.rpc(), false)


func _on_player_finished(run_time: float) -> void:
	if Session.player_finished:
		return  # повторный вход в финишную зону ничего не начисляет
	Session.add_run_coins(B.finish_coins)  # раздел 6: за финиш — 5 монет
	Session.player_finished = true
	if is_host():
		_host_handle_finished(local_peer_id, run_time)
	else:
		_send(func() -> void: rpc_player_finished.rpc(run_time), false)


# --- Логика хоста (раздел 6: всё, что даёт награду, решает хост) ---

## Монета: первый запрос выигрывает, остальные отклоняются.
func _host_handle_coin(peer_id: int, spawn_id: int) -> void:
	if _picked_coins.has(spawn_id):
		return
	_picked_coins[spawn_id] = peer_id
	_broadcast_coin_picked(spawn_id, peer_id)


## Попадание по мобу: моб жив, атакующий в пределах 96 px от расчётной
## позиции моба на время клиента, перезарядка соблюдена (раздел 6, шаг 3).
func _host_handle_hit(peer_id: int, spawn_id: int, at_run_time: float, from_position: Vector2 = Vector2.ZERO) -> void:
	if _killed_mobs.has(spawn_id):
		return
	var mob: Mob = _mobs.get(spawn_id)
	if mob == null:
		return
	var attacker: Vector2 = from_position if peer_id == local_peer_id else remote_position(peer_id)
	if attacker == Vector2.INF:
		return
	if attacker.distance_to(mob.position_at(at_run_time)) > B.hit_accept_range:
		if _net_log:
			Log.debug("Отказ попадания %d по мобу %d: дистанция" % [peer_id, spawn_id], "Net")
		return
	var now: int = Time.get_ticks_msec()
	var min_gap_msec: int = int(maxf(0.0, B.attack_cooldown - Protocol.HIT_COOLDOWN_TOLERANCE) * 1000.0)
	if _last_hit_msec.has(peer_id) and now - int(_last_hit_msec[peer_id]) < min_gap_msec:
		if _net_log:
			Log.debug("Отказ попадания %d по мобу %d: перезарядка" % [peer_id, spawn_id], "Net")
		return
	_last_hit_msec[peer_id] = now
	_killed_mobs[spawn_id] = true
	Log.debug("Моб %d убит игроком %d" % [spawn_id, peer_id], "Net")
	_broadcast_mob_killed(spawn_id, [peer_id], B.mob_kill_coins)


## Финиш игрока: запускает отсчёт 90 с после первого, конец — когда дошли все.
func _host_handle_finished(peer_id: int, run_time: float) -> void:
	if not players.has(peer_id) or players[peer_id]["finished"]:
		return
	players[peer_id]["finished"] = true
	Log.info("Игрок %d финишировал за %.1f с" % [peer_id, run_time], "Net")
	if _first_finish_run_time < 0.0:
		_first_finish_run_time = Session.run_time
	var all_done: bool = true
	for slot: Dictionary in players.values():
		if not slot["finished"]:
			all_done = false
			break
	if all_done:
		_host_end_run(RunEndReason.ALL_FINISHED)


## Условия конца забега, которые считает только хост (разделы 5, 7.6).
func _check_run_end_conditions() -> void:
	if not is_host():
		return
	if Session.run_time >= B.run_time_limit:
		_host_end_run(RunEndReason.TIME_LIMIT)
	elif _first_finish_run_time >= 0.0 and Session.run_time - _first_finish_run_time >= B.finish_wait_time:
		_host_end_run(RunEndReason.FINISH_WAIT)


func _host_end_run(reason: int) -> void:
	if not Session.run_active:
		return
	_lobby_locked = false
	if is_networked():
		rpc_run_ended.rpc(reason)
	_apply_run_ended(reason)


## Возврат игрока на его чекпоинт: позицию выбирает и рассылает хост.
func _host_respawn(peer_id: int) -> void:
	var index: int = 0
	if players.has(peer_id):
		index = int(players[peer_id]["checkpoint"])
	var position: Vector2 = _checkpoint_position(index)
	_broadcast_respawn(peer_id, position)


func _checkpoint_position(index: int) -> Vector2:
	if _checkpoints.is_empty():
		return Vector2.ZERO
	return _checkpoints[clampi(index, 0, _checkpoints.size() - 1)]


# --- Рассылка и применение событий ---

func _broadcast_roster() -> void:
	if is_networked():
		rpc_roster_update.rpc(_roster_entries())
	else:
		EventBus.roster_changed.emit(players.size())


func _broadcast_coin_picked(spawn_id: int, winner_peer: int) -> void:
	if is_networked():
		rpc_coin_picked.rpc(spawn_id, winner_peer)
	else:
		_apply_coin_picked(spawn_id, winner_peer)


func _broadcast_mob_killed(spawn_id: int, killer_ids: Array, coins: int) -> void:
	if is_networked():
		rpc_mob_killed.rpc(spawn_id, killer_ids, coins)
	else:
		_apply_mob_killed(spawn_id, killer_ids, coins)


func _broadcast_hang(peer_id: int, hanging: bool) -> void:
	if is_networked():
		rpc_hang_state.rpc(peer_id, hanging)
	else:
		_apply_hang(peer_id, hanging)


func _broadcast_respawn(peer_id: int, position: Vector2) -> void:
	if is_networked():
		rpc_respawn.rpc(peer_id, position)
	else:
		_apply_respawn(peer_id, position)


func _apply_coin_picked(spawn_id: int, winner_peer: int) -> void:
	EventBus.coin_picked.emit(spawn_id, winner_peer)
	if winner_peer == local_peer_id:
		Session.add_run_coins(B.coin_value)


func _apply_mob_killed(spawn_id: int, killer_ids: Array, coins: int) -> void:
	# RPC приносит нетипизированный Array — сигнал объявлен как Array[int].
	var killers: Array[int] = []
	for pid: int in killer_ids:
		killers.append(int(pid))
	EventBus.mob_killed.emit(spawn_id, killers)
	if local_peer_id in killers:
		Session.add_run_coins(coins)


func _apply_hang(peer_id: int, hanging: bool) -> void:
	if peer_id == local_peer_id:
		return  # своё состояние «Висит» игрок ведёт сам
	if players.has(peer_id):
		players[peer_id]["hanging"] = hanging
	var remote: RemotePlayer = _remotes.get(peer_id)
	if remote != null:
		remote.set_remote_hanging(hanging)


func _apply_respawn(peer_id: int, position: Vector2) -> void:
	_apply_hang(peer_id, false)
	if peer_id == local_peer_id:
		EventBus.player_respawned.emit(position)
	else:
		var remote: RemotePlayer = _remotes.get(peer_id)
		if remote != null:
			remote.teleport(position)


func _apply_run_ended(reason: int) -> void:
	if not Session.run_active:
		return
	Session.end_run(Session.player_finished)
	EventBus.run_finished.emit(Session.player_finished, Session.run_time)
	Log.info("Забег завершён для всех (причина %d)" % reason, "Net")


func _apply_roster(entries: Array) -> void:
	var fresh: Dictionary = {}
	for entry: Dictionary in entries:
		fresh[int(entry["peer_id"])] = _new_slot(str(entry["name"]), bool(entry["finished"]))
	players = fresh
	EventBus.roster_changed.emit(players.size())


# --- Старт забега по протоколу раздела 8 ---

func _try_send_go() -> void:
	if not _awaiting_go:
		return
	for slot: Dictionary in players.values():
		if not slot["ready"]:
			return
	_send_go()


func _send_go() -> void:
	if not _awaiting_go:
		return
	_awaiting_go = false
	_ready_deadline_msec = 0
	var go_at: int = host_time_now_msec() + int(Protocol.GO_DELAY * 1000.0)
	if is_networked():
		rpc_go.rpc(go_at)
	else:
		go_host_msec = go_at
		EventBus.run_go_scheduled.emit()
	Log.info("GO назначен на %d мс (через %.1f с)" % [go_at, Protocol.GO_DELAY], "Net")


func _enter_run_scene() -> void:
	get_tree().call_deferred("change_scene_to_file", RUN_SCENE)


func _reset_run_state() -> void:
	_mobs.clear()
	_checkpoints.clear()
	_picked_coins.clear()
	_killed_mobs.clear()
	_last_hit_msec.clear()
	_remotes.clear()
	go_host_msec = 0
	_first_finish_run_time = -1.0
	_awaiting_go = false
	_ready_deadline_msec = 0
	_seq = 0
	for slot: Dictionary in players.values():
		slot["ready"] = false
		slot["checkpoint"] = 0
		slot["finished"] = false
		slot["hanging"] = false


# --- Снапшоты ---

func _send_own_snapshot() -> void:
	if _local_player == null:
		return
	var data := Snapshot.pack(
		_seq, _local_player.global_position.x, _local_player.global_position.y,
		_local_player.velocity.x, _local_player.velocity.y,
		_local_player.get_anim_state(), _local_player.get_flags()
	)
	_seq = (_seq + 1) & 0xFFFF
	bytes_sent += data.size()
	if multiplayer.is_server():
		for pid: int in multiplayer.get_peers():
			_send(func() -> void: rpc_id(pid, "rpc_snapshot", local_peer_id, data), true)
	else:
		_send(func() -> void: rpc_id(1, "rpc_snapshot", 0, data), true)


func _deliver_snapshot(peer_id: int, data: PackedByteArray) -> void:
	var remote: RemotePlayer = _remotes.get(peer_id)
	if remote == null:
		return
	remote.apply_snapshot(Snapshot.unpack(data), Time.get_ticks_msec())


# --- Подключения (раздел 8: отключения) ---

## Клиент успешно подключился к хосту: представляемся (rpc_hello).
func _on_connected_to_server() -> void:
	Log.info("Подключение к хосту установлено, peer id %d" % multiplayer.get_unique_id(), "Net")
	local_peer_id = multiplayer.get_unique_id()
	if not players.has(local_peer_id):
		players[local_peer_id] = _new_slot(_display_name())
	_send(func() -> void: rpc_hello.rpc(_display_name()), false)


func _on_peer_connected(peer_id: int) -> void:
	Log.info("Пир подключился: %d" % peer_id, "Net")
	if multiplayer.is_server() and (_lobby_locked or Session.run_active):
		Log.warn("Пир %d отключён: подключение к идущему забегу запрещено" % peer_id, "Net")
		_kick(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	Log.warn("Пир отключился: %d" % peer_id, "Net")
	if multiplayer.is_server():
		players.erase(peer_id)
		_broadcast_roster()
	else:
		# Клиенты соединены звездой с хостом: потеря хоста = конец забега.
		_on_host_lost("Пир %d покинул игру" % peer_id)


func _on_server_disconnected() -> void:
	_on_host_lost("Соединение с хостом потеряно")


func _on_connection_failed() -> void:
	Log.error("Не удалось подключиться к хосту %s" % Dev.join_address, "Net")
	_teardown_network()
	EventBus.host_lost.emit("Не удалось подключиться")


func _on_host_lost(reason: String) -> void:
	# Раздел 8: хост отключился — забег завершается у всех с сообщением.
	Log.warn("Хост покинул игру: %s" % reason, "Net")
	_teardown_network()
	if Session.run_active:
		Session.end_run(Session.player_finished)
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
	_remotes.clear()
	_lobby_locked = false
	_awaiting_go = false
	_ready_deadline_msec = 0
	go_host_msec = 0


func _kick(peer_id: int) -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


# --- Вспомогательное ---

func _new_slot(player_name: String, finished: bool = false) -> Dictionary:
	return {
		"name": player_name,
		"ready": false,
		"checkpoint": 0,
		"finished": finished,
		"hanging": false,
	}


func _roster_entries() -> Array:
	var entries: Array = []
	for peer_id: int in players.keys():
		var slot: Dictionary = players[peer_id]
		entries.append({"peer_id": peer_id, "name": slot["name"], "finished": slot["finished"]})
	return entries


## Отправка RPC через транспорт: единая точка эмуляции плохой сети.
func _send(call: Callable, unreliable: bool) -> void:
	if _net_log:
		Log.debug("rpc send (unreliable=%s)" % str(unreliable), "Net")
	if transport != null:
		transport.send(call, unreliable)
	else:
		call.call()
