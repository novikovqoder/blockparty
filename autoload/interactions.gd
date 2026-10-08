# Учёт взаимодействий для экрана «Встречи» (раздел 13 SPEC): очки по peer_id,
# окно — текущее пребывание в мире. Считается на каждом клиенте для себя.
# Этап П0 хранит каркас: события наполнятся на этапах П3–П5 (мобы, кооп),
# голос — П6; выбор фраз, история 10 сессий и симпатии — П7.
# Не делает: накопительные лимиты по видам событий («не больше 20» и т.д.) —
# появятся вместе с источниками событий, чтобы не хранить мёртвый код.
extends Node

const B: Balance = preload("res://gameplay/balance.tres")

## Типы событий (значения очков — в balance.tres, группа «Взаимодействия»).
const KIND_PROXIMITY: String = "proximity"      # секунда рядом (до 8 м)
const KIND_VOICE_HEARD: String = "voice_heard"  # секунда его голоса
const KIND_PULL_GOT: String = "pull_got"        # он вытянул меня из расщелины
const KIND_PULL_GAVE: String = "pull_gave"      # я вытянул его
const KIND_HAND_HELD: String = "hand_held"      # держались за руку (каждые 30 с)
const KIND_CAMPFIRE: String = "campfire"        # сидели рядом у костра (30 с)
const KIND_BEACON_LIT: String = "beacon_lit"    # вместе зажгли маяк
const KIND_GATE_OPEN: String = "gate_open"      # вместе открыли ворота руин
const KIND_BOOST_GOT: String = "boost_got"      # он подсадил меня на уступ
const KIND_BOOST_GAVE: String = "boost_gave"    # я подсадил его
const KIND_FIREFLY: String = "firefly"          # вместе поймали золотого светлячка
const KIND_EMOTE_REPLY: String = "emote_reply"  # ответная эмоция в течение 5 с

## peer_id -> суммарные очки.
var _scores: Dictionary = {}
## Журнал событий: {peer_id, kind, points, time}.
var _events: Array[Dictionary] = []
## Партнёр по связи «за руку» и сколько секунд она уже длится (раздел 9.5:
## очки «каждые 30 с», пока пара идёт вместе).
var _hand_partner: int = 0
var _hand_seconds: float = 0.0
## Кто сейчас сидит у костра (раздел 9.6) и сколько секунд сижу с кем-то
## из них — очки «сидели рядом у костра» каждые 30 с (раздел 13).
var _seated_peers: Array[int] = []
var _campfire_seconds: float = 0.0


func _ready() -> void:
	EventBus.player_pulled.connect(_on_player_pulled)
	EventBus.ruins_state.connect(_on_ruins_state)
	EventBus.mob_killed.connect(_on_mob_killed)
	EventBus.player_boosted.connect(_on_player_boosted)
	EventBus.beacons_state.connect(_on_beacons_state)
	EventBus.hand_link.connect(_on_hand_link)
	EventBus.campfire_seats.connect(_on_campfire_seats)
	EventBus.world_entered.connect(reset)


## Секунды вместе идут в очки каждые 30 с (раздел 13: «за руку» и «у костра»).
const HAND_TICK: float = 30.0
const CAMPFIRE_TICK: float = 30.0


func _process(delta: float) -> void:
	if _hand_partner != 0:
		_hand_seconds += delta
		if _hand_seconds >= HAND_TICK:
			_hand_seconds -= HAND_TICK
			add_points(_hand_partner, KIND_HAND_HELD, B.pts_hand_held, Session.world_time)
	var others := _seated_others()
	if others.is_empty():
		_campfire_seconds = 0.0
		return
	_campfire_seconds += delta
	if _campfire_seconds >= CAMPFIRE_TICK:
		_campfire_seconds -= CAMPFIRE_TICK
		for peer: int in others:
			add_points(peer, KIND_CAMPFIRE, B.pts_campfire, Session.world_time)


## Занятость мест у костра (раздел 9.6): запоминаем сидящих — пока я сижу
## с кем-то ещё, копим 30-секундные интервалы (раздел 13).
func _on_campfire_seats(seats: Array) -> void:
	_seated_peers.clear()
	for peer: int in seats:
		if peer != 0:
			_seated_peers.append(peer)
	_campfire_seconds = 0.0


## Сидящие у костра кроме меня (пусто — очки не копятся).
func _seated_others() -> Array[int]:
	if not _seated_peers.has(Net.local_peer_id):
		return []
	var others: Array[int] = []
	for peer: int in _seated_peers:
		if peer != Net.local_peer_id:
			others.append(peer)
	return others


## Связь «за руку» (раздел 9.5): включилась — копим секунды с партнёром,
## оборвалась — сброс (следующая связь считает заново).
func _on_hand_link(leader_peer: int, follower_peer: int, on: bool) -> void:
	var local := Net.local_peer_id
	if on and (leader_peer == local or follower_peer == local):
		_hand_partner = follower_peer if leader_peer == local else leader_peer
		_hand_seconds = 0.0
	elif not on and (leader_peer == local or follower_peer == local):
		_hand_partner = 0
		_hand_seconds = 0.0


## Вытягивание из расщелины (раздел 9.1): очки обоим — я вытянул его,
## меня вытянул он.
func _on_player_pulled(helper_peer: int, target_peer: int) -> void:
	if helper_peer == Net.local_peer_id:
		add_points(target_peer, KIND_PULL_GAVE, B.pts_pull, Session.world_time)
	if target_peer == Net.local_peer_id:
		add_points(helper_peer, KIND_PULL_GOT, B.pts_pull, Session.world_time)


## Ворота руин открыты плитами (раздел 9.2): очки каждому участнику за
## каждого другого. Запасной путь одиночки очков не даёт (открывший один).
func _on_ruins_state(open: bool, _plates: Array, openers: Array, _reward: Array) -> void:
	if not open or not openers.has(Net.local_peer_id):
		return
	for opener: int in openers:
		if opener != Net.local_peer_id:
			add_points(opener, KIND_GATE_OPEN, B.pts_gate_open, Session.world_time)


## Золотой светлячок убит парой (раздел 8): каждому из двоих — очки друг
## за друга (список killers длиннее одного только у светлячка).
func _on_mob_killed(_spawn_id: int, killers: Array, _respawn_at: float) -> void:
	if not killers.has(Net.local_peer_id) or killers.size() < 2:
		return
	for killer: int in killers:
		if killer != Net.local_peer_id:
			add_points(killer, KIND_FIREFLY, B.pts_firefly, Session.world_time)


## Подсадка на голову (разделы 5, 13): base подсадил jumper — очки
## «я подсадил его» базе и «он подсадил меня» прыгнувшему.
func _on_player_boosted(base_peer: int, jumper_peer: int) -> void:
	if jumper_peer == Net.local_peer_id:
		add_points(base_peer, KIND_BOOST_GOT, B.pts_boost, Session.world_time)
	if base_peer == Net.local_peer_id:
		add_points(jumper_peer, KIND_BOOST_GAVE, B.pts_boost, Session.world_time)


## Маяк зажжён парой (раздел 7): очки каждому участнику за другого.
## Соло-зажигание (запасной путь) lighters из одного — очков не даёт.
func _on_beacons_state(_lit: Array, lighters: Array, _starfall_started_at: float) -> void:
	if not lighters.has(Net.local_peer_id) or lighters.size() < 2:
		return
	for lighter: int in lighters:
		if lighter != Net.local_peer_id:
			add_points(lighter, KIND_BEACON_LIT, B.pts_beacon_lit, Session.world_time)


## Записать событие взаимодействия с другим игроком (at_world_time — с).
func add_points(peer_id: int, kind: String, points: float, at_world_time: float) -> void:
	_scores[peer_id] = score(peer_id) + points
	_events.append({"peer_id": peer_id, "kind": kind, "points": points, "time": at_world_time})


## Очки, набранные во взаимодействиях с игроком peer_id.
func score(peer_id: int) -> float:
	return float(_scores.get(peer_id, 0.0))


## Журнал событий текущего пребывания в мире (для экрана «Встречи» — П7).
func events() -> Array[Dictionary]:
	return _events


## Peer_id с наибольшими очками (топ карточек «Встреч»; caller фильтрует себя).
func top_peers(limit: int) -> Array[int]:
	var peers: Array[int] = []
	for peer_id: int in _scores.keys():
		peers.append(peer_id)
	peers.sort_custom(func(a: int, b: int) -> bool: return score(a) > score(b))
	return peers.slice(0, limit)


## Новый заход в мир — журналы пусты (история прошлых сессий — П7).
func reset() -> void:
	_scores.clear()
	_events.clear()
	_hand_partner = 0
	_hand_seconds = 0.0
	_seated_peers.clear()
	_campfire_seconds = 0.0
