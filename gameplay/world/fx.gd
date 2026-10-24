# Малые эффекты мира (раздел 16 SPEC): круги на воде при входе в неё
# (костёр с искрами и дымом удалён с наследием Blockparty, born-unblessed).
# Эффекты — GPUParticles3D и примитивы;
# спрайты частиц — CC0-нарезки assets/vfx/particles (доработка П9:
# нетекстурный квад выглядит белым квадратом). Пыль приземления после
# переделки П9 живёт в FootFx (порции по шагам, у ног игрока). Ноды
# однократных эффектов освобождают себя после проигрывания; частицы
# в мировых координатах (local_coords = false), поэтому эмиттер можно
# вешать на движущийся узел — шлейп не «едет» за ним. В headless (сервер)
# частицы не тикают, но создаются безопасно — логика от них не зависит.
class_name Fx
extends Node3D

## Спрайты частиц (CC0): мягкое светящееся пятно искр.
const SOFT_TEX: Texture2D = preload("res://assets/vfx/particles/soft.png")


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

