# Разбор аргументов командной строки для локальных тестов (раздел 4 SPEC):
# --dev-host, --dev-join=IP, --dev-name, --dev-spawn=ZONE, --bot, --net-lag,
# --net-loss, --log-net, --shot-dir, --simple-graphics. Аргументы передаются
# Godot после «--» и читаются через OS.get_cmdline_user_args().
# Не делает: не применяет аргументы сам — их применяют Net, Session, SteamService.
extends Node

## Порт ENet для --dev-host (раздел 4 SPEC).
const DEV_PORT: int = 7777
## Лимит FPS headless-копий в режиме --bot: без него каждая копия грузит
## процессор на 100% и нагрузочный прогон 12 экземпляров душит сам себя.
const HEADLESS_BOT_MAX_FPS: int = 60
## Зоны появления для --dev-spawn (раздел 4 SPEC; Площадь — по умолчанию).
const SPAWN_ZONES: PackedStringArray = ["plaza", "forest", "ruins", "hills", "crevasse", "lake"]

var host_mode: bool = false      # --dev-host: запуститься хостом через ENet
var join_address: String = ""    # --dev-join=IP: подключиться клиентом
var player_name: String = ""     # --dev-name: имя игрока без Steam
var spawn_zone: String = ""      # --dev-spawn=ZONE: появиться сразу в зоне
var bot: bool = false            # --bot: бот для нагрузочных тестов (ходьба — П3)
var net_lag_ms: int = 0          # --net-lag: эмуляция задержки сети, мс
var net_loss_percent: int = 0    # --net-loss: эмуляция потери пакетов, %
var log_net: bool = false        # --log-net: подробный лог сетевых RPC
var shot_dir: String = ""        # --shot-dir=PATH: скриншоты площадок и выход
var simple_graphics: bool = false  # --simple-graphics: «Простая графика» (раздел 15)


func _init() -> void:
	var parsed: Dictionary = parse_args(OS.get_cmdline_user_args())
	host_mode = parsed["host_mode"]
	join_address = parsed["join_address"]
	player_name = parsed["player_name"]
	spawn_zone = parsed["spawn_zone"]
	bot = parsed["bot"]
	net_lag_ms = parsed["net_lag_ms"]
	net_loss_percent = parsed["net_loss_percent"]
	log_net = parsed["log_net"]
	shot_dir = parsed["shot_dir"]
	simple_graphics = parsed["simple_graphics"]


func _ready() -> void:
	# Settings в порядке автолоадов раньше Dev — флаг применяем здесь.
	if simple_graphics:
		Settings.simple_graphics = true


## Разбор списка аргументов в словарь с полями-константами этого автолоада.
## Отдельная статическая функция — чтобы тесты GUT проверяли разбор без автолоада.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var result := {
		"host_mode": false,
		"join_address": "",
		"player_name": "",
		"spawn_zone": "",
		"bot": false,
		"net_lag_ms": 0,
		"net_loss_percent": 0,
		"log_net": false,
		"shot_dir": "",
		"simple_graphics": false,
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
		elif arg.begins_with("--dev-spawn="):
			# Неизвестная зона игнорируется — остаётся стандартная Площадь.
			var zone: String = arg.get_slice("=", 1)
			if zone in SPAWN_ZONES:
				result["spawn_zone"] = zone
		elif arg.begins_with("--net-lag="):
			result["net_lag_ms"] = maxi(0, _to_int(arg.get_slice("=", 1), 0))
		elif arg.begins_with("--net-loss="):
			result["net_loss_percent"] = clampi(_to_int(arg.get_slice("=", 1), 0), 0, 100)
		elif arg.begins_with("--shot-dir="):
			result["shot_dir"] = arg.get_slice("=", 1)
		elif arg == "--simple-graphics":
			result["simple_graphics"] = true
	return result


static func _to_int(text: String, fallback: int) -> int:
	if text.is_valid_int():
		return text.to_int()
	return fallback
