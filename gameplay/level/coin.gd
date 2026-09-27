# Монета на уровне (раздел 6 SPEC): видна всем, подбирается по принципу
# «первый коснувшийся» — подтверждение даёт «хост» (этап 1 — локально).
class_name Coin
extends Area2D

const PAL: Palette = preload("res://assets/palette.tres")

## id спавна из LevelPlan.
var spawn_id: int = -1

var _picked: bool = false


func _init() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	add_child(shape)


func _ready() -> void:
	add_child(Prim.outlined_rect(Vector2(18, 18), PAL.coin, Color(0.8, 0.6, 0.1), 1.5))
	body_entered.connect(_on_body_entered)
	EventBus.coin_picked.connect(_on_coin_picked)
	# Лёгкое покачивание, чтобы монета была заметна.
	var t := create_tween().set_loops()
	t.tween_property(self, "scale", Vector2(1.15, 1.15), 0.5)
	t.tween_property(self, "scale", Vector2.ONE, 0.5)


func setup(p_spawn_id: int) -> void:
	spawn_id = p_spawn_id


func _on_body_entered(body: Node2D) -> void:
	if _picked or not (body is Player):
		return
	# Раздел 6: клиент только просит, решение за «хостом» (первый запрос выигрывает).
	EventBus.coin_pickup_requested.emit(spawn_id)


func _on_coin_picked(picked_id: int) -> void:
	if picked_id != spawn_id or _picked:
		return
	_picked = true
	hide()
	set_deferred("monitoring", false)
	queue_free()
