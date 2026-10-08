# Нажимная плита у ворот руин (раздел 9.2 SPEC): состояние «занята»
# считает хост по снапшотам позиций (кто стоит в plate_radius), узел
# только рисует проседание и подсветку. Порядок плит — по имени узла
# (Plate1..Plate3, генерирует tools/generate_island.gd).
class_name RuinPlate
extends Node3D

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")

## Группа узлов плит (хост собирает позиции по порядку имени).
const GROUP: StringName = &"ruin_plate"

## Плита: плоский камень над землёй, м.
const PLATE_SIZE: Vector3 = Vector3(1.5, 0.16, 1.5)
## Проседание нажатой плиты, м.
const PRESS_DROP: float = 0.05
## Длительность хода плиты, с.
const MOVE_TIME: float = 0.15

var _top: MeshInstance3D
var _material: StandardMaterial3D
var _pressed: bool = false
## Индекс плиты в порядке имени (Plate1..Plate3) — как сортирует хост.
var _index: int = 0


func _ready() -> void:
	add_to_group(GROUP)
	_index = _compute_index()
	EventBus.ruins_state.connect(_on_ruins_state)
	_build_plate()


func _on_ruins_state(_open: bool, plates: Array, _openers: Array, _reward: Array) -> void:
	if _index < plates.size():
		set_pressed(int(plates[_index]) != 0)


## Позиция среди плит группы в порядке имени (тот же порядок у хоста).
func _compute_index() -> int:
	var siblings: Array = []
	for node in get_tree().get_nodes_in_group(GROUP):
		if node is RuinPlate:
			siblings.append(node)
	siblings.sort_custom(
		func(a: RuinPlate, b: RuinPlate) -> bool:
			return (a as Node).name.naturalcasecmp_to((b as Node).name) < 0
	)
	return siblings.find(self)


## Применить состояние от хоста: плита просела и светится слабым
## золотым, пока на ней кто-то стоит.
func set_pressed(pressed: bool) -> void:
	if pressed == _pressed:
		return
	_pressed = pressed
	var tween := create_tween()
	tween.tween_property(_top, "position:y", -PRESS_DROP if pressed else 0.0, MOVE_TIME)
	_material.emission_enabled = pressed
	if pressed:
		_material.emission = PAL.firefly
		_material.emission_energy_multiplier = 0.7


## Плита на невысоком постаменте (коллизии не нужна — она ниже шага).
func _build_plate() -> void:
	var base := MeshInstance3D.new()
	base.name = "Base"
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(PLATE_SIZE.x + 0.2, 0.1, PLATE_SIZE.z + 0.2)
	base.mesh = base_mesh
	var base_material := StandardMaterial3D.new()
	base_material.albedo_color = PAL.ruin_dark.darkened(0.1)
	base.material_override = base_material
	base.position = Vector3(0.0, 0.05, 0.0)
	add_child(base)

	_top = MeshInstance3D.new()
	_top.name = "Top"
	var mesh := BoxMesh.new()
	mesh.size = PLATE_SIZE
	_top.mesh = mesh
	_material = StandardMaterial3D.new()
	_material.albedo_color = PAL.ruin_brick
	_top.material_override = _material
	_top.position = Vector3(0.0, 0.1 + PLATE_SIZE.y * 0.5, 0.0)
	add_child(_top)
