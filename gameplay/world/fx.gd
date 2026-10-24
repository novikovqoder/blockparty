# Малые эффекты мира (раздел 16 SPEC): круги на воде при входе в неё;
# постоянные — искры и дым костра. Эффекты — GPUParticles3D и примитивы;
# спрайты частиц — CC0-нарезки assets/vfx/particles (доработка П9:
# нетекстурный квад выглядит белым квадратом). Пыль приземления после
# переделки П9 живёт в FootFx (порции по шагам, у ног игрока). Ноды
# однократных эффектов освобождают себя после проигрывания; частицы
# в мировых координатах (local_coords = false), поэтому эмиттер можно
# вешать на движущийся узел — шлейп не «едет» за ним. В headless (сервер)
# частицы не тикают, но создаются безопасно — логика от них не зависит.
class_name Fx
extends Node3D

const SMOKE_SHADER: Shader = preload("res://assets/shaders/smoke.gdshader")
## Спрайты частиц (CC0): мягкое светящееся пятно искр.
const SOFT_TEX: Texture2D = preload("res://assets/vfx/particles/soft.png")


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
	material.albedo_texture = SOFT_TEX
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


## Лёгкий дым костра (доработка П5.13, живой огонь): редкие мягкие клубы
## (smoke.gdshader) над пламенем — поднимаются, разворачиваются турбулентностью
## и тают; нода возвращается вставившемуся (костёр меняет amount по сидящим).
static func campfire_smoke(node: Node3D, pos: Vector3, amount: int) -> GPUParticles3D:
	var fx := GPUParticles3D.new()
	fx.name = "Smoke"
	fx.amount = amount
	fx.lifetime = 4.2
	fx.position = pos
	fx.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 12.0
	process.initial_velocity_min = 0.45
	process.initial_velocity_max = 0.7
	# Лёгкая тяга вверх (газ от огня), без гравитации.
	process.gravity = Vector3(0.0, 0.18, 0.0)
	process.scale_min = 0.55
	process.scale_max = 1.0
	# Клубы разворачивает ветерком турбулентности — дым не столб.
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.35
	process.turbulence_noise_scale = 0.6
	process.turbulence_noise_speed = Vector3(0.3, 0.1, 0.2)
	# Альфа по жизни: быстро проявляется, медленно тает.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.18, Color(1.0, 1.0, 1.0, 0.55))
	gradient.add_point(0.6, Color(1.0, 1.0, 1.0, 0.3))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	# Клуб растёт по жизни (крутая кривая не нужна — масштаб умеренный).
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 1.0))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	process.scale_curve = curve_tex
	fx.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.75, 0.75)
	var material := ShaderMaterial.new()
	material.shader = SMOKE_SHADER
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

