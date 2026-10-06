# Одноразовая диагностика шага 3 П4.5: что реально запечено в island_art.res —
# группы предметов PropGroup, число экземпляров, габариты меша (пустые группы
# = потеря предметов). Запуск: godot --headless --path . -s tools/dump_island_art.gd
extends SceneTree


func _initialize() -> void:
	var art: IslandArt = load("res://gameplay/world/island_art.res") as IslandArt
	if art == null:
		print("island_art.res не читается как IslandArt")
		quit(1)
		return
	print("чанков рельефа: %d, коллайдеров: %d" % [art.chunks.size(), art.colliders.size()])
	var trees := 0
	var in_forest := 0
	var keys: Array = art.prop_groups.keys()
	keys.sort()
	for key: String in keys:
		var group: PropGroup = art.prop_groups[key]
		if group == null or group.mesh == null:
			print("%s: ПУСТО" % key)
			continue
		var aabb := group.mesh.get_aabb()
		print(
			"%s: instances=%d aabb=%.1fx%.1fx%.1f" % [
				key, group.transforms.size(), aabb.size.x, aabb.size.y, aabb.size.z,
			]
		)
		if String(key).contains("tree"):
			for xf: Transform3D in group.transforms:
				trees += 1
				if Vector2(xf.origin.x, xf.origin.z).distance_to(Vector2(-52, -52)) < 40.0:
					in_forest += 1
	print("деревьев всего=%d в круге леса=%d" % [trees, in_forest])
	quit(0)
