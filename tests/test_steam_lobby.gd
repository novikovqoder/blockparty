# Тесты чистой логики лобби Steam (раздел 11 SPEC): выбор мира из результатов
# поиска, разбор аргумента запуска +connect_lobby, метаданные лобби и строка
# connect для Rich Presence. Живой Steam-клиент на сервере недоступен — сами
# сетевые пути Steam проверяются вручную на двух ПК (критерии этапа П4).
extends GutTest

const SteamServiceScript: GDScript = preload("res://autoload/steam_service.gd")


# --- Выбор мира из поиска (раздел 11: самый населённый, не полный) ---

func test_pick_best_most_populated_wins() -> void:
	var best: int = SteamServiceScript.pick_best_lobby([
		{"id": 11, "members": 2, "limit": 12},
		{"id": 22, "members": 7, "limit": 12},
		{"id": 33, "members": 4, "limit": 12},
	])
	assert_eq(best, 22, "входим в самый населённый мир")


func test_pick_best_skips_full_worlds() -> void:
	var best: int = SteamServiceScript.pick_best_lobby([
		{"id": 11, "members": 12, "limit": 12},
		{"id": 22, "members": 3, "limit": 12},
	])
	assert_eq(best, 22, "полный мир пропускается")


func test_pick_best_no_suitable_world() -> void:
	assert_eq(
		SteamServiceScript.pick_best_lobby([
			{"id": 11, "members": 12, "limit": 12},
			{"id": 22, "members": 16, "limit": 16},
		]),
		0,
		"все полные — своего мира нет, надо создавать",
	)
	assert_eq(SteamServiceScript.pick_best_lobby([]), 0, "пустой список")


func test_pick_best_zero_limit_is_joinable() -> void:
	# limit 0 — лобби без явного лимита: настоящий лимит проверит Steam.
	var best: int = SteamServiceScript.pick_best_lobby([
		{"id": 11, "members": 40, "limit": 0},
	])
	assert_eq(best, 11, "не считается полным")


func test_pick_best_skips_blocked() -> void:
	# Раздел 11: миры с заблокированными игроками пропускаются (блок-лист — П8,
	# но выбор мира уже учитывает флаг).
	var best: int = SteamServiceScript.pick_best_lobby([
		{"id": 11, "members": 9, "limit": 12, "blocked": true},
		{"id": 22, "members": 2, "limit": 12},
	])
	assert_eq(best, 22, "мир с заблокированным игроком пропускается")


func test_pick_best_tie_keeps_first() -> void:
	var best: int = SteamServiceScript.pick_best_lobby([
		{"id": 11, "members": 5, "limit": 12},
		{"id": 22, "members": 5, "limit": 12},
	])
	assert_eq(best, 11, "при равенстве — первый в списке (детерминизм)")


# --- Аргумент запуска +connect_lobby (раздел 11) ---

func test_parse_connect_lobby_two_args() -> void:
	var lobby: int = SteamServiceScript.parse_connect_lobby(
		PackedStringArray(["--foo", "+connect_lobby", "10980112345678901"]),
	)
	assert_eq(lobby, 10980112345678901, "Steam пишет «+connect_lobby <id>» двумя токенами")


func test_parse_connect_lobby_equals_form() -> void:
	var lobby: int = SteamServiceScript.parse_connect_lobby(
		PackedStringArray(["+connect_lobby=777"]),
	)
	assert_eq(lobby, 777, "форма через «=» тоже поддерживается")


func test_parse_connect_lobby_invalid() -> void:
	assert_eq(SteamServiceScript.parse_connect_lobby(PackedStringArray([])), 0)
	assert_eq(
		SteamServiceScript.parse_connect_lobby(PackedStringArray(["+connect_lobby"])),
		0,
		"нет следующего токена",
	)
	assert_eq(
		SteamServiceScript.parse_connect_lobby(PackedStringArray(["+connect_lobby", "abc"])),
		0,
		"не число",
	)
	assert_eq(
		SteamServiceScript.parse_connect_lobby(PackedStringArray(["--dev-host"])),
		0,
		"обычные аргументы не мешают",
	)


# --- Метаданные лобби (раздел 11: game, ver, mode, players, host_name) ---

func test_lobby_metadata_public() -> void:
	var meta: Array[Dictionary] = SteamServiceScript.lobby_metadata(
		SteamServiceScript.LOBBY_MODE_PUBLIC, 3, "Kotik",
	)
	var by_key: Dictionary = {}
	for pair: Dictionary in meta:
		by_key[str(pair["key"])] = str(pair["value"])
	assert_eq(by_key.size(), 5, "ровно пять полей из раздела 11")
	assert_eq(by_key["game"], "blockparty")
	assert_eq(by_key["ver"], str(Protocol.PROTOCOL_VERSION), "версия протокола")
	assert_eq(by_key["mode"], "public")
	assert_eq(by_key["players"], "3", "число игроков строкой")
	assert_eq(by_key["host_name"], "Kotik")


func test_lobby_metadata_friends_mode() -> void:
	var meta: Array[Dictionary] = SteamServiceScript.lobby_metadata(
		SteamServiceScript.LOBBY_MODE_FRIENDS, 1, "Host",
	)
	var modes: Array = meta.filter(
		func(pair: Dictionary) -> bool: return str(pair["key"]) == "mode",
	)
	assert_eq(str(modes[0]["value"]), "friends")


# --- Rich Presence (раздел 11: status «На острове (5 / 12)», connect) ---

func test_rich_presence_connect_command() -> void:
	assert_eq(
		SteamServiceScript.connect_command(42),
		"+connect_lobby 42",
		"connect передаётся командой запуска",
	)


func test_rich_presence_status_text() -> void:
	# tr() в контексте GUT не подгружает переводы (возвращает ключ), поэтому
	# проверяем саму пару ключ→строка в strings.csv: статус «На острове
	# (5 / 12)» — формат с двумя числами, ru и en.
	for row: PackedStringArray in _strings_csv():
		if row[0] == "RP_IN_WORLD":
			assert_true(row[1].contains("(%d / %d)"), "ru: счётчик «N / M»: %s" % row[1])
			assert_true(row[2].contains("(%d / %d)"), "en: счётчик «N / M»: %s" % row[2])
			return
	fail_test("ключ RP_IN_WORLD не найден в strings.csv")


## Все новые ключи Steam-этапа есть в обоих языках (правило: весь текст — tr()).
func test_steam_strings_exist() -> void:
	var keys: PackedStringArray = [
		"MENU_NET_SEARCHING", "MENU_NET_CREATING", "MENU_NET_JOINING",
		"MENU_NET_JOIN_FAILED", "LOBBY_FAIL_CREATE", "LOBBY_FAIL_FULL",
		"LOBBY_FAIL_CLOSED", "LOBBY_FAIL_GENERIC", "RP_IN_WORLD",
		"ESC_INVITE_FRIEND",
	]
	var have: Dictionary = {}
	for row: PackedStringArray in _strings_csv():
		have[row[0]] = true
	for key: String in keys:
		assert_true(have.has(key), "ключ %s есть в strings.csv" % key)


func _strings_csv() -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var file := FileAccess.open("res://i18n/strings.csv", FileAccess.READ)
	if file == null:
		fail_test("strings.csv не открывается")
		return rows
	while not file.eof_reached():
		var line: String = file.get_line()
		if line.is_empty() or line.begins_with("keys,"):
			continue
		rows.append(line.split(","))
	file.close()
	return rows
