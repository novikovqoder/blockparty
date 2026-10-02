# Статичная монета острова (раздел 8 SPEC): ровно 60 штук расставлены
# генератором (смотровые, мостки, вершины, руины, лес, пирс); подбирается
# касанием, даёт монету и возрождается через 300 с (Balance). Вращение — от
# часов мира (детерминировано). На П2 логика локальная (одиночный мир);
# в сети сбор монет решает хост и рассылает событие (П3 заменит тело метода).
class_name CoinPickup
extends Area3D

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")

## Какая это монета в данных острова (события coin_collected, снапшоты П3).
@export var spawn_id: int = 0

var _visual: Node3D
var _active: bool = true


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # слой игроков
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	_build_visual()


func _process(_delta: float) -> void:
	_visual.rotation.y = Session.world_time * 2.0


func _on_body_entered(body: Node3D) -> void:
	if not _active or not body is Player:
		return
	_active = false
	hide()
	set_deferred("monitoring", false)
	Session.add_world_coins(B.coin_reward)
	EventBus.coin_collected.emit(spawn_id)
	Log.info("Монета %d собрана" % spawn_id, "Coin")
	var timer: SceneTreeTimer = get_tree().create_timer(B.coin_respawn_sec)
	timer.timeout.connect(_revive)


func _revive() -> void:
	_active = true
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
