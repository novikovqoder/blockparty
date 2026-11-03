# Тесты П17 п.3 «Импосторы дальних деревьев»: у каждой базы вида есть
# атласы albedo+нормалей (раскладка 4×4 кадра, RGBA8/RGV8) с живым
# силуэтом, дальний уровень LOD2 заменён импостором (90–400 м) без дыры
# на стыке с LOD1, переход — плавный (FADE_SELF у обоих), шейдер выбирает
# кадр по углу «камера → дерево» и читает атлас нормалей.
extends GutTest

const DIR: String = "res://assets/visual/trees/impostors/"
const ATLAS_PX: int = 512


## Базы всех видов:вариантов (как перечислено в EzTreeMeshes.ASSETS).
func _bases() -> Array[String]:
	var bases: Array[String] = []
	for type: StringName in EzTreeMeshes.ASSETS:
		for entry: Array in EzTreeMeshes.ASSETS[type]:
			if not bases.has(String(entry[0])):
				bases.append(String(entry[0]))
	bases.sort()
	return bases


func test_atlases_for_every_base() -> void:
	# Т3 плана: у каждого вида:варианта есть атлас — тула печёт по базе,
	# варианты вида отличаются только масштабом (quad берёт размер группы).
	var bases := _bases()
	assert_gt(bases.size(), 15, "баз больше 15 (4 вида + кусты + гигант)")
	for base: String in bases:
		var albedo := load(DIR + "%s_impostor.png" % base) as Texture2D
		var normals := load(DIR + "%s_impostor_normal.png" % base) as Texture2D
		assert_not_null(albedo, "%s: атлас albedo есть" % base)
		assert_not_null(normals, "%s: атлас нормалей есть" % base)
		if albedo == null or normals == null:
			continue
		assert_eq(albedo.get_width(), ATLAS_PX, "%s: атлас 512 px" % base)
		assert_eq(albedo.get_height(), ATLAS_PX, "%s: атлас квадратный" % base)
		assert_eq(normals.get_width(), ATLAS_PX,
			"%s: атлас нормалей 512 px" % base)


func test_atlas_silhouette_alive() -> void:
	# Силуэт запечён: в кадре 0 (азимут 0, низкая камера) доля пикселей
	# выше порога вырезки заметна — не пустой и не сплошной прямоугольник.
	for base: String in ["pine_large_v0", "oak_medium_v0", "aspen_medium_v0",
			"bush_1_v0", "oak_large_v1"]:
		var texture := load(DIR + "%s_impostor.png" % base) as Texture2D
		assert_not_null(texture, "%s: атлас есть" % base)
		if texture == null:
			continue
		var image := texture.get_image()
		var solid := 0
		for y: int in range(0, 128, 4):
			for x: int in range(0, 128, 4):
				if image.get_pixel(x, y).a >= 0.3:
					solid += 1
		var share: float = float(solid) / 1024.0
		assert_between(share, 0.08, 0.92,
			"%s: силуэт кадра 0 живой (доля %.2f)" % [base, share])


func test_impostor_level_replaces_lod2() -> void:
	# LOD2 (90–220 м) заменён импостором 90–400: у LOD1 конец на стыке,
	# импостор начинается там же (в пределах fade-полей — без «дыры»),
	# LOD2-меш больше не инстанцируется, тени у импостора нет.
	var view := IslandView.new()
	var art := IslandArt.new()
	var set: Dictionary = EzTreeMeshes.build_set(&"etree_oak", 0)
	var group := PropGroup.new()
	group.mesh = set["mesh"]
	group.lods = set["lods"]
	group.transforms = [
		Transform3D(Basis(), Vector3(3.0, 0.0, 3.0)),
		Transform3D(Basis().rotated(Vector3.UP, 1.2), Vector3(30.0, 0.0, 7.0)),
	]
	group.colors = [Color.WHITE, Color(0.9, 1.0, 0.85)]
	art.prop_groups = {"etree_oak:0": group}
	view.art = art
	view._build_tree_lods("etree_oak:0", "etree_oak", group)
	var lod1: MultiMeshInstance3D = null
	var impostor: MultiMeshInstance3D = null
	for child: Node in view.get_children():
		if not child is MultiMeshInstance3D:
			continue
		var instance := child as MultiMeshInstance3D
		if String(instance.name).ends_with("_lod1"):
			lod1 = instance
		if String(instance.name).ends_with("_impostor"):
			impostor = instance
	assert_not_null(lod1, "уровень LOD1 построен")
	assert_not_null(impostor, "импостор-уровень построен")
	assert_eq(view.get_child_count(), 3,
		"уровня всего три: LOD0, LOD1 и импостор (LOD2 заменён)")
	if impostor == null or lod1 == null:
		view.free()
		return
	assert_almost_eq(impostor.visibility_range_begin,
		TreeImpostors.RANGE_BEGIN, 0.01, "импостор начинается на 90 м")
	assert_almost_eq(impostor.visibility_range_end,
		TreeImpostors.RANGE_END, 0.01, "импостор виден до 400 м (за туман)")
	assert_almost_eq(lod1.visibility_range_end, TreeImpostors.RANGE_BEGIN,
		0.01, "LOD1 заканчивается на стыке с импостором")
	# «Дыры» нет: с учётом fade-полей зоны перекрываются.
	assert_lte(
		impostor.visibility_range_begin
			- impostor.visibility_range_begin_margin,
		lod1.visibility_range_end + lod1.visibility_range_end_margin,
		"стык LOD1 → импостор без дыры (поля перекрываются)")
	# Плавный переход — дизеринг-фейд у обоих.
	assert_eq(lod1.visibility_range_fade_mode,
		GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF,
		"LOD1 фейдится на стыке")
	assert_eq(impostor.visibility_range_fade_mode,
		GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF,
		"импостор фейдится на стыке")
	assert_eq(impostor.cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"импостор тень не отбрасывает")
	# Инстансов столько же, сколько деревьев группы; quad — 4 вершины.
	assert_eq(impostor.multimesh.instance_count, 2,
		"по инстансу на дерево группы")
	assert_eq(impostor.multimesh.mesh.get_surface_count(), 1,
		"импостор — одна поверхность")
	assert_eq(
		(impostor.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			as PackedVector3Array).size(), 4, "импостор — quad")
	view.free()


func test_impostor_shader_selects_frame_and_lights_by_normals() -> void:
	# Шейдер: кадр атласа выбирается по углу на камеру (atan по to_cam),
	# нормали атласа идут в NORMAL через базис квада, свет — тот же
	# wrap-Ламберт, что у кроны (стык уровней не читается по свету).
	var code := TreeImpostors.SHADER.code
	assert_true(code.contains("atan(to_cam.x, to_cam.z)"),
		"кадр выбирается по азимуту на камеру")
	assert_true(code.contains("frame_uv"),
		"UV приводится к ячейке кадра")
	assert_true(code.contains("normal_tex"),
		"атлас нормалей подключён")
	assert_true(code.contains("bb_right * normal_map.x"),
		"нормали атласа разворачиваются базисом квада")
	assert_true(code.contains("float wrap = 0.5;"),
		"свет — wrap-Ламберт как у кроны")
	# Материал базы: атласы и порог вырезки подключены.
	var material := TreeImpostors.build("etree_pine:0", _sample_group())
	assert_not_null(material, "группа etree_pine собирается")
	if material == null:
		return
	var shader := material.material_override as ShaderMaterial
	assert_not_null(shader.get_shader_parameter("atlas_tex"),
		"атлас albedo подключён")
	assert_not_null(shader.get_shader_parameter("normal_tex"),
		"атлас нормалей подключён")
	assert_almost_eq(float(shader.get_shader_parameter("alpha_cut")),
		TreeImpostors.ALPHA_CUT, 0.001, "порог вырезки атласа")
	material.free()


## Минимальная группа сосны (меш с AABB для квада).
func _sample_group() -> PropGroup:
	var set: Dictionary = EzTreeMeshes.build_set(&"etree_pine", 0)
	var group := PropGroup.new()
	group.mesh = set["mesh"]
	group.lods = set["lods"]
	group.transforms = [Transform3D(Basis(), Vector3(3.0, 0.0, 3.0))]
	group.colors = [Color.WHITE]
	return group
