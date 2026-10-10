# Авторитет хоста для заданий жителей (П5.5): стадия каждого задания,
# прогресс шагов и участники. Чистая логика без узлов — как
# ActivityAuthority: позиции хост передаёт параметрами, состояние ходит
# в world_state ("quests") и rpc_quest_state. Участник — игрок, сделавший
# хотя бы одно действие задания или находящийся в радиусе финала
# в момент завершения; награду получает каждый участник. После выполнения
# задание снова доступно со следующего игрового дня.
class_name QuestAuthority
extends RefCounted

## Стадии задания.
const AVAILABLE: int = 0
const ACTIVE: int = 1
const DONE: int = 2

## Число шагов каждого задания: 5 пучков мяты, 3 маяка, 4 вехи (ТЗ П5.5).
const THYME_STEPS: int = 5
const LUMI_STEPS: int = 3
const FINN_STEPS: int = 4

## id -> {stage: int, done_day: int, steps: Array[int], peers: Array}.
var _quests: Dictionary = {}


func _init() -> void:
	clear()


## Полный сброс (новый мир): вызывается вместе с activity.clear().
func clear() -> void:
	_quests = {
		Protocol.QUEST_THYME: _new_quest(THYME_STEPS),
		Protocol.QUEST_LUMI: _new_quest(LUMI_STEPS),
		Protocol.QUEST_FINN: _new_quest(FINN_STEPS),
	}


func _new_quest(step_count: int) -> Dictionary:
	var steps: Array[int] = []
	steps.resize(step_count)
	steps.fill(0)
	return {"stage": AVAILABLE, "done_day": -1, "steps": steps, "peers": []}


## Взять задание (кнопка «Помогу» в диалоге жителя): только доступное,
## берущий — первый участник. Лениво закрывает вчерашние выполнения
## (rollover), если тик смены дня ещё не дошёл. true — задание стало ACTIVE.
func take(id: String, peer: int, day_index: int) -> bool:
	var quest := _quest(id)
	if quest.is_empty() or peer == 0:
		return false
	_rollover_one(quest, day_index)
	if int(quest["stage"]) != AVAILABLE:
		return false
	quest["stage"] = ACTIVE
	_join(quest, peer)
	return true


## Шаг задания (мята/маяк/веха): только идущее, шаг ещё не сделан.
## Сделавший становится участником. true — шаг зачтён.
func do_step(id: String, index: int, peer: int) -> bool:
	var quest := _quest(id)
	if quest.is_empty() or int(quest["stage"]) != ACTIVE or peer == 0:
		return false
	var steps: Array = quest["steps"]
	if index < 0 or index >= steps.size() or int(steps[index]) != 0:
		return false
	steps[index] = 1
	_join(quest, peer)
	return true


## Все ли шаги сделаны (готовность финала).
func steps_done(id: String) -> bool:
	var quest := _quest(id)
	if quest.is_empty():
		return false
	for value: int in quest["steps"]:
		if value == 0:
			return false
	return true


## Финал: DONE с сегодняшним днём; участники — накопленные peers плюс все
## из extra_peers (радиус финала, раздел «Общие правила»). Возвращает
## {"peers": Array[int], "day": int} или {} — не идёт / шаги не готовы.
func finish(id: String, day_index: int, extra_peers: Array[int]) -> Dictionary:
	var quest := _quest(id)
	if quest.is_empty() or int(quest["stage"]) != ACTIVE or not steps_done(id):
		return {}
	quest["stage"] = DONE
	quest["done_day"] = day_index
	for peer: int in extra_peers:
		_join(quest, peer)
	return {"peers": (quest["peers"] as Array).duplicate(), "day": day_index}


## Выполнено ли в этот же игровой день (льгота ворот Финна: соло-таймер
## 20 с действует в день выполнения).
func done_today(id: String, day_index: int) -> bool:
	var quest := _quest(id)
	return not quest.is_empty() and int(quest["stage"]) == DONE \
		and int(quest["done_day"]) == day_index


## Смена дня (тик хоста): выполненное вчера и раньше снова доступно.
## true — хотя бы одно задание открылось (нужно разослать состояние).
func day_rollover(day_index: int) -> bool:
	var changed := false
	for quest: Dictionary in _quests.values():
		changed = _rollover_one(quest, day_index) or changed
	return changed


func _rollover_one(quest: Dictionary, day_index: int) -> bool:
	if int(quest["stage"]) == DONE and day_index > int(quest["done_day"]):
		quest["stage"] = AVAILABLE
		quest["done_day"] = -1
		(quest["steps"] as Array[int]).fill(0)
		(quest["peers"] as Array).clear()
		return true
	return false


## Награда Тимьяна: 10 каждому + 2 за каждого ДРУГОГО сидящего у костра
## (до +10). Сидящий получает бонус за остальных сидящих, несидящий
## участник — за всех сидящих: так «+2 за каждого другого» честно для всех.
static func thyme_reward(seated_others: int, b: Balance) -> int:
	return b.quest_reward_base + mini(
		b.quest_thyme_bonus_max, seated_others * b.quest_thyme_bonus_per_other
	)


## Стадия задания; неизвестный id трактуется как DONE (значок скрыт,
## диалог благодарит — мир без этого задания).
func stage(id: String) -> int:
	var quest := _quest(id)
	return DONE if quest.is_empty() else int(quest["stage"])


func is_active(id: String) -> bool:
	return stage(id) == ACTIVE


## Прогресс: сколько шагов сделано и сколько всего (HUD-трекер и реплика
## диалога).
func step_progress(id: String) -> Vector2i:
	var quest := _quest(id)
	if quest.is_empty():
		return Vector2i.ZERO
	var done := 0
	for value: int in quest["steps"]:
		done += value
	return Vector2i(done, (quest["steps"] as Array[int]).size())


## Копия состояния для world_state и rpc_quest_state (глубокая — никто
## не мутирует рассылаемое).
func state() -> Dictionary:
	var copy: Dictionary = {}
	for id: String in _quests:
		var quest: Dictionary = _quests[id]
		copy[id] = {
			"stage": int(quest["stage"]),
			"done_day": int(quest["done_day"]),
			"steps": (quest["steps"] as Array[int]).duplicate(),
			"peers": (quest["peers"] as Array).duplicate(),
		}
	return copy


func _quest(id: String) -> Dictionary:
	var quest: Variant = _quests.get(id)
	return quest if quest is Dictionary else {}


func _join(quest: Dictionary, peer: int) -> void:
	if peer == 0:
		return
	var peers: Array = quest["peers"]
	if not peers.has(peer):
		peers.append(peer)
