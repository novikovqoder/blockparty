# Авторитет хоста для активностей (разделы 9, 10 SPEC): лестницы смотровых,
# места у костра. Чистая логика без узлов — обязательные тесты раздела 18
# («таймеры, места у костра»). Позиции и флаги игроков хост передаёт
# параметрами (из снапшотов), мировые константы — из данных острова.
# Состояние фиксируется словарём state() для world_state и rpc_activity.
class_name ActivityAuthority
extends RefCounted

# --- Места у костра (раздел 9.6) ---

## Занятость мест: индекс -> peer сидящего (0 — свободно). Места ставит
## генератор острова (8 лавок на площади), индекс — порядок имён узлов.
var _seats: Array[int] = []


## Число мест (вызывается каждый тик хоста; повторный вызов с тем же числом
## ничего не меняет — занятость живёт).
func setup_seats(count: int) -> void:
	if _seats.size() == count:
		return
	_seats.resize(count)
	_seats.fill(0)


## Сесть на место (раздел 9.6): индекс существует, место свободно,
## расстояние до лавки в норме (с допуском на пинг — позиции из снапшотов).
## Один игрок занимает одно место: прежнее место освобождается.
func try_sit(peer: int, seat_index: int, distance: float, b: Balance) -> Dictionary:
	if seat_index < 0 or seat_index >= _seats.size():
		return {}
	if distance > b.campfire_seat_radius + b.ping_slack:
		return {}
	if _seats[seat_index] != 0:
		return {}  # занято
	stand_up(peer)
	_seats[seat_index] = peer
	return {"seat": seat_index, "peer": peer}


## Встать с места (раздел 9.6: любое движение). Возвращает {"seat", "peer"}
## освободившегося места или {} — игрок не сидел.
func stand_up(peer: int) -> Dictionary:
	for i: int in _seats.size():
		if _seats[i] == peer:
			_seats[i] = 0
			return {"seat": i, "peer": peer}
	return {}


## Тик мест (хост, activity_tick): игрок вышел из мира — место свободно
## (entries — {peer, pos, floor} всех игроков в мире). Одно событие за тик.
func update_seats(entries: Array[Dictionary]) -> Dictionary:
	var present := {}
	for entry: Dictionary in entries:
		present[int(entry["peer"])] = true
	for i: int in _seats.size():
		if _seats[i] != 0 and not present.has(_seats[i]):
			var peer := _seats[i]
			_seats[i] = 0
			return {"seat": i, "peer": peer}
	return {}


## Занятость мест для world_state (раздел 10): массив peer по индексам.
func seats_state() -> Array[int]:
	return _seats.duplicate()


# --- Лестницы смотровых (раздел 9.3) ---

## Когда лестница каждой смотровой скрывается по часам мира (−1 — сброшена).
var _ladders: Array[float] = []


## Число лестниц (сколько смотровых на острове) — вызывает хост при старте
## мира; пустой массив до этого игнорирует любые индексы.
func setup_ladders(count: int) -> void:
	if _ladders.size() == count:
		return
	_ladders = []
	for i: int in count:
		_ladders.append(-1.0)


## Проверка сброса лестницы (раздел 9.3): поднявшийся нажал E у края.
## on_top — стоит ли просящий на площадке (окно высоты и радиус — net.gd
## по позиции узла). Повторный сброс активной лестницы игнорируется.
func try_drop_ladder(index: int, world_time: float, on_top: bool, b: Balance) -> Dictionary:
	if index < 0 or index >= _ladders.size() or not on_top:
		return {}
	if _ladders[index] >= world_time:
		return {}  # уже висит
	_ladders[index] = world_time + b.ladder_time
	return {"index": index, "until": _ladders[index]}


## Тик лестниц (хост, activity_tick): возвращает событие о скрывшейся
## лестнице или {} — без изменений.
func update_ladders(world_time: float) -> Dictionary:
	for i: int in _ladders.size():
		if _ladders[i] >= 0.0 and world_time >= _ladders[i]:
			_ladders[i] = -1.0
			return {"index": i, "active": false}
	return {}


## Лестницы какой смотровой висят: [{index, until}] для world_state.
func ladders_state() -> Array[Dictionary]:
	var state: Array[Dictionary] = []
	for i: int in _ladders.size():
		if _ladders[i] >= 0.0:
			state.append({"index": i, "until": _ladders[i]})
	return state


## Полный сброс (новый мир).
func clear() -> void:
	_seats = []
	_ladders = []
