# Упаковка и распаковка 3D-снапшота игрока в PackedByteArray (раздел 10 SPEC):
# seq uint16, x/y/z float32, yaw int16 (угол × 10000 / π), vx/vy/vz int16
# (м/с × 100), anim_state uint8, flags uint8 — 24 байта (бюджет «около 26»).
# Точность: координаты — float32, скорости теряют сотые доли м/с, поворот —
# шаг около 0.0006 рад (обязательный тест раздела 18).
class_name Snapshot
extends RefCounted

## Множитель кодирования поворота: радианы -> int16 (раздел 10).
const YAW_SCALE: float = 10000.0 / PI


## Закодировать поворот модели, радианы -> int16.
static func yaw_encode(yaw: float) -> int:
	return clampi(int(round(yaw * YAW_SCALE)), -32768, 32767)


## Декодировать поворот модели, int16 -> радианы.
static func yaw_decode(encoded: int) -> float:
	return float(encoded) / YAW_SCALE


## Собрать снапшот в байты.
static func pack(seq: int, x: float, y: float, z: float, yaw: float, vx: float, vy: float, vz: float, anim_state: int, flags: int) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	buffer.put_u16(seq & 0xFFFF)
	buffer.put_float(x)
	buffer.put_float(y)
	buffer.put_float(z)
	buffer.put_16(yaw_encode(yaw))
	buffer.put_16(clampi(int(round(vx * 100.0)), -32768, 32767))
	buffer.put_16(clampi(int(round(vy * 100.0)), -32768, 32767))
	buffer.put_16(clampi(int(round(vz * 100.0)), -32768, 32767))
	buffer.put_u8(anim_state & 0xFF)
	buffer.put_u8(flags & 0xFF)
	return buffer.data_array


## Разобрать снапшот; возвращает {seq, x, y, z, yaw, vx, vy, vz, anim, flags}.
static func unpack(data: PackedByteArray) -> Dictionary:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	buffer.data_array = data
	var seq: int = buffer.get_u16()
	var x: float = buffer.get_float()
	var y: float = buffer.get_float()
	var z: float = buffer.get_float()
	var yaw: float = yaw_decode(buffer.get_16())
	var vx: float = float(buffer.get_16()) / 100.0
	var vy: float = float(buffer.get_16()) / 100.0
	var vz: float = float(buffer.get_16()) / 100.0
	var anim: int = buffer.get_u8()
	var flags: int = buffer.get_u8()
	return {
		"seq": seq,
		"x": x,
		"y": y,
		"z": z,
		"yaw": yaw,
		"vx": vx,
		"vy": vy,
		"vz": vz,
		"anim": anim,
		"flags": flags,
	}


## Размер пакета этой версии (для панели F3 и теста бюджета).
static func packed_size() -> int:
	return 2 + 4 + 4 + 4 + 2 + 2 + 2 + 2 + 1 + 1
