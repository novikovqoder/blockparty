# Авторитет хоста для активностей (разделы 9, 10 SPEC): лестницы смотровых.
# Чистая логика без узлов — обязательные тесты раздела 18 («таймеры»).
# Позиции и флаги игроков хост передаёт
# параметрами (из снапшотов), мировые константы — из данных острова.
# Состояние фиксируется словарём state() для world_state и rpc_activity.
class_name ActivityAuthority
extends RefCounted

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
	_ladders = []
