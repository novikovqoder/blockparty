# Веха задания Финна «Короткая тропа» (П5.5). Точки фиксированы
# относительно зон (QuestLayout, seed мира): Площадь → мосток → за краем
# Расщелины → ворота руин. До установки — светящееся кольцо-точка на земле
# и невысокий шест; удержание E 1 с ставит флажок. Тропа-лента между
# вехами проявляется финалом задания (до конца сессии, отдельный узел).
class_name TrailFlag
extends Interactable

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")

## Группа вех (хост валидирует дистанцию по узлам группы).
const FLAG_GROUP: StringName = &"quest_flag"

## Какому заданию принадлежит и номер вехи (шаг задания).
@export var quest_id: String = Protocol.QUEST_FINN
@export var index: int = 0

var _active: bool = false
var _planted: bool = false
var _ring: MeshInstance3D
var _pole: MeshInstance3D
var _flag: MeshInstance3D


func _ready() -> void:
	super()
	add_to_group(FLAG_GROUP)
	EventBus.quest_state.connect(_on_quest_state)
	_build_visual()
	_apply_state()


## «E — поставить веху»: пока задание идёт и веха не стоит.
func hint_key() -> String:
	return "" if (_planted or not _active) else "HINT_FLAG"


## Удержание E 1 с (ТЗ П5.5).
func hold_time(_player: Node3D) -> float:
	return B.quest_flag_hold


func use(_player: Node3D) -> void:
	Net.request_quest_action(quest_id, Protocol.QUEST_KIND_FLAG, index)


## Применить состояние заданий от хоста.
func _on_quest_state(state: Dictionary) -> void:
	var quest: Variant = state.get(quest_id)
	if quest is Dictionary:
		_active = int(quest["stage"]) == QuestAuthority.ACTIVE
		var steps: Array = quest["steps"]
		if index >= 0 and index < steps.size():
			_planted = int(steps[index]) != 0
	_apply_state()


func _apply_state() -> void:
	visible = _active
	_flag.visible = _planted
	_pole.visible = _active
	var ring_mat := _ring.material_override as StandardMaterial3D
	ring_mat.emission_energy_multiplier = 1.2 if _planted else 0.7


## Кольцо-точка на земле, шест и флажок (появляется после установки).
func _build_visual() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.62
	_ring.mesh = torus
	_ring.position = Vector3(0.0, 0.05, 0.0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = PAL.beacon_glow
	ring_mat.emission_enabled = true
	ring_mat.emission = PAL.beacon_glow
	ring_mat.emission_energy_multiplier = 0.7
	_ring.material_override = ring_mat
	add_child(_ring)

	_pole = MeshInstance3D.new()
	_pole.name = "Pole"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.035
	cyl.height = 1.5
	_pole.mesh = cyl
	_pole.position = Vector3(0.0, 0.75, 0.0)
	_pole.material_override = _mat(PAL.zone_stone[2].lightened(0.3))
	add_child(_pole)

	_flag = MeshInstance3D.new()
	_flag.name = "Flag"
	var prism := PrismMesh.new()
	prism.size = Vector3(0.45, 0.3, 0.02)
	_flag.mesh = prism
	_flag.position = Vector3(0.235, 1.3, 0.0)
	_flag.material_override = _mat(PAL.beacon_glow, true)
	add_child(_flag)


func _mat(color: Color, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.8
	return material
