# Статичная монета острова (раздел 8 SPEC): ровно 60 штук расставлены
# генератором (смотровые, мостки, вершины, руины, лес, пирс); подбирается
# касанием, возрождается через 300 с (Balance). Вращение — от часов мира
# (детерминировано). В сети касание подтверждает хост: «кто первый — того
# и монета» (раздел 10), возрождение клиент вычисляет сам по respawn_at
# из события (позднее подключившиеся получают его из world_state).
class_name CoinPickup
extends Area3D

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")

## Какая это монета в данных острова (события coin_collected, world_state).
@export var spawn_id: int = 0

var _visual: Node3D
## Время возрождения по world_time (<= 0 — лежит).
var _respawn_at: float = -1.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # слой игроков
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	EventBus.coin_collected.connect(_on_coin_collected)
	EventBus.world_state_applied.connect(_on_world_state)
	_build_visual()


func _process(_delta: float) -> void:
	if not is_present():
		if Session.world_time >= _respawn_at:
			_revive()
		return
	_visual.rotation.y = Session.world_time * 2.0


## Касание игрока: запрос хосту, «кто первый — того и монета» (раздел 10).
func _on_body_entered(body: Node3D) -> void:
	if not is_present() or not body is Player:
		return
	Net.request_coin_collect(spawn_id, Net.world_time_sec())


## Хост подтвердил подбор: монета исчезает у всех до respawn_at.
func _on_coin_collected(taken_id: int, _collector_peer: int, respawn_at: float) -> void:
	if taken_id != spawn_id:
		return
	_respawn_at = respawn_at
	Fx.sparkle(get_parent(), global_position, PAL.coin)
	hide()
	set_deferred("monitoring", false)


## Вход в идущий мир (раздел 10): собранные монеты — из world_state.
func _on_world_state(_dead_mobs: Array, taken_coins: Array) -> void:
	for entry: Dictionary in taken_coins:
		if int(entry["spawn_id"]) == spawn_id:
			_respawn_at = maxf(_respawn_at, float(entry["respawn_at"]))
			hide()
			set_deferred("monitoring", false)


## Лежит ли монета сейчас (возрождение — по расписанию от хоста).
func is_present() -> bool:
	return _respawn_at <= 0.0 or Session.world_time >= _respawn_at


func _revive() -> void:
	_respawn_at = -1.0
	show()
	set_deferred("monitoring", true)


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.42, 0.1, 0.42)
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = PAL.coin
	material.roughness = 0.4
	material.emission_enabled = true
	material.emission = PAL.coin
	material.emission_energy_multiplier = 0.5
	mesh.material_override = material
	_visual.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(0.8, 1.0, 0.8)
	shape.shape = box_shape
	add_child(shape)
