# Тест чистой логики кооп-механик (gameplay/coop/coop_director.gd):
# плиты и ворота — N = min(min_players, игроков, ≤3), запасной таймер 45 с;
# уступ — лестница, когда кто-то наверху, иначе платформа через 45 с;
# падающие платформы — 0,6 с стояния и восстановление через 5 с.
# Без сети и нод: тиками кормим позициями (Vector2.INF — игрока нет).
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")


func _gate(id: int, min_players: int) -> Dictionary:
	return CoopDirector.make_gate(
		id,
		[Rect2(0, 500, 96, 60), Rect2(200, 500, 96, 60), Rect2(400, 500, 96, 60)],
		Rect2(600, 0, 200, 576),
		min_players
	)


func _ledge(id: int) -> Dictionary:
	return CoopDirector.make_ledge(id, Rect2(0, 0, 300, 576), Rect2(300, 0, 400, 300))


func _director(objects: Array, platforms: Array = []) -> CoopDirector:
	var director := CoopDirector.new()
	director.setup(objects, platforms)
	return director


func _has_event(events: Array[Dictionary], type: int) -> bool:
	for event: Dictionary in events:
		if int(event["event"]) == type:
			return true
	return false


# --- Сколько игроков нужно плитам (раздел 7.2) ---

func test_gate_need_formula() -> void:
	var director := CoopDirector.new()
	assert_eq(director.gate_need(2, 4), 2, "min_players меньше игроков")
	assert_eq(director.gate_need(3, 10), 3, "не больше 3 (раздел 7.2)")
	assert_eq(director.gate_need(5, 10), 3, "верхняя граница 3")
	assert_eq(director.gate_need(3, 1), 1, "одиночке хватает одной плиты")
	assert_eq(director.gate_need(3, 2), 2, "двоим нужно 2")


# --- Ворота: плиты ---

func test_gate_opens_with_distinct_players() -> void:
	var director := _director([_gate(0, 3)])
	var events := director.tick(0.1, {1: Vector2(40, 540), 2: Vector2(240, 540), 3: Vector2(440, 540)})
	assert_true(_has_event(events, CoopDirector.Event.GATE_OPEN))
	assert_eq(events[0]["participants"], [1, 2, 3])


func test_gate_two_on_one_plate_not_enough() -> void:
	# Двое на одной плите считаются за одного: need = 3 при трёх игроках.
	var director := _director([_gate(0, 3)])
	var events := director.tick(0.1, {1: Vector2(40, 540), 2: Vector2(45, 540), 3: Vector2(900, 540)})
	assert_false(_has_event(events, CoopDirector.Event.GATE_OPEN))


func test_gate_solo_opens_alone() -> void:
	var director := _director([_gate(0, 3)])
	var events := director.tick(0.1, {1: Vector2(40, 540)})
	assert_true(_has_event(events, CoopDirector.Event.GATE_OPEN))


func test_gate_opens_once_forever() -> void:
	var director := _director([_gate(0, 2)])
	director.tick(0.1, {1: Vector2(40, 540), 2: Vector2(240, 540)})
	var again := director.tick(0.1, {1: Vector2(40, 540), 2: Vector2(240, 540)})
	assert_false(_has_event(again, CoopDirector.Event.GATE_OPEN), "открытие навсегда")


# --- Ворота: запасной таймер 45 с ---

func test_gate_fallback_after_45s() -> void:
	var director := _director([_gate(0, 3)])
	var events: Array[Dictionary] = []
	for i: int in 45:
		events = director.tick(1.0, {1: Vector2(700, 540)})  # стоит у ворот
	assert_true(_has_event(events, CoopDirector.Event.GATE_OPEN))
	assert_eq(events[0]["participants"], [], "запасное открытие — без участников")


func test_gate_fallback_accumulates_only_when_present() -> void:
	var director := _director([_gate(0, 3)])
	var events: Array[Dictionary] = []
	for i: int in 30:
		events = director.tick(1.0, {1: Vector2(700, 540)})  # 30 с у ворот
	for i: int in 10:
		events = director.tick(1.0, {1: Vector2.INF})        # ушёл — тишина
	assert_false(_has_event(events, CoopDirector.Event.GATE_OPEN), "таймер стоит без игроков")
	for i: int in 14:
		events = director.tick(1.0, {1: Vector2(700, 540)})
	assert_false(_has_event(events, CoopDirector.Event.GATE_OPEN), "44 с присутствия — ещё закрыто")
	events = director.tick(1.0, {1: Vector2(700, 540)})
	assert_true(_has_event(events, CoopDirector.Event.GATE_OPEN), "45-я секунда у ворот")


# --- Уступ: лестница и запасная платформа ---

func test_ladder_drops_when_someone_on_top() -> void:
	var director := _director([_ledge(0)])
	var events := director.tick(0.1, {1: Vector2(500, 200)})  # кто-то наверху
	assert_true(_has_event(events, CoopDirector.Event.LADDER_DROP))


func test_ledge_fallback_platform_after_45s() -> void:
	var director := _director([_ledge(0)])
	var events: Array[Dictionary] = []
	for i: int in 45:
		events = director.tick(1.0, {1: Vector2(100, 540)})  # стоит у стены
	assert_true(_has_event(events, CoopDirector.Event.LEDGE_PLATFORM))


func test_ledge_no_platform_after_ladder() -> void:
	# Лестница опущена (кто-то наверху) — запасная платформа не нужна.
	var director := _director([_ledge(0)])
	director.tick(0.1, {1: Vector2(500, 200)})
	var events: Array[Dictionary] = []
	for i: int in 100:
		events = director.tick(1.0, {1: Vector2(100, 540)})
	assert_false(_has_event(events, CoopDirector.Event.LEDGE_PLATFORM))


# --- Падающие платформы (раздел 6) ---

func _platform_zone() -> Dictionary:
	return {"id": 5, "zone": Rect2(200, 480, 100, 24)}


func test_platform_falls_after_delay() -> void:
	var director := _director([], [_platform_zone()])
	var events: Array[Dictionary] = []
	for i: int in 6:
		events = director.tick(0.1, {1: Vector2(250, 495)})  # 0,6 с стояния
	assert_true(_has_event(events, CoopDirector.Event.PLATFORM_FALL), "падает через 0,6 с")


func test_platform_restores_after_5s() -> void:
	var director := _director([], [_platform_zone()])
	for i: int in 6:
		director.tick(0.1, {1: Vector2(250, 495)})  # упала
	var events: Array[Dictionary] = []
	for i: int in 50:
		events = director.tick(0.1, {1: Vector2(900, 495)})  # сошёл: 5,0 с — на границе
	assert_false(_has_event(events, CoopDirector.Event.PLATFORM_RESTORE), "ровно 5 с — ещё падшая")
	events = director.tick(0.1, {1: Vector2(900, 495)})  # чуть больше 5 с
	assert_true(_has_event(events, CoopDirector.Event.PLATFORM_RESTORE), "возвращается после 5 с")


func test_platform_resets_when_player_leaves() -> void:
	var director := _director([], [_platform_zone()])
	for i: int in 3:
		director.tick(0.1, {1: Vector2(250, 495)})  # 0,3 с — половина
	var events := director.tick(0.1, {1: Vector2(900, 495)})  # сошёл: задержка сброшена
	assert_false(_has_event(events, CoopDirector.Event.PLATFORM_FALL))
	for i: int in 5:
		events = director.tick(0.1, {1: Vector2(250, 495)})  # ещё 0,5 с
	assert_false(_has_event(events, CoopDirector.Event.PLATFORM_FALL), "0,5 с после сброса — не падает")
	events = director.tick(0.1, {1: Vector2(250, 495)})
	assert_true(_has_event(events, CoopDirector.Event.PLATFORM_FALL))
