# Малые эффекты мира (раздел 16 SPEC): однократные частицы — облачко пыли
# при приземлении, блёстки при подборе монеты, «пуф» при смерти моба, круги
# на воде при входе в неё; постоянные — искры костра. Все эффекты —
# процедурные GPUParticles3D и примитивы (правило проекта: без ассетов).
# Ноды однократных эффектов освобождают себя после проигрывания; частицы
# в мировых координатах (local_coords = false), поэтому эмиттер можно
# вешать на движущийся узел — шлейп не «едет» за ним. В headless (сервер)
# частицы не тикают, но создаются безопасно — логика от них не зависит.
class_name Fx
extends Node3D

## Сколько секунд нода эффекта живёт до самоосвобождения, с.
const LINGER: float = 2.0


## Облачко пыли (приземление, «пуф» моба): мягкий клубок у земли.
static func puff(
	parent: Node3D, pos: Vector3, color: Color,
	amount: int = 12, size: float = 0.14, speed: float = 1.3,
) -> void:
	var fx := _one_shot(parent, pos, amount, 0.55, color, size)
	var process := fx.process_material as ParticleProcessMaterial
	process.direction = Vector3.UP
	process.spread = 70.0
	process.initial_velocity_min = speed * 0.4
	process.initial_velocity_max = speed
	process.gravity = Vector3(0, -2.0, 0)
	process.scale_max = size * 8.0


## Блёстки вверх (монета, светлячок): искры с лёгким разлётом.
static func sparkle(
	parent: Node3D, pos: Vector3, color: Color, amount: int = 14,
) -> void:
	var fx := _one_shot(parent, pos, amount, 0.7, color, 0.07)
	var process := fx.process_material as ParticleProcessMaterial
	process.direction = Vector3.UP
	process.spread = 55.0
	process.initial_velocity_min = 1.0
	process.initial_velocity_max = 2.2
	process.gravity = Vector3(0, -4.0, 0)
	process.scale_max = 0.5


## Постоянные искры костра (раздел 16): тёплые угольки вверх, нода
## возвращается вставившемуся — освобождать самому.
static func fire_sparks(node: Node3D, pos: Vector3, color: Color) -> GPUParticles3D:
	var fx := GPUParticles3D.new()
	fx.name = "Sparks"
	fx.amount = 22
	fx.lifetime = 1.3
	fx.position = pos
	fx.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 26.0
	process.initial_velocity_min = 0.8
	process.initial_velocity_max = 1.8
	process.gravity = Vector3(0, 0.7, 0)
	process.scale_min = 0.35
	process.scale_max = 1.0
	fx.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.2
	quad.material = material
	fx.draw_pass_1 = quad
	node.add_child(fx)
	return fx


## Круги на воде при входе в неё (раздел 16): расширяющееся тонкое кольцо
## на уровне поверхности, растворяется за ~1 с.
static func water_ring(parent: Node3D, pos: Vector3, color: Color) -> void:
	var ring := MeshInstance3D.new()
	ring.name = "WaterRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.42
	ring.mesh = torus
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color, 0.7)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = material
	ring.position = pos
	parent.add_child(ring)
	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector3(3.2, 1.0, 3.2), 0.9)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(
		material, "albedo_color:a", 0.0, 0.9).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(ring.queue_free)


## Каркас однократного эффекта: GPUParticles3D с квадратной частицей цвета.
static func _one_shot(
	parent: Node3D, pos: Vector3, amount: int, lifetime: float,
	color: Color, size: float,
) -> GPUParticles3D:
	var fx := GPUParticles3D.new()
	fx.name = "Fx"
	fx.amount = amount
	fx.lifetime = lifetime
	fx.one_shot = true
	fx.explosiveness = 0.9
	fx.position = pos
	fx.local_coords = false
	fx.emitting = true
	var process := ParticleProcessMaterial.new()
	process.scale_min = 0.5
	fx.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = material
	fx.draw_pass_1 = quad
	parent.add_child(fx)
	var timer := fx.get_tree().create_timer(LINGER)
	timer.timeout.connect(fx.queue_free)
	return fx
