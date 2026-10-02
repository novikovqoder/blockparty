# «Камень духа» (раздел 6 SPEC): точка возрождения, куда игрок переносится
# после неудачного падения (конец висения в расщелине — раздел 9.1).
# Визуал — из примитивов: постамент и светящийся куб (правило проекта).
class_name RespawnStone
extends Node3D

const PAL: Palette = preload("res://assets/palette.tres")

## Группа, по которой Player ищет ближайший камень (на острове их несколько).
const GROUP: StringName = &"respawn"


func _ready() -> void:
	add_to_group(GROUP)
	_build()


func _build() -> void:
	_add_box(Vector3(1.0, 0.4, 1.0), Vector3(0.0, 0.2, 0.0), PAL.stone, 0.0)
	_add_box(Vector3(0.5, 0.5, 0.5), Vector3(0.0, 0.65, 0.0), PAL.beacon_glow, 1.5)


func _add_box(size: Vector3, position: Vector3, color: Color, glow: float) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	mesh.material_override = material
	mesh.position = position
	add_child(mesh)
