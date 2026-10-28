# Пробник П15-ДОП2 п. 4: числа вокруг кромки (запуск: godot --headless
# -s tools/probe_band.gd). Печатает перепады клеток, релакс, высоты
# полосы/чанков/коллизии вдоль линии сетки 0.25 м.
extends SceneTree

const ART: IslandArt = preload("res://gameplay/world/island_art.res")


func _initialize() -> void:
	var heights: PackedFloat32Array = ART.heights
	var mesh := ShoreBand.build_band_mesh(ART, IslandGen.SEA_LEVEL)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[
		Mesh.ARRAY_VERTEX]
	var by_key: Dictionary = {}
	for v: Vector3 in verts:
		by_key[Vector2i(roundi(v.z * 4.0), roundi(v.x * 4.0))] = v.y
	# 1) Худшие вторые разности на полном релаксе (как в тесте).
	var worst: Array = [0.0, Vector2.ZERO]
	for z4: int in range(-IslandGen.HALF * 4, IslandGen.HALF * 4):
		for x4: int in range(-IslandGen.HALF * 4 + 1,
				IslandGen.HALF * 4 - 1):
			if not (by_key.has(Vector2i(z4, x4))
					and by_key.has(Vector2i(z4, x4 - 1))
					and by_key.has(Vector2i(z4, x4 + 1))):
				continue
			var x: float = float(x4) / 4.0
			var z: float = float(z4) / 4.0
			if ShoreBand.cell_relax(heights, x, z) < 0.999:
				continue
			var second: float = absf(float(by_key[Vector2i(z4, x4 + 1)])
				- 2.0 * float(by_key[Vector2i(z4, x4)])
				+ float(by_key[Vector2i(z4, x4 - 1)]))
			if second > worst[0]:
				worst = [second, Vector2(x, z)]
	print("worst 2nd diff full-relax: %.3f at %s" % [worst[0], worst[1]])
	# 2) Разбор худшего места: клетка, соседи, высоты.
	var at: Vector2 = worst[1]
	var cx: int = floori(at.x)
	var cz: int = floori(at.y)
	print(("cell (%d, %d) drop %.2f relax %.3f; west drop %.2f relax %.3f;"
		+ " east drop %.2f relax %.3f") % [
		cx, cz, ShoreBand.cell_drop(heights, cx, cz),
		ShoreBand.cell_relax(heights, at.x, at.y),
		ShoreBand.cell_drop(heights, cx - 1, cz),
		ShoreBand.cell_relax(heights, at.x - 1.0, at.y),
		ShoreBand.cell_drop(heights, cx + 1, cz),
		ShoreBand.cell_relax(heights, at.x + 1.0, at.y)])
	for dxc: int in [-6, -4, -2, -1, 0, 1, 2, 4, 6]:
		var x: float = at.x + float(dxc) * 0.25
		var z: float = at.y
		var key: Vector2i = Vector2i(roundi(z * 4.0), roundi(x * 4.0))
		var has: bool = by_key.has(key)
		var h_band: float = float(by_key.get(key, NAN))
		var tri: float = ShoreBand.tri_height(heights, x, z)
		var bil: float = ShoreBand.bilinear_height(heights, x, z)
		var col: float = ShoreBand.collision_height(heights, x, z)
		var relax: float = ShoreBand.cell_relax(heights, x, z)
		var blend_and_more: float = ShoreBand.cubic_height(heights, x, z)
		print(("dx=%+0.2f x=%7.2f relax=%.3f band=%s tri=%7.3f bil=%7.3f"
			+ " col=%7.3f cubic=%7.3f") % [
			float(dxc) * 0.25, x, relax,
			("%7.3f" % h_band) if has else "  ---- ", tri, bil, col,
			blend_and_more])
	# 3) Сколько вершин ниже чанков при полном релаксе (и насколько).
	var worst_floor: float = 0.0
	var worst_floor_at: Vector2 = Vector2.ZERO
	var full: int = 0
	for v: Vector3 in verts:
		if ShoreBand.cell_relax(heights, v.x, v.z) < 0.999:
			continue
		full += 1
		var tri: float = ShoreBand.tri_height(heights, v.x, v.z)
		var bil: float = ShoreBand.bilinear_height(heights, v.x, v.z)
		var below: float = maxf(tri - v.y, bil - v.y)
		if below > worst_floor:
			worst_floor = below
			worst_floor_at = Vector2(v.x, v.z)
	print("full-relax verts: %d; worst below chunk/bil: %.3f at %s" % [
		full, worst_floor, worst_floor_at])
	# 4) Распределение |tri − col| на клетках полосы.
	var mask := ShoreBand.band_mask(ART, IslandGen.SEA_LEVEL)
	var faces: int = IslandGen.POINTS - 1
	var worst_skew: float = 0.0
	var relax_at_skew: float = 0.0
	for fz: int in faces:
		for fx: int in faces:
			if mask[fz * faces + fx] == 0:
				continue
			var tri_c: float = ShoreBand.tri_height(heights,
				float(fx - IslandGen.HALF) + 0.5,
				float(fz - IslandGen.HALF) + 0.5)
			var col_c: float = ShoreBand.collision_height(heights,
				float(fx - IslandGen.HALF) + 0.5,
				float(fz - IslandGen.HALF) + 0.5)
			var skew: float = absf(tri_c - col_c)
			if skew > worst_skew:
				worst_skew = skew
				relax_at_skew = ShoreBand.cell_relax(heights,
					float(fx - IslandGen.HALF) + 0.5,
					float(fz - IslandGen.HALF) + 0.5)
	print("worst |tri−col| in band cells: %.3f (relax there %.3f)"
		% [worst_skew, relax_at_skew])
	quit()
