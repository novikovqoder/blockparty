# Тест разбора аргументов командной строки (autoload/dev.gd, parse_args).
# Требование этапа П0: аргументы раздела 4 SPEC разбираются корректно.
extends GutTest

const DevScript: GDScript = preload("res://autoload/dev.gd")


func test_no_args_gives_defaults() -> void:
	var d: Dictionary = DevScript.parse_args(PackedStringArray([]))
	assert_false(d["host_mode"])
	assert_eq(d["join_address"], "")
	assert_eq(d["player_name"], "")
	assert_eq(d["spawn_zone"], "")
	assert_false(d["bot"])
	assert_eq(d["net_lag_ms"], 0)
	assert_eq(d["net_loss_percent"], 0)
	assert_false(d["log_net"])


func test_flags() -> void:
	var d: Dictionary = DevScript.parse_args(PackedStringArray([
		"--dev-host", "--bot", "--log-net", "--simple-graphics",
	]))
	assert_true(d["host_mode"])
	assert_true(d["bot"])
	assert_true(d["log_net"])
	assert_true(d["simple_graphics"])


func test_values_with_equals() -> void:
	var d: Dictionary = DevScript.parse_args(PackedStringArray([
		"--dev-join=127.0.0.1",
		"--dev-name=Bot3",
		"--dev-spawn=ruins",
	]))
	assert_eq(d["join_address"], "127.0.0.1")
	assert_eq(d["player_name"], "Bot3")
	assert_eq(d["spawn_zone"], "ruins")


func test_spawn_zone_validated() -> void:
	# Раздел 4: зоны фиксированы (plaza, forest, ruins, hills, crevasse, lake);
	# неизвестная игнорируется — остаётся стандартная Площадь.
	var d: Dictionary = DevScript.parse_args(PackedStringArray(["--dev-spawn=atlantis"]))
	assert_eq(d["spawn_zone"], "")
	for zone: String in DevScript.SPAWN_ZONES:
		var z: Dictionary = DevScript.parse_args(PackedStringArray(["--dev-spawn=%s" % zone]))
		assert_eq(z["spawn_zone"], zone, "зона %s должна приниматься" % zone)


func test_seed_arg_gone() -> void:
	# Мир фиксированный: --dev-seed из v1 удалён (раздел 4 SPEC).
	var d: Dictionary = DevScript.parse_args(PackedStringArray(["--dev-seed=42"]))
	assert_false(d.has("level_seed"), "--dev-seed больше не разбирается")


func test_network_emulation_args() -> void:
	var d: Dictionary = DevScript.parse_args(PackedStringArray(["--net-lag=150", "--net-loss=5"]))
	assert_eq(d["net_lag_ms"], 150)
	assert_eq(d["net_loss_percent"], 5)


func test_invalid_numbers_fall_back() -> void:
	var d: Dictionary = DevScript.parse_args(PackedStringArray([
		"--net-lag=-10",
		"--net-loss=500",
	]))
	assert_eq(d["net_lag_ms"], 0, "отрицательная задержка не допускается")
	assert_eq(d["net_loss_percent"], 100, "потери ограничены 100%")


func test_unknown_args_ignored() -> void:
	var d: Dictionary = DevScript.parse_args(PackedStringArray(["--something-else", "positional"]))
	assert_false(d["host_mode"])
	assert_eq(d["join_address"], "")
