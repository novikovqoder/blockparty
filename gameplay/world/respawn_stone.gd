# «Камень духа» (раздел 6 SPEC): точка возрождения, куда игрок переносится
# после неудачного падения (конец висения в расщелине — раздел 9.1).
# Визуал — каменный постамент со шпилем (текстура кладки руин, доработка-2
# П5.13 П5) и маленький светящийся огонёк-шар наверху.
class_name RespawnStone
extends Node3D

const PAL: Palette = preload("res://assets/palette.tres")

## Группа, по которой Player ищет ближайший камень (на острове их несколько).
const GROUP: StringName = &"respawn"
## Габарит камня духа: постамент + шпиль (коллизия, баг vfx-fix), м.
const SOLID_SIZE: Vector3 = Vector3(1.0, 0.9, 1.0)
## Высота постамента и шпиля, м (сумма = SOLID_SIZE.y).
const PEDESTAL_H: float = 0.4
const SPIRE_H: float = 0.5


func _ready() -> void:
	add_to_group(GROUP)
	_build()


func _build() -> void:
	var solid := BoxShape3D.new()
	solid.size = SOLID_SIZE
	SolidBody.add(self, solid, Vector3(0.0, SOLID_SIZE.y * 0.5, 0.0))
	# Доработка-2 П5.13, П5: постамент и шпиль — текстурная кладка
	# (RuinMat.panel, BoxMesh без вершинных цветов), огонёк — сфера.
	var stone := RuinMat.panel()
	_add_box(
		Vector3(1.0, PEDESTAL_H, 1.0),
		Vector3(0.0, PEDESTAL_H * 0.5, 0.0), stone)
	_add_box(
		Vector3(0.55, SPIRE_H, 0.55),
		Vector3(0.0, PEDESTAL_H + SPIRE_H * 0.5, 0.0), stone)
	_add_glow(0.07, Vector3(0.0, PEDESTAL_H + SPIRE_H + 0.1, 0.0))


func _add_box(size: Vector3, position: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = position
	add_child(mesh)


func _add_glow(radius: float, position: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Glow"
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = PAL.lamp_glow
	material.emission_enabled = true
	material.emission = PAL.lamp_glow
	material.emission_energy_multiplier = 1.5
	mesh.material_override = material
	mesh.position = position
	add_child(mesh)
