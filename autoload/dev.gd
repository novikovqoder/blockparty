# Разбор аргументов командной строки для локальных тестов (раздел 3 SPEC):
# --dev-host, --dev-join=IP, --dev-name, --dev-seed, --bot, --net-lag, --net-loss, --log-net.
# Аргументы передаются Godot после «--» и читаются через OS.get_cmdline_user_args().
# Не делает: не применяет аргументы сам — их применяют Net, Session, SteamService.
extends Node

## Порт ENet для --dev-host (раздел 3 SPEC).
const DEV_PORT: int = 7777

var host_mode: bool = false      # --dev-host: запуститься хостом через ENet
var join_address: String = ""    # --dev-join=IP: подключиться клиентом
var player_name: String = ""     # --dev-name: имя игрока без Steam
var level_seed: int = -1         # --dev-seed: фиксированный seed уровня (-1 = генерировать)
var bot: bool = false            # --bot: простой бот для нагрузочных тестов
var net_lag_ms: int = 0          # --net-lag: эмуляция задержки сети, мс
var net_loss_percent: int = 0    # --net-loss: эмуляция потери пакетов, %
var log_net: bool = false        # --log-net: подробный лог сетевых RPC


func _init() -> void:
	var parsed: Dictionary = parse_args(OS.get_cmdline_user_args())
	host_mode = parsed["host_mode"]
	join_address = parsed["join_address"]
	player_name = parsed["player_name"]
	level_seed = parsed["level_seed"]
	bot = parsed["bot"]
	net_lag_ms = parsed["net_lag_ms"]
	net_loss_percent = parsed["net_loss_percent"]
	log_net = parsed["log_net"]


## Разбор списка аргументов в словарь с полями-константами этого автолоада.
## Отдельная статическая функция — чтобы тесты GUT проверяли разбор без автолоада.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var result := {
		"host_mode": false,
		"join_address": "",
		"player_name": "",
		"level_seed": -1,
		"bot": false,
		"net_lag_ms": 0,
		"net_loss_percent": 0,
		"log_net": false,
	}
	for arg: String in args:
		if arg == "--dev-host":
			result["host_mode"] = true
		elif arg == "--bot":
			result["bot"] = true
		elif arg == "--log-net":
			result["log_net"] = true
		elif arg.begins_with("--dev-join="):
			result["join_address"] = arg.get_slice("=", 1)
		elif arg.begins_with("--dev-name="):
			result["player_name"] = arg.get_slice("=", 1)
		elif arg.begins_with("--dev-seed="):
			result["level_seed"] = _to_int(arg.get_slice("=", 1), -1)
		elif arg.begins_with("--net-lag="):
			result["net_lag_ms"] = maxi(0, _to_int(arg.get_slice("=", 1), 0))
		elif arg.begins_with("--net-loss="):
			result["net_loss_percent"] = clampi(_to_int(arg.get_slice("=", 1), 0), 0, 100)
	return result


static func _to_int(text: String, fallback: int) -> int:
	if text.is_valid_int():
		return text.to_int()
	return fallback
