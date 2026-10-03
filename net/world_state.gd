# Сериализация состояния мира для входа в любой момент (раздел 10 SPEC):
# хост отправляет rpc_world_state одним надёжным пакетом — эпоху часов мира,
# состав игроков (ник + флаг «в мире», для персонажей), мёртвых мобов и
# подобранные монеты с временем возрождения по world_time. Поздно вошедший
# клиент применяет пакет и сразу видит то же, что остальные.
# Формат (little endian): u32 эпоха, u8 n × {i32 peer, u8 len, имя utf8,
# u8 в мире}, u16 n × {u16 spawn_id, f32 respawn_at} — мобы, затем монеты.
# Чистые функции без узлов — обязательный тест раздела 18 «без потерь».
class_name WorldState
extends RefCounted

## Ник в ростере длиннее не передаётся (раздел 14).
const NAME_MAX_CHARS: int = 20


## Собрать состояние в байты. Словарь: {world_epoch_msec: int,
## players: [{peer_id, name, in_world}], dead_mobs: [{spawn_id, respawn_at}],
## taken_coins: [{spawn_id, respawn_at}]}.
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
		state["players"].append({
			"peer_id": peer_id,
			"name": name_bytes.get_string_from_utf8(),
			"in_world": in_world,
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
	return state
