# Моб (раздел 8 SPEC): Area3D на слое игроков — в него попадает удар
# (Player._end_attack проверяет overlapping_areas). Траектория — чистая
# функция от часов мира (MobMotion + параметры из IslandGen), поэтому моб
# одинаков у всех и не требует синхронизации в сети (П3 подключит только
# события «убит/возрождён» от хоста). Убитый моб исчезает, даёт монеты
# и возрождается по таймеру (раздел 8). Визуал — дочерние узлы из примитивов,
# собираются в _build подвидами (модели можно заменить сцеными).
class_name Mob
extends Area3D

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")

## Какой это моб в данных острова (события mob_killed, снапшоты П3).
@export var spawn_id: int = 0

var _killed: bool = false


func _ready() -> void:
	# Слой 2 — игроки: удар ищет Area3D на этом слое; сами мобы ничего
	# не мониторят (движение — по формулам, не по физике).
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	monitorable = true
	_build()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = hitbox_size()
	shape.shape = box
	add_child(shape)


func _process(_delta: float) -> void:
	if _killed:
		return
	_apply_motion(Session.world_time)


## Выставить позицию/поворот по траектории (переопределяют подвиды).
func _apply_motion(_world_time: float) -> void:
	pass


## Удар игрока (раздел 8: птица и зверёк — один удар).
func take_hit() -> void:
	if _killed or not is_killable():
		return
	_killed = true
	hide()
	Session.add_world_coins(reward())
	EventBus.mob_killed.emit(spawn_id)
	Log.info("Моб %d убит" % spawn_id, "Mob")
	var timer: SceneTreeTimer = get_tree().create_timer(respawn_sec())
	timer.timeout.connect(_revive)


func _revive() -> void:
	_killed = false
	show()


## Светлячок неуязвим в одиночку (нужны два игрока рядом — раздел 8, П5).
func is_killable() -> bool:
	return true


func reward() -> int:
	return 1


func respawn_sec() -> float:
	return B.mob_respawn_sec


## Визуальная модель (переопределяют подвиды).
func _build() -> void:
	pass


## Размер зоны попадания удара, м (переопределяют подвиды).
func hitbox_size() -> Vector3:
	return Vector3(0.9, 0.9, 0.9)


# --- Примитивы для моделей подвидов ---

func _box(
	size: Vector3, position: Vector3, color: Color, parent: Node3D,
	glow: float = 0.0,
) -> MeshInstance3D:
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
	parent.add_child(mesh)
	return mesh
