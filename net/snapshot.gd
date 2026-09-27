# Упаковка и распаковка снапшота игрока в PackedByteArray (раздел 8 SPEC):
# seq uint16, x float32, y float32, vx int16, vy int16, anim_state uint8,
# flags uint8 — 16 байт. Скорости теряют доли px/с (допустимое округление,
# обязательный тест раздела 16).
class_name Snapshot
extends RefCounted


## Собрать снапшот в байты.
static func pack(seq: int, x: float, y: float, vx: float, vy: float, anim_state: int, flags: int) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	buffer.put_u16(seq & 0xFFFF)
	buffer.put_float(x)
	buffer.put_float(y)
	buffer.put_16(clampi(int(round(vx)), -32768, 32767))
	buffer.put_16(clampi(int(round(vy)), -32768, 32767))
	buffer.put_u8(anim_state & 0xFF)
	buffer.put_u8(flags & 0xFF)
	return buffer.data_array


## Разобрать снапшот; возвращает {seq, x, y, vx, vy, anim, flags}.
static func unpack(data: PackedByteArray) -> Dictionary:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	buffer.data_array = data
	return {
		"seq": buffer.get_u16(),
		"x": buffer.get_float(),
		"y": buffer.get_float(),
		"vx": float(buffer.get_16()),
		"vy": float(buffer.get_16()),
		"anim": buffer.get_u8(),
		"flags": buffer.get_u8(),
	}


## Размер пакета этой версии (для панели F3 и теста бюджета).
static func packed_size() -> int:
	return 2 + 4 + 4 + 2 + 2 + 1 + 1
