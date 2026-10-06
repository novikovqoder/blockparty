# Доказательство конвенции обхода вершин Godot (шаг 1 доработки П4.5):
# у заведомо видимых сверху примитивов движка (PlaneMesh, BoxMesh) и у чанка
# рельефа считаем ориентацию треугольника «правилом правой руки» —
# (b−a)×(c−a). Если знаки противоположны, рельеф намотан не по конвенции
# движка и отсекается как задняя сторона. Запуск:
#   godot --headless --path . -s res://tools/winding_probe.gd
extends SceneTree


func _init() -> void:
	_up_triangle("PlaneMesh (виден сверху)", PlaneMesh.new())
	_up_triangle("BoxMesh (верхняя грань)", BoxMesh.new())
	var art: IslandArt = load("res://gameplay/world/island_art.res") as IslandArt
	# Чанк над площадью: клетка (0,4) → cx=4, cz=4 из 8×8.
	var mesh: ArrayMesh = art.chunks[4 * 8 + 4] as ArrayMesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var found := 0
	for t: int in range(0, indices.size(), 3):
		var a: Vector3 = verts[indices[t]]
		var b: Vector3 = verts[indices[t + 1]]
		var c: Vector3 = verts[indices[t + 2]]
		var n: Vector3 = (b - a).cross(c - a).normalized()
		if n.y > 0.9 or n.y < -0.9:
			print("чанк рельефа: треугольник y∈[%.1f,%.1f] нормаль = %s"
				% [a.y, c.y, n])
			found += 1
			if found >= 3:
				break
	quit()


## Первый почти горизонтальный треугольник примитива и его «правовинтовая»
## нормаль: знак говорит, какой обход считает лицевым движок.
func _up_triangle(tag: String, prim: PrimitiveMesh) -> void:
	var arrays: Array = prim.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for t: int in range(0, indices.size(), 3):
		var a: Vector3 = verts[indices[t]]
		var b: Vector3 = verts[indices[t + 1]]
		var c: Vector3 = verts[indices[t + 2]]
		var n: Vector3 = (b - a).cross(c - a).normalized()
		if absf(n.y) > 0.9:
			print("%s: треугольник y=%.1f нормаль = %s" % [tag, a.y, n])
			return
