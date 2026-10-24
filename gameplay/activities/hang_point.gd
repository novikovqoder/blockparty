# Точка цепляния на кромке расщелины (раздел 9.1 SPEC): светящийся
# маячок над кромкой, за который цепляется упавший (HangArea выбирает
# ближайшую точку). Механика вытягивания другим игроком удалена с
# наследием Blockparty (born-unblessed): провисев hang_time, игрок
# переносится к Камню духа. Дети Crevasse в island.tscn.
class_name HangPoint
extends Node3D

const PAL: Palette = preload("res://assets/palette.tres")

## Шарик-маячок точки (радиус, м; доработка-2 П5.13 П5 — сфера, не куб).
const POINT_SIZE: float = 0.09
## Подъём кубика над кромкой, м.
const POINT_LIFT: float = 0.12


func _ready() -> void:
	_build_glow()


## Светящаяся точка на кромке (цвет светлячка; доработка-2 П5.13 П5 —
## сфера вместо кубика-примитива).
func _build_glow() -> void:
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	var mesh := SphereMesh.new()
	mesh.radius = POINT_SIZE
	mesh.height = POINT_SIZE * 2.0
	glow.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = PAL.firefly
	material.emission_enabled = true
	material.emission = PAL.firefly
	material.emission_energy_multiplier = 2.0
	glow.material_override = material
	glow.position = Vector3.UP * POINT_LIFT
	add_child(glow)
