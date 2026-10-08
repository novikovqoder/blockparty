# Зона расщелины (разделы 5, 9.1 SPEC): упавший в CrevasseArea игрок не
# погибает, а цепляется за ближайшую HangPoint на краю и висит hang_time
# секунд, затем переносится к Камню духа. В сети подтверждает хост
# (раздел 10): клиент висящего сам считает таймер, вытягивание — запрос
# rpc_request_pull от помощника (HangPoint-дети, П5) и проверка хоста.
class_name HangArea
extends Area3D

const B: Balance = preload("res://gameplay/balance.tres")


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2  # слой игроков
	body_entered.connect(_on_body_entered)


## Позиции точек HangPoint (дети-узлы), для выбора ближайшей.
func point_positions() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for child in get_children():
		if child is HangPoint:
			points.append((child as HangPoint).global_position)
	return points


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		var player := body as Player
		var points := point_positions()
		if points.is_empty():
			return
		player.start_hang(HangLogic.nearest_point(points, player.global_position))
