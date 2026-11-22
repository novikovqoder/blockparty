# ВРЕМЕННАЯ проверка фикса 3 (НЕ КОММИТИТЬ): коллайдеры у коридоров спусков.
extends SceneTree


func _initialize() -> void:
	_check.call_deferred()


func _check() -> void:
	var art: IslandArt = load("res://gameplay/world/island_art.res")
	var segments: Array = [
		[Vector2(-74.0, 54.0), Vector2(-60.7426, 45.0423)],
		[Vector2(-44.0, 52.5), Vector2(-33.2494, 40.6499)],
	]
	for segment: Array in segments:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		print("=== спуск %s -> %s ===" % [a, b])
		var n := 0
		for c: Dictionary in art.colliders:
			var pos: Vector3 = c["pos"]
			var flat := Vector2(pos.x, pos.z)
			var d: float = Geometry2D.get_closest_point_to_segment(
				flat, a, b).distance_to(flat)
			if d <= 3.5:
				n += 1
				print("  prop @ (%7.2f,%6.2f,%7.2f) size %s d=%.2f" % [
					pos.x, pos.y, pos.z, str(c["size"]), d])
		if n == 0:
			print("  чисто")
	quit(0)
