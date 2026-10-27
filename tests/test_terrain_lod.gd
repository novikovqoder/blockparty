# Доработка-2 П5.13, П1 — рельеф: адаптивная тесселяция и гладкие нормали.
# Требование владельца: сетка ~0.5 м вблизи игрока, дальше плавно крупнее,
# БЕЗ видимых переходов. Проверяется численно:
#   - ближний чанк (TerrainBuilder.build_near_chunk) — квад 0.5 м:
#     максимальное ребро треугольника в радиусе 50 м от зрителя ≤ порога,
#     вершины лежат на билинейной поверхности карты высот;
#   - стык уровней детализации без щелей: вершины ближнего чанка на общем
#     ребре с печёным 1-метровым лежат на его рёбрах (трещин нет);
#   - нормали — гладкие: единичные, из карт производных высот (не зависят
#     от шага сетки, на границе двух ближних чанков совпадают), соседние
#     вершины пологого участка отличаются слабо;
#   - IslandView.update_viewer перестраивает чанки вокруг зрителя
#     (в радиусе LOD_RADIUS — 0.5 м, дальше — печёные) и возвращает
#     печёные при удалении;
#   - сглаживание карты высот (IslandGen._smooth_pass) гасит рябь,
#     не трогая линейные склоны и крутые кромки.
extends GutTest

const ART: IslandArt = preload("res://gameplay/world/island_art.res")
const ISLAND: PackedScene = preload("res://gameplay/world/island.tscn")

## Порог максимального ребра треугольника в радиусе 50 м, м: катеты 0.5 —
## гипотенуза 0.707, запас на округления.
const NEAR_EDGE_MAX: float = 0.75
## Ребро печёного (1 м) уровня.
const FAR_EDGE_MAX: float = 1.45
## Разница нормалей соседних вершин пологого участка (полный угол).
const SMOOTH_NORMAL_MAX: float = 0.35
## Число вершин чанков: ближний — сетка 65 × 65, печёный — 32 × 32 квадрата.
const NEAR_VERTICES: int = 65 * 65
const FAR_VERTICES: int = TerrainBuilder.CHUNK * TerrainBuilder.CHUNK * 4

static var _maps_cache: Dictionary = {}


func _maps() -> Dictionary:
	if _maps_cache.is_empty():
		_maps_cache = TerrainBuilder.slope_maps(ART.heights)
	return _maps_cache


func _near_mesh(cx: int, cz: int) -> ArrayMesh:
	return TerrainBuilder.build_near_chunk(
		ART.heights, _maps(),
		ART.chunks[cz * TerrainBuilder.CHUNKS_PER_SIDE + cx] as ArrayMesh,
		cx, cz)


## Квадраты чанка: размер треугольника — горизонтальная проекция рёбер
## (тесселяция сетки; вертикальная составляющая ребра — это сам рельеф,
## у террасной кромки она по определению велика и сетку не характеризует).
func _max_edge(mesh: ArrayMesh) -> float:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var worst := 0.0
	for t: int in range(0, indices.size(), 3):
		for pair: Vector2i in [
			Vector2i(indices[t], indices[t + 1]),
			Vector2i(indices[t + 1], indices[t + 2]),
			Vector2i(indices[t + 2], indices[t]),
		]:
			var a: Vector3 = verts[pair.x]
			var b: Vector3 = verts[pair.y]
			worst = maxf(worst, Vector2(b.x - a.x, b.z - a.z).length())
	return worst


func test_near_chunk_triangle_size() -> void:
	# Площадь (0, 4) — чанк 4 × 5 (x ∈ [0, 32], z ∈ [32, 64]); холм (−58, 42)
	# — чанк 2 × 5; Лес (−52, −52) — чанк 2 × 2. Все ближние чанки — квад
	# 0.5 м, максимальное ребро (гипотенуза) ≤ NEAR_EDGE_MAX.
	for cell: Vector2i in [Vector2i(4, 5), Vector2i(2, 5), Vector2i(2, 2)]:
		var mesh := _near_mesh(cell.x, cell.y)
		assert_almost_eq(_max_edge(mesh), 0.7071, 0.02,
			"чанк (%d, %d): диагональ квада 0.5 м" % [cell.x, cell.y])
		assert_lt(_max_edge(mesh), NEAR_EDGE_MAX,
			"чанк (%d, %d): максимальный треугольник ≤ порога вблизи игрока"
			% [cell.x, cell.y])


func test_far_chunks_stay_coarse() -> void:
	# Дальние чанки — печёные 1-метровые: диагональ квада 1 м (уровень
	# «дальше плавно крупнее», но не грубее прежней сетки всего острова).
	var mesh: ArrayMesh = ART.chunks[0]
	assert_almost_eq(_max_edge(mesh), sqrt(2.0), 0.05,
		"печёный чанк — квад 1 м")
	assert_lt(_max_edge(mesh), FAR_EDGE_MAX, "печёный чанк не грубее 1 м")


func test_near_chunk_follows_heightmap() -> void:
	# Каждая вершина ближнего чанка — на билинейной поверхности карты
	# высот: геометрия не «выдумана», это та же функция рельефа.
	var arrays: Array = _near_mesh(4, 5).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), NEAR_VERTICES, "сетка 65 × 65 вершин (шаг 0.5 м)")
	for i: int in range(0, verts.size(), 97):  # выборка ~282 вершин
		var expected: float = TerrainBuilder.height_at(
			ART.heights, verts[i].x, verts[i].z)
		assert_almost_eq(verts[i].y, expected, 0.001,
			"вершина %d на билинейной высоте карты" % i)


func test_no_cracks_between_lod_levels() -> void:
	# Стык уровней: ближний чанк (4, 5) примыкает западным ребром x = 0
	# к печёному чанку (3, 5) (x ∈ [−32, 0], z ∈ [32, 64]). Вершины ближнего
	# на ребре делят рёбра печёных квадратов ровно пополам, а высота
	# середины ребра печёного квада — среднее высот его концов (ребро
	# линейно) — обязана совпадать с билинейной высотой карты в этой
	# точке: иначе на стыке щель.
	var near := _near_mesh(4, 5)
	var near_arrays: Array = near.surface_get_arrays(0)
	var near_verts: PackedVector3Array = near_arrays[Mesh.ARRAY_VERTEX]
	var baked: Array = (ART.chunks[5 * TerrainBuilder.CHUNKS_PER_SIDE + 3]
		as ArrayMesh).surface_get_arrays(0)
	var baked_verts: PackedVector3Array = baked[Mesh.ARRAY_VERTEX]
	# Печёный чанк (3, 5): квадраты по строкам z ∈ [32, 64); столбец x = −1
	# (последний, 31-й) выходит на ребро x = 0 вершинами v2 (0, z+1) и
	# v3 (0, z). Середина ребра v2–v3 — среднее высот карты по узлам.
	for z0: int in range(32, 64):
		var square: int = (z0 - 32) * TerrainBuilder.CHUNK + 31
		var bottom: Vector3 = baked_verts[square * 4 + 3]   # (0, z0)
		var top: Vector3 = baked_verts[square * 4 + 2]      # (0, z0+1)
		assert_almost_eq(bottom.y,
			ART.heights[IslandGen._idx(0, z0)], 0.0001,
			"печёная вершина (0, %d) на узле карты" % z0)
		var midpoint: float = bottom.lerp(top, 0.5).y
		var expected: float = TerrainBuilder.height_at(
			ART.heights, 0.0, float(z0) + 0.5)
		assert_almost_eq(midpoint, expected, 0.001,
			"середина ребра печёного квада (0, %d) на высоте карты" % z0)
	# Вершины ближнего чанка на линии x = 0: 65 штук с шагом 0.5 м, каждая
	# на билинейной высоте карты — той же функции, что у печёного ребра.
	var found := 0
	for vertex: Vector3 in near_verts:
		if absf(vertex.x) < 0.001 and vertex.z >= 32.0 and vertex.z <= 64.0:
			var expected: float = TerrainBuilder.height_at(
				ART.heights, 0.0, vertex.z)
			assert_almost_eq(vertex.y, expected, 0.001,
				"вершина ближнего чанка на границе — высота карты")
			found += 1
	assert_eq(found, 65, "на границе чанка 65 вершин с шагом 0.5 м")


func test_normals_smooth_and_from_heightmap() -> void:
	# Нормали ближнего чанка: единичные и совпадают с картой производных
	# высот (terrain.slope_maps) — тем же полем, что и у соседних чанков,
	# поэтому на границе двух ближних чанков нормали совпадают (нет шва
	# освещения). Гладкость: на пологом участке соседние точки отличаются
	# слабо — фасетной огранки нет.
	var arrays: Array = _near_mesh(4, 5).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var maps := _maps()
	for i: int in range(0, verts.size(), 131):
		assert_almost_eq(normals[i].length(), 1.0, 0.001,
			"нормаль %d единичная" % i)
		var expected: Vector3 = TerrainBuilder.normal_from_maps(
			maps, verts[i].x, verts[i].z)
		assert_almost_eq(normals[i].dot(expected), 1.0, 0.001,
			"нормаль %d — карта производных высот" % i)
	# Граница ближних чанков (4, 5) и (5, 5) — ребро x = 32: вершины обоих
	# чанков на одном ребре обязаны иметь равные нормали (общее поле
	# производных, без огранки по чанкам).
	var east_arrays: Array = _near_mesh(5, 5).surface_get_arrays(0)
	var east_verts: PackedVector3Array = east_arrays[Mesh.ARRAY_VERTEX]
	var east_normals: PackedVector3Array = east_arrays[Mesh.ARRAY_NORMAL]
	var east_by_z: Dictionary = {}
	for i: int in east_verts.size():
		if absf(east_verts[i].x - 32.0) < 0.001:
			east_by_z[snappedf(east_verts[i].z, 0.001)] = east_normals[i]
	var compared := 0
	for i: int in verts.size():
		if absf(verts[i].x - 32.0) < 0.001:
			var other: Vector3 = east_by_z.get(
				snappedf(verts[i].z, 0.001), Vector3.ZERO)
			assert_almost_eq(normals[i].dot(other), 1.0, 0.001,
				"нормали на ребре x=32 (z=%.1f) совпадают" % verts[i].z)
			compared += 1
	assert_eq(compared, 65, "на ребре сравнено 65 вершин")
	# Гладкость: пологий участок (уклон < 0.15) — соседи по 0.5 м
	# отличаются слабо; считаем по самой карте производных.
	var smooth_pairs := 0
	var worst_angle := 0.0
	for z: float in range(-10, 10):
		for x: float in range(-10, 10):
			var here: Vector3 = TerrainBuilder.normal_from_maps(maps, x, z)
			var east: Vector3 = TerrainBuilder.normal_from_maps(maps, x + 0.5, z)
			var slope: float = absf(
				TerrainBuilder.height_at(ART.heights, x + 1.0, z)
				- TerrainBuilder.height_at(ART.heights, x - 1.0, z)) * 0.5
			if slope > 0.15:
				continue
			var angle: float = here.angle_to(east)
			worst_angle = maxf(worst_angle, angle)
			smooth_pairs += 1
	assert_gt(smooth_pairs, 100, "пологих пар для проверки достаточно")
	assert_lt(worst_angle, SMOOTH_NORMAL_MAX,
		"нормали пологого участка гладкие (худший угол %.3f рад)" % worst_angle)


func test_viewer_lod_switch() -> void:
	# IslandView.update_viewer: чанки в радиусе LOD_RADIUS от зрителя —
	# ближние (65 × 65 вершин), дальние — печёные; при удалении зрителя
	# ближние возвращаются к печёным. Гистерезис: сразу за границей
	# радиуса чанк остаётся ближним.
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	var view := island.get_node("IslandView") as IslandView
	island.update_viewer(Vector3(0.0, 2.0, 4.0))
	var terrain := view.get_node("Terrain")
	var near_chunks := 0
	var far_chunks := 0
	for child: Node in terrain.get_children():
		# П15 9.1: береговая полоса (ShoreBand) — не чанк, у неё своя
		# густая сетка 0.25 м; в подсчёт уровней чанков не входит.
		if child is MeshInstance3D and child.name == "ShoreBand":
			continue
		if child is MeshInstance3D:
			var count: int = (child as MeshInstance3D).mesh.surface_get_arrays(
				0)[Mesh.ARRAY_VERTEX].size()
			if count == NEAR_VERTICES:
				near_chunks += 1
			else:
				assert_eq(count, FAR_VERTICES, "дальний чанк — печёный 1 м")
				far_chunks += 1
	# Спавн (0, 4): ближние — чанки с центрами ближе 50 м: семь штук
	# (столбцы центров x = −16/16/48, строки z = −16/16/48).
	assert_between(near_chunks, 6, 12,
		"вокруг спавна ближних чанков 0.5 м — заметное кольцо (факт %d)" % near_chunks)
	assert_eq(near_chunks + far_chunks,
		TerrainBuilder.CHUNKS_PER_SIDE * TerrainBuilder.CHUNKS_PER_SIDE,
		"чанков столько же, сколько было")
	# Гистерезис: зритель чуть дальше радиуса — ближние не сбрасываются
	# мгновенно (стоя на границе, рельеф не мигает).
	island.update_viewer(Vector3(52.0, 2.0, 4.0))
	var still_near := 0
	for child: Node in terrain.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh \
				.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == NEAR_VERTICES:
			still_near += 1
	assert_gt(still_near, 0, "гистерезис держит ближний уровень у границы")
	# Зритель ушёл в угол (120, 120): чанки вокруг спавна обязаны вернуться
	# к печёным (проверяем чанк площади — центр (16, 16), индекс cz·8+cx),
	# а вокруг новой позиции появляются ближние.
	island.update_viewer(Vector3(120.0, 2.0, 120.0))
	# Индекс чанка (4, 4) — 4·8+4 = 36; дети Terrain: CollisionShape3D + 64.
	var spawn_index: int = 1 + 4 * TerrainBuilder.CHUNKS_PER_SIDE + 4
	var spawn_mesh: Mesh = (terrain.get_child(spawn_index) as MeshInstance3D).mesh
	assert_eq(spawn_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(),
		FAR_VERTICES, "чанк площади после отъезда зрителя снова печёный")
	var corner_near := 0
	for child: Node in terrain.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh \
				.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == NEAR_VERTICES:
			corner_near += 1
	assert_gt(corner_near, 0, "вокруг новой позиции есть ближние чанки")


func test_smooth_pass_calms_ripple_keeps_forms() -> void:
	# Сглаживание карты высот (IslandGen._smooth_pass) на синтетике:
	#   линейный склон (плоскость) не меняется вовсе — форма холмов,
	#     записанная равномерным градиентом, сохраняется;
	#   высокочастотная рябь (амплитуда как у ряби эрозии на склонах
	#     острова) гасится — остаточный размах < половины;
	#   крутая кромка (перепад ≥ MAX_STEP) не размывается.
	var plane := PackedFloat32Array()
	plane.resize(IslandGen.POINTS * IslandGen.POINTS)
	var ripple := PackedFloat32Array()
	ripple.resize(plane.size())
	var cliff := PackedFloat32Array()
	cliff.resize(plane.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261018
	for z: int in range(-IslandGen.HALF, IslandGen.HALF + 1):
		for x: int in range(-IslandGen.HALF, IslandGen.HALF + 1):
			var i: int = (z + IslandGen.HALF) * IslandGen.POINTS + x + IslandGen.HALF
			var slope: float = float(x) * 0.4  # склон 14 м на сторону
			plane[i] = slope
			ripple[i] = slope + rng.randf_range(-0.25, 0.25)
			cliff[i] = 1.0 if x < 20 else 10.0
	var plane_before := plane.duplicate()
	var ripple_before := ripple.duplicate()
	var cliff_before := cliff.duplicate()
	IslandGen._smooth_pass(plane)
	IslandGen._smooth_pass(ripple)
	IslandGen._smooth_pass(cliff)
	var plane_worst := 0.0
	for i: int in plane.size():
		plane_worst = maxf(plane_worst, absf(plane[i] - plane_before[i]))
	var ripple_stats := func(before: PackedFloat32Array,
			after: PackedFloat32Array) -> float:
		# Типичная рябь: среднее отклонение высоты от среднего соседей
		# (внутренние точки). Максимум не годится: худшие точки ряби —
		# самые «крутые», а у крутых перепадов сглаживание сознательно
		# гашено (защита кромок) — метрика обязана измерять рябь,
		# а не обрывы.
		var total := 0.0
		var count := 0
		for z: int in range(-IslandGen.HALF + 1, IslandGen.HALF):
			for x: int in range(-IslandGen.HALF + 1, IslandGen.HALF):
				var idx: int = (z + IslandGen.HALF) * IslandGen.POINTS + x + IslandGen.HALF
				var avg: float = (
					before[(z - 1 + IslandGen.HALF) * IslandGen.POINTS + x - 1 + IslandGen.HALF]
					+ before[(z + IslandGen.HALF) * IslandGen.POINTS + x - 1 + IslandGen.HALF]
					+ before[(z + 1 + IslandGen.HALF) * IslandGen.POINTS + x - 1 + IslandGen.HALF]
					+ before[(z - 1 + IslandGen.HALF) * IslandGen.POINTS + x + IslandGen.HALF]
					+ before[(z + 1 + IslandGen.HALF) * IslandGen.POINTS + x + IslandGen.HALF]
					+ before[(z - 1 + IslandGen.HALF) * IslandGen.POINTS + x + 1 + IslandGen.HALF]
					+ before[(z + IslandGen.HALF) * IslandGen.POINTS + x + 1 + IslandGen.HALF]
					+ before[(z + 1 + IslandGen.HALF) * IslandGen.POINTS + x + 1 + IslandGen.HALF]
				) / 8.0
				total += absf(after[idx] - avg)
				count += 1
		return total / float(count)
	var ripple_before_range: float = ripple_stats.call(ripple_before, ripple_before)
	var ripple_after_range: float = ripple_stats.call(ripple_before, ripple)
	assert_almost_eq(plane_worst, 0.0, 0.02,
		"равномерный склон сглаживанием не тронут")
	assert_lt(ripple_after_range, ripple_before_range * 0.5,
		"рябь после прохода тише вдвое (%.3f < %.3f)" % [
			ripple_after_range, ripple_before_range])
	var cliff_worst := 0.0
	for i: int in cliff.size():
		cliff_worst = maxf(cliff_worst, absf(cliff[i] - cliff_before[i]))
	assert_lt(cliff_worst, 0.05, "крутая кромка не размывается")


func test_near_chunk_deterministic() -> void:
	# Детерминизм: два построения ближнего чанка дают равные вершины.
	var first: PackedVector3Array = _near_mesh(4, 5).surface_get_arrays(0)[
		Mesh.ARRAY_VERTEX]
	var second: PackedVector3Array = _near_mesh(4, 5).surface_get_arrays(0)[
		Mesh.ARRAY_VERTEX]
	assert_eq(first, second, "повторная сборка ближнего чанка равна")
