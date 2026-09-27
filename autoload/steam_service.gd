# Единственная точка обращения к GodotSteam: инициализация Steam, SteamID,
# persona name и аватар игрока. Остальной код работает только с сигналами и
# методами этого сервиса (правило проекта).
# Не делает на этапе 0: лобби, друзья, инвайты, Rich Presence, голос (этапы 4–5).
# Без Steam-клиента и при dev-аргументах (--dev-host/--dev-join) сразу сообщает
# о неудаче — игра продолжает работу в офлайн-режиме ENet.
#
# Имена API сверены с установленной сборкой GodotSteam 4.22.1 (GDExtension):
# steamInitEx(app_id: int, embed_callbacks: bool) -> Dictionary{status: int, verbal: String},
# status == 0 — успех; getSteamID() -> int; getPersonaName() -> String.
extends Node

## Тестовый App ID 480 (Spacewar) — общий для всех разработчиков, поэтому
## лобби обязательно фильтруются по тегу игры (раздел 2 SPEC).
const DEV_APP_ID: int = 480

## Steam инициализирован, можно работать.
signal steam_ready
## Steam недоступен: reason поясняет, почему (нет клиента, dev-режим, ошибка init).
signal steam_failed(reason: String)

var available: bool = false
var steam_id: int = 0
var persona_name: String = ""


func _ready() -> void:
	if Dev.host_mode or Dev.join_address != "":
		_fail("режим разработки ENet (--dev-host/--dev-join): Steam не используется")
		return
	if not ClassDB.class_exists("Steam"):
		_fail("модуль GodotSteam не загружен")
		return
	# embed_callbacks = true: GodotSteam сам обрабатывает колбэки Steam каждый кадр.
	var init_result: Dictionary = Steam.steamInitEx(DEV_APP_ID, true)
	var status: int = int(init_result.get("status", -1))
	if status != 0:
		_fail("steamInitEx не удался (status=%d): %s" % [status, str(init_result.get("verbal", "причина неизвестна"))])
		return
	available = true
	steam_id = Steam.getSteamID()
	persona_name = Steam.getPersonaName()
	Log.info("Steam инициализирован: id=%s, имя=%s" % [str(steam_id), persona_name], "Steam")
	steam_ready.emit()


func _fail(reason: String) -> void:
	available = false
	Log.warn("Steam недоступен: %s" % reason, "Steam")
	steam_failed.emit(reason)
