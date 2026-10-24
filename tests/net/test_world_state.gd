# Обязательный тест раздела 18: сериализация и десериализация world_state
# без потерь (раздел 10: клиент, подключившийся позже, получает те же часы,
# ростер и активности). Мёртвые мобы были в формате до протокола 6 —
# мобы удалены в доработке П5.13.
extends GutTest

const EPS: float = 0.001


func test_roundtrip_full_state() -> void:
	var state := {
		"world_epoch_msec": 172_500_000,
		"players": [
			{"peer_id": 1, "name": "Host", "in_world": true},
			{"peer_id": 234567890, "name": "Длинное имя игрока", "in_world": false,
				"appearance": PackedByteArray([1, 3, 1, 0, 1, 1, 7, 5, 2])},
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
	# Без поля внешности (старый формат) — дефолтные нули, не мусор.
	assert_eq((first.get("appearance", PackedByteArray()) as PackedByteArray),
		PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0]), "без поля внешности — дефолт")
	assert_eq(int(second["peer_id"]), 234567890)
	assert_false(bool(second["in_world"]))
	assert_eq((second["appearance"] as PackedByteArray),
		PackedByteArray([1, 3, 1, 0, 1, 1, 7, 5, 2]),
		"внешность байтами проходит пакет без потерь")


func test_roundtrip_empty_world() -> void:
	# Пустой мир: только хост.
	var state := {
		"world_epoch_msec": 5000,
		"players": [{"peer_id": 1, "name": "Host", "in_world": true}],
	}
	var parsed := WorldState.unpack(WorldState.pack(state))
	assert_eq((parsed["players"] as Array).size(), 1)


func test_names_are_cut_to_limit() -> void:
	var long_name := "A".repeat(80)
	var state := {
		"world_epoch_msec": 1,
		"players": [{"peer_id": 7, "name": long_name, "in_world": true}],
	}
	var parsed := WorldState.unpack(WorldState.pack(state))
	assert_eq(str(parsed["players"][0]["name"]).length(), WorldState.NAME_MAX_CHARS)


func test_full_roster_fits() -> void:
	# Полный ростер (жёсткий предел раздела 10) — формат его вмещает.
	var players: Array = []
	for i: int in range(Protocol.MAX_PLAYERS):
		players.append({
			"peer_id": i + 1,
			"name": "P%d" % (i + 1),
			"in_world": true,
			"appearance": PackedByteArray([i % 2, i % 6, i % 2, 0, 0, i % 2,
				i % 10, i % 8, i % 6]),
		})
	var state := {
		"world_epoch_msec": 42,
		"players": players,
	}
	var data := WorldState.pack(state)
	var parsed := WorldState.unpack(data)
	assert_eq((parsed["players"] as Array).size(), Protocol.MAX_PLAYERS)
	assert_eq(int(parsed["players"][1]["appearance"][0]), 1,
		"внешность полного роста проходит")


func test_activities_roundtrip() -> void:
	# Активности П5 (разделы 9.2+): вошедший в любой момент видит открытые
	# ворота руин и занятые плиты; блок в конце пакета опционален.
	var state := {
		"world_epoch_msec": 42,
		"players": [{"peer_id": 1, "name": "Host", "in_world": true}],
		"activities": {"ruins": {"gate_open": true, "gate_opened_at": 123.5, "plates": [4, 0, 7]}},
	}
	var parsed := WorldState.unpack(WorldState.pack(state))
	var ruins: Dictionary = (parsed["activities"] as Dictionary)["ruins"]
	assert_true(bool(ruins["gate_open"]))
	assert_almost_eq(float(ruins["gate_opened_at"]), 123.5, EPS)
	assert_eq(int(ruins["plates"][0]), 4)
	assert_eq(int(ruins["plates"][2]), 7)
	# Без блока активностей (старый формат) — словарь остаётся пустым.
	var bare := {
		"world_epoch_msec": 42,
		"players": [],
	}
	assert_false(WorldState.unpack(WorldState.pack(bare)).has("activities"))
