# Учёт взаимодействий между игроками для экрана результатов (раздел 11 SPEC).
# Считается на каждом клиенте для себя: очки по peer_id и журнал событий.
# Этап 3 наполняется событиями помощи от хоста (вытягивание, кооп-ворота,
# золотая цель) и локальным прыжком с головы; очки одинаковые у Net и здесь.
# Не делает: секунды рядом, голос, ответные эмоции, выбор фразы-момента и
# сам экран результатов — этап 6.
extends Node

const B: Balance = preload("res://gameplay/balance.tres")

## Типы событий (значения очков — в balance.tres, группа «Взаимодействия»).
const KIND_PULL_GOT: String = "pull_got"          # он вытянул меня
const KIND_PULL_GAVE: String = "pull_gave"        # я вытянул его
const KIND_GATE_OPEN: String = "gate_open"        # вместе открыли ворота
const KIND_GOLDEN_KILL: String = "golden_kill"    # вместе убили золотую цель
const KIND_HEAD_JUMP: String = "head_jump"        # прыгнул с его головы

## peer_id -> суммарные очки.
var _scores: Dictionary = {}
## Журнал событий: {peer_id, kind, points, time}.
var _events: Array[Dictionary] = []


## Записать событие взаимодействия с другим игроком.
func add_points(peer_id: int, kind: String, points: float, at_run_time: float) -> void:
	_scores[peer_id] = score(peer_id) + points
	_events.append({"peer_id": peer_id, "kind": kind, "points": points, "time": at_run_time})


## Очки, набранные во взаимодействиях с игроком peer_id.
func score(peer_id: int) -> float:
	return float(_scores.get(peer_id, 0.0))


## Журнал событий забега (для экрана результатов — этап 6).
func events() -> Array[Dictionary]:
	return _events


## Peer_id с наибольшими очками (топ для карточек; без себя — caller фильтрует).
func top_peers(limit: int) -> Array[int]:
	var peers: Array[int] = []
	for peer_id: int in _scores.keys():
		peers.append(peer_id)
	peers.sort_custom(func(a: int, b: int) -> bool: return score(a) > score(b))
	return peers.slice(0, limit)


## Новый забег — журналы пусты (вызывает сцена забега).
func reset() -> void:
	_scores.clear()
	_events.clear()
