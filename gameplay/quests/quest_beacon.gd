# Квестовый маяк задания Луми «Зажги маяки» (П5.5). Два стоят у подножия
# существующих башен мирового события (Холмы и Озеро — объекты
# переиспользуются, новых башен нет), третий — на смотровой площадке
# (та, что требует подсадки; соло-пути уже существуют). Зажигание —
# удержание E 2 с; если рядом стоит второй игрок — вдвое быстрее
# (допущение: «рядом» = в quest_hold_helper_radius). Зажжённые лампы
# квеста не влияют на мировой цикл маяков.
class_name QuestBeacon
extends Interactable

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")

## Группа квестовых маяков (хост валидирует дистанцию по узлам группы).
const QBEACON_GROUP: StringName = &"quest_beacon"

## Какому заданию принадлежит и номер маяка (шаг задания).
@export var quest_id: String = Protocol.QUEST_LUMI
@export var index: int = 0

var _active: bool = false
var _lit: bool = false
var _lamp: MeshInstance3D
var _light: OmniLight3D


func _ready() -> void:
	super()
	add_to_group(QBEACON_GROUP)
	EventBus.quest_state.connect(_on_quest_state)
	_build_visual()
	_apply_state()


## «E — зажечь маяк»: пока задание идёт и маяк не горит.
func hint_key() -> String:
	return "" if (_lit or not _active) else "HINT_BEACON"


## Удержание 2 с; второй игрок рядом (quest_hold_helper_radius) ускоряет
## вдвое — как «держат двое».
func hold_time(player: Node3D) -> float:
	if not _helper_near(player):
		return B.quest_beacon_hold
	return B.quest_beacon_hold * 0.5


func use(_player: Node3D) -> void:
	Net.request_quest_action(quest_id, Protocol.QUEST_KIND_BEACON, index)


## Применить состояние заданий от хоста.
func _on_quest_state(state: Dictionary) -> void:
	var quest: Variant = state.get(quest_id)
	if quest is Dictionary:
		_active = int(quest["stage"]) == QuestAuthority.ACTIVE
		var steps: Array = quest["steps"]
		if index >= 0 and index < steps.size():
			_lit = int(steps[index]) != 0
	_apply_state()


func _apply_state() -> void:
	visible = _active
	_light.visible = _lit
	var material := _lamp.material_override as StandardMaterial3D
	material.emission_enabled = _lit
	material.albedo_color = PAL.beacon_glow if _lit \
		else PAL.beacon_glow.darkened(0.45)


## Кто-то из игроков (кроме держащего) в радиусе помощи.
func _helper_near(player: Node3D) -> bool:
	for group: StringName in [Player.GROUP, RemotePlayer.GROUP]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body == null or body == player:
				continue
			if body.global_position.distance_to(global_position) \
					<= B.quest_hold_helper_radius:
				return true
	return false


## Малый столб с лампой — у подножия большой башни или на площадке.
func _build_visual() -> void:
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.13
	cyl.height = 1.3
	pole.mesh = cyl
	pole.position = Vector3(0.0, 0.65, 0.0)
	pole.material_override = _mat(PAL.zone_stone[3].darkened(0.1))
	add_child(pole)

	_lamp = MeshInstance3D.new()
	_lamp.name = "Lamp"
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	_lamp.mesh = sphere
	_lamp.position = Vector3(0.0, 1.4, 0.0)
	_lamp.material_override = _mat(PAL.beacon_glow.darkened(0.45))
	add_child(_lamp)

	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.position = Vector3(0.0, 1.4, 0.0)
	_light.omni_range = 6.0
	_light.light_color = PAL.beacon_glow
	_light.light_energy = 1.1
	add_child(_light)


func _mat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
