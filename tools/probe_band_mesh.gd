# Пробник береговой полосы (П15 блок 4): godot --headless -s
# tools/probe_band_mesh.gd — размер/время меша, отклонение вершин от
# коллизии HeightMapShape3D (raycast) и шаг сетки.
extends SceneTree


func _init() -> void:
	var art: IslandArt = load("res://gameplay/world/island_art.res")
	var t0: int = Time.get_ticks_msec()
	var mesh := ShoreBand.build_band_mesh(art, IslandGen.SEA_LEVEL)
	print("band build ms=%d" % (Time.get_ticks_msec() - t0))
	var surface: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = surface[Mesh.ARRAY_INDEX]
	print("verts=%d tris=%d" % [verts.size(), idx.size() / 3])

	# Шаг сетки: горизонтальная проекция рёбер подквадов — 0.25 м
	# (3D-расстояние на обрывах больше — там честный склон).
	var worst_step: float = 0.0
	for i: int in range(0, idx.size(), 3):
		var a: Vector3 = verts[idx[i]]
		var b: Vector3 = verts[idx[i + 1]]
		worst_step = maxf(worst_step,
			absf(Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) - 0.25))
	print("worst step diff=%.4f" % worst_step)
	var h_min: float = INF
	var h_max: float = -INF
	for v: Vector3 in verts:
		h_min = minf(h_min, v.y)
		h_max = maxf(h_max, v.y)
	print("band y range: %.2f..%.2f" % [h_min, h_max])

	# Отклонение от коллизии: физическая сцена с HeightMapShape3D.
	var root := Node3D.new()
	get_root().add_child(root)
	var body := StaticBody3D.new()
	root.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = IslandGen.POINTS
	shape.map_depth = IslandGen.POINTS
	shape.map_data = art.heights
	collision.shape = shape
	body.add_child(collision)
	# Физике нужен кадр для активации пространства.
	await process_frame
	await process_frame
	var space := root.get_world_3d().direct_space_state
	var worst_up: float = 0.0
	var worst_down: float = 0.0
	var step: int = maxi(1, verts.size() / 3000)
	for i: int in range(0, verts.size(), step):
		var v: Vector3 = verts[i]
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(v.x, v.y + 2.0, v.z), Vector3(v.x, v.y - 2.0, v.z))
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var delta: float = v.y - float(hit.position.y)
		if delta >= 0.0:
			worst_up = maxf(worst_up, delta)
		else:
			worst_down = minf(worst_down, delta)
	print("collision delta: up=%.3f down=%.3f (проверено %d)"
		% [worst_up, worst_down, (verts.size() + step - 1) / step])
	quit(0)
