# Авторитет хоста для активностей и социальных механик (разделы 7, 9, 10 SPEC):
# маяки и цикл Звездопада, ворота руин и сундук, лестницы смотровых, места
# у костра, связи «за руку», вытягивание из расщелины. Чистая логика без
# узлов — обязательные тесты раздела 18 («маяки, плиты, таймеры, места
# у костра, связь за руку»). Позиции и флаги игроков хост передаёт
# параметрами (из снапшотов), мировые константы — из данных острова.
# Состояние фиксируется словарём state() для world_state и rpc_activity.
class_name ActivityAuthority
extends RefCounted

# --- Вытягивание из расщелины (раздел 9.1) ---

## Проверка вытягивания из расщелины (раздел 9.1): helper удержал E у точки,
## где висит target. Хост видит флаг «висит» и позиции из снапшотов;
## дистанция допускает пинг (как mob_hit_slack у удара).
func try_pull(
	target: int,
	helper: int,
	world_time: float,
	target_hanging: bool,
	distance: float,
	b: Balance,
) -> Dictionary:
	if not target_hanging or helper == target:
		return {}
	if distance > b.pull_radius + b.mob_hit_slack:
		return {}
	return {"helper": helper, "target": target, "at": world_time}


# --- Ворота руин и сундук (разделы 8, 9.2) ---

## Момент открытия ворот по часам мира (−1 — закрыты).
var _gate_opened_at: float = -1.0
## Когда у закрытых ворот появился игрок (запасной путь, −1 — никого).
var _gate_wait_started_at: float = -1.0
## Peer на каждой плите (0 — пусто); индексы — порядок плит у ворот.
var _plates: Array[int] = []


## Тик ворот руин (вызывает хост activity_tick раз, раздел 9.2):
## plate_peers — кто стоит на плитах по снапшотам, player_count — игроков
## в мире, anyone_at_gate — есть ли игрок у закрытых ворот (запасной путь).
## Возвращает событие: {} — без изменений, {"plates": [int]} — изменились
## плиты, {"opened": bool, "openers": [int], "plates": [int]} — ворота
## открылись (openers — разные игроки на плитах; пусто при запасном пути),
## {"closed": true} — 10 минут истекли, ворота и сундук сброшены.
func update_ruins_gate(
	plate_peers: Array[int],
	player_count: int,
	anyone_at_gate: bool,
	world_time: float,
	b: Balance,
) -> Dictionary:
	# Открыты: только таймер сброса (ворота и сундук — 10 минут, раздел 8).
	if _gate_opened_at >= 0.0:
		if world_time - _gate_opened_at >= b.gate_reset_sec:
			_gate_opened_at = -1.0
			_gate_wait_started_at = -1.0
			_plates = _empty_plates(_plates.size())
			return {"closed": true}
		return {}
	# Первый тик: запоминаем размер, не устраивая ложного события.
	if _plates.is_empty():
		_plates = _empty_plates(plate_peers.size())
	# Изменились плиты — событие для анимации; хватает разных игроков — открытие.
	if plate_peers != _plates:
		_plates = plate_peers.duplicate()
		var openers := _distinct_peers(_plates)
		# N = min(3, игроков в мире), но не меньше 2: один игрок плиты не откроет.
		var n: int = clampi(player_count, 2, 3)
		if openers.size() >= n:
			_gate_opened_at = world_time
			_gate_wait_started_at = -1.0
			return {"opened": true, "openers": openers, "plates": _plates.duplicate()}
		return {"plates": _plates.duplicate()}
	# Плиты те же — запасной путь: 60 с присутствия у закрытых ворот.
	if anyone_at_gate:
		if _gate_wait_started_at < 0.0:
			_gate_wait_started_at = world_time
		if world_time - _gate_wait_started_at >= b.gate_open_wait:
			_gate_opened_at = world_time
			_gate_wait_started_at = -1.0
			return {"opened": true, "openers": [], "plates": _plates.duplicate()}
	else:
		_gate_wait_started_at = -1.0
	return {}


## Состояние руин для world_state (раздел 10: вошедший в любой момент видит
## открытые ворота и сундук без повторной награды).
func ruins_state() -> Dictionary:
	return {
		"gate_open": _gate_opened_at >= 0.0,
		"gate_opened_at": _gate_opened_at,
		"plates": _plates.duplicate(),
	}


## Награда сундука (раздел 8): peers из entries ({peer, pos}) в радиусе
## от центра сундука — каждый получает chest_reward монет в момент открытия.
static func peers_in_radius(entries: Array, center: Vector3, radius: float) -> Array[int]:
	var peers: Array[int] = []
	for entry: Dictionary in entries:
		var pos: Vector3 = entry["pos"]
		if pos.distance_to(center) <= radius:
			peers.append(int(entry["peer"]))
	return peers


func _distinct_peers(plate_peers: Array[int]) -> Array[int]:
	var peers: Array[int] = []
	for peer: int in plate_peers:
		if peer != 0 and not peers.has(peer):
			peers.append(peer)
	return peers


func _empty_plates(count: int) -> Array[int]:
	var plates: Array[int] = []
	for i: int in count:
		plates.append(0)
	return plates


## Полный сброс (новый мир): вызывается вместе с authority.clear().
func clear() -> void:
	_gate_opened_at = -1.0
	_gate_wait_started_at = -1.0
	_plates = []
