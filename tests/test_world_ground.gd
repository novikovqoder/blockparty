# Тесты земли всего острова (доработка П5.13): чанки несут тангенты
# (нормал-мап земли требует их — без массива Forward+ роняет warning на
# каждый чанк и земля ломается), тангенты совпадают с аналитикой квадрата
# высот и с тем, что посчитал бы сам движок (SurfaceTool.generate_tangents
# по тем же вершинам и UV), а WorldSelfCheck проходит на запечённом мире:
# предметы не висят над землёй и не стоят под водой, вода — в чаше озера.
extends GutTest

const ISLAND: PackedScene = preload("res://gameplay/world/island.tscn")
const ART: IslandArt = preload("res://gameplay/world/island_art.res")

## Доля однонаправленности тангентов (косинус угла): mikktspace
## ортогонализует тангент к сглаженной нормали, у нас — фасетный к фасету;
## расхождение микроскопическое, но не нулевое.
const TANGENT_DOT: float = 0.98


const BU_LEGACY: Script = preload("res://tests/helpers/bu_flag.gd")


func before_all() -> void:
	BU_LEGACY.legacy_off()


func after_all() -> void:
	BU_LEGACY.legacy_restore()


func test_chunks_have_facet_tangents() -> void:
	# Каждый квад каждого чанка: массив ARRAY_TANGENT заполнен (4 float на
	# вершину), направление — аналитике dP/du = normalize(1, dh/dx, 0),
	# w = +1 (бинормаль движка cross(TANGENT, NORMAL)·w — вдоль dP/dv).
	var checked := 0
	for chunk: Mesh in ART.chunks:
		var arrays: Array = (chunk as ArrayMesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		assert_eq(
			tangents.size(), verts.size() * 4,
			"тангентов ровно 4 float на вершину")
		for vi: int in range(0, verts.size(), 4):
			var dy: float = (
				verts[vi + 2].y + verts[vi + 3].y
				- verts[vi].y - verts[vi + 1].y) * 0.5
			var expected := Vector3(1.0, dy, 0.0).normalized()
			for k: int in 4:
				var base: int = (vi + k) * 4
				var actual := Vector3(
					tangents[base], tangents[base + 1], tangents[base + 2])
				assert_almost_eq(
					actual.dot(expected), 1.0, 1.0 - TANGENT_DOT,
					"тангент квада вдоль dP/du (vi=%d k=%d)" % [vi, k])
				assert_almost_eq(
					tangents[base + 3], 1.0, 0.001,
					"бинормаль w = +1 (vi=%d k=%d)" % [vi, k])
				checked += 1
	assert_gt(checked, 200000, "тангенты проверены по всем чанкам")


func test_tangents_match_engine_surfacetool() -> void:
	# Сверка с движком: тот же чанк, собранный через SurfaceTool (вершины
	# и индексы один в один, UV = (x, z), нормали и тангенты — генераторами
	# движка), — generate_tangents() даёт то же направление и тот же знак w,
	# что записал TerrainBuilder. Если движок сменит конвенцию бинормали,
	# тест увидит расхождение первым.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261018
	var chunk: ArrayMesh = ART.chunks[rng.randi_range(0, ART.chunks.size() - 1)]
	var arrays: Array = chunk.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vi: int in verts.size():
		st.set_uv(Vector2(verts[vi].x, verts[vi].z))
		st.add_vertex(verts[vi])
	for ii: int in indices.size():
		st.add_index(indices[ii])
	var base_mesh := st.commit()
	var st2 := SurfaceTool.new()
	st2.append_from(base_mesh, 0, Transform3D())
	st2.generate_normals()
	st2.generate_tangents()
	var final_arrays: Array = st2.commit_to_arrays()
	var tool_verts: PackedVector3Array = final_arrays[Mesh.ARRAY_VERTEX]
	var tool_tangents: PackedFloat32Array = final_arrays[Mesh.ARRAY_TANGENT]
	# generate_normals() может пересобрать вершинность (раздуть дубликатами)
	# — сверяем через словарь позиций: дубликаты одного квада дают один
	# тангент, первого вхождения достаточно.
	var by_position: Dictionary = {}
	for j: int in tool_verts.size():
		if not by_position.has(tool_verts[j]):
			by_position[tool_verts[j]] = j
	var mismatch := 0
	var w_flip := 0
	var compared := 0
	for vi: int in range(0, verts.size(), 4):
		# Квад наш: все 4 тангента равны — берём первый.
		var mine := Vector3(
			tangents[vi * 4], tangents[vi * 4 + 1], tangents[vi * 4 + 2])
		var mine_w: float = tangents[vi * 4 + 3]
		var j: int = by_position.get(verts[vi], -1)
		if j < 0:
			continue
		compared += 1
		var theirs := Vector3(
			tool_tangents[j * 4], tool_tangents[j * 4 + 1],
			tool_tangents[j * 4 + 2])
		if theirs.dot(mine) < TANGENT_DOT:
			mismatch += 1
		if not is_equal_approx(tool_tangents[j * 4 + 3], mine_w):
			w_flip += 1
	assert_gt(compared, 900, "сверены почти все квадраты чанка")
	# Направление: mikktspace ортогонализует к сглаженной нормали —
	# на крутых изломах квадов чуть отличается от фасетного; допускаем
	# малую долю квадов с расхождением (не направления «в противоположные
	# стороны», а микросдвиг ортогонализации).
	assert_lt(float(mismatch) / maxf(compared, 1.0), 0.05,
		"направления тангентов совпадают с SurfaceTool (расхождений %d из %d)"
		% [mismatch, compared])
	assert_eq(w_flip, 0, "знаки бинормали w совпадают с SurfaceTool")


func test_world_self_check_passes() -> void:
	# Полная самопроверка мира на запечённой сцене — тот же код, что
	# --selftest-world в экспортированной сборке.
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	var result: Dictionary = WorldSelfCheck.run(island)
	for reason: String in result["reasons"]:
		print("SELFTEST-WORLD reason: %s" % reason)
	assert_true(result["ok"], "WorldSelfCheck проходит")
	assert_gt(result["metrics"]["props_checked"], 500,
		"проверено заметное число предметов")
	assert_eq(result["metrics"]["chunks"],
		TerrainBuilder.CHUNKS_PER_SIDE * TerrainBuilder.CHUNKS_PER_SIDE,
		"чанков — вся карта")
	# Дочистка П5.13: «белых квадратов» нет — каждый меш острова (включая
	# костёр, жителей, воду и частицы) несёт материал, заглушек не осталось.
	assert_gt(result["metrics"]["surfaces_checked"], 100,
		"материалы проверены по всему острову")
	assert_eq(result["metrics"]["surfaces_bare"], 0,
		"ни одной поверхности без материала")
	assert_eq(result["metrics"]["surfaces_placeholder"], 0,
		"ни одного белого албедо без текстуры")


func test_ground_y_interpolates_heightmap() -> void:
	# Билинейная высота самопроверки: в вершинах сетки — карта высот
	# один в один, в центре квада — среднее четырёх углов.
	for wx: float in [-100.0, -12.0, 0.0, 40.0, 120.0]:
		for wz: float in [-100.0, -3.0, 0.0, 55.0, 120.0]:
			var x0: int = floori(wx)
			var z0: int = floori(wz)
			var h: float = ART.heights[
				(z0 + IslandGen.HALF) * IslandGen.POINTS + x0 + IslandGen.HALF]
			assert_almost_eq(
				WorldSelfCheck.ground_y(ART.heights, wx, wz), h, 0.001,
				"в узле сетки высота один в один (%.0f, %.0f)" % [wx, wz])
	var h00: float = ART.heights[(0 + IslandGen.HALF) * IslandGen.POINTS + 0 + IslandGen.HALF]
	var h10: float = ART.heights[(0 + IslandGen.HALF) * IslandGen.POINTS + 1 + IslandGen.HALF]
	var h01: float = ART.heights[(1 + IslandGen.HALF) * IslandGen.POINTS + 0 + IslandGen.HALF]
	var h11: float = ART.heights[(1 + IslandGen.HALF) * IslandGen.POINTS + 1 + IslandGen.HALF]
	assert_almost_eq(
		WorldSelfCheck.ground_y(ART.heights, 0.5, 0.5),
		(h00 + h10 + h01 + h11) * 0.25, 0.001,
		"в центре квада — среднее углов")
