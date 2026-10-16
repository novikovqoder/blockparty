# Одноразовая диагностика (П5.8 A1 → П5.9): какие вершинные цвета дают
# рантайм-меши — средняя яркость/оттенок по типу предмета. Чёрный средний
# цвет = фон атласа попал в вершины (листва без альфа-вырезки); у деревьев
# TreeGen печатаются обе поверхности (кора и крона).
# Запуск: godot --headless -s tools/dump_prop_colors.gd
extends SceneTree


func _initialize() -> void:
	var types := [
		&"etree_oak", &"etree_giant", &"etree_bush", &"rrock", &"dead_log",
		&"rgrass", &"fern", &"tree_leafy", &"tree_spruce",
	]
	for type in types:
		for variant: int in 4:
			var mesh := PropMeshes.mesh(type, variant)
			if mesh == null or mesh.get_surface_count() == 0:
				continue
			for surface: int in mesh.get_surface_count():
				_dump(type, variant, surface, mesh.surface_get_arrays(surface))
	quit(0)


func _dump(type: StringName, variant: int, surface: int, arrays: Array) -> void:
	var colors := arrays[Mesh.ARRAY_COLOR] as PackedColorArray
	if colors.is_empty():
		return
	var sum := Color()
	var dark := 0
	for c: Color in colors:
		sum += c
		if maxf(c.r, maxf(c.g, c.b)) < 0.09:
			dark += 1
	var avg := sum / float(colors.size())
	print(
		"%s:%d/%d средний=%s тёмных=%.0f%%" % [
			type, variant, surface, avg, 100.0 * dark / colors.size(),
		]
	)
