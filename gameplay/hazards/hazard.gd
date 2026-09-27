# Базовое статичное препятствие с отбрасыванием (раздел 4, 6 SPEC): шипы и
# кактусы дают отбрасывание, мигание и неуязвимость, урона и смерти нет.
# Визуал и хитбокс задают подклассы spikes.gd / cactus.gd.
class_name Hazard
extends Area2D

var _hits: Array[Node2D] = []


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visual()


func _build_visual() -> void:
	pass  # определяет подкласс


## Пока игрок пересекается с препятствием, урон не повторяется (неуязвимость
# и так защищает, но и сами касания шлём однократно до выхода из зоны).
func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if player != null and not _hits.has(player):
		_hits.append(player)
		player.apply_hit(global_position)


func _on_body_exited(body: Node2D) -> void:
	_hits.erase(body)
