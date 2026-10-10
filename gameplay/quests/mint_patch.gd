# Пучок мяты для задания Тимьяна «Вечерний чай» (П5.5). Позиции
# детерминированы (QuestLayout, seed мира): на земле в Лесу, не в предметах.
# Слегка светится, чтобы находиться в тумане. Виден только пока задание
# идёт; подобрал любой участник — засчитано всем (шаг общий). Подтверждает
# хост (QuestAuthority), узел шлёт запрос и рисует результат.
class_name MintPatch
extends Interactable

const PAL: Palette = preload("res://assets/palette.tres")

## Группа пучков мяты (хост валидирует дистанцию по узлам группы).
const MINT_GROUP: StringName = &"quest_mint"
## Коллизия пучка (баг vfx-fix): низкий цилиндр по габариту стеблей.
const MINT_RADIUS: float = 0.28
const MINT_HEIGHT: float = 0.5

var _body: StaticBody3D

## Какому заданию принадлежит (id Protocol) и номер пучка (шаг задания).
@export var quest_id: String = Protocol.QUEST_THYME
@export var index: int = 0

var _active: bool = false
var _taken: bool = false


func _ready() -> void:
	super()
	add_to_group(MINT_GROUP)
	EventBus.quest_state.connect(_on_quest_state)
	_build_visual()
	_apply_visibility()


## «E — собрать мяту»: пока задание идёт и пучок не собран.
func hint_key() -> String:
	return "" if (_taken or not _active) else "HINT_MINT"


func use(_player: Node3D) -> void:
	Net.request_quest_action(quest_id, Protocol.QUEST_KIND_MINT, index)


## Применить состояние заданий от хоста.
func _on_quest_state(state: Dictionary) -> void:
	var quest: Variant = state.get(quest_id)
	if quest is Dictionary:
		_active = int(quest["stage"]) == QuestAuthority.ACTIVE
		var steps: Array = quest["steps"]
		if index >= 0 and index < steps.size():
			_taken = int(steps[index]) != 0
	_apply_visibility()


func _apply_visibility() -> void:
	visible = _active and not _taken
	# Коллизия живёт вместе с видимостью: собранная/несуществующая мята
	# не остаётся невидимым препятствием.
	SolidBody.set_enabled(_body, visible)


## Три стебля с листовыми верхушками; верхушки со слабым свечением
## (мята «светится в тумане»). Модели — примитивы, заменить сценой позже.
func _build_visual() -> void:
	var solid := CylinderShape3D.new()
	solid.radius = MINT_RADIUS
	solid.height = MINT_HEIGHT
	_body = SolidBody.add(self, solid, Vector3(0.0, MINT_HEIGHT * 0.5, 0.0))
	var stem_color: Color = PAL.zone_leaf[1].darkened(0.2)
	var leaf_color: Color = PAL.zone_leaf[1].lightened(0.25)
	for i: int in 3:
		var stem := MeshInstance3D.new()
		stem.name = "Stem%d" % (i + 1)
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.03
		cyl.bottom_radius = 0.045
		cyl.height = 0.5
		stem.mesh = cyl
		stem.material_override = _mat(stem_color, false)
		var angle := TAU * float(i) / 3.0 + 0.4
		stem.position = Vector3(cos(angle) * 0.12, 0.25, sin(angle) * 0.12)
		stem.rotation_degrees = Vector3(sin(angle) * 8.0, 0.0, -cos(angle) * 8.0)
		add_child(stem)

		var top := MeshInstance3D.new()
		top.name = "Top%d" % (i + 1)
		var sphere := SphereMesh.new()
		sphere.radius = 0.09
		sphere.height = 0.16
		top.mesh = sphere
		top.material_override = _mat(leaf_color, true)
		top.position = stem.position + Vector3(0.0, 0.26, 0.0)
		add_child(top)


func _mat(color: Color, glow: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.6
	return material
