# Обязательный тест раздела 18: сериализация и десериализация world_state
# без потерь (раздел 10: клиент, подключившийся позже, получает те же
# мёртвых мобов и подобранные монеты с временем возрождения).
extends GutTest

const EPS: float = 0.001


func test_roundtrip_full_state() -> void:
	var state := {
		"world_epoch_msec": 172_500_000,
		"players": [
			{"peer_id": 1, "name": "Host", "in_world": true},
			{"peer_id": 234567890, "name": "Длинное имя игрока", "in_world": false,
				"character": 2},
		],
		"dead_mobs": [
			{"spawn_id": 3, "respawn_at": 185.5},
			{"spawn_id": 17, "respawn_at": 1234.25},
		],
		"taken_coins": [
			{"spawn_id": 0, "respawn_at": 300.0},
			{"spawn_id": 41, "respawn_at": 42.5},
			{"spawn_id": 59, "respawn_at": 7.0},
		],
	}
	var parsed := WorldState.unpack(WorldState.pack(state))
	assert_eq(int(parsed["world_epoch_msec"]), 172_500_000)
	assert_eq((parsed["players"] as Array).size(), 2)
	var first: Dictionary = parsed["players"][0]
	var second: Dictionary = parsed["players"][1]
	assert_eq(int(first["peer_id"]), 1)
	assert_eq(str(first["name"]), "Host")
	assert_true(bool(first["in_world"]))
	assert_eq(int(first.get("character", -1)), 0, "без поля персонаж — 0 (дефолт)")
	assert_eq(int(second["peer_id"]), 234567890)
	assert_false(bool(second["in_world"]))
	assert_eq(int(second["character"]), 2, "номер персонажа проходит пакет")
	assert_eq((parsed["dead_mobs"] as Array).size(), 2)
	assert_eq(int(parsed["dead_mobs"][0]["spawn_id"]), 3)
	assert_almost_eq(float(parsed["dead_mobs"][0]["respawn_at"]), 185.5, EPS)
	assert_almost_eq(float(parsed["dead_mobs"][1]["respawn_at"]), 1234.25, EPS)
	assert_eq((parsed["taken_coins"] as Array).size(), 3)
	assert_eq(int(parsed["taken_coins"][2]["spawn_id"]), 59)
	assert_almost_eq(float(parsed["taken_coins"][2]["respawn_at"]), 7.0, EPS)


func test_roundtrip_empty_world() -> void:
	# Пустой мир: только хост, никого не убито и не собрано.
	var state := {
		"world_epoch_msec": 5000,
		"players": [{"peer_id": 1, "name": "Host", "in_world": true}],
		"dead_mobs": [],
		"taken_coins": [],
	}
	var parsed := WorldState.unpack(WorldState.pack(state))
	assert_eq((parsed["players"] as Array).size(), 1)
	assert_eq((parsed["dead_mobs"] as Array).size(), 0)
	assert_eq((parsed["taken_coins"] as Array).size(), 0)


func test_names_are_cut_to_limit() -> void:
	var long_name := "A".repeat(80)
	var state := {
		"world_epoch_msec": 1,
		"players": [{"peer_id": 7, "name": long_name, "in_world": true}],
		"dead_mobs": [],
		"taken_coins": [],
	}
	var parsed := WorldState.unpack(WorldState.pack(state))
	assert_eq(str(parsed["players"][0]["name"]).length(), WorldState.NAME_MAX_CHARS)


func test_full_island_fits() -> void:
	# Все 60 монет и 17 мобов острова единовременно мертвы/собраны —
	# реальный максимум, формат его вмещает.
	var dead: Array = []
	for i: int in range(17):
		dead.append({"spawn_id": i, "respawn_at": float(i) * 10.0})
	var taken: Array = []
	for i: int in range(60):
		taken.append({"spawn_id": i, "respawn_at": 300.0})
	var players: Array = []
	for i: int in range(Protocol.MAX_PLAYERS):
		players.append({
			"peer_id": i + 1,
			"name": "P%d" % (i + 1),
			"in_world": true,
			"character": i % 3,
		})
	var state := {
		"world_epoch_msec": 42,
		"players": players,
		"dead_mobs": dead,
		"taken_coins": taken,
	}
	var data := WorldState.pack(state)
	var parsed := WorldState.unpack(data)
	assert_eq((parsed["players"] as Array).size(), Protocol.MAX_PLAYERS)
	assert_eq(int(parsed["players"][2]["character"]), 2, "персонаж полного роста")
	assert_eq((parsed["dead_mobs"] as Array).size(), 17)
	assert_eq((parsed["taken_coins"] as Array).size(), 60)
	assert_eq(int(parsed["taken_coins"][59]["spawn_id"]), 59)


func test_respawn_times_survive_fractional_seconds() -> void:
	# respawn_at — float32: точность до ~0.001 с на масштабе часов мира.
	var state := {
		"world_epoch_msec": 1,
		"players": [],
		"dead_mobs": [{"spawn_id": 5, "respawn_at": 3599.75}],
		"taken_coins": [{"spawn_id": 6, "respawn_at": 60123.5}],
	}
	var parsed := WorldState.unpack(WorldState.pack(state))
	assert_almost_eq(float(parsed["dead_mobs"][0]["respawn_at"]), 3599.75, 0.01)
	assert_almost_eq(float(parsed["taken_coins"][0]["respawn_at"]), 60123.5, 4.0)
