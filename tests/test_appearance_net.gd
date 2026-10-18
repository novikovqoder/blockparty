# Сетевые тесты внешности (П5.8, часть B3): rpc_hello везёт внешность
# байтами индексов, хост не доверяет клиенту — validated() чинит диапазоны
# и причёску по полу; ростер и слоты хранят байты, peer_appearance() всегда
# валидная внешность; PROTOCOL_VERSION 4 отсекает старые клиенты.
extends GutTest


## Байты «злоумышленника»: все индексы вне диапазонов, причёска-борода
## на женском теле.
func _garbage() -> PackedByteArray:
	return PackedByteArray([1, 200, 99, 77, 5, 42, 250, 99, 88])


func test_hello_bytes_survive_roster_roundtrip() -> void:
	# Слот хранит байты, записи ростера их сохраняют (pack/unpack — в
	# test_world_state, здесь — словарь Net._roster_entries).
	var saved_players: Dictionary = Net.players.duplicate(true)
	Net.players = {5: Net._new_slot("Гость", PackedByteArray([1, 3, 1, 0, 1, 1, 7, 5, 2]))}
	var entries: Array = Net._roster_entries()
	assert_eq((entries[0]["appearance"] as PackedByteArray),
		PackedByteArray([1, 3, 1, 0, 1, 1, 7, 5, 2]),
		"байты внешности прошли через запись ростера")
	var parsed := WorldState.unpack(WorldState.pack({
		"world_epoch_msec": 1000, "players": entries,
	}))
	var restored: PackedByteArray = parsed["players"][0]["appearance"]
	var ap := Appearance.from_bytes(restored)
	assert_eq(ap.gender, 1, "пол после ростера и пакета")
	assert_eq(ap.hair, 3, "причёска после ростера и пакета")
	Net.players = saved_players


func test_host_validates_hello_ranges() -> void:
	# Правило хоста из rpc_hello: from_bytes(мусор).validated() — все
	# индексы в диапазонах, причёска допустима для пола (борода не
	# остаётся на женском теле).
	var fixed := Appearance.from_bytes(_garbage()).validated()
	var female_hairs: Array = []
	female_hairs.append_array(Appearance.hair_variants(Appearance.GENDER_FEMALE))
	assert_has(female_hairs, fixed.hair, "причёска допустима для женского тела")
	assert_between(fixed.top, 0, Appearance.OUTFITS.size() - 1, "верх в диапазоне")
	assert_between(fixed.hair_color, 0, Appearance.HAIR_COLORS.size() - 1,
		"цвет волос в диапазоне")
	assert_between(fixed.skin, 0, Appearance.SKIN_COLORS.size() - 1, "кожа в диапазоне")
	assert_true(fixed.same(fixed.validated()),
		"повторная валидация ничего не меняет")


func test_peer_appearance_from_junk_slot_is_default() -> void:
	# Слот с мусором (старые пакеты, битые данные) — дефолтная валидная
	# внешность, сцены получают готовую комбинацию.
	var saved_players: Dictionary = Net.players.duplicate(true)
	Net.players = {
		7: {"name": "Мусор", "in_world": true, "appearance": _garbage()},
		8: {"name": "Пусто", "in_world": true},
	}
	var ap7 := Net.peer_appearance(7)
	assert_true(ap7.same(Appearance.from_bytes(_garbage()).validated()),
		"мусор починен валидацией")
	var ap8 := Net.peer_appearance(8)
	assert_true(ap8.same(Appearance.default_for(0).validated()),
		"слот без внешности — дефолт")
	Net.players = saved_players


func test_local_slot_carries_editor_appearance() -> void:
	# Слот локального игрока берёт внешность из user:// (редактор, B2);
	# rpc_hello отдаёт эти байты хосту без правок.
	var slot: Dictionary = Net._new_local_slot()
	var ap := Appearance.from_bytes(slot["appearance"] as PackedByteArray)
	assert_between(ap.gender, 0, 1, "пол из редактора валиден")
	assert_true(ap.same(ap.validated()), "внешность из save уже валидна")


func test_protocol_version_is_6() -> void:
	# 6 — доработка П5.13 (world_state без мёртвых мобов: мобы удалены);
	# 5 — П5.9 переделка (мир без монет/заданий/маяков); внешность байтами
	# индексов осталась от 4.
	assert_eq(Protocol.PROTOCOL_VERSION, 6,
		"мир без мобов — версия протокола 6")
