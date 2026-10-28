# П15-ДОП2, п. 1 «Дно моря плавно до горизонта»: юбка морского дна.
# Дно за краем карты существует и уходит к горизонту: глубина монотонно
# растёт от края карты по гладкой кривой без уступов, на стыке с картой —
# та же высота и наклон (шва нет), юбка без коллизии и тени; ползунки F3
# меняют склон, «Скопировать значения» печатает константы юбки. Карта
# высот острова не меняется (контроль — test_water3).
extends GutTest

const ART: IslandArt = preload("res://gameplay/world/island_art.res")
## Границы колец юбки (полустороны, м) и край — из SeafloorSkirt.RINGS.
const RING_EDGES: Array[float] = [128.0, 136.0, 152.0, 176.0, 256.0, 384.0,
	640.0]


func test_seafloor_built_in_view() -> void:
	# Юбка строится вместе с рельефом: меш непустой, тени нет, коллизии
	# нет, уходит до края последнего кольца. _build_terrain вызывается
	# напрямую — пропсы и наполнение к юбке не относятся (весь мир в
	# test_island_scene).
	var view := IslandView.new()
	view.art = ART
	view._build_terrain()
	var skirt := view.get_node_or_null("SeafloorSkirt") as SeafloorSkirt
	assert_not_null(skirt, "юбка дна построена с рельефом")
	if skirt == null:
		view.free()
		return
	assert_true(skirt.mesh.get_surface_count() > 0, "меш юбки непустой")
	var arrays: Array = skirt.mesh.surface_get_arrays(0)
	assert_true((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		> 1000, "вершин больше тысячи")
	assert_true((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		> 6000, "квадов больше трёх тысяч")
	assert_eq(skirt.cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"юбка не отбрасывает тень")
	assert_true(skirt.get_children().is_empty(),
		"у юбки нет детей — коллизии нет")
	assert_almost_eq(skirt.mesh.get_aabb().position.y,
		-SeafloorSkirt.FAR_DEPTH_M, 0.01,
		"глубина юбки — до ровного дна вдали")
	var aabb: AABB = skirt.mesh.get_aabb()
	assert_almost_eq(aabb.position.x, -640.0, 0.01, "юбка доходит до −640 м")
	assert_almost_eq(aabb.end.x, 640.0, 0.01, "юбка доходит до +640 м")
	view.free()


func test_height_monotonic_smooth_to_horizon() -> void:
	# От края карты к горизонту глубина только растёт, а наклон нигде не
	# превышает теоретический максимум quintic smoothstep
	# (15/8·перепад/шельф в середине) — уступов и изломов нет.
	var shelf: float = SeafloorSkirt.SHELF_M
	var far: float = SeafloorSkirt.FAR_DEPTH_M
	var max_slope: float = 15.0 / 8.0 * (far + IslandGen.SEA_FLOOR) / shelf
	# Четыре стороны и диагональ: вдоль каждой чебышевское расстояние
	# за край равно смещению от края.
	var inner: Vector2 = Vector2(37.0, -53.0)
	for from_edge: Vector2 in [
		Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0),
		Vector2(0.0, -1.0), Vector2(1.0, 1.0),
	]:
		var edge_mask: Vector2 = Vector2(
			absf(from_edge.x), absf(from_edge.y))
		var anchor: Vector2 = from_edge * float(IslandGen.HALF) \
			+ (Vector2.ONE - edge_mask) * inner
		var prev: float = SeafloorSkirt.height_at(
			anchor.x, anchor.y, shelf, far)
		for d: int in range(1, 512):
			var p: Vector2 = anchor + from_edge * float(d)
			var h: float = SeafloorSkirt.height_at(p.x, p.y, shelf, far)
			assert_true(h <= prev + 1e-4,
				"глубина не поднимается (сторона %s, d=%d)"
				% [from_edge, d])
			assert_true(prev - h <= max_slope + 1e-4,
				"наклон не круче smoothstep-максимума (сторона %s, d=%d)"
				% [from_edge, d])
			prev = h
		assert_almost_eq(prev, -far, 1e-4,
			"вдали — ровное дно (сторона %s)" % [from_edge])


func test_seam_matches_map_border() -> void:
	# Стык с картой: высота юбки на краю равна высоте узлов края (дно
	# карты ровно SEA_FLOOR), наклон у шва почти ноль — шва не видно.
	var heights: PackedFloat32Array = ART.heights
	var shelf: float = SeafloorSkirt.SHELF_M
	var far: float = SeafloorSkirt.FAR_DEPTH_M
	var worst_h: float = 0.0
	for i: int in range(0, IslandGen.POINTS, 16):
		var c: float = float(i - IslandGen.HALF)
		for edge: Vector2 in [Vector2(1.0, 0.0), Vector2(0.0, 1.0)]:
			var x: float = edge.x * float(IslandGen.HALF) + edge.y * c
			var z: float = edge.y * float(IslandGen.HALF) + edge.x * c
			var node: int = (int(z) + IslandGen.HALF) * IslandGen.POINTS \
				+ int(x) + IslandGen.HALF
			worst_h = maxf(worst_h, absf(SeafloorSkirt.height_at(
				x, z, shelf, far) - heights[node]))
	assert_true(worst_h <= 0.05,
		"стык по высоте ≤5 см, факт %.3f м" % worst_h)
	# Наклон у шва: дно карты у края плоское (наклон 0), кривая юбки C² —
	# на первых двух метрах (первый квад юбки) наклон ≤0.02 м/м, у самого
	# шва почти ноль: излома в стыке нет.
	for pair: Array in [
		[Vector2(130.0, 40.0), Vector2(128.0, 40.0)],
		[Vector2(-60.0, -130.0), Vector2(-60.0, -128.0)],
		[Vector2(128.5, -90.0), Vector2(128.0, -90.0)],
	]:
		var a: Vector2 = pair[0]
		var b: Vector2 = pair[1]
		var slope: float = absf(
			SeafloorSkirt.height_at(a.x, a.y, shelf, far)
			- SeafloorSkirt.height_at(b.x, b.y, shelf, far)) \
			/ a.distance_to(b)
		assert_true(slope <= 0.02,
			"наклон у шва ≤0.02 м/м (%s), факт %.4f" % [a, slope])
	# Внутри карты юбка не поднимается выше дна.
	assert_almost_eq(SeafloorSkirt.height_at(0.0, 0.0, shelf, far),
		IslandGen.SEA_FLOOR, 1e-6, "внутри карты — уровень дна карты")


func test_mesh_rings_without_holes() -> void:
	# Кольца покрывают всё от края карты до горизонта без дыр: на каждой
	# границе кольца есть вершины, ни один квад не заходит внутрь карты.
	var mesh := SeafloorSkirt.build_mesh(
		ART.heights, SeafloorSkirt.SHELF_M, SeafloorSkirt.FAR_DEPTH_M)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[
		Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = mesh.surface_get_arrays(0)[
		Mesh.ARRAY_INDEX]
	var cheb_from: Array[float] = []
	cheb_from.resize(verts.size())
	for i: int in verts.size():
		cheb_from[i] = maxf(absf(verts[i].x), absf(verts[i].z))
	for edge: float in RING_EDGES:
		var found: bool = false
		for value: float in cheb_from:
			if absf(value - edge) < 0.01:
				found = true
				break
		assert_true(found, "на границе %d м есть вершины" % edge)
	var min_cheb: float = 1e9
	for t: int in range(0, indices.size(), 3):
		var tri_cheb: float = minf(cheb_from[indices[t]],
			minf(cheb_from[indices[t + 1]], cheb_from[indices[t + 2]]))
		min_cheb = minf(min_cheb, tri_cheb)
	assert_true(min_cheb >= float(IslandGen.HALF) - 0.01,
		"квады не заходят внутрь карты, минимум чебышев %.2f" % min_cheb)


func test_slope_rebuild_and_clamps() -> void:
	# Ползунок склона пересобирает меш; экстремальные значения не рвут
	# геометрию (ширина и глубина ограничены снизу).
	var skirt := SeafloorSkirt.new()
	skirt.setup(ART.heights)
	add_child_autofree(skirt)
	assert_almost_eq(skirt.mesh.get_aabb().position.y,
		-SeafloorSkirt.FAR_DEPTH_M, 0.01, "номинал — глубина константы")
	skirt.set_slope(30.0, 120.0)
	assert_almost_eq(skirt.mesh.get_aabb().position.y, -120.0, 0.01,
		"после смены склона меш глубже")
	skirt.set_slope(-50.0, 0.0)
	assert_true(skirt.mesh.get_aabb().position.y < IslandGen.SEA_FLOOR,
		"при экстремумах юбка остаётся ниже дна карты")
	assert_almost_eq(
		SeafloorSkirt.height_at(200.0, 0.0, skirt._shelf, skirt._far_depth),
		-skirt._far_depth, 1e-4, "вдали — ровное дно при любом склоне")


func test_panel_seafloor_sliders() -> void:
	# Ползунки F3: номиналы равны константам юбки, «Скопировать значения»
	# печатает их как константы; без вида острова (сервер) применение не
	# падает, с видом — пересобирает меш юбки.
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	var defs: Dictionary = {}
	for def: Dictionary in panel.WATER_SLIDERS:
		defs[def["id"]] = def
	assert_almost_eq(float(defs[&"seafloor_shelf"]["def"]),
		SeafloorSkirt.SHELF_M, 1e-6, "номинал шельфа — константа юбки")
	assert_almost_eq(float(defs[&"seafloor_deep"]["def"]),
		SeafloorSkirt.FAR_DEPTH_M, 1e-6, "номинал глубины — константа юбки")
	assert_eq(defs[&"seafloor_shelf"]["const"], "SHELF_M",
		"константа шельфа для «Скопировать значения»")
	assert_eq(defs[&"seafloor_deep"]["const"], "FAR_DEPTH_M",
		"константа глубины для «Скопировать значения»")
	var text: String = panel.build_water_values_text()
	assert_true(text.contains("const SHELF_M: float = "),
		"текст значений содержит константу шельфа")
	assert_true(text.contains("const FAR_DEPTH_M: float = "),
		"текст значений содержит константу глубины")
	panel._on_water_slider_changed(30.0, &"seafloor_shelf")
	panel._on_water_slider_changed(120.0, &"seafloor_deep")
	assert_almost_eq(float(panel._water_values[&"seafloor_deep"]),
		120.0, 1e-6, "значение ползунка сохраняется (без падения)")
	# С видом острова: применение пересобирает юбку с новым склоном.
	var view := IslandView.new()
	view.art = ART
	view._build_terrain()
	var skirt := view.get_node("SeafloorSkirt") as SeafloorSkirt
	panel._view = view
	panel._on_water_slider_changed(45.0, &"seafloor_shelf")
	panel._on_water_slider_changed(110.0, &"seafloor_deep")
	assert_almost_eq(skirt.mesh.get_aabb().position.y, -110.0, 0.01,
		"ползунки панели пересобирают юбку дна")
	view.free()

