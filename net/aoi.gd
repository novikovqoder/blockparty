# AOI-фильтр хоста (раздел 10 SPEC): снапшоты пересылаются игроку тем реже,
# чем дальше он от отправителя — до 60 м все 20 Гц, до 150 м — 4 Гц, дальше —
# 1 Гц (только для карты и ников). Чистая логика без узлов: хост спрашивает
# allow() перед каждой пересылкой, фильтр сам помнит, когда пара
# «отправитель → получатель» получала снапшот в последний раз.
# Обязательный тест раздела 18 «AOI-фильтр».
class_name AoiFilter
extends RefCounted


## Частота пересылки по дистанции между игроками, Гц (раздел 10).
static func rate_hz(distance: float) -> float:
	if distance <= Protocol.AOI_FULL_DISTANCE:
		return Protocol.AOI_RATE_FULL_HZ
	if distance <= Protocol.AOI_FAR_DISTANCE:
		return Protocol.AOI_RATE_MID_HZ
	return Protocol.AOI_RATE_FAR_HZ


## Минимальная пауза между пересылками для частоты, мс.
static func min_interval_msec(rate: float) -> int:
	return int(round(1000.0 / rate))


## Переслать ли снапшот от from_peer игроку to_peer сейчас. Позиции нужны
## только для дистанции; позиция получателя неизвестна (он ещё не прислал
## ни одного снапшота) считается нулевой — до первого снапшота шлём полностью.
func allow(from_peer: int, to_peer: int, distance: float, now_msec: int) -> bool:
	var key := _key(from_peer, to_peer)
	var last: int = int(_last_sent.get(key, -0x7FFFFFFF))
	if now_msec - last < min_interval_msec(rate_hz(distance)):
		return false
	_last_sent[key] = now_msec
	return true


## Забыть историю отправок (новый мир).
func clear() -> void:
	_last_sent.clear()


var _last_sent: Dictionary = {}


static func _key(from_peer: int, to_peer: int) -> String:
	return "%d>%d" % [from_peer, to_peer]
