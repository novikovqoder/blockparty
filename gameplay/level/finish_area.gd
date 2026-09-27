# Финишная черта (раздел 7.6): пересечение — финиш игрока; событие получает
# сцена забега (остановка часов, награда за финиш) — здесь только сигнал.
class_name FinishArea
extends Area2D

const PAL: Palette = preload("res://assets/palette.tres")


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(32, 400)
	shape.shape = box
	shape.position = Vector2(0, -200)
	add_child(shape)
	# Два столба и «лента» финиша.
	for side: float in [-24.0, 24.0]:
		var pole := Prim.outlined_rect(Vector2(12, 360), PAL.finish, PAL.outline)
		pole.position = Vector2(side, -180)
		add_child(pole)
	add_child(_banner())
	body_entered.connect(_on_body_entered)


func _banner() -> Node2D:
	var banner := Prim.outlined_rect(Vector2(48, 24), PAL.coin, PAL.outline)
	banner.position = Vector2(0, -352)
	return banner


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		EventBus.player_finished.emit(Session.run_time)
