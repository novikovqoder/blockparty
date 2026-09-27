# Синхронизация часов с хостом (раздел 8 SPEC): клиент раз в секунду шлёт ping,
# хост отвечает своим временем, смещение = время хоста + RTT/2 − локальное,
# сглаживание скользящим средним по последним 8 замерам. Чистая логика —
# проверяется тестами GUT.
class_name ClockSync
extends RefCounted

var _offsets: Array[float] = []
var _last_rtt: int = -1


## Сбросить историю (новое подключение).
func clear() -> void:
	_offsets.clear()
	_last_rtt = -1


## Замер: host_msec — время хоста из pong, local_recv_msec — локальное время
## получения pong, rtt_msec — круговая задержка.
func add_sample(host_msec: int, local_recv_msec: int, rtt_msec: int) -> void:
	var offset: float = float(host_msec) + float(rtt_msec) * 0.5 - float(local_recv_msec)
	_offsets.append(offset)
	if _offsets.size() > Protocol.CLOCK_WINDOW:
		_offsets.pop_front()
	_last_rtt = rtt_msec


## Сглаженное смещение «время хоста − локальное время», мс.
func offset_msec() -> float:
	if _offsets.is_empty():
		return 0.0
	var sum := 0.0
	for offset: float in _offsets:
		sum += offset
	return sum / float(_offsets.size())


## Последний RTT, мс (для панели F3; −1 — замеров нет).
func last_rtt_msec() -> int:
	return _last_rtt
