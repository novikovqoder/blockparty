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


# --- Золотой светлячок «на двоих» (раздел 8) ---

## Первый удар по светлячку: spawn_id -> {peer, at} — окно firefly_window,
## в которое удар второго игрока убивает.
var _firefly_pair: Dictionary = {}


## Удар по светлячку (раздел 8): уязвим только от ударов двух РАЗНЫХ
## игроков в пределах firefly_window. Первый удар открывает окно
## ({"weakened": peer, "until": t}), удар другого в окне убивает
## ({"killed": [первый, второй], "respawn_at": t}); тот же игрок снова —
## окно обновляется без события, за окном — новое окно.
func try_firefly_hit(
	spawn_id: int,
	peer: int,
	world_time: float,
	respawn_sec: float,
	b: Balance,
) -> Dictionary:
	var pair: Dictionary = _firefly_pair.get(spawn_id, {})
	if not pair.is_empty() and world_time - float(pair["at"]) <= b.firefly_window:
		if int(pair["peer"]) != peer:
			_firefly_pair.erase(spawn_id)
			return {
				"killed": [int(pair["peer"]), peer],
				"respawn_at": world_time + respawn_sec,
			}
		_firefly_pair[spawn_id] = {"peer": peer, "at": world_time}
		return {}
	_firefly_pair[spawn_id] = {"peer": peer, "at": world_time}
	return {"weakened": peer, "until": world_time + b.firefly_window}


# --- Маяки и Звездопад (раздел 7) ---

## Момент зажигания каждого маяка по часам мира (−1 — не горит).
var _beacons: Array[float] = []
## Первый E по незажжённому маяку: index -> {peer, at} — окно
## beacon_pair_window, в которое E второго игрока зажигает маяк.
var _beacon_press: Dictionary = {}
## Старт текущего Звездопада по часам мира (−1 — не идёт и не был).
var _starfall_started_at: float = -1.0
## Звездопад уже закончился (событие отправлено; звёзды доживают и
## собираются до старта + duration + lifetime).
var _starfall_ended: bool = false
## Когда маяки гаснут после Звездопада (конец + beacon_reset_sec; −1 — нет).
var _beacons_reset_at: float = -1.0
## Подобранные звёзды текущего Звездопада: index -> peer.
var _stars_taken: Dictionary = {}


## Число маяков (сколько на острове) — вызывает хост при старте мира;
## пустой массив до этого игнорирует любые индексы.
func setup_beacons(count: int) -> void:
	if _beacons.size() == count:
		return
	_beacons = []
	for i: int in count:
		_beacons.append(-1.0)


## Нажатие E у маяка (раздел 7): зажигается от двух РАЗНЫХ игроков
## в пределах beacon_pair_window; при одном игроке в мире — сразу
## (клиент уже удержал beacon_solo_hold). Возвращает {"lighters": [int]}
## при зажигании (и "starfall_started_at" — если этим зажжён последний),
## {} — иначе. Повторное зажигание горящего игнорируется.
func try_beacon_light(
	index: int, peer: int, world_time: float, player_count: int, b: Balance
) -> Dictionary:
	if index < 0 or index >= _beacons.size() or _beacons[index] >= 0.0:
		return {}
	# Запасной путь при малом онлайне: одиночка удержал E — зажигаем.
	if player_count <= 1:
		return _light_beacon(index, [peer], world_time, b)
	var press: Dictionary = _beacon_press.get(index, {})
	if not press.is_empty() and world_time - float(press["at"]) <= b.beacon_pair_window:
		if int(press["peer"]) == peer:
			_beacon_press[index] = {"peer": peer, "at": world_time}
			return {}
		_beacon_press.erase(index)
		return _light_beacon(index, [int(press["peer"]), peer], world_time, b)
	_beacon_press[index] = {"peer": peer, "at": world_time}
	return {}


## Тик цикла (раздел 7): конец Звездопада (новые звёзды не рождаются,
## упавшие доживают star_lifetime), затем гашение маяков через
## beacon_reset_sec после конца — цикл начинается снова.
## Возвращает {"starfall_ended": true} / {"beacons_reset": true} / {}.
func update_beacons(world_time: float, b: Balance) -> Dictionary:
	if _starfall_started_at >= 0.0 and not _starfall_ended \
			and world_time >= _starfall_started_at + b.starfall_duration:
		_starfall_ended = true
		return {"starfall_ended": true}
	if _beacons_reset_at >= 0.0 and world_time >= _beacons_reset_at:
		var count := _beacons.size()
		_beacons = []
		for i: int in count:
			_beacons.append(-1.0)
		_beacon_press.clear()
		_stars_taken.clear()
		_starfall_started_at = -1.0
		_starfall_ended = false
		_beacons_reset_at = -1.0
		return {"beacons_reset": true}
	return {}


## Подбор звезды Звездопада (раздел 7): только пока звезда жива (окно
## сбора — star_lifetime после конца), каждая — одному игроку («кто
## первый»), до следующего цикла.
func try_take_star(index: int, peer: int, world_time: float, b: Balance) -> Dictionary:
	if _starfall_started_at < 0.0 or world_time \
			>= _starfall_started_at + b.starfall_duration + b.star_lifetime:
		return {}
	if _stars_taken.has(index):
		return {}
	_stars_taken[index] = peer
	return {"index": index, "collector": peer}


## Состояние маяков для world_state (раздел 10: вошедший в любой момент
## видит горящие маяки и идущий Звездопад).
func beacons_state() -> Dictionary:
	var lit: Array[int] = []
	for i: int in _beacons.size():
		if _beacons[i] >= 0.0:
			lit.append(i)
	return {"lit": lit, "starfall_started_at": _starfall_started_at}


## Подобранные звёзды для world_state: индексы (без игрока — награды уже
## выданы, поздно вошедшему монеты не начисляются).
func stars_taken_state() -> Array[int]:
	var taken: Array[int] = []
	for index: int in _stars_taken:
		taken.append(index)
	return taken


## Зажечь маяк; последним — старт Звездопада (раздел 7).
func _light_beacon(
	index: int, lighters: Array[int], world_time: float, b: Balance
) -> Dictionary:
	_beacons[index] = world_time
	var event := {"lighters": lighters}
	for lit_at: float in _beacons:
		if lit_at < 0.0:
			return event
	_starfall_started_at = world_time
	_starfall_ended = false
	_beacons_reset_at = world_time + b.starfall_duration + b.beacon_reset_sec
	_stars_taken.clear()
	event["starfall_started_at"] = world_time
	return event


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
	_ladders = []
	_firefly_pair.clear()
	_beacons = []
	_beacon_press.clear()
	_starfall_started_at = -1.0
	_starfall_ended = false
	_beacons_reset_at = -1.0
	_stars_taken.clear()
