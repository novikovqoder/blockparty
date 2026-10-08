# Моб (раздел 8 SPEC): Area3D на слое игроков — в него попадает удар
# (Player._end_attack проверяет overlapping_areas). Траектория — чистая
# функция от часов мира (MobMotion + параметры из IslandGen), поэтому моб
# одинаков у всех и не требует синхронизации в сети. «Убит» и «возрождён»
# решает хост (раздел 10): событие mob_killed приносит respawn_at, моб
# оживает сам, когда world_time его достигает, — позднее подключившийся
# получает то же расписание из world_state. Визуал — дочерние узлы из
# примитивов, собираются в _build подвидами (модели можно заменить сцеными).
class_name Mob
extends Area3D

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")

## Группа узлов мобов (хост ищет моба для проверки удара).
const GROUP: StringName = &"mob"

## Какой это моб в данных острова (события mob_killed, world_state).
@export var spawn_id: int = 0

## Время возрождения по world_time (<= 0 — жив).
var _respawn_at: float = -1.0


func _ready() -> void:
	# Слой 2 — игроки: удар ищет Area3D на этом слое; сами мобы ничего
	# не мониторят (движение — по формулам, не по физике).
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	monitorable = true
	add_to_group(GROUP)
	EventBus.mob_killed.connect(_on_mob_killed)
	EventBus.world_state_applied.connect(_on_world_state)
	_build()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = hitbox_size()
	shape.shape = box
	add_child(shape)


func _process(_delta: float) -> void:
	if not is_alive():
		if Session.world_time >= _respawn_at:
			_revive()
		return
	_apply_motion(Session.world_time)


## Жив ли моб сейчас (возрождение — по расписанию от хоста).
func is_alive() -> bool:
	return _respawn_at <= 0.0 or Session.world_time >= _respawn_at


## Выставить позицию/поворот по траектории (переопределяют подвиды).
func _apply_motion(_world_time: float) -> void:
	pass


## Расчётная позиция в момент world_time (переопределяют подвиды) — хост
## проверяет по ней дистанцию удара (раздел 8), не доверяя клиенту.
func position_at(_world_time: float) -> Vector3:
	return global_position


## Удар игрока (раздел 8: попадание видит клиент, убийство решает хост —
## светлячка добивает только второй игрок в окне, хост это знает).
func take_hit() -> void:
	if is_alive():
		Net.request_mob_hit(spawn_id, Net.world_time_sec())


## Хост подтвердил убийство (раздел 10): прячем до respawn_at.
func _on_mob_killed(killed_id: int, _killers: Array, respawn_at: float) -> void:
	if killed_id != spawn_id:
		return
	_respawn_at = respawn_at
	Fx.puff(get_parent(), global_position, poof_color())
	hide()


## Вход в идущий мир (раздел 10): расписание мёртвых мобов — из world_state.
func _on_world_state(dead_mobs: Array, _taken_coins: Array) -> void:
	for entry: Dictionary in dead_mobs:
		if int(entry["spawn_id"]) == spawn_id:
			_respawn_at = maxf(_respawn_at, float(entry["respawn_at"]))
			hide()


func _revive() -> void:
	_respawn_at = -1.0
	show()


## Цвет «пуфа» частиц при смерти (переопределяют подвиды).
func poof_color() -> Color:
	return Color.WHITE


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
	mesh.material_override = _standard(color, glow)
	mesh.position = position
	parent.add_child(mesh)
	return mesh


## Огранённый примитив моба (раздел 16: птица — «огранённое тело-призма»)
## с общим шейдером lowpoly; цвет однотонный.
func _lowpoly(
	prim: PrimitiveMesh, position: Vector3, color: Color, parent: Node3D,
	rotation: Vector3 = Vector3.ZERO,
) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = prim
	mesh.material_override = LowPolyMat.flat_or_mat(color)
	mesh.position = position
	mesh.rotation = rotation
	parent.add_child(mesh)
	return mesh


## Сглаженный примитив (округлые зверьки, как персонажи-«мармеладки»).
func _smooth(
	prim: PrimitiveMesh, position: Vector3, color: Color, parent: Node3D,
	rotation: Vector3 = Vector3.ZERO,
) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = prim
	mesh.material_override = _standard(color, 0.0)
	mesh.position = position
	mesh.rotation = rotation
	parent.add_child(mesh)
	return mesh


func _standard(color: Color, glow: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	return material
