# Одноразовая диагностика (vfx-fix): почему монета не подбирается
# касанием в headless-прогоне. Ставит игрока на Coin1 и печатает
# каждую секунду дистанцию, флаги Area3D и пересечение.
# Запуск: godot --headless -s tools/diag_coin.gd --path .
extends SceneTree

const ISLAND: PackedScene = preload("res://gameplay/world/island.tscn")
const PLAYER: PackedScene = preload("res://gameplay/player/player.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var island := ISLAND.instantiate()
	get_root().add_child(island)
	var coin := island.get_node("Coin1") as Area3D
	var player := PLAYER.instantiate()
	island.add_child(player)
	player.global_position = coin.global_position + Vector3(0.0, 0.2, 0.0)
	for i: int in range(240):
		await physics_frame
		if i % 60 == 59:
			print("t=%.1f dist=%.3f visible=%s monitoring=%s overlaps=%s layers: player=%d coin_mask=%d bodies=%d" % [
				float(i) / 60.0,
				player.global_position.distance_to(coin.global_position),
				coin.visible,
				coin.monitoring,
				coin.overlaps_body(player),
				player.get_collision_layer(),
				coin.get_collision_mask(),
				coin.get_overlapping_bodies().size(),
			])
			for shape: Node in player.get_children():
				if shape is CollisionShape3D:
					print("  player shape: %s disabled=%s" % [
						(shape as CollisionShape3D).shape,
						(shape as CollisionShape3D).disabled])
		if not coin.visible:
			print("t=%.2f: монета скрыта" % (float(i) / 60.0))
			break
	quit()
