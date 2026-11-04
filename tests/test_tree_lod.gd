# Тесты П18 Сборки 1 п.3 «LOD умнее демо»: ближний уровень дерева —
# гибрид (полная листва LOD0 + ветки LOD1 демо), дальние — LOD1/LOD2
# демо; уровни ведутся дистанцией до ближайшего дерева группы с
# гистерезисом 5 % (без visibility_range и FADE_SELF — AABB группы весь
# остров, дальние уровни при ходьбе не выключались), переход 0↔1 —
# перетекание листвы через uniform reveal canopy-шейдера (порог выреза
# едет от пресетного до полного отсечения и встречно), 1↔2 — мгновенный.
extends GutTest


func _sample_group() -> PropGroup:
	var group := PropGroup.new()
	var set: Dictionary = EzTreeMeshes.build_set(&"etree_bush", 0)
	group.mesh = set["mesh"]
	group.lods = set["lods"]
	group.transforms = [
		Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)),
		Transform3D(Basis(), Vector3(30.0, 0.0, 0.0)),
	]
	group.colors = [Color.WHITE, Color.WHITE]
	return group


## reveal уровня (null = uniform ещё не ставился — дефолт шейдера 1.0).
func _reveal(mats: Array[Array], level: int) -> float:
	var value: Variant = mats[level][0].get_shader_parameter("reveal")
	return 1.0 if value == null else float(value)


func test_near_level_is_hybrid_leaves_lod0_branches_lod1() -> void:
	# Состав гибрида: вершины листвы — ровно LOD0 GLB («листва НЕ
	# трогается», leafStride 1), вершины веток — LOD1 GLB демо
	# (sectionStride 3, segmentFactor 0.75; полный меш веток LOD0
	# больше не используется). Сравнение через отношение к GLB: ×k
	# равномерен, отношение каждой вершины к GLB-оригиналу одно.
	for type: StringName in [&"etree_pine", &"etree_oak", &"etree_bush"]:
		var list: Array = EzTreeMeshes.ASSETS[type]
		var base := String(list[0][0])
		var target_h: float = list[0][1]
		var info := EzTreeMeshes.entry(base)
		var max_v: Array = info.get("lods", [{}])[0].get(
			"aabb", {}).get("max", [0.0, target_h, 0.0])
		var k: float = target_h / maxf(float(max_v[1]), 0.01)

		var set: Dictionary = EzTreeMeshes.build_set(type, 0)
		var hybrid: Mesh = set["mesh"]
		# Листва гибрида — последняя поверхность (кора первая).
		var leaf_verts := hybrid.surface_get_arrays(
			hybrid.get_surface_count() - 1)[Mesh.ARRAY_VERTEX] \
			as PackedVector3Array
		var glb_leaves := _glb_verts(base, 0, "Leaves")
		assert_eq(leaf_verts.size(), glb_leaves.size(),
			"%s: вершин листвы гибрида = LOD0 GLB" % base)
		var leaf_ok := 0
		for i: int in minf(leaf_verts.size(), glb_leaves.size()):
			if absf(leaf_verts[i].length() / maxf(glb_leaves[i].length(), 1e-9)
					- k) < 0.002 \
					or leaf_verts[i].distance_to(glb_leaves[i] * k) < 0.01:
				leaf_ok += 1
		assert_eq(leaf_ok, leaf_verts.size(),
			"%s: листва гибрида = LOD0 GLB ×k" % base)

		var bark_verts := hybrid.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] \
			as PackedVector3Array
		var glb_branches := _glb_verts(base, 1, "Branches")
		assert_eq(bark_verts.size(), glb_branches.size(),
			"%s: вершин веток гибрида = LOD1 GLB" % base)
		var bark_ok := 0
		for i: int in minf(bark_verts.size(), glb_branches.size()):
			if bark_verts[i].distance_to(glb_branches[i] * k) < 0.01:
				bark_ok += 1
		assert_eq(bark_ok, bark_verts.size(),
			"%s: ветки гибрида = LOD1 GLB ×k (не LOD0)" % base)
		# Дальние уровни — LOD1/LOD2 демо целиком.
		var lod1: Mesh = (set["lods"] as Array[Mesh])[0]
		var lod1_bark := lod1.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] \
			as PackedVector3Array
		assert_eq(lod1_bark.size(), glb_branches.size(),
			"%s: LOD1 — уровень демо (ветки как LOD1 GLB)" % base)


func _glb_verts(base: String, lod: int, node_name: String) -> PackedVector3Array:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(
			"%s%s_lod%d.glb" % [EzTreeMeshes.DIR, base, lod], state) != OK:
		return PackedVector3Array()
	var scene := doc.generate_scene(state)
	var arrays: Array = []
	var node := _find_node(scene, node_name)
	if node is MeshInstance3D:
		arrays = (node as MeshInstance3D).mesh.surface_get_arrays(0)
	scene.free()
	if arrays.is_empty():
		return PackedVector3Array()
	return arrays[Mesh.ARRAY_VERTEX]


func _find_node(root: Node, node_name: String) -> Node:
	var node := root.get_node_or_null(NodePath(node_name))
	if node != null:
		return node
	for child: Node in root.get_children():
		node = _find_node(child, node_name)
		if node != null:
			return node
	return null


func test_lod_nodes_without_visibility_range_or_fade() -> void:
	# Уровни — тремя нодами без visibility_range (AABB мультимеша группы —
	# весь остров) и без дизеринг-фейда FADE_SELF (П18: никакого
	# дизеринга по расстоянию). View вне дерева: _ready строил бы остров
	# целиком (art пуст — тесту нужны только уровни).
	var view := IslandView.new()
	view._build_tree_lods("etree_bush:0", "etree_bush", _sample_group())
	assert_eq(view._tree_lods.size(), 1, "группа деревьев зарегистрирована")
	var state: Dictionary = view._tree_lods[0]
	var nodes: Array[MultiMeshInstance3D] = state["nodes"]
	assert_eq(nodes.size(), 3, "три уровня на группу")
	for index: int in nodes.size():
		assert_eq(nodes[index].visibility_range_begin, 0.0,
			"lod%d: без visibility_range_begin" % index)
		assert_eq(nodes[index].visibility_range_end, 0.0,
			"lod%d: без visibility_range_end" % index)
		assert_eq(nodes[index].visibility_range_fade_mode,
			GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED,
			"lod%d: без FADE_SELF" % index)
	view.free()


func test_lod_target_boundaries_and_hysteresis() -> void:
	# Границы 70/150 м и гистерезис 5 %: подъём — за порогом, спуск —
	# на 5 % ниже порога (уровень не дребезжит, стоя на границе).
	assert_eq(IslandView._tree_lod_target(0.0, 0), 0, "вплотную — гибрид")
	assert_eq(IslandView._tree_lod_target(69.9, 0), 0, "до 70 м — гибрид")
	assert_eq(IslandView._tree_lod_target(70.1, 0), 1, "за 70 м — LOD1")
	assert_eq(IslandView._tree_lod_target(68.0, 1), 1,
		"гистерезис: 68 м держит LOD1 (спуск ниже 66.5)")
	assert_eq(IslandView._tree_lod_target(66.0, 1), 0, "ниже 66.5 м — гибрид")
	assert_eq(IslandView._tree_lod_target(149.9, 1), 1, "до 150 м — LOD1")
	assert_eq(IslandView._tree_lod_target(150.1, 1), 2, "за 150 м — LOD2")
	assert_eq(IslandView._tree_lod_target(145.0, 2), 2,
		"гистерезис: 145 м держит LOD2 (спуск ниже 142.5)")
	assert_eq(IslandView._tree_lod_target(140.0, 2), 1, "ниже 142.5 м — LOD1")
	# Ползунок F3 «Детализация деревьев»: границы ×0.5.
	assert_eq(IslandView._tree_lod_target(35.1, 0, 0.5), 1,
		"×0.5: за 35 м — LOD1")
	assert_eq(IslandView._tree_lod_target(34.0, 0, 0.5), 0,
		"×0.5: до 35 м — гибрид")


func test_blend_moves_reveal_and_restores_threshold() -> void:
	# Перетекание 0↔1: при переходе уходящему уровню reveal едет от 1
	# (порог пресета) к 0 (полное отсечение), встречному — от 0 к 1;
	# по завершении порог возвращается к пресетному (reveal = 1),
	# уходящий уровень гасится. Смена 1→2 — мгновенная (reveal сразу 1).
	# Деревья группы в 0 и 30 м; зритель в (90, 0) — до ближнего 60 м.
	var view := IslandView.new()
	view._build_tree_lods("etree_bush:0", "etree_bush", _sample_group())
	var state: Dictionary = view._tree_lods[0]
	var nodes: Array[MultiMeshInstance3D] = state["nodes"]
	var mats: Array[Array] = state["mats"]

	# Стартовый выбор — уровень 0.
	view._update_tree_lods(Vector2(90.0, 0.0))
	assert_eq(state["level"], 0, "60 м от ближнего дерева — гибрид")
	assert_true(nodes[0].visible, "гибрид виден")
	assert_false(nodes[1].visible, "LOD1 скрыт")
	assert_false(nodes[2].visible, "LOD2 скрыт")

	# За 70 м — перетекание 0→1: оба уровня видимы, reveal расходится.
	view._update_tree_lods(Vector2(105.0, 0.0))
	assert_eq(state["level"], 1, "75 м до ближнего дерева — цель LOD1")
	assert_eq(state["blend_from"], 0, "уходящий — гибрид")
	assert_true(nodes[0].visible, "уходящий видим до конца перетекания")
	assert_true(nodes[1].visible, "встречный видим сразу")
	var reveal0: float = _reveal(mats, 0)
	var reveal1: float = _reveal(mats, 1)
	assert_almost_eq(reveal0, 1.0, 0.0001, "уходящий стартует полным")
	assert_almost_eq(reveal1, 0.0, 0.0001, "встречный стартует вырезанным")

	# Полный цикл перетекания (0.4 с мелкими тактами) — на середине
	# reveal между уровнями расходится, в конце оба — пресетный порог.
	view._process(0.05)
	assert_lt(_reveal(mats, 0), 0.9, "уходящий: reveal поехал вниз")
	assert_gt(_reveal(mats, 1), 0.1, "встречный: reveal поехал вверх")
	for i: int in 9:
		view._process(0.05)
	assert_eq(state["blend_from"], -1, "перетекание завершено")
	assert_almost_eq(_reveal(mats, 0), 1.0, 0.0001,
		"после перехода порог уходящего — пресетный (reveal = 1)")
	assert_almost_eq(_reveal(mats, 1), 1.0, 0.0001,
		"порог пришедшего — пресетный (reveal = 1)")
	assert_false(nodes[0].visible, "уходящий уровень погашен")
	assert_true(nodes[1].visible, "LOD1 остался")

	# 155 м — мгновенная смена 1→2 (без перетекания).
	view._update_tree_lods(Vector2(185.0, 0.0))
	assert_eq(state["level"], 2, "155 м до ближнего дерева — LOD2")
	assert_eq(state["blend_from"], -1, "смена дальних уровней мгновенная")
	assert_almost_eq(_reveal(mats, 2), 1.0, 0.0001,
		"LOD2 с пресетным порогом сразу")
	assert_false(nodes[1].visible, "LOD1 погашен сразу")
	assert_true(nodes[2].visible, "LOD2 включен")

	# Возврат в зону гистерезиса не дёргает уровень: 145 м держит LOD2.
	view._update_tree_lods(Vector2(175.0, 0.0))
	assert_eq(state["level"], 2, "145 м (гистерезис 5 %) держит LOD2")
	view.free()


func test_tree_detail_slider_forces_recalc() -> void:
	# Ползунок F3 «Детализация деревьев»: сеттер запоминает множитель
	# (диапазон 0.5–2×) и форсирует пересчёт на ближайшем update_viewer.
	var view := IslandView.new()
	view.set_tree_detail(0.5)
	assert_almost_eq(view._tree_detail_mult, 0.5, 0.0001, "множитель ×0.5")
	view._tree_lod_last_center = Vector2.ZERO
	view.set_tree_detail(1.5)
	assert_eq(view._tree_lod_last_center, Vector2(1e9, 1e9),
		"после смены ползунка пересчёт форсируется")
	view.free()


func test_tree_shadows_near_level_only() -> void:
	# П18 Сборки 1 п.4: тень отбрасывает только ближний уровень-гибрид
	# (виден до 70 м — тени деревьев до ~70 м; ветки гибрида и LOD1
	# одинаковы, тень не рвётся на стыке); дальние уровни без тени.
	var view := IslandView.new()
	view._build_tree_lods("etree_bush:0", "etree_bush", _sample_group())
	var nodes: Array[MultiMeshInstance3D] = view._tree_lods[0]["nodes"]
	assert_eq(nodes[0].cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"ближний уровень отбрасывает тень")
	assert_eq(nodes[1].cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"LOD1 без тени")
	assert_eq(nodes[2].cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"LOD2 без тени")
	# Галочка F3 «Тени деревьев»: снятая гасит тень и у ближнего уровня,
	# возврат возвращает только ей.
	view.set_tree_shadows(false)
	for index: int in nodes.size():
		assert_eq(nodes[index].cast_shadow,
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"lod%d: галочка погасила тень" % index)
	view.set_tree_shadows(true)
	assert_eq(nodes[0].cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"возврат галочки вернул тень ближнему уровню")
	assert_eq(nodes[1].cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"дальние остаются без тени")
	view.free()


func test_f3_tree_shadow_checkbox() -> void:
	# П18 Сборки 1 п.4: галочка «Тени деревьев» в EFFECTS с подписью i18n;
	# уровневая база — тени солнца есть на NORMAL и выше (SIMPLE без теней,
	# GraphicsQuality.apply).
	var panel := DebugPanel.new()
	add_child_autofree(panel)
	assert_true(panel.EFFECTS.has(&"tshadow"), "галочка «Тени деревьев» есть")
	assert_true(panel.EFFECT_LABELS.has(&"tshadow"),
		"у «Тени деревьев» есть подпись i18n")
	panel.watch_graphics(Environment.new(), null, GraphicsQuality.Tier.SIMPLE)
	assert_false(panel._tier_effect_on(&"tshadow"),
		"SIMPLE: теней солнца нет — не эффект уровня")
	panel.watch_graphics(Environment.new(), null, GraphicsQuality.Tier.NORMAL)
	assert_true(panel._tier_effect_on(&"tshadow"),
		"NORMAL: тени деревьев — эффект уровня")
	panel.watch_graphics(Environment.new(), null, GraphicsQuality.Tier.HIGH)
	assert_true(panel._tier_effect_on(&"tshadow"), "HIGH: как NORMAL")
