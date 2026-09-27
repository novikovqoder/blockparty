# Чистая логика хоста для кооп-механик (разделы 7.2, 7.3 и падающие платформы
# раздела 6 SPEC). Хост раз в тик кормит director позициями игроков (по
# снапшотам), тот копит состояние плит, запасных таймеров и платформ и
# возвращает события, которые хост рассылает rpc_coop_open /
# rpc_platform_state. Отдельный класс — чтобы логику проверял юнит-тест без
# сети и без нод.
#
# Кооп-объекты (описания одинаковые у всех, строят секции):
#   ворота: plates (зоны плит), open_zone (зона запасного таймера у ворот),
#           min_players; открываются, когда на плитах стоит need разных
#           игроков, need = min(min_players, игроков в забеге, 3).
#   уступ:  open_zone (зона запасного таймера у стены), top_zone (наверху);
#           лестница опускается, когда кто-то оказался наверху.
class_name CoopDirector
extends RefCounted

const B: Balance = preload("res://gameplay/balance.tres")

## Типы событий тика (что рассылает хост).
enum Event {
	GATE_OPEN,        # ворота открыты (участники — стоявшие на плитах)
	LADDER_DROP,      # лестница опущена (кто-то наверху)
	LEDGE_PLATFORM,   # запасная платформа у уступа (таймер 45 с)
	PLATFORM_FALL,    # падающая платформа упала
	PLATFORM_RESTORE, # падающая платформа восстановилась
}


## Описание ворот: id, плиты, зона у ворот, минимум игроков.
static func make_gate(id: int, plates: Array[Rect2], open_zone: Rect2, min_players: int) -> Dictionary:
	return {"id": id, "kind": "gate", "plates": plates, "open_zone": open_zone, "top_zone": Rect2(), "min_players": maxi(1, min_players)}


## Описание уступа: id, зона у стены, зона наверху.
static func make_ledge(id: int, open_zone: Rect2, top_zone: Rect2) -> Dictionary:
	return {"id": id, "kind": "ledge", "plates": [], "open_zone": open_zone, "top_zone": top_zone, "min_players": 1}


var _objects: Array = []
var _platforms: Array = []  # {id, zone}
var _state: Dictionary = {}   # id -> {main: bool, fallback: bool, present: float}
var _platform_state: Dictionary = {}  # id -> {stand: float, fallen: bool, restore: float}


## Загрузить уровень: описания кооп-объектов и падающих платформ.
func setup(objects: Array, platforms: Array) -> void:
	_objects = objects
	_platforms = platforms
	_state.clear()
	_platform_state.clear()
	for object: Dictionary in objects:
		_state[int(object["id"])] = {"main": false, "fallback": false, "present": 0.0}
	for platform: Dictionary in platforms:
		_platform_state[int(platform["id"])] = {"stand": 0.0, "fallen": false, "restore": 0.0}


## Один тик логики: delta — секунды, positions — peer_id -> Vector2
## (Vector2.INF — игрока нет). Возвращает события для рассылки.
func tick(delta: float, positions: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for object: Dictionary in _objects:
		var state: Dictionary = _state[int(object["id"])]
		if object["kind"] == "gate":
			_tick_gate(delta, object, state, positions, events)
		else:
			_tick_ledge(delta, object, state, positions, events)
	for platform: Dictionary in _platforms:
		_tick_platform(delta, platform, positions, events)
	return events


## Сколько разных игроков нужно плитам ворот (раздел 7.2: N = min, не больше 3).
func gate_need(min_players: int, player_count: int) -> int:
	return mini(mini(min_players, maxi(1, player_count)), B.coop_max_players)


func _tick_gate(delta: float, object: Dictionary, state: Dictionary, positions: Dictionary, events: Array[Dictionary]) -> void:
	if state["main"] or state["fallback"]:
		return  # ворота открыты навсегда
	var pressed: Array[int] = []
	for peer_id: int in positions.keys():
		var pos: Vector2 = positions[peer_id]
		if pos == Vector2.INF:
			continue
		for plate: Rect2 in object["plates"]:
			if plate.has_point(pos) and not pressed.has(peer_id):
				pressed.append(peer_id)
				break
	var need: int = gate_need(int(object["min_players"]), positions.size())
	if not pressed.is_empty() and pressed.size() >= need:
		state["main"] = true
		events.append({"event": Event.GATE_OPEN, "id": int(object["id"]), "participants": pressed})
		return
	# Запасной таймер: копится, пока у закрытых ворот есть хоть один игрок.
	if _any_in(positions, object["open_zone"]):
		state["present"] = float(state["present"]) + delta
		if float(state["present"]) >= B.gate_fallback_time:
			state["fallback"] = true
			events.append({"event": Event.GATE_OPEN, "id": int(object["id"]), "participants": []})


func _tick_ledge(delta: float, object: Dictionary, state: Dictionary, positions: Dictionary, events: Array[Dictionary]) -> void:
	if not state["main"] and _any_in(positions, object["top_zone"]):
		# Кто-то наверху — опускаем лестницу (раздел 7.3).
		state["main"] = true
		events.append({"event": Event.LADDER_DROP, "id": int(object["id"]), "participants": []})
	if state["main"]:
		return  # лестница опущена — запасная платформа не нужна
	if _any_in(positions, object["open_zone"]):
		state["present"] = float(state["present"]) + delta
		if float(state["present"]) >= B.ledge_fallback_time:
			state["fallback"] = true
			events.append({"event": Event.LEDGE_PLATFORM, "id": int(object["id"]), "participants": []})


func _tick_platform(delta: float, platform: Dictionary, positions: Dictionary, events: Array[Dictionary]) -> void:
	var id: int = int(platform["id"])
	var state: Dictionary = _platform_state[id]
	if state["fallen"]:
		state["restore"] = float(state["restore"]) + delta
		if float(state["restore"]) >= B.falling_platform_restore:
			state["fallen"] = false
			state["restore"] = 0.0
			state["stand"] = 0.0
			events.append({"event": Event.PLATFORM_RESTORE, "id": id})
		return
	if _any_in(positions, platform["zone"]):
		state["stand"] = float(state["stand"]) + delta
		if float(state["stand"]) >= B.falling_platform_delay:
			state["fallen"] = true
			state["stand"] = 0.0
			state["restore"] = 0.0
			events.append({"event": Event.PLATFORM_FALL, "id": id})
	else:
		state["stand"] = 0.0  # сошёл до задержки — падение отменяется


## Есть ли хоть один живой игрок внутри зоны.
func _any_in(positions: Dictionary, zone: Rect2) -> bool:
	for peer_id: int in positions.keys():
		var pos: Vector2 = positions[peer_id]
		if pos != Vector2.INF and zone.has_point(pos):
			return true
	return false
