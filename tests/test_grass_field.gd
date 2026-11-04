# Тесты П18 Сборки 2 «Поле травы/цветов как в демо ez-tree»
# (docs/eztree_demo/PLAN_p18.md, src/app/grass.js): пучок из GLB — ровно
# 6 треугольников; параметры демо через k = 0.38 (масштаб size ±
# variation по осям, цвет экземпляра (0.25+0.1r, 0.3+0.3r, 0.1),
# emissive 0x308040 × 0.05, затемнение 0.6); раскладка чанками
# детерминирована по мировым клеткам (не «плавает» за игроком);
# запретные зоны (вода/пляж, Площадь, дворы, руины, каньон, причал,
# крутая скала, гравий тропы); пятнистость тем же шумом, что земля;
# цветы трёх видов ~по 50 на круге HIGH, вид пятна детерминирован;
# уровни HIGH/ULTRA (радиус 100/120, фактическая плотность в диапазоне
# демо 5000–25000); материал/шейдер (ветер формулы крон, кромка
# масштабом к нулю, PBR без ручного light()). Карта высот не менялась —
# сверка хешем, как test_water3.
extends GutTest

const ART: IslandArt = preload("res://gameplay/world/island_art.res")
const FIELD_SHADER: Shader = preload(
	"res://assets/shaders/grass_ez.gdshader")
## Контрольная сумма heights печёного арта (test_water3:19): поле садится
## ПОВЕРХ земли, карта высот (коллизия) обязана совпасть побитово.
const HEIGHTS_CHECKSUM: int = 2041845998


# --- модель пучка демо ---

func test_tuft_is_six_triangles() -> void:
	# Задание П18: «пучок = 6 треугольников» — grass.glb демо (3
	# скрещенные плоскости), одна поверхность, текстура пучка при нём.
	var tuft: Dictionary = GrassField.tuft_data()
	var mesh: Mesh = tuft["mesh"]
	assert_eq(mesh.get_surface_count(), 1, "у пучка одна поверхность")
	var arrays := mesh.surface_get_arrays(0)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_eq(idx.size() / 3, 6, "пучок — ровно 6 треугольников")
	assert_ne(tuft["texture"], null, "текстура пучка из GLB при нём")
	assert_almost_eq(float(tuft["height"]), 2.0, 0.001,
		"высота модели GLB — 2 демо-ед. (основание в нуле)")


func test_flower_models_loaded() -> void:
	# Три модели цветов демо, каждая — 6–7 поверхностей с albedo
	# (у части лепестков — плоский цвет без карты, как в GLB).
	for kind: String in ["white", "blue", "yellow"]:
		var surfaces: Array = GrassField.flower_data(kind)
		assert_between(surfaces.size(), 5, 8,
			"у цветка %s 5–8 поверхностей (GLB)" % kind)
		var tris := 0
		for surface: Dictionary in surfaces:
			var arrays: Array = (surface["mesh"] as ArrayMesh) \
				.surface_get_arrays(0)
			tris += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		assert_between(tris, 600, 900,
			"цветок %s ~800 треугольников (GLB демо)" % kind)


# --- параметры демо через k ---

func test_tuft_scale_and_color_demo_ranges() -> void:
	# Масштаб size {5,4,5} ± variation {1,2,1} ×k = 0.38 — по каждой оси
	# отдельно (grass.js:191); цвет экземпляра (0.25+0.1r, 0.3+0.3r, 0.1).
	# Проба — чанки вокруг луга: раскладка обязана накрыть диапазоны.
	var chunks := _chunks_around(Vector2(20.0, 25.0), GraphicsQuality.Tier.ULTRA)
	var gathered := GrassField.gather_from(chunks)
	var transforms := _tuft_transforms(gathered)
	var colors := _tuft_colors(gathered)
	var scales: Array[Vector3] = []
	for xf: Transform3D in transforms:
		var b := xf.basis
		scales.append(Vector3(b.x.length(), b.y.length(), b.z.length()))
	assert_gt(scales.size(), 500, "проба не холостая (пучков > 500)")
	var min_x := 9e9; var max_x := -9e9
	var min_y := 9e9; var max_y := -9e9
	var min_z := 9e9; var max_z := -9e9
	for s: Vector3 in scales:
		min_x = minf(min_x, s.x); max_x = maxf(max_x, s.x)
		min_y = minf(min_y, s.y); max_y = maxf(max_y, s.y)
		min_z = minf(min_z, s.z); max_z = maxf(max_z, s.z)
	# Итоговый размер инстанса = модель × масштаб: ширина модели 1.96,
	# высота 2.0 демо-ед. — умножаются на scale ∈ [size, size+var] ×k.
	assert_between(min_x, GrassField.SIZE.x - 0.01, GrassField.SIZE.x + 0.01,
		"мин. масштаб X = size.x ×k")
	assert_between(max_x, (GrassField.SIZE.x + GrassField.SIZE_VAR.x) - 0.01,
		(GrassField.SIZE.x + GrassField.SIZE_VAR.x) + 0.01,
		"макс. масштаб X = (size.x + variation.x) ×k")
	assert_between(min_y, GrassField.SIZE.y - 0.01, GrassField.SIZE.y + 0.01,
		"мин. масштаб Y = size.y ×k")
	assert_between(max_y, (GrassField.SIZE.y + GrassField.SIZE_VAR.y) - 0.01,
		(GrassField.SIZE.y + GrassField.SIZE_VAR.y) + 0.01,
		"макс. масштаб Y = (size.y + variation.y) ×k")
	assert_between(min_z, GrassField.SIZE.z - 0.01, GrassField.SIZE.z + 0.01,
		"мин. масштаб Z = size.z ×k")
	assert_between(max_z, (GrassField.SIZE.z + GrassField.SIZE_VAR.z) - 0.01,
		(GrassField.SIZE.z + GrassField.SIZE_VAR.z) + 0.01,
		"макс. масштаб Z = (size.z + variation.z) ×k")
	for c: Color in colors:
		assert_between(c.r, 0.249, 0.351, "тон R = 0.25 + 0.1r демо")
		assert_between(c.g, 0.299, 0.601, "тон G = 0.3 + 0.3r демо")
		assert_almost_eq(c.b, 0.1, 0.0001, "тон B = 0.1 демо")


# --- детерминизм по мировым клеткам ---

func test_chunk_layout_deterministic() -> void:
	# Раскладка — чистая функция мировых координат: повторная сборка чанка
	# даёт те же трансформы/цвета; порядок соседних чанков и позиция
	# игрока на поток клетки не влияют (поле не «плавает»).
	var first := GrassField.build_chunk(ART, GraphicsQuality.Tier.ULTRA, 3, 4)
	var again := GrassField.build_chunk(ART, GraphicsQuality.Tier.ULTRA, 3, 4)
	assert_gt((first["tuft"]["transforms"] as Array).size(), 0,
		"чанк (3, 4) населён (проба не холостая)")
	var a: Array = first["tuft"]["transforms"]
	var b: Array = again["tuft"]["transforms"]
	assert_eq(a.size(), b.size(), "повторная сборка — то же число пучков")
	for i: int in mini(a.size(), b.size()):
		assert_true((a[i] as Transform3D).origin.is_equal_approx(
			(b[i] as Transform3D).origin), "позиции совпадают побитово")
	assert_eq((first["tuft"]["colors"] as PackedColorArray).size(),
		a.size(), "цветов столько же, сколько пучков")
	# Сборка тех же чанков в другом порядке даёт ту же сумму.
	var one := GrassField.gather_from({
		Vector2i(3, 4): GrassField.build_chunk(
			ART, GraphicsQuality.Tier.ULTRA, 3, 4),
		Vector2i(4, 4): GrassField.build_chunk(
			ART, GraphicsQuality.Tier.ULTRA, 4, 4),
	})
	var two := GrassField.gather_from({
		Vector2i(4, 4): GrassField.build_chunk(
			ART, GraphicsQuality.Tier.ULTRA, 4, 4),
		Vector2i(3, 4): GrassField.build_chunk(
			ART, GraphicsQuality.Tier.ULTRA, 3, 4),
	})
	assert_eq((one["tuft"]["transforms"] as Array).size(),
		(two["tuft"]["transforms"] as Array).size(),
		"сумма чанков не зависит от порядка сборки")


# --- уровни ---

func test_field_tiers_radius_and_counts() -> void:
	# Поле на HIGH/ULTRA (SIMPLE/NORMAL — печёная подложка), радиусы
	# 100/120 м; фактический счёт пучков — в диапазоне демо 5000–25000
	# («плотность как в демо или гуще — пучки дешёвые»), HIGH ≈ ½ ULTRA.
	assert_true(GrassField.is_field_enabled(GraphicsQuality.Tier.HIGH),
		"HIGH: поле включено")
	assert_true(GrassField.is_field_enabled(GraphicsQuality.Tier.ULTRA),
		"ULTRA: поле включено")
	assert_false(GrassField.is_field_enabled(GraphicsQuality.Tier.NORMAL),
		"NORMAL: только печёная подложка rgrass")
	assert_almost_eq(GrassField.radius_for_tier(GraphicsQuality.Tier.HIGH),
		100.0, 0.0001, "радиус HIGH ~100 м")
	assert_almost_eq(GrassField.radius_for_tier(GraphicsQuality.Tier.ULTRA),
		120.0, 0.0001, "радиус ULTRA ~120 м")
	var started := Time.get_ticks_msec()
	var high := _gather_around(Vector2(20.0, 25.0), GraphicsQuality.Tier.HIGH)
	var elapsed := Time.get_ticks_msec() - started
	var high_count := (high["tuft"]["transforms"] as Array).size()
	assert_between(high_count, 4000, 25000,
		"HIGH: фактический счёт пучков в диапазоне демо (факт %d)"
			% high_count)
	var ultra := _gather_around(Vector2(20.0, 25.0), GraphicsQuality.Tier.ULTRA)
	var ultra_count := (ultra["tuft"]["transforms"] as Array).size()
	assert_between(ultra_count, 5000, 25000,
		"ULTRA: фактический счёт пучков в диапазоне демо (факт %d)"
			% ultra_count)
	assert_between(float(high_count) / float(ultra_count), 0.35, 0.75,
		"HIGH ≈ ½ ULTRA (факт %.2f)"
			% (float(high_count) / float(ultra_count)))
	# Чистая сборка всего круга HIGH с нуля — регрессионный потолок:
	# в рантайме она никогда не идёт одним куском, IslandView строит
	# по GRASS_CHUNK_BUDGET чанков за кадр (~30-40 мс, без фриза входа),
	# полный круг вырастает вокруг игрока меньше чем за секунду.
	assert_lt(elapsed, 1500,
		"сборка круга HIGH из чанков < 1.5 с (факт %d мс)" % elapsed)


# --- запретные зоны ---

func test_field_blocks_forbidden_zones() -> void:
	# Те же зоны, что у травы-буста: вода/пляж, Площадь, дворы построек,
	# терраса руин, каньон, причал, крутая скала и гравий тропы. Центр —
	# чаща Леса: круг 100+ м захватывает блокируемые клетки.
	var gathered := _gather_around(
		Vector2(-30.0, -30.0), GraphicsQuality.Tier.ULTRA)
	var transforms := _tuft_transforms(gathered)
	assert_gt(transforms.size(), 100,
		"в чаще Леса вокруг есть поле (проба не пустая)")
	for xf: Transform3D in transforms:
		var pos := Vector2(xf.origin.x, xf.origin.z)
		assert_gt(xf.origin.y, GrassField.BEACH_H,
			"пучок выше линии пляжа/воды")
		assert_lt(ForestGround._plaza_weight(pos.x, pos.y), 0.06,
			"поле не растёт на Площади")
		assert_false(IslandGen.on_village_pad(pos),
			"поле не растёт во дворах построек")
		assert_gte(pos.distance_to(GroundClutter.RUIN_CENTER), 24.0,
			"поле не растёт на террасе руин")
		assert_false(
			pos.x >= IslandGen.CREVASSE_X0 - 2.0
			and pos.x <= IslandGen.CREVASSE_X1 + 2.0
			and pos.y >= IslandGen.CREVASSE_Z0 - 2.0
			and pos.y <= IslandGen.CREVASSE_Z1 + 2.0,
			"поле не растёт в каньоне")
		assert_false(
			pos.x >= 1.5 and pos.x <= 9.5
			and pos.y >= 55.5 and pos.y <= 75.5,
			"поле не растёт на причале")
		# Гравий тропы: клетка с весом тропы выше блока пучков не даёт
		# (дрожание ±0.45 м не должно переносить посадку на гравий —
		# проверяем вес в самой точке посадки; блок — path >= 0.2 в
		# GroundDetails._grass_cell_state).
		var cell := GroundDetails._grass_cell_state(ART,
			roundi(pos.x), roundi(pos.y))
		assert_lt(float(cell["path"]), 0.2,
			"пучок не стоит на гравии тропы")


# --- пятнистость и цветы ---

func test_field_patchiness_same_noise_as_ground() -> void:
	# Пятнистость — тем же шумом, что земля (IslandGen._grass_patch):
	# в пустошах шума трава сильно реже (аналог skip демо при
	# patchiness 0.7). Сравниваем счёт пучков в клетках гуще/реже.
	var chunks := _chunks_around(Vector2(60.0, 60.0), GraphicsQuality.Tier.ULTRA)
	var gathered := GrassField.gather_from(chunks)
	var dense := 0
	var bare := 0
	var dense_count := 0
	var bare_count := 0
	for xf: Transform3D in _tuft_transforms(gathered):
		var patch: float = IslandGen._grass_patch(
			roundi(xf.origin.x), roundi(xf.origin.z))
		if patch > 0.75:
			dense += 1
		elif patch < 0.25:
			bare += 1
	# Доли самих клеток в пробе — для честного сравнения плотностей.
	for x: int in range(0, 120):
		for z: int in range(0, 120):
			var patch: float = IslandGen._grass_patch(x, z)
			if patch > 0.75:
				dense_count += 1
			elif patch < 0.25:
				bare_count += 1
	if dense_count > 20 and bare_count > 20:
		var dense_rate := float(dense) / float(dense_count)
		var bare_rate := float(bare) / float(bare_count)
		assert_gt(dense_rate, bare_rate * 3.0,
			"в гуще пятен трава минимум втрое гуще пустошей (факт %.3f vs %.3f)"
				% [dense_rate, bare_rate])
	else:
		fail_test("проба не покрыла оба типа пятен (гуще %d / пустошей %d)"
			% [dense_count, bare_count])


func test_flower_kinds_and_counts() -> void:
	# Цветы — три вида демо, по ~50 на круге HIGH (допуск 20–120: пятна
	# шума и зоны режут), вид пятна детерминирован крупной клеткой —
	# в одном пятне виды не смешиваются.
	var gathered := _gather_around(Vector2(20.0, 25.0), GraphicsQuality.Tier.HIGH)
	for kind: String in ["white", "blue", "yellow"]:
		var transforms: Array = \
			gathered["flower_%s" % kind]["transforms"]
		assert_between(transforms.size(), 20, 120,
			"цветов вида %s ~50 на круге HIGH (факт %d)"
				% [kind, transforms.size()])
		for xf: Transform3D in transforms:
			assert_eq(GrassField.flower_kind_for(
				roundi(xf.origin.x), roundi(xf.origin.z)), kind,
				"вид цветка согласован с клеткой пятна (%s)" % kind)
			var scale: float = xf.basis.x.length()
			assert_between(scale, GrassField.FLOWER_SCALE_FROM - 0.0001,
				GrassField.FLOWER_SCALE_TO + 0.0001,
				"масштаб цветка = 0.02–0.05 демо ×k")


func test_flowers_follow_tuft_zones() -> void:
	# Цветы селятся теми же зонами, что трава: не на воде/Площади/дворах.
	var gathered := _gather_around(
		Vector2(-30.0, -30.0), GraphicsQuality.Tier.ULTRA)
	var total := 0
	for kind: String in ["white", "blue", "yellow"]:
		for xf: Transform3D in gathered["flower_%s" % kind]["transforms"]:
			total += 1
			var pos := Vector2(xf.origin.x, xf.origin.z)
			assert_gt(xf.origin.y, GrassField.BEACH_H,
				"цветок выше линии пляжа/воды")
			assert_false(IslandGen.on_village_pad(pos),
				"цветок не растёт во дворах построек")
			assert_lt(ForestGround._plaza_weight(pos.x, pos.y), 0.06,
				"цветок не растёт на Площади")
	assert_gt(total, 5, "цветы в чаще Леса есть (проба не пустая)")


# --- ноды и материал ---

func test_field_nodes_and_material() -> void:
	# Ноды: пучки с инстанс-цветами и по ноде на поверхность цветов
	# (раскладка вида общая); материал — PBR-шейдер grass_ez без ручного
	# light() (тени принимает), без тени отбрасывания (П18 блок 4 —
	# кляксы у ног), кромка fade от радиуса уровня, ветер формулы крон,
	# эмиссия и затемнение — числа демо.
	var code := FIELD_SHADER.code
	assert_false(code.contains("void light()"),
		"без ручного light(): PBR-тени, как у демо (MeshStandardMaterial)")
	assert_true(code.contains("mat_dim"),
		"затемнение материала 0.6 демо — uniform")
	assert_true(code.contains("emission_color"),
		"эмиссия 0x308040 × 0.05 демо — uniform")
	assert_true(code.contains("VERTEX *= keep"),
		"кромка: масштаб пучка к нулю, не обрыв")
	assert_false(code.contains("alpha_blend"), "без alpha blend")
	WorldMaterials.textured_headless = true
	var nodes := GrassField.make_nodes(GraphicsQuality.Tier.HIGH)
	assert_true(nodes.has("grass_tuft"), "нода пучков")
	var kinds := 0
	for type: String in nodes:
		assert_eq((nodes[type] as MultiMeshInstance3D).cast_shadow,
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"поле не отбрасывает тени (%s)" % type)
		if type.begins_with("flower_"):
			kinds += 1
	assert_eq(kinds, 20,
		"по ноде на поверхность цветов (6+7+7 из GLB)")
	var tuft: MultiMeshInstance3D = nodes["grass_tuft"]
	assert_true(tuft.multimesh.use_colors,
		"пучки несут инстанс-тон раскладки")
	var material := tuft.material_override as ShaderMaterial
	assert_eq(material.shader, FIELD_SHADER, "материал пучков — grass_ez")
	assert_almost_eq(float(material.get_shader_parameter("mat_dim")),
		0.6, 0.0001, "затемнение материала демо ×0.6")
	assert_almost_eq(float(
		material.get_shader_parameter("emission_energy")), 0.05, 0.0001,
		"эмиссия демо ×0.05")
	assert_almost_eq(float(material.get_shader_parameter("fade_start")),
		GrassField.radius_for_tier(GraphicsQuality.Tier.HIGH)
			- GrassField.EDGE_M, 0.0001, "кромка начинается у радиуса − EDGE")
	assert_almost_eq(float(material.get_shader_parameter("fade_end")),
		GrassField.radius_for_tier(GraphicsQuality.Tier.HIGH), 0.0001,
		"кромка заканчивается на радиусе уровня")
	assert_almost_eq(float(material.get_shader_parameter("wind_strength")),
		0.5 * GrassField.K, 0.0001, "ветер — амплитуда крон (0.5·k)")
	assert_almost_eq(float(
		material.get_shader_parameter("wind_noise_scale")),
		70.0 * GrassField.K, 0.0001, "масштаб шума ветра крон (70·k)")
	WorldMaterials.textured_headless = false


func test_field_apply_fills_buffers() -> void:
	# apply_field переносит gather в ноды: счётчики пучков и цветов
	# честны, пустая раскладка очищает буферы.
	var nodes := GrassField.make_nodes(GraphicsQuality.Tier.HIGH)
	var gathered := _gather_around(Vector2(20.0, 25.0), GraphicsQuality.Tier.HIGH)
	GrassField.apply_field(nodes, gathered)
	var mm: MultiMesh = (nodes["grass_tuft"] as MultiMeshInstance3D).multimesh
	assert_eq(mm.instance_count,
		(gathered["tuft"]["transforms"] as Array).size(),
		"счётчик пучков = раскладка gather")
	assert_gt(mm.instance_count, 0, "поле не пусто")
	GrassField.apply_field(nodes, GrassField.gather_from({}))
	assert_eq((nodes["grass_tuft"] as MultiMeshInstance3D) \
		.multimesh.instance_count, 0, "пустая раскладка очищает буфер")


# --- земля не менялась ---

func test_field_heights_hash_unchanged() -> void:
	# Поле садится поверх земли, карта высот и коллизия обязаны совпасть
	# побитово (контроль перезапёк island_art не нужен — поле рантаймное).
	var checksum := 0
	for h: float in ART.heights:
		checksum = hash([checksum, h])
	assert_eq(checksum, HEIGHTS_CHECKSUM,
		"карта высот арта не изменилась (хеш)")


# --- помощники ---

func _chunks_around(center: Vector2, tier: int) -> Dictionary:
	var chunks: Dictionary = {}
	for key: Vector2i in GrassField.chunk_keys(tier, center):
		chunks[key] = GrassField.build_chunk(ART, tier, key.x, key.y)
	return chunks


func _gather_around(center: Vector2, tier: int) -> Dictionary:
	return GrassField.gather_from(_chunks_around(center, tier))


func _tuft_transforms(gathered: Dictionary) -> Array:
	return gathered["tuft"]["transforms"]


func _tuft_colors(gathered: Dictionary) -> PackedColorArray:
	return gathered["tuft"]["colors"]
