# Тесты П17 п.2 «Объём кроны»: нормали карточек листвы сферические от
# центра кроны (запекаются в EzTreeMeshes._lod_mesh на всех трёх уровнях
# детализации), AO по глубине — в COLOR.rgb вершин листвы, у коры
# подключены карты нормалей и шероховатости по породам (Bark001–003),
# вариация тона per-instance детерминирована и ограничена ±6 %, а
# перезапечённый island_art.res держит ту же карту высот (хеш генератора
# не менялся — генератор/коллизия не тронуты).
extends GutTest

## Хеш данных генератора (test_island_gen/test_ground_water2): перепечка
## island_art.res обязана его сохранять — меняются только меши и тоны.
const ISLAND_HASH: int = 941246210
const ART_PATH: String = "res://gameplay/world/island_art.res"

## Кэш данных генератора между тестами файла (generate() дорогой, ~10 с).
static var _gen_cache: Dictionary = {}


func _island_data() -> Dictionary:
	if _gen_cache.is_empty():
		_gen_cache = IslandGen.generate()
	return _gen_cache


## Поверхность листвы уровня дерева — та, что с материалом canopy-шейдера
## (кора — первая, листва — последняя; ищем по шейдеру, не по индексу).
func _leaves_surface(mesh: Mesh) -> int:
	for surface: int in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface)
		if material is ShaderMaterial \
				and (material as ShaderMaterial).shader == EzTreeMeshes.CANOPY_SHADER:
			return surface
	return -1


func test_leaf_normals_spherical_from_crown_center() -> void:
	# Т2 плана: ≥ 95 % вершин листвы смотрят от центра кроны
	# (dot(normal, vertex − центр) > 0) на каждом уровне детализации —
	# крона освещается объёмной сферой, а не россыпью плоскостей.
	for type: String in ["etree_pine", "etree_oak", "etree_aspen",
			"etree_bush", "etree_giant"]:
		var set: Dictionary = EzTreeMeshes.build_set(StringName(type), 0)
		var levels: Array[Mesh] = [set["mesh"]]
		levels.append_array(set["lods"] as Array[Mesh])
		for level_index: int in levels.size():
			var label := "%s/lod%d" % [type, level_index - 1]
			var mesh: Mesh = levels[level_index]
			var surface := _leaves_surface(mesh)
			assert_gte(surface, 0, "%s: есть поверхность листвы" % label)
			if surface < 0:
				continue
			var arrays: Array = mesh.surface_get_arrays(surface)
			var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
			var aabb := AABB(verts[0], Vector3.ZERO)
			for vertex: Vector3 in verts:
				aabb = aabb.expand(vertex)
			var center := EzTreeMeshes.crown_center(aabb)
			var aligned := 0
			var unit := 0
			for i: int in verts.size():
				if normals[i].dot(verts[i] - center) > 0.0:
					aligned += 1
				if absf(normals[i].length() - 1.0) < 0.001:
					unit += 1
			assert_eq(unit, verts.size(), "%s: нормали единичные" % label)
			assert_gt(
				float(aligned) / float(verts.size()), 0.95,
				"%s: ≥ 95 %% вершин от центра кроны (факт %.3f)" % [
					label, float(aligned) / float(verts.size())])


func test_leaf_ao_baked_in_color() -> void:
	# Т2 плана: AO в COLOR.rgb вершин листвы — оттенок серого в
	# [0.45..1] (у поверхности кроны 1, в середине темнее), затенение
	# внутри кроны действительно есть (минимум заметно ниже 1).
	for type: String in ["etree_pine", "etree_oak", "etree_bush"]:
		var set: Dictionary = EzTreeMeshes.build_set(StringName(type), 0)
		var mesh: Mesh = set["mesh"]
		var arrays: Array = mesh.surface_get_arrays(_leaves_surface(mesh))
		var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var colors := arrays[Mesh.ARRAY_COLOR] as PackedColorArray
		assert_eq(
			colors.size(), verts.size(), "%s: AO каждой вершине листвы" % type)
		var min_ao := 2.0
		var max_ao := -1.0
		var tint_error := 0.0
		for color: Color in colors:
			min_ao = minf(min_ao, color.r)
			max_ao = maxf(max_ao, color.r)
			tint_error = maxf(tint_error, absf(color.r - color.g))
			tint_error = maxf(tint_error, absf(color.r - color.b))
		assert_almost_eq(tint_error, 0.0, 0.001,
			"%s: AO — оттенок серого, без цветового сдвига" % type)
		assert_between(min_ao, 0.45, 1.0,
			"%s: AO не темнее 0.45 (факт %.3f)" % [type, min_ao])
		assert_almost_eq(max_ao, 1.0, 0.001,
			"%s: у поверхности кроны AO = 1" % type)
		assert_lt(min_ao, 0.95,
			"%s: затенение внутри кроны есть (минимум %.3f)" % [type, min_ao])


func test_bark_uses_normal_and_roughness_maps() -> void:
	# Кора — PBR: карты нормалей и шероховатости подключены по породе
	# (тип коры — из manifest.json пресета), шейдер их читает
	# (NORMAL_MAP / ROUGHNESS, спекуляр по карте шероховатости).
	for type: String in ["etree_pine", "etree_oak", "etree_aspen"]:
		var set: Dictionary = EzTreeMeshes.build_set(StringName(type), 0)
		var material := (set["mesh"] as Mesh).surface_get_material(0) \
			as ShaderMaterial
		assert_eq(material.shader, EzTreeMeshes.BARK_SHADER,
			"%s: поверхность коры с bark-шейдером" % type)
		var normal_tex: Texture2D = material.get_shader_parameter("normal_tex")
		var rough_tex: Texture2D = material.get_shader_parameter("roughness_tex")
		assert_not_null(normal_tex, "%s: карта нормалей коры подключена" % type)
		assert_not_null(rough_tex, "%s: карта шероховатости коры подключена" % type)
		# Порода → свой набор карт (сосна Bark003, дуб/ясень Bark001,
		# осина Bark002 — как в пресетах генератора; размер сэта не важен:
		# у Bark001 карты 2K — его сет «1K» неполный, ниже планки аудита).
		var base := String((EzTreeMeshes.ASSETS[StringName(type)] as Array)[0][0])
		var kind := String(EzTreeMeshes.entry(base)["bark"]["type"])
		assert_true(String(normal_tex.resource_path).contains("%s_" % kind)
				and String(normal_tex.resource_path).ends_with("_NormalGL.jpg"),
			"%s: нормали коры — %s" % [type, kind])
		assert_true(String(rough_tex.resource_path).contains("%s_" % kind)
				and String(rough_tex.resource_path).ends_with("_Roughness.jpg"),
			"%s: шероховатость коры — %s" % [type, kind])
	assert_true(EzTreeMeshes.BARK_SHADER.code.contains("NORMAL_MAP"),
		"tree_bark.gdshader читает карту нормалей")
	assert_true(EzTreeMeshes.BARK_SHADER.code.contains("ROUGHNESS"),
		"tree_bark.gdshader читает карту шероховатости")


func test_crown_tone_jitter_bounded_and_deterministic() -> void:
	# П17 п.2 «Вариация тона по дереву»: jitter от позиции дерева
	# детерминирован (одна позиция — один тон), разнообразен и ограничен:
	# яркость ±6 %, сдвиг оттенка — только R-канал (зелёнее/жёлтее).
	var base := Color(0.9, 0.95, 0.8)
	var distinct := {}
	for i: int in 24:
		var pos := Vector3(float(i) * 3.7, 0.0, float(i) * -1.3)
		var tone := IslandArt.crown_tone(base, pos)
		assert_eq(tone, IslandArt.crown_tone(base, pos),
			"позиция %s: тон детерминирован" % pos)
		assert_between(tone.g, base.g * 0.93, base.g * 1.08,
			"яркость G в пределах ±6 %% (факт %.3f)" % tone.g)
		assert_between(tone.b, base.b * 0.93, base.b * 1.08,
			"яркость B в пределах ±6 %")
		assert_between(tone.r, base.r * 0.87, base.r * 1.14,
			"оттенок R в пределах яркость×(±6 %)")
		distinct[tone.to_html(true)] = true
	assert_gt(distinct.size(), 12,
		"24 дерева — больше 12 различных тонов (факт %d)" % distinct.size())


func test_island_art_heights_match_generator() -> void:
	# Т2 плана: перезапёк island_art.res (сферические нормали, AO, тоны)
	# не меняет карту высот — хеш данных генератора прежний, высоты
	# в ресурсе равны свежесгенерированным (генератор и коллизия не
	# тронуты, мир одинаков у всех).
	var art := load(ART_PATH) as IslandArt
	assert_not_null(art, "island_art.res загружается")
	var data := _island_data()
	assert_eq(IslandGen.island_hash(data), ISLAND_HASH,
		"хеш острова не изменился")
	assert_eq(
		hash(art.heights), hash(data["heights"]),
		"высоты island_art.res равны свежесгенерированным")
