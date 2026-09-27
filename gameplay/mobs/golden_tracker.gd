# Чистая логика золотой цели (разделы 6, 7.4 SPEC): цель уязвима, только если
# её ударили 2 РАЗНЫХ игрока в пределах golden_hit_window. Состояние держит
# хост; клиенты видят результат через rpc_mob_killed / rpc_mob_damaged.
# Отдельный класс — чтобы логику проверял юнит-тест без сети.
class_name GoldenTracker
extends RefCounted

const B: Balance = preload("res://gameplay/balance.tres")

## spawn_id -> {peer_id: int, at: float} — последний удар, пока цель жива.
var _hits: Dictionary = {}


## Зарегистрировать удар игрока peer_id в момент at (run_time, с).
## Возвращает {killed: bool, first_hit: bool, participants: Array[int]}:
## killed — цель добита ударами двух разных игроков, participants — кто.
func register_hit(spawn_id: int, peer_id: int, at: float) -> Dictionary:
	var last: Dictionary = _hits.get(spawn_id, {})
	if not last.is_empty():
		var in_window: bool = at - float(last["at"]) <= B.golden_hit_window
		if in_window and int(last["peer_id"]) != peer_id:
			_hits.erase(spawn_id)
			return {
				"killed": true,
				"first_hit": false,
				"participants": [int(last["peer_id"]), peer_id],
			}
	# Первый удар (или окно истекло / тот же игрок) — цель «заведена».
	_hits[spawn_id] = {"peer_id": peer_id, "at": at}
	return {"killed": false, "first_hit": true, "participants": []}


## Убрать состояние цели (новый забег).
func reset() -> void:
	_hits.clear()
