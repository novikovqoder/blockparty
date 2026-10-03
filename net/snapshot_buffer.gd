# Буфер 3D-снапшотов чужого игрока (раздел 10 SPEC): линейная интерполяция
# позиции и поворота (по кратчайшей дуге) с задержкой отрисовки, ограниченная
# экстраполяция скоростью, телепорт при расхождении больше 5 м, отбрасывание
# снапшотов со старым seq. Чистая логика без узлов — проверяется тестами GUT.
class_name SnapshotBuffer
extends RefCounted

const WRAP_HALF: int = 0x8000  # половина диапазона uint16 для сравнения seq
const KEEP_WINDOW_MSEC: int = 2000  # сколько истории держать в буфере

## Принятые снапшоты: {t: мс получения, seq, x, y, z, yaw, vx, vy, vz, anim, flags}.
var _samples: Array[Dictionary] = []
var _last_seq: int = -1
var _last_rendered := Vector3.ZERO
var _last_yaw: float = 0.0
var _has_rendered: bool = false


## Пуст ли буфер (нет ни одного снапшота).
func is_empty() -> bool:
	return _samples.is_empty()


## Сбросить буфер (новый мир, телепорт).
func clear() -> void:
	_samples.clear()
	_last_seq = -1
	_has_rendered = false


## Принять снапшот; false — отброшен как старый или дубликат по seq.
func push(snap: Dictionary, recv_msec: int) -> bool:
	var seq: int = snap["seq"]
	if _last_seq >= 0 and not _is_seq_newer(seq, _last_seq):
		return false
	_last_seq = seq
	var sample := snap.duplicate()
	sample["t"] = recv_msec
	_samples.append(sample)
	_trim(recv_msec)
	return true


## Состояние на момент render_msec (обычно «сейчас минус задержка»).
## Возвращает {x, y, z, yaw, vx, vy, vz, anim, flags, teleported, frozen}.
func sample(render_msec: int) -> Dictionary:
	var result := {
		"x": _last_rendered.x,
		"y": _last_rendered.y,
		"z": _last_rendered.z,
		"yaw": _last_yaw,
		"vx": 0.0,
		"vy": 0.0,
		"vz": 0.0,
		"anim": Protocol.AnimState.IDLE,
		"flags": 0,
		"teleported": false,
		"frozen": false,
	}
	if _samples.is_empty():
		return result
	var last: Dictionary = _samples[_samples.size() - 1]
	# База — последний снапшот: если данных нет дольше лимита экстраполяции,
	# замираем на его позиции (а не на нуле до первого рендера).
	result["x"] = float(last["x"])
	result["y"] = float(last["y"])
	result["z"] = float(last["z"])
	result["yaw"] = float(last["yaw"])
	result["vx"] = float(last["vx"])
	result["vy"] = float(last["vy"])
	result["vz"] = float(last["vz"])
	_copy_state(result, last)

	if render_msec >= last["t"]:
		# Данных нет: экстраполяция скоростью не дольше лимита, затем замри
		# на последней отрисованной позиции (до первого рендера — на последнем
		# снапшоте, не в нуле).
		var ahead_msec: int = render_msec - int(last["t"])
		if ahead_msec <= Protocol.EXTRAPOLATION_MS:
			var dt: float = float(ahead_msec) / 1000.0
			result["x"] = float(last["x"]) + float(last["vx"]) * dt
			result["y"] = float(last["y"]) + float(last["vy"]) * dt
			result["z"] = float(last["z"]) + float(last["vz"]) * dt
		else:
			result["frozen"] = true
			if _has_rendered:
				result["x"] = _last_rendered.x
				result["y"] = _last_rendered.y
				result["z"] = _last_rendered.z
				result["yaw"] = _last_yaw
	else:
		# Найти пару снапшотов, между которыми попадает время отрисовки.
		for i: int in range(_samples.size() - 1, 0, -1):
			var newer: Dictionary = _samples[i]
			if render_msec > int(newer["t"]):
				continue
			var older: Dictionary = _samples[i - 1]
			var span: int = int(newer["t"]) - int(older["t"])
			var blend: float = 1.0 if span <= 0 else clampf(
				float(render_msec - int(older["t"])) / float(span), 0.0, 1.0
			)
			result["x"] = lerpf(float(older["x"]), float(newer["x"]), blend)
			result["y"] = lerpf(float(older["y"]), float(newer["y"]), blend)
			result["z"] = lerpf(float(older["z"]), float(newer["z"]), blend)
			# Поворот — по кратчайшей дуге (раздел 10), не через 2π.
			result["yaw"] = lerp_angle(float(older["yaw"]), float(newer["yaw"]), blend)
			result["vx"] = lerpf(float(older["vx"]), float(newer["vx"]), blend)
			result["vy"] = lerpf(float(older["vy"]), float(newer["vy"]), blend)
			result["vz"] = lerpf(float(older["vz"]), float(newer["vz"]), blend)
			_copy_state(result, newer)
			break

	var rendered := Vector3(float(result["x"]), float(result["y"]), float(result["z"]))
	if _has_rendered and rendered.distance_to(_last_rendered) > Protocol.TELEPORT_DISTANCE:
		result["teleported"] = true
	_last_rendered = rendered
	_last_yaw = float(result["yaw"])
	_has_rendered = true
	return result


## Сравнение seq с учётом wrap uint16: новый ли seq относительно last.
static func _is_seq_newer(seq: int, last: int) -> bool:
	if seq == last:
		return false
	var diff: int = (seq - last) & 0xFFFF
	return diff < WRAP_HALF


## Скопировать анимацию и флаги из снапшота в результат.
static func _copy_state(result: Dictionary, snap: Dictionary) -> void:
	result["anim"] = snap["anim"]
	result["flags"] = snap["flags"]


## Убрать снапшоты старше KEEP_WINDOW_MSEC (крайний всегда остаётся).
func _trim(now_msec: int) -> void:
	while _samples.size() > 1 and now_msec - int(_samples[0]["t"]) > KEEP_WINDOW_MSEC:
		_samples.pop_front()
