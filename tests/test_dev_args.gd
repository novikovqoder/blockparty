# Тест разбора аргументов командной строки (autoload/dev.gd, parse_args).
# Требование этапа 0: аргументы из раздела 3 SPEC разбираются корректно.
extends GutTest

const DevScript: GDScript = preload("res://autoload/dev.gd")


func test_no_args_gives_defaults() -> void:
	var d: Dictionary = DevScript.parse_args(PackedStringArray([]))
	assert_false(d["host_mode"])
	assert_eq(d["join_address"], "")
	assert_eq(d["player_name"], "")
	assert_eq(d["level_seed"], -1)
	assert_false(d["bot"])
	assert_eq(d["net_lag_ms"], 0)
	assert_eq(d["net_loss_percent"], 0)
	assert_false(d["log_net"])


func test_flags() -> void:
	var d: Dictionary = DevScript.parse_args(PackedStringArray(["--dev-host", "--bot", "--log-net"]))
	assert_true(d["host_mode"])
	assert_true(d["bot"])
	assert_true(d["log_net"])


func test_values_with_equals() -> void:
	var d: Dictionary = DevScript.parse_args(PackedStringArray([
		"--dev-join=127.0.0.1",
		"--dev-name=Bot3",
		"--dev-seed=12345",
	]))
	assert_eq(d["join_address"], "127.0.0.1")
	assert_eq(d["player_name"], "Bot3")
	assert_eq(d["level_seed"], 12345)


func test_network_emulation_args() -> void:
	var d: Dictionary = DevScript.parse_args(PackedStringArray(["--net-lag=150", "--net-loss=5"]))
	assert_eq(d["net_lag_ms"], 150)
	assert_eq(d["net_loss_percent"], 5)


func test_invalid_numbers_fall_back() -> void:
	var d: Dictionary = DevScript.parse_args(PackedStringArray([
		"--dev-seed=abc",
		"--net-lag=-10",
		"--net-loss=500",
	]))
	assert_eq(d["level_seed"], -1, "нечисловой seed должен вернуться к -1")
	assert_eq(d["net_lag_ms"], 0, "отрицательная задержка не допускается")
	assert_eq(d["net_loss_percent"], 100, "потери ограничены 100%")


func test_unknown_args_ignored() -> void:
	var d: Dictionary = DevScript.parse_args(PackedStringArray(["--something-else", "positional"]))
	assert_false(d["host_mode"])
	assert_eq(d["join_address"], "")
