# Пропасть (раздел 5, 7.1 SPEC): зона под уровнем пола; вошедший игрок
# переходит в состояние «Висит» у ближайшего левого края (HangPoint секции).
class_name PitArea
extends Area2D

const PAL: Palette = preload("res://assets/palette.tres")

## Края пропасти, за которые можно зацепиться, — в локальных координатах
## секции (Chunk.add_pit); в мировые переводятся в момент зацепа.
var hang_points: Array[Vector2] = []


## Геометрия зоны пропасти и её края зацепа.
func setup(rect: Rect2, points: Array[Vector2]) -> void:
	hang_points = points
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center()
	add_child(shape)
	# Тёмный провал — чтобы пропасть читалась на фоне.
	add_child(Prim.rect(rect.size, PAL.pit))


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if player == null:
		return
	# Раздел 5: зацеп за ближайший левый край пропасти (сравнение локально,
	# игроку отдаём мировую точку — чанк смещён на offset_x).
	var local_x := to_local(player.global_position).x
	var best: Vector2 = hang_points[0] if not hang_points.is_empty() else position
	for point: Vector2 in hang_points:
		if point.x <= local_x and point.x >= best.x:
			best = point
	player.enter_hang(to_global(best))
