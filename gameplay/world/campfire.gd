# Костёр на площади (раздел 6 SPEC): место сбора — каменное кольцо и лавки
# уже в GridMap острова, здесь только огонь (светящийся уголь + поленья и
# тёплый свет). Сидение, очки «рядом с костром» и анимации участников — П5.
class_name Campfire
extends Node3D

const PAL: Palette = preload("res://assets/palette.tres")


func _ready() -> void:
	_build()


func _build() -> void:
	var cross := Node3D.new()
	cross.name = "Logs"
	add_child(cross)
	var log_material := StandardMaterial3D.new()
	log_material.albedo_color = PAL.trunk
	log_material.roughness = 1.0
	for angle: float in [0.6, -0.6]:
		var log := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.9, 0.18, 0.24)
		log.mesh = box
		log.material_override = log_material
		log.rotation.y = angle
		log.position = Vector3(0.0, 0.15, 0.0)
		cross.add_child(log)
	var ember := MeshInstance3D.new()
	var ember_box := BoxMesh.new()
	ember_box.size = Vector3(0.34, 0.2, 0.34)
	ember.mesh = ember_box
	var ember_material := StandardMaterial3D.new()
	ember_material.albedo_color = PAL.fire
	ember_material.emission_enabled = true
	ember_material.emission = PAL.fire
	ember_material.emission_energy_multiplier = 1.8
	ember.material_override = ember_material
	ember.position = Vector3(0.0, 0.36, 0.0)
	add_child(ember)
	var light := OmniLight3D.new()
	light.light_color = PAL.fire
	light.omni_range = 9.0
	light.light_energy = 0.55
	light.position = Vector3(0.0, 0.6, 0.0)
	add_child(light)
