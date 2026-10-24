# Учёт взаимодействий для экрана «Встречи» (раздел 13 SPEC): очки по peer_id,
# окно — текущее пребывание в мире. Считается на каждом клиенте для себя.
# Кооп-механики Blockparty (подсадка, вытягивание, «за руку», ворота руин)
# удалены с наследием (born-unblessed) — остались близость, голос, костёр.
# Не делает: накопительные лимиты по видам событий («не больше 20» и т.д.) —
# появятся вместе с источниками событий, чтобы не хранить мёртвый код.
extends Node

const B: Balance = preload("res://gameplay/balance.tres")

## Типы событий (значения очков — в balance.tres, группа «Взаимодействия»).
const KIND_PROXIMITY: String = "proximity"      # секунда рядом (до 8 м)
const KIND_VOICE_HEARD: String = "voice_heard"  # секунда его голоса
const KIND_CAMPFIRE: String = "campfire"        # сидели рядом у костра (30 с)

## peer_id -> суммарные очки.
var _scores: Dictionary = {}
## Журнал событий: {peer_id, kind, points, time}.
var _events: Array[Dictionary] = []
## Кто сейчас сидит у костра (раздел 9.6) и сколько секунд сижу с кем-то
## из них — очки «сидели рядом у костра» каждые 30 с (раздел 13).
var _seated_peers: Array[int] = []
var _campfire_seconds: float = 0.0


func _ready() -> void:
	EventBus.campfire_seats.connect(_on_campfire_seats)
	EventBus.world_entered.connect(reset)


## Секунды вместе у костра идут в очки каждые 30 с (раздел 13).
const CAMPFIRE_TICK: float = 30.0


func _process(delta: float) -> void:
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
	_seated_peers.clear()
	_campfire_seconds = 0.0
