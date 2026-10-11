# Одноразовая проверка (П5.7, блок 2): цифры ориентиров Леса из свежих
# данных генератора — глубина оврага в середине и на кромке, высота мостика
# против берегов, наличие гиганта/мостика/папоротников. Запуск:
#   godot --headless --script tools/scan_forest.gd --path .
extends SceneTree


func _init() -> void:
	await create_timer(0.01).timeout
	_scan()
	_edges()
	quit()


func _scan() -> void:
	var data: Dictionary = IslandGen.generate()
	var heights: PackedFloat32Array = data["heights"]
	var mid := Vector2i(roundi(IslandGen.GULLY_MID.x), roundi(IslandGen.GULLY_MID.y))
	print("дно в середине: %.2f" % heights[IslandGen._idx(mid.x, mid.y)])
	var across := Vector2(-IslandGen.GULLY_DIR.y, IslandGen.GULLY_DIR.x)
	for d: float in [2.6, 3.2, 4.0]:
		var flat: Vector2 = IslandGen.GULLY_MID + across * d
		var cell := Vector2i(roundi(flat.x), roundi(flat.y))
		print("кромка %+0.1f м по тропе (%d, %d): %.2f"
			% [d, cell.x, cell.y, heights[IslandGen._idx(cell.x, cell.y)]])
	var counts: Dictionary = {}
	var bridge_y: float = NAN
	var giant: Vector3 = Vector3.ZERO
	for prop: Dictionary in data["props"]:
		var type := String(prop["type"])
		counts[type] = counts.get(type, 0) + 1
		if type == "log_bridge":
			bridge_y = (prop["pos"] as Vector3).y
		if type == "tree_giant":
			giant = prop["pos"]
	print("мостик y=%.2f (настил %.2f), гигант %s" % [bridge_y, bridge_y + 0.45, giant])
	for type: String in ["fern", "log", "tree_giant", "log_bridge", "tree_leafy"]:
		print("%s: %d" % [type, counts.get(type, 0)])


func _edges() -> void:
	var data: Dictionary = IslandGen.generate()
	var heights: PackedFloat32Array = data["heights"]
	var trail := Vector2(-0.588, -0.809)
	for d: float in [-2.4, -2.2, 2.2, 2.4, 2.6]:
		var flat: Vector2 = IslandGen.GULLY_MID + trail * d
		print("край мостика %+0.1f по тропе: ground %.2f"
			% [d, IslandGen.ground_height(heights, flat.x, flat.y)])
