class_name MainMenuGame
extends Node
## Обвязка главного меню Born Unblessed для игры (П9). Сцена комплекта
## scenes/menu_bu/main_menu_bu.tscn встраивается КАК ЕСТЬ: этот узел
## инстанцирует её дочерней сценой и связывает с игрой — старт, Steam-поток
## входа (раздел 11), приглашения, автовход ботов и самопроверок.
## Старое меню Blockparty доступно по --old-menu (Dev.menu_scene_path()).

const WORLD_SCENE: String = "res://scenes/world_scene.tscn"
const MENU_BU_SCENE: String = "res://scenes/menu_bu/main_menu_bu.tscn"
## Пауза перед автовходом бота/самопроверки — как в старом меню.
const AUTO_ENTER_DELAY: float = 1.0

var _menu: MainMenuBU
var _auto_wait: float = 0.0


func _ready() -> void:
	var packed: PackedScene = load(MENU_BU_SCENE) as PackedScene
	_menu = packed.instantiate() as MainMenuBU
	add_child(_menu)
	_menu.start_requested.connect(_on_start_requested)
	if not SteamService.available:
		return
	EventBus.steam_world_ready.connect(_on_steam_world_ready)
	SteamService.lobby_join_failed.connect(_on_steam_lobby_join_failed)
	SteamService.invite_received.connect(_on_steam_invite)
	# Раздел 11: вход в мир по +connect_lobby при закрытой игре.
	var invited_lobby: int = SteamService.consume_pending_connect_lobby()
	if invited_lobby != 0:
		Log.info("MainMenuBU: вход по приглашению +connect_lobby %d" % invited_lobby, "Menu")
		SteamService.join_lobby(invited_lobby)


func _process(delta: float) -> void:
	# Автостарт: прогулочный бот (--bot) и самопроверки
	# (--selftest-anim, --selftest-world) входят в мир сами — как в старом меню.
	if not (Session.bot or Session.selftest_anim or Session.selftest_world) \
			or Session.in_world or _menu.section == MainMenuBU.Section.STARTING:
		return
	_auto_wait += delta
	if _auto_wait >= AUTO_ENTER_DELAY:
		Log.info("Автостарт бота/самопроверки: вхожу в мир", "Menu")
		# Через анимацию наезда на рыцаря — тот же путь, что у игрока.
		_menu._start(&"new")


## «Продолжить»/«Новая игра»/глава (П9): сюжетной игры пока нет — старт
## временно ведёт туда же, куда «В мир» старого меню (раздел 11): dev-ENet
## и офлайн — сразу одиночный мир, Steam — быстрый вход в публичный мир,
## мир грузится по steam_world_ready.
func _on_start_requested(_mode: StringName) -> void:
	if _start_goes_direct():
		_enter_world()
	else:
		Log.info("MainMenuBU: «В мир» (Steam)", "Menu")
		SteamService.quick_join_public()


## Dev-ENet мир уже поднят (раздел 10) или Steam нет — локальный мир без сети.
func _start_goes_direct() -> bool:
	return Net.is_networked() or not SteamService.available


func _enter_world() -> void:
	if Session.in_world:
		return
	get_tree().call_deferred("change_scene_to_file", WORLD_SCENE)


# --- Steam-поток входа (раздел 11), как в старом меню ---

## Транспорт мира поднят (хост или клиент): грузим остров.
func _on_steam_world_ready() -> void:
	_enter_world()


## Вход не удался. Строки статуса сети у нового меню нет — возвращаем меню
## из затемнения старта в главный раздел: игрок может повторить или выйти.
func _on_steam_lobby_join_failed(reason: String) -> void:
	Log.info("MainMenuBU: вход не удался (%s) — меню возвращается" % reason, "Menu")
	if _menu.section != MainMenuBU.Section.STARTING:
		return
	var fade: ColorRect = _menu._fade
	_menu.section = MainMenuBU.Section.MAIN
	_menu.open_section(MainMenuBU.Section.MAIN)
	if fade:
		create_tween().tween_property(fade, "color:a", 0.0, 1.0)


## Друг приглашает через оверлей, пока мы в меню (раздел 11). В мире
## приглашение не прерывает игру — уведомления, П7.
func _on_steam_invite(_inviter_id: int, lobby_id: int) -> void:
	if Session.in_world or Net.is_networked() \
			or _menu.section == MainMenuBU.Section.STARTING:
		return
	Log.info("MainMenuBU: приглашение в лобби %d — вхожу" % lobby_id, "Menu")
	SteamService.join_lobby(lobby_id)
