# Золотая звезда Звездопада (раздел 7 SPEC): падает с неба star_fall_time
# секунд, лежит до star_lifetime и исчезает; подбирается касанием —
# подтверждает хост («кто первый»), звезда исчезает у всех по star_taken.
# Рождает и позиционирует Starfall (детерминированно от старта и индекса),
# узлу остаётся падение по часам мира и визуал.
class_name StarPickup
extends Area3D

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")

## Номер звезды в Звездопаде (события star_taken, «кто первый»).
var index: int = 0
## Высота земли под звездой (куда падает), м.
var ground_y: float = 0.0
## Момент рождения по часам мира — задаёт Starfall.
var born_at: float = 0.0

var _visual: Node3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # слой игроков
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	EventBus.star_taken.connect(_on_star_taken)
	_build_visual()


func _process(_delta: float) -> void:
	# Падение по часам мира: у всех клиентов одинаково (раздел 10).
	var age := Session.world_time - born_at
	var k := clampf(age / B.star_fall_time, 0.0, 1.0)
	position.y = lerpf(ground_y + B.star_spawn_height, ground_y + 0.35, k)
	_visual.rotation.y = Session.world_time * 3.0


## Касание игрока: запрос хосту, «кто первый — того и монета» (раздел 7).
func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		Net.request_star_collect(index)


## Хост подтвердил подбор: звезда исчезает у всех.
func _on_star_taken(taken_index: int, _collector_peer: int) -> void:
	if taken_index != index:
		return
	Fx.sparkle(get_parent(), global_position, PAL.coin)
	queue_free()


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var mesh := MeshInstance3D.new()
	mesh.name = "Star"
	# Кристалл-звезда: гранёная призма, во время падения вращается.
	var crystal := PrismMesh.new()
	crystal.size = Vector3(0.42, 0.6, 0.42)
	crystal.left_to_right = 0.0
	mesh.mesh = crystal
	var material := StandardMaterial3D.new()
	material.albedo_color = PAL.coin
	material.emission_enabled = true
	material.emission = PAL.coin
	material.emission_energy_multiplier = 1.2
	mesh.material_override = material
	_visual.add_child(mesh)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8
	shape.shape = sphere
	add_child(shape)
