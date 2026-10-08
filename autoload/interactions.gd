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


func _ready() -> void:
	EventBus.player_pulled.connect(_on_player_pulled)
	EventBus.ruins_state.connect(_on_ruins_state)
	EventBus.mob_killed.connect(_on_mob_killed)
	EventBus.player_boosted.connect(_on_player_boosted)
	EventBus.world_entered.connect(reset)


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
