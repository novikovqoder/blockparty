# Мини-звездопад финала Луми (П5.5): quest_starfall_mini_duration (20 с)
# над островом падают декоративные звёзды — только визуально, подобрать
# нельзя (настоящий Звездопад с подбором — раздел 7). Если настоящий
# уже идёт, мини — ярче и гуще. Частицы процедурные; в headless не тикают,
# но создаются безопасно — логика от них не зависит.
class_name MiniStarfall
extends Node3D

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")

## Высота рождения звёзд над островом, м.
const SPAWN_Y: float = 55.0
## Сколько секунд после конца узел доживает, с.
const LINGER: float = 3.0
## Спокойная плотность/яркость; при настоящем Звездопаде — вдвое больше.
const BASE_AMOUNT: int = 36
const BASE_ENERGY: float = 2.2
const BOOST: int = 2


## Запустить мини-звездопад: real_starfall — идёт ли настоящий (ярче).
static func spawn(parent: Node3D, real_starfall: bool) -> void:
	var fx := MiniStarfall.new()
	parent.add_child(fx)
	fx._run(real_starfall)


func _run(real_starfall: bool) -> void:
	var scale: int = BOOST if real_starfall else 1
	var fx := GPUParticles3D.new()
	fx.name = "MiniStarfall"
	fx.amount = BASE_AMOUNT * scale
	fx.lifetime = 1.8
	fx.position = Vector3(0.0, SPAWN_Y, 0.0)
	fx.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(
		IslandGen.HALF * 0.7, 1.0, IslandGen.HALF * 0.7
	)
	# Падают по диагонали вниз — читаются как метеоры, не как «дождь точек».
	process.direction = Vector3(0.35, -1.0, 0.2).normalized()
	process.spread = 8.0
	process.initial_velocity_min = 16.0
	process.initial_velocity_max = 24.0
	process.gravity = Vector3.ZERO
	process.scale_min = 0.7
	process.scale_max = 1.3
	fx.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var material := StandardMaterial3D.new()
	material.albedo_color = PAL.coin
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = PAL.beacon_glow
	material.emission_energy_multiplier = BASE_ENERGY * scale
	quad.material = material
	fx.draw_pass_1 = quad
	add_child(fx)
	var timer := get_tree().create_timer(B.quest_starfall_mini_duration)
	timer.timeout.connect(func() -> void:
		fx.emitting = false
		var linger := get_tree().create_timer(LINGER)
		linger.timeout.connect(queue_free)
	)
