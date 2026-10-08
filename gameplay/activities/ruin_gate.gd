# Ворота руин (раздел 9.2 SPEC): плита-решётка в проёме каменной рамы
# (рама — проп ruin_gate в island_art). Открытие/закрытие подтверждает
# хост (ActivityAuthority по снапшотам плит), узел только рисует: плита
# опускается в пол террасы, коллизия гаснет. Дети island.tscn (руины).
class_name RuinGate
extends Node3D

const PAL: Palette = preload("res://assets/palette.tres")

## Группа узлов ворот (хост берёт позицию зоны «у ворот»).
const GROUP: StringName = &"ruin_gate"

## Плита: ширина проёма с запасом, высота до перекладины рамы, м.
const PANEL_SIZE: Vector3 = Vector3(3.1, 2.95, 0.34)
## Глубина опускания в пол террасы, м (плита уходит целиком).
const OPEN_DROP: float = 2.95
## Длительность хода плиты, с.
const MOVE_TIME: float = 1.2

var _panel: MeshInstance3D
var _collision: CollisionShape3D
var _open: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	EventBus.ruins_state.connect(_on_ruins_state)
	_build_panel()


func _on_ruins_state(open: bool, _plates: Array, _openers: Array, _reward: Array) -> void:
	set_open(open)


## Применить состояние от хоста (rpc_ruins / world_state): плита опускается
## или поднимается. Повторный вызов с тем же состоянием — холостой.
func set_open(open: bool) -> void:
	if open == _open:
		return
	_open = open
	_collision.disabled = open
	var target_y: float = -OPEN_DROP if open else 0.0
	var tween := create_tween()
	tween.tween_property(_panel, "position:y", target_y, MOVE_TIME).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_IN_OUT)


## Плита-решётка: тёмный камень со светлыми рёбрами и коллизией.
func _build_panel() -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	add_child(body)
	_collision = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = PANEL_SIZE
	_collision.shape = shape
	body.add_child(_collision)

	_panel = MeshInstance3D.new()
	_panel.name = "Panel"
	var mesh := BoxMesh.new()
	mesh.size = PANEL_SIZE
	_panel.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = PAL.ruin_dark
	_panel.material_override = material
	add_child(_panel)

	# Два горизонтальных ребра, чтобы плита читалась как решётка.
	for rail_y: float in [0.75, 1.85]:
		var rail := MeshInstance3D.new()
		rail.name = "Rail%d" % int(rail_y * 100)
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(PANEL_SIZE.x - 0.12, 0.1, PANEL_SIZE.z + 0.06)
		rail.mesh = rail_mesh
		var rail_material := StandardMaterial3D.new()
		rail_material.albedo_color = PAL.ruin_brick
		rail.material_override = rail_material
		rail.position = Vector3(0.0, rail_y - PANEL_SIZE.y * 0.5, 0.0)
		_panel.add_child(rail)
