# Место у костра (раздел 9.6 SPEC): невидимый маркер на лавке площади —
# лавки рисует генератор острова (предметы «bench»), узел даёт подсказку
# «E — сесть» и шлёт запрос хосту. Занятость приходит событием campfire_seats:
# свободное место чужому игроку не предлагается. Встают любым движением
# (клиент игрока), хост только подтверждает занятость.
class_name CampfireSeat
extends Interactable

## Группа узлов мест (Net собирает их по порядку имён Seat1..Seat8).
const SEAT_GROUP: StringName = &"campfire_seat"

## Точка, куда смотрит сидящий (центр костра) — задаёт генератор острова.
@export var face_target: Vector3 = Vector3.ZERO

var seat_index: int = 0
var _occupied_by: int = 0


func _ready() -> void:
	super()
	add_to_group(SEAT_GROUP)
	EventBus.campfire_seats.connect(_on_campfire_seats)


## Подсказка «E — сесть»: только у свободного места (занятое молчит).
func hint_key() -> String:
	return "" if _occupied_by != 0 else "HINT_SIT"


func use(_player: Node3D) -> void:
	Net.request_sit(seat_index)


## Занятость мест от хоста (раздел 9.6): индекс узла — порядок имени.
func _on_campfire_seats(seats: Array) -> void:
	if seat_index >= 0 and seat_index < seats.size():
		_occupied_by = int(seats[seat_index])
