# Костёр на площади (раздел 6 SPEC): место сбора — каменное кольцо и лавки
# расставлены генератором острова (предметы «boulder» и «bench»), здесь
# только огонь: поленья, светящийся уголь, искры (раздел 16) и тёплый свет.
# Сидение, очки «рядом с костром» и анимации участников — П5.
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
	# Уголь: огранённый камень с углями — чуть живее бокса (раздел 16).
	var ember := MeshInstance3D.new()
	var ember_mesh := SphereMesh.new()
	ember_mesh.radius = 0.22
	ember_mesh.height = 0.44
	ember_mesh.radial_segments = 5
	ember_mesh.rings = 1
	ember.mesh = ember_mesh
	var ember_material := StandardMaterial3D.new()
	ember_material.albedo_color = PAL.fire
	ember_material.emission_enabled = true
	ember_material.emission = PAL.fire
	ember_material.emission_energy_multiplier = 1.8
	ember.material_override = ember_material
	ember.position = Vector3(0.0, 0.32, 0.0)
	add_child(ember)
	# Искры над углями (раздел 16: «искры костра»).
	Fx.fire_sparks(self, Vector3(0.0, 0.5, 0.0), PAL.fire)
	var light := OmniLight3D.new()
	light.light_color = PAL.fire
	light.omni_range = 9.0
	light.light_energy = 0.55
	light.position = Vector3(0.0, 0.6, 0.0)
	add_child(light)
