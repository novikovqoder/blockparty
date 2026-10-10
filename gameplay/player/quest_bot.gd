# Автопрогон задания жителя для e2e-проверки сети (П5.5, --quest-bot):
# одна копия поднимает мир (--dev-host), вторая подключается (--dev-join);
# обе с --quest-bot. Клиент-«лидер» телепортом ходит по шагам «Вечернего
# чая»: берёт у Тимьяна, собирает пять пучков мяты, садится у костра —
# задание выполняется и награда уходит каждому участнику. Хост-«помощник»
# просто телепортируется к костру и стоит в радиусе финала: оба игрока
# получают монеты, e2e-скрипт (tools/quest_e2e.sh) сверяет логи обеих
# копий. Телепорт вместо ходьбы — проверяется сетевой путь заданий
# (rpc взятия/шагов/финала и world_state), а не движение (его гоняет
# --bot); позиции подтверждает хост по снапшотам, как у людей.
class_name QuestBot
extends Node

## Пауза после телепорта до запроса: снапшоты 20 Гц — хост должен увидеть
# позицию у узла (не меньше трёх снапшотов).
const SETTLE: float = 0.6
## Повтор запроса, если шаг не зачли (потеря/гонка), с.
const RETRY: float = 1.5
## Максимум повторов одного шага — дальше прогон признаётся застрявшим.
const MAX_ATTEMPTS: int = 6

## Фазы прогона.
enum {
	WAIT_WORLD,  # ждём входа в мир и узлов острова
	GO_TAKE,     # телепорт к Тимьяну
	WAIT_TAKE,   # запросили взятие — ждём ACTIVE
	GO_MINT,     # телепорт к пучку мяты
	WAIT_MINT,   # запросили подбор — ждём шаг в state
	GO_SEAT,     # телепорт к лавке
	WAIT_SEAT,   # сели — ждём финал (DONE)
	GO_CAMP,     # помощник: телепорт к костру и стояние в радиусе финала
	DONE,
}

var _player: Player = null
var _phase: int = WAIT_WORLD
var _state: Dictionary = {}
var _mint_index: int = 0
var _settle_left: float = 0.0
var _retry_left: float = 0.0
var _attempts: int = 0


func setup(player: Player) -> void:
	_player = player


func _ready() -> void:
	EventBus.quest_state.connect(_on_quest_state)


func _on_quest_state(state: Dictionary) -> void:
	_state = state


func _physics_process(delta: float) -> void:
	if _player == null or not Session.in_world:
		return
	match _phase:
		WAIT_WORLD:
			_wait_world()
		GO_TAKE, GO_MINT, GO_SEAT, GO_CAMP:
			_settle_left -= delta
			if _settle_left > 0.0:
				return
			_arrive()
		WAIT_TAKE, WAIT_MINT, WAIT_SEAT:
			_wait_confirm(delta)


## Мир готов: узлы заданий построены. Хост — помощник у костра, клиент —
# лидер, проходящий задание.
func _wait_world() -> void:
	if get_tree().get_nodes_in_group(Townsfolk.TOWNSFOLK_GROUP).is_empty():
		return
	if Net.is_host():
		Log.info("Автопрогон: помощник идёт к костру (радиус финала)", "QuestBot")
		_go_to(_camp_pos(), GO_CAMP)
		return
	Log.info("Автопрогон: лидер идёт брать «Вечерний чай»", "QuestBot")
	var folk := _townsfolk()
	if folk == null:
		return
	_go_to(folk.global_position + Vector3(1.1, 0.3, 0.0), GO_TAKE)


## Телепорт состоялся (выдержана пауза SETTLE): действие фазы.
func _arrive() -> void:
	match _phase:
		GO_TAKE:
			Log.info("Автопрогон: прошу задание у Тимьяна", "QuestBot")
			Net.request_quest_take(Protocol.QUEST_THYME)
			_confirm(WAIT_TAKE)
		GO_MINT:
			Log.info(
				"Автопрогон: подбираю мяту %d/5" % (_mint_index + 1), "QuestBot"
			)
			Net.request_quest_action(
				Protocol.QUEST_THYME, Protocol.QUEST_KIND_MINT, _mint_index
			)
			_confirm(WAIT_MINT)
		GO_SEAT:
			var seat := _free_seat()
			if seat == null:
				# Все места заняты: финал Тимьяна зачтёт и стоящих у костра.
				Log.info("Автопрогон: мест нет — стою у костра", "QuestBot")
				_phase = DONE
				return
			Log.info("Автопрогон: сажусь у костра (место %d)" % (seat.seat_index + 1), "QuestBot")
			Net.request_sit(seat.seat_index)
			_confirm(WAIT_SEAT)
		GO_CAMP:
			# Помощник просто стоит у костра до конца прогона.
			_phase = DONE


## Ждём подтверждения от хоста (изменение quest_state); таймаут — повтор.
func _wait_confirm(delta: float) -> void:
	var quest: Dictionary = _state.get(Protocol.QUEST_THYME, {})
	var stage: int = int(quest.get("stage", -1))
	var steps: Array = quest.get("steps", [])
	match _phase:
		WAIT_TAKE:
			if stage == QuestAuthority.ACTIVE:
				Log.info("Автопрогон: задание взято, иду за мятой", "QuestBot")
				_next_mint(steps)
				return
			if stage == QuestAuthority.AVAILABLE:
				_retry(delta, func() -> void: Net.request_quest_take(Protocol.QUEST_THYME))
		WAIT_MINT:
			if _mint_index < steps.size() and int(steps[_mint_index]) == 1:
				_attempts = 0
				_next_mint(steps)
				return
			_retry(delta, func() -> void: Net.request_quest_action(
				Protocol.QUEST_THYME, Protocol.QUEST_KIND_MINT, _mint_index
			))
		WAIT_SEAT:
			if stage == QuestAuthority.DONE:
				Log.info("Автопрогон: задание выполнено", "QuestBot")
				_phase = DONE
		_:
			_phase = DONE


## К следующему несобранному пучку; все собраны — к костру.
func _next_mint(steps: Array) -> void:
	for i: int in steps.size():
		if int(steps[i]) == 0:
			_mint_index = i
			var mint := _mint_node(i)
			if mint == null:
				continue
			_go_to(mint.global_position + Vector3(0.6, 0.3, 0.0), GO_MINT)
			return
	_go_to(_seat_pos(), GO_SEAT)


## Повтор действия, если хост не подтвердил за RETRY; после MAX_ATTEMPTS
# прогон останавливается (e2e-скрипт увидит отсутствие финала в логах).
func _retry(delta: float, action: Callable) -> void:
	_retry_left -= delta
	if _retry_left > 0.0:
		return
	_attempts += 1
	if _attempts > MAX_ATTEMPTS:
		Log.warn(
			"Автопрогон: шаг не подтверждается — остановка (попыток %d)"
			% _attempts, "QuestBot"
		)
		_phase = DONE
		return
	Log.warn("Автопрогон: нет подтверждения, повтор (попытка %d)" % _attempts, "QuestBot")
	action.call()
	_retry_left = RETRY


## Телепорт и переход в фазу ожидания SETTLE.
func _go_to(pos: Vector3, phase: int) -> void:
	_player.global_position = pos
	_settle_left = SETTLE
	_phase = phase


func _confirm(phase: int) -> void:
	_retry_left = RETRY
	_attempts = 0
	_phase = phase


func _townsfolk() -> Townsfolk:
	for node in get_tree().get_nodes_in_group(Townsfolk.TOWNSFOLK_GROUP):
		var folk := node as Townsfolk
		if folk != null and folk.quest_id == Protocol.QUEST_THYME:
			return folk
	return null


func _mint_node(index: int) -> MintPatch:
	for node in get_tree().get_nodes_in_group(MintPatch.MINT_GROUP):
		var mint := node as MintPatch
		if mint != null and mint.index == index:
			return mint
	return null


func _free_seat() -> CampfireSeat:
	var best: CampfireSeat = null
	for node in get_tree().get_nodes_in_group(CampfireSeat.SEAT_GROUP):
		var seat := node as CampfireSeat
		if seat == null or seat.hint_key() == "":
			continue  # занятые молчат
		if best == null or seat.seat_index < best.seat_index:
			best = seat
	return best


func _seat_pos() -> Vector3:
	var seat := _free_seat()
	if seat != null:
		return seat.global_position + Vector3(0.0, 0.3, 0.0)
	return _camp_pos()


## Точка помощника: в паре метров от костра — внутри quest_campfire_radius
## финала, но не на самом огне.
func _camp_pos() -> Vector3:
	return QuestLayout.CAMPFIRE + Vector3(2.6, 0.5, 0.0)
