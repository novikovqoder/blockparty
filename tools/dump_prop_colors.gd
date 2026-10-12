# Одноразовая диагностика (П5.8 A1): какие вершинные цвета дают рантайм-меши
# Cc0Meshes — средняя яркость/оттенок по типу предмета. Чёрный средний цвет
# = фон атласа попал в вершины (листва без альфа-вырезки).
# Запуск: godot --headless -s tools/dump_prop_colors.gd
extends SceneTree


func _initialize() -> void:
	var types := [
		&"rtree_leafy", &"tree_giant", &"rshrub", &"rrock", &"rlog",
		&"rgrass", &"fern", &"tree_leafy", &"tree_spruce",
	]
	for type in types:
		for variant: int in 4:
			var mesh := Cc0Meshes.mesh(type, variant)
			if mesh == null or mesh.get_surface_count() == 0:
				continue
			var arrays := mesh.surface_get_arrays(0)
			var colors := arrays[Mesh.ARRAY_COLOR] as PackedColorArray
			if colors.is_empty():
				continue
			var sum := Color()
			var dark := 0
			for c: Color in colors:
				sum += c
				if maxf(c.r, maxf(c.g, c.b)) < 0.09:
					dark += 1
			var avg := sum / float(colors.size())
			print(
				"%s:%d средний=%s тёмных=%.0f%%" % [
					type, variant, avg, 100.0 * dark / colors.size(),
				]
			)
	quit(0)
