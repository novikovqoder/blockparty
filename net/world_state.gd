# Сериализация состояния мира для входа в любой момент (раздел 10 SPEC):
# хост отправляет rpc_world_state одним надёжным пакетом — эпоху часов мира,
# состав игроков (ник, внешность байтами индексов редактора П5.8, флаг
# «в мире»), мёртвых мобов и подобранные монеты с временем возрождения
# по world_time. Поздно вошедший клиент применяет пакет и сразу видит то же,
# что остальные. Формат (little endian): u32 эпоха, u8 n × {i32 peer,
# u8 len, имя utf8, u8 в мире, 9 байтов внешности (Appearance.to_bytes)},
# u16 n × {u16 spawn_id, f32 respawn_at} — мобы, затем монеты. Чистые
# функции без узлов — обязательный тест раздела 18 «без потерь».
class_name WorldState
extends RefCounted

## Ник в ростере длиннее не передаётся (раздел 14).
const NAME_MAX_CHARS: int = 20


## Собрать состояние в байты. Словарь: {world_epoch_msec: int,
## players: [{peer_id, name, in_world, appearance: PackedByteArray}],
## dead_mobs: [{spawn_id, respawn_at}], taken_coins: [{spawn_id, respawn_at}]}.
static func pack(state: Dictionary) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	buffer.put_u32(int(state["world_epoch_msec"]) & 0xFFFFFFFF)
	var players: Array = state.get("players", [])
	buffer.put_u8(mini(players.size(), 255))
	for entry: Dictionary in players:
		buffer.put_32(int(entry["peer_id"]))
		var name := str(entry["name"]).left(NAME_MAX_CHARS).to_utf8_buffer()
		buffer.put_u8(mini(name.size(), 255))
		buffer.put_data(name)
		buffer.put_u8(1 if bool(entry.get("in_world", false)) else 0)
		# Внешность — 9 байтов индексов; короткое/мусорное поле дополняется
		# дефолтом (клиент ещё раз проверит диапазоны validated()).
		var appearance: PackedByteArray = entry.get("appearance", PackedByteArray())
		for i: int in Appearance.NET_SIZE:
			buffer.put_u8(appearance[i] if i < appearance.size() else 0)
	var dead_mobs: Array = state.get("dead_mobs", [])
	buffer.put_u16(mini(dead_mobs.size(), 0xFFFF))
	for entry: Dictionary in dead_mobs:
		buffer.put_u16(int(entry["spawn_id"]) & 0xFFFF)
		buffer.put_float(float(entry["respawn_at"]))
	var taken_coins: Array = state.get("taken_coins", [])
	buffer.put_u16(mini(taken_coins.size(), 0xFFFF))
	for entry: Dictionary in taken_coins:
		buffer.put_u16(int(entry["spawn_id"]) & 0xFFFF)
		buffer.put_float(float(entry["respawn_at"]))
	# Активности П5 (разделы 7, 9: ворота руин; дальше — маяки и костёр):
	# произвольный словарь в конце пакета, старые клиенты его игнорируют.
	var activities: Dictionary = state.get("activities", {})
	buffer.put_u8(1 if not activities.is_empty() else 0)
	if not activities.is_empty():
		buffer.put_var(activities)
	return buffer.data_array


## Разобрать пакет; возвращает словарь того же вида, что pack().
static func unpack(data: PackedByteArray) -> Dictionary:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	buffer.data_array = data
	var state := {
		"world_epoch_msec": buffer.get_u32(),
		"players": [],
		"dead_mobs": [],
		"taken_coins": [],
	}
	var player_count: int = buffer.get_u8()
	for i: int in player_count:
		var peer_id: int = buffer.get_32()
		var name_size: int = buffer.get_u8()
		var name_bytes := (buffer.get_data(name_size) as Array)[1] as PackedByteArray
		var in_world: bool = buffer.get_u8() != 0
		var appearance := PackedByteArray()
		appearance.resize(Appearance.NET_SIZE)
		for b: int in Appearance.NET_SIZE:
			appearance[b] = buffer.get_u8()
		state["players"].append({
			"peer_id": peer_id,
			"name": name_bytes.get_string_from_utf8(),
			"in_world": in_world,
			"appearance": appearance,
		})
	var mob_count: int = buffer.get_u16()
	for i: int in mob_count:
		state["dead_mobs"].append({
			"spawn_id": buffer.get_u16(),
			"respawn_at": buffer.get_float(),
		})
	var coin_count: int = buffer.get_u16()
	for i: int in coin_count:
		state["taken_coins"].append({
			"spawn_id": buffer.get_u16(),
			"respawn_at": buffer.get_float(),
		})
	# Активности — в конце пакета: пакет от хоста без блока (старый формат)
	# оставляет словарь пустым.
	if buffer.get_position() < data.size():
		if buffer.get_u8() != 0:
			state["activities"] = buffer.get_var() as Dictionary
	return state
