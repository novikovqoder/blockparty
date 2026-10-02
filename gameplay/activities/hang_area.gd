# Зона расщелины (разделы 5, 9.1 SPEC): упавший в CrevasseArea игрок не
# погибает, а цепляется за ближайшую HangPoint на краю и висит hang_time
# секунд, затем переносится к Камню духа. В П1 (одиночный режим) состояние
# считает сам игрок; в сети это решает хост (раздел 10, П3) — код Player
# не меняется. HangPoints — светящиеся точки на кромке (дети этого узла).
# Не делает: удержание E помощником и rpc_request_pull (П5), эмоцию
# «Помогите!» со стрелкой (П5).
class_name HangArea
extends Area3D

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")

## Светящаяся точка HangPoint: кубик со свечением, парит над кромкой.
const POINT_SIZE: float = 0.14
const POINT_LIFT: float = 0.12


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2  # слой игроков
	body_entered.connect(_on_body_entered)
	_build_points()


## Позиции точек HangPoint (Marker3D-дети), для выбора ближайшей.
func point_positions() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for child in get_children():
		if child is Marker3D:
			points.append((child as Marker3D).global_position)
	return points


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		var player := body as Player
		var points := point_positions()
		if points.is_empty():
			return
		player.start_hang(HangLogic.nearest_point(points, player.global_position))


## Точки задаются детьми-Marker3D в сцене; подсветка — из примитивов.
func _build_points() -> void:
	for child in get_children():
		if child is Marker3D:
			var marker := child as Marker3D
			var glow := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3.ONE * POINT_SIZE
			glow.mesh = mesh
			var material := StandardMaterial3D.new()
			material.albedo_color = PAL.firefly
			material.emission_enabled = true
			material.emission = PAL.firefly
			material.emission_energy_multiplier = 2.0
			glow.material_override = material
			glow.position = Vector3.UP * POINT_LIFT
			marker.add_child(glow)
