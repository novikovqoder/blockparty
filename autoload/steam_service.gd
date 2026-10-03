# Единственная точка обращения к GodotSteam: инициализация Steam, SteamID,
# persona name, а с этапа П4 — лобби-миры (раздел 11 SPEC): создание, поиск
# с фильтрами, вход/выход, метаданные лобби, приглашение через оверлей и
# Rich Presence. Остальной код работает только с сигналами и методами этого
# сервиса (правило проекта; SteamMultiplayerPeer — единственное исключение,
# он живёт в SteamTransport как пир мультиплеера). Голос — П6.
# Без Steam-клиента и при dev-аргументах (--dev-host/--dev-join) сразу сообщает
# о неудаче — игра продолжает работу в офлайн-режиме ENet.
#
# Имена API сверены с установленной сборкой GodotSteam 4.22.1 (GDExtension):
# steamInitEx(app_id: int, embed_callbacks: bool) -> Dictionary{status: int, verbal: String},
# status == 0 — успех; createLobby(lobby_type: int, max_members: int) -> сигнал
# lobby_created(connect: int, lobby_id: int), connect == 1 (k_EResultOK) — успех;
# joinLobby(steam_lobby_id: int) -> сигнал lobby_joined(lobby: int, permissions: int,
# locked: bool, response: int), response == CHAT_ROOM_ENTER_RESPONSE_SUCCESS;
# requestLobbyList() -> сигнал lobby_match_list(lobbies: Array[int]);
# setLobbyData/getLobbyData/getLobbyOwner/getNumLobbyMembers/getLobbyMemberLimit;
# setRichPresence(key: String, value: String); activateGameOverlayInviteDialog(lobby_id).
extends Node

## Тестовый App ID 480 (Spacewar) — общий для всех разработчиков, поэтому
## лобби обязательно фильтруются по тегу игры (раздел 2 SPEC).
const DEV_APP_ID: int = 480

## Данные лобби (раздел 11 SPEC): игра, версия протокола, режим, число игроков.
const LOBBY_KEY_GAME: String = "game"
const LOBBY_VALUE_GAME: String = "blockparty"
const LOBBY_KEY_VER: String = "ver"
const LOBBY_KEY_MODE: String = "mode"
const LOBBY_KEY_PLAYERS: String = "players"
const LOBBY_KEY_HOST: String = "host_name"
## Публичный мир (кнопка «В мир») и мир для друзей (раздел 11).
const LOBBY_MODE_PUBLIC: String = "public"
const LOBBY_MODE_FRIENDS: String = "friends"

## Steam инициализирован, можно работать.
signal steam_ready
## Steam недоступен: reason поясняет, почему (нет клиента, dev-режим, ошибка init).
signal steam_failed(reason: String)
## Вошли в лобби-мир (создали или присоединились): as_owner — мы хозяин лобби,
## то есть хост мира (раздел 11).
signal lobby_joined(lobby_id: int, as_owner: bool)
## Не удалось войти в лобби-мир (не нашли, не создалось, отказано).
signal lobby_join_failed(reason: String)
## Друг приглашает в свой мир через оверлей Steam (раздел 11).
signal invite_received(inviter_id: int, lobby_id: int)

var available: bool = false
var steam_id: int = 0
var persona_name: String = ""

## Текущее лобби-мир (0 — вне лобби).
var current_lobby_id: int = 0
## Лобби из аргумента запуска +connect_lobby <id> (0 — нет); забирает меню.
var pending_connect_lobby_id: int = 0

var _flow_active: bool = false
var _flow_mode: String = ""


func _ready() -> void:
	# Раздел 11: вход по +connect_lobby <id> при закрытой игре — Steam кладёт
	# аргумент в командную строку запуска (не в пользовательские после «--»).
	pending_connect_lobby_id = parse_connect_lobby(OS.get_cmdline_args())
	if Dev.host_mode or Dev.join_address != "":
		_fail("режим разработки ENet (--dev-host/--dev-join): Steam не используется")
		return
	if not ClassDB.class_exists("Steam"):
		_fail("модуль GodotSteam не загружен")
		return
	# embed_callbacks = true: GodotSteam сам обрабатывает колбэки Steam каждый кадр.
	var init_result: Dictionary = Steam.steamInitEx(DEV_APP_ID, true)
	var status: int = int(init_result.get("status", -1))
	if status != 0:
		_fail("steamInitEx не удался (status=%d): %s" % [status, str(init_result.get("verbal", "причина неизвестна"))])
		return
	available = true
	steam_id = Steam.getSteamID()
	persona_name = Steam.getPersonaName()
	_wire_lobby_signals()
	_wire_presence()
	Log.info("Steam инициализирован: id=%s, имя=%s" % [str(steam_id), persona_name], "Steam")
	if pending_connect_lobby_id != 0:
		Log.info("Приглашение из командной строки: лобби %d" % pending_connect_lobby_id, "Steam")
	steam_ready.emit()


func _wire_lobby_signals() -> void:
	if not Steam.lobby_created.is_connected(_on_lobby_created):
		Steam.lobby_created.connect(_on_lobby_created)
	if not Steam.lobby_joined.is_connected(_on_lobby_joined):
		Steam.lobby_joined.connect(_on_lobby_joined)
	if not Steam.lobby_match_list.is_connected(_on_lobby_match_list):
		Steam.lobby_match_list.connect(_on_lobby_match_list)
	if not Steam.lobby_invite.is_connected(_on_lobby_invite):
		Steam.lobby_invite.connect(_on_lobby_invite)
	if not Steam.lobby_kicked.is_connected(_on_lobby_kicked):
		Steam.lobby_kicked.connect(_on_lobby_kicked)


func _fail(reason: String) -> void:
	available = false
	Log.warn("Steam недоступен: %s" % reason, "Steam")
	steam_failed.emit(reason)


# --- Лобби-миры (раздел 11 SPEC) ---

## «В мир» (раздел 11): ищем публичные миры этой игры и версии со свободными
## местами, заходим в самый населённый; если ничего нет — создаём свой мир.
func quick_join_public() -> void:
	if not _begin_flow():
		return
	# Фильтры запроса (раздел 11): игра, версия протокола, публичный режим,
	# хотя бы одно свободное место. Чужие игры на App ID 480 отсеиваются
	# фильтром game и не попадают в список вообще.
	Steam.addRequestLobbyListStringFilter(LOBBY_KEY_GAME, LOBBY_VALUE_GAME, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListStringFilter(LOBBY_KEY_VER, str(Protocol.PROTOCOL_VERSION), Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListStringFilter(LOBBY_KEY_MODE, LOBBY_MODE_PUBLIC, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListFilterSlotsAvailable(1)
	Steam.requestLobbyList()
	Log.info("Поиск публичного мира (game=%s, ver=%d)" % [LOBBY_VALUE_GAME, Protocol.PROTOCOL_VERSION], "Steam")


## «Мир для друзей» (раздел 11): лобби «только для друзей», приглашение —
## кнопкой «Пригласить» (оверлей Steam) из меню и из мира.
func create_world(mode: String) -> void:
	if not _begin_flow():
		return
	_create_lobby(mode)


## Вход в конкретное лобби (приглашение из оверлея, +connect_lobby).
func join_lobby(lobby_id: int) -> void:
	if not _begin_flow():
		return
	Log.info("Вход в лобби %d" % lobby_id, "Steam")
	Steam.joinLobby(lobby_id)


## Выход из лобби-мира (выход из мира, потеря мира); безопасен вне лобби.
func leave_lobby() -> void:
	_flow_active = false
	_flow_mode = ""
	if current_lobby_id == 0:
		return
	Log.info("Выход из лобби %d" % current_lobby_id, "Steam")
	Steam.leaveLobby(current_lobby_id)
	current_lobby_id = 0
	Steam.clearRichPresence()


## Пригласить друга через оверлей Steam (раздел 11) — для текущего лобби.
func open_invite_overlay() -> void:
	if current_lobby_id == 0:
		return
	Steam.activateGameOverlayInviteDialog(current_lobby_id)


## Хост обновляет в данных лобби текущее число игроков (раздел 11).
func set_lobby_players(count: int) -> void:
	if current_lobby_id == 0 or Steam.getLobbyOwner(current_lobby_id) != steam_id:
		return
	Steam.setLobbyData(current_lobby_id, LOBBY_KEY_PLAYERS, str(count))


## Забрать и обнулить лобби из +connect_lobby (вызывает главное меню).
func consume_pending_connect_lobby() -> int:
	var lobby_id: int = pending_connect_lobby_id
	pending_connect_lobby_id = 0
	return lobby_id


func _begin_flow() -> bool:
	if not available:
		lobby_join_failed.emit("Steam недоступен")
		return false
	if current_lobby_id != 0 or _flow_active:
		return false
	_flow_active = true
	return true


func _create_lobby(mode: String) -> void:
	_flow_mode = mode
	var lobby_type: int = Steam.LOBBY_TYPE_PUBLIC
	if mode == LOBBY_MODE_FRIENDS:
		lobby_type = Steam.LOBBY_TYPE_FRIENDS_ONLY
	Log.info("Создание мира: тип %d, мест %d" % [lobby_type, Protocol.MAX_PLAYERS], "Steam")
	Steam.createLobby(lobby_type, Protocol.MAX_PLAYERS)


## Лобби создано (хост): заполняем данные из раздела 11 и объявляем вход.
## Владелец лобби становится хостом мира сразу — мир «открыт, пока есть места».
func _on_lobby_created(connect: int, lobby_id: int) -> void:
	if not _flow_active:
		return
	if connect != 1:  # k_EResultOK
		_flow_active = false
		lobby_join_failed.emit(tr("LOBBY_FAIL_CREATE") % connect)
		return
	current_lobby_id = lobby_id
	for pair: Dictionary in lobby_metadata(_flow_mode, 1, persona_name):
		Steam.setLobbyData(lobby_id, str(pair["key"]), str(pair["value"]))
	Steam.setLobbyJoinable(lobby_id, true)
	Log.info("Мир-лобби создан: %d (режим %s)" % [lobby_id, _flow_mode], "Steam")
	_flow_active = false
	_flow_mode = ""
	lobby_joined.emit(lobby_id, true)


## Ответ на joinLobby (и подтверждение входа в собственное лобби после
## создания — тогда уже объявлено в _on_lobby_created).
func _on_lobby_joined(lobby: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		if _flow_active:
			_flow_active = false
			_flow_mode = ""
			lobby_join_failed.emit(enter_fail_text(response))
		return
	if current_lobby_id == lobby:
		return  # собственное лобби после создания — уже объявлено
	current_lobby_id = lobby
	_flow_active = false
	_flow_mode = ""
	var as_owner: bool = Steam.getLobbyOwner(lobby) == steam_id
	Log.info("Вошли в лобби %d (хост мира: %s)" % [lobby, str(as_owner)], "Steam")
	lobby_joined.emit(lobby, as_owner)


## Результат поиска публичных миров (раздел 11: самый населённый, не полный).
func _on_lobby_match_list(lobbies: Array) -> void:
	if not _flow_active:
		return
	var candidates: Array = []
	for lobby_id: int in lobbies:
		candidates.append({
			"id": lobby_id,
			"members": Steam.getNumLobbyMembers(lobby_id),
			"limit": Steam.getLobbyMemberLimit(lobby_id),
			# Блок-лист (раздел 14) появится к П8 — пока мир не блокируется.
			"blocked": false,
		})
	var best: int = pick_best_lobby(candidates)
	if best != 0:
		Log.info(
			"Найдено миров: %d, входим в %d (игроков %d/%d)"
			% [lobbies.size(), best, Steam.getNumLobbyMembers(best), Steam.getLobbyMemberLimit(best)],
			"Steam",
		)
		Steam.joinLobby(best)
	else:
		# Свободных миров нет — создаём свой публичный (раздел 11).
		Log.info("Свободных миров нет — создаём свой публичный", "Steam")
		_create_lobby(LOBBY_MODE_PUBLIC)


## Друг прислал приглашение (игра запущена): меню само решает, заходить ли.
func _on_lobby_invite(inviter_id: int, lobby: int, _game: int) -> void:
	Log.info("Приглашение в лобби %d от %s" % [lobby, _friend_name(inviter_id)], "Steam")
	invite_received.emit(inviter_id, lobby)


## Нас исключили из лобби (или лобби распалось): мир закроется транспортом.
func _on_lobby_kicked(lobby_id: int, _admin_id: int, due_to_disconnect: bool) -> void:
	if current_lobby_id != lobby_id:
		return
	Log.warn("Лобби %d закрыто (отключение: %s)" % [lobby_id, str(due_to_disconnect)], "Steam")
	current_lobby_id = 0


func _friend_name(steam_id_value: int) -> String:
	var name: String = Steam.getFriendPersonaName(steam_id_value)
	return name if name != "" else str(steam_id_value)


# --- Rich Presence (раздел 11 SPEC) ---

func _wire_presence() -> void:
	EventBus.world_entered.connect(_on_world_entered)
	EventBus.world_left.connect(func(_session_time: float) -> void: _clear_presence())
	EventBus.roster_changed.connect(_on_roster_changed)


## Вошли в мир: друзья видят статус «На острове (N / 12)» и кнопку входа.
func _on_world_entered() -> void:
	_refresh_presence()


## Состав мира изменился — обновить счётчик в статусе.
func _on_roster_changed(_count: int) -> void:
	if Session.in_world:
		_refresh_presence()


func _refresh_presence() -> void:
	if not available or current_lobby_id == 0:
		return
	Steam.setRichPresence("status", presence_status_text(Net.in_world_count(), Protocol.MAX_PLAYERS))
	# Ключ connect: Steam передаёт значение в командную строку при входе друга
	# через список друзей (раздел 11).
	Steam.setRichPresence("connect", connect_command(current_lobby_id))


func _clear_presence() -> void:
	if available:
		Steam.clearRichPresence()


## Статус Rich Presence «На острове (5 / 12)» (раздел 11).
func presence_status_text(count: int, max_players: int) -> String:
	return tr("RP_IN_WORLD") % [count, max_players]


# --- Чистые функции (тестируются GUT) ---

## Самый населённый мир со свободными местами (раздел 11); 0 — подходящих нет.
## blocked — миры с заблокированными игроками (блок-лист, раздел 14).
static func pick_best_lobby(candidates: Array) -> int:
	var best_id: int = 0
	var best_members: int = -1
	for candidate: Dictionary in candidates:
		if bool(candidate.get("blocked", false)):
			continue
		var limit: int = int(candidate.get("limit", 0))
		var members: int = int(candidate.get("members", 0))
		if limit > 0 and members >= limit:
			continue  # полный
		if members > best_members:
			best_members = members
			best_id = int(candidate.get("id", 0))
	return best_id


## Аргумент запуска +connect_lobby <id>: Steam пишет его в командную строку
## при входе из списка друзей/Rich Presence закрытой игры (раздел 11).
## Поддерживает обе формы: «+connect_lobby 123» и «+connect_lobby=123».
static func parse_connect_lobby(args: PackedStringArray) -> int:
	for i: int in args.size():
		var arg: String = args[i]
		if arg == "+connect_lobby" and i + 1 < args.size():
			var next: String = args[i + 1]
			if next.is_valid_int():
				return next.to_int()
		elif arg.begins_with("+connect_lobby="):
			var value: String = arg.get_slice("=", 1)
			if value.is_valid_int():
				return value.to_int()
	return 0


## Данные лобби-мира (раздел 11): game, ver, mode, players, host_name.
static func lobby_metadata(mode: String, players: int, host_name: String) -> Array[Dictionary]:
	return [
		{"key": LOBBY_KEY_GAME, "value": LOBBY_VALUE_GAME},
		{"key": LOBBY_KEY_VER, "value": str(Protocol.PROTOCOL_VERSION)},
		{"key": LOBBY_KEY_MODE, "value": mode},
		{"key": LOBBY_KEY_PLAYERS, "value": str(players)},
		{"key": LOBBY_KEY_HOST, "value": host_name},
	]


## Строка connect для Rich Presence: friend жмёт «Войти» — Steam запускает
## игру с этим аргументом (разбирает parse_connect_lobby).
static func connect_command(lobby_id: int) -> String:
	return "+connect_lobby %d" % lobby_id


## Текст причины отказа входа по коду ChatRoomEnterResponse.
func enter_fail_text(response: int) -> String:
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_FULL:
		return tr("LOBBY_FAIL_FULL")
	if response == Steam.CHAT_ROOM_ENTER_RESPONSE_DOESNT_EXIST:
		return tr("LOBBY_FAIL_CLOSED")
	return tr("LOBBY_FAIL_GENERIC") % response
