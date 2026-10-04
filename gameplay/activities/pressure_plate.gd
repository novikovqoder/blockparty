# Нажимная плита (раздел 6 SPEC, зона «Руины»): проседает и светится, когда
# на ней стоит хотя бы один игрок. На этапе П1 — индикатор для тестовой
# площадки; подсчёт «N разных игроков» и открытие ворот — П5 (CoopDirector
# по снапшотам, раздел 10), состояние тогда подтверждает хост.
class_name PressurePlate
extends Node3D

const PAL: Palette = preload("res://assets/palette.tres")

## Насколько плита проседает под игроком, м.
const PRESS_DEPTH: float = 0.08
## Плавность хода, с⁻¹.
const MOVE_SPEED: float = 10.0

@onready var _rest: Marker3D = $PlateRest
@onready var _body: StaticBody3D = $Plate
@onready var _area: Area3D = $Sense
@onready var _material := _make_material()

var _pressed: bool = false


func _ready() -> void:
	(_body.get_node("PlateMesh") as MeshInstance3D).material_override = _material
	_area.body_entered.connect(_update_pressed)
	_area.body_exited.connect(_update_pressed)


func _process(delta: float) -> void:
	var target: float = _rest.position.y - (PRESS_DEPTH if _pressed else 0.0)
	_body.position.y = move_toward(_body.position.y, target, MOVE_SPEED * delta)
	_material.emission_energy_multiplier = move_toward(
		_material.emission_energy_multiplier, 0.8 if _pressed else 0.0, MOVE_SPEED * delta
	)


## Нажата ли плита (в П5 — «кто стоит» считает хост по снапшотам).
func is_pressed() -> bool:
	return _pressed


func _update_pressed(_body_node: Node3D) -> void:
	_pressed = not _area.get_overlapping_bodies().is_empty()


func _make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = PAL.ruin_dark
	material.roughness = 1.0
	material.emission_enabled = true
	material.emission = PAL.beacon_glow
	material.emission_energy_multiplier = 0.0
	return material
