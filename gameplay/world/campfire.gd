# Костёр на площади (раздел 6 SPEC): место сбора — каменное кольцо и лавки
# расставлены генератором острова (предметы «boulder» и «bench»), здесь
# только огонь: поленья, светящийся уголь, искры (раздел 16) и тёплый свет.
# Сидение у костра — П5 (раздел 9.6): от campfire_company_size сидящих
# огонь разгорается — свет и искры сильнее, один игрок оставляет его
# спокойным.
class_name Campfire
extends Node3D

const PAL: Palette = preload("res://assets/palette.tres")
const B: Balance = preload("res://gameplay/balance.tres")

## Параметры спокойного огня / разгоревшегося (раздел 9.6).
const CALM_ENERGY: float = 0.55
const CALM_RANGE: float = 9.0
const CALM_SPARKS: int = 12
const COMPANY_ENERGY: float = 1.0
const COMPANY_RANGE: float = 13.0
const COMPANY_SPARKS: int = 26
## Коллизия очага (баг vfx-fix): цилиндр по габариту поленьев и угля —
## игрок не проходит сквозь огонь. Каменное кольцо — предметы «boulder»,
## у них своя коллизия в раскладке.
const HEARTH_RADIUS: float = 0.55
const HEARTH_HEIGHT: float = 0.55

var _light: OmniLight3D
var _sparks: GPUParticles3D


func _ready() -> void:
	_build()
	EventBus.campfire_seats.connect(_on_campfire_seats)


func _build() -> void:
	# Твёрдый очаг (баг vfx-fix): поленья и уголь — не призраки.
	var hearth := CylinderShape3D.new()
	hearth.radius = HEARTH_RADIUS
	hearth.height = HEARTH_HEIGHT
	SolidBody.add(self, hearth, Vector3(0.0, HEARTH_HEIGHT * 0.5, 0.0))
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
	_sparks = Fx.fire_sparks(self, Vector3(0.0, 0.5, 0.0), PAL.fire)
	_light = OmniLight3D.new()
	_light.light_color = PAL.fire
	_light.omni_range = CALM_RANGE
	_light.light_energy = CALM_ENERGY
	_light.position = Vector3(0.0, 0.6, 0.0)
	add_child(_light)


## Сколько сидящих сейчас (раздел 9.6): двое и больше — огонь сильнее.
func _on_campfire_seats(seats: Array) -> void:
	var seated := 0
	for peer: int in seats:
		if peer != 0:
			seated += 1
	if seated >= B.campfire_company_size:
		_light.light_energy = COMPANY_ENERGY
		_light.omni_range = COMPANY_RANGE
		_sparks.amount = COMPANY_SPARKS
	else:
		_light.light_energy = CALM_ENERGY
		_light.omni_range = CALM_RANGE
		_sparks.amount = CALM_SPARKS
