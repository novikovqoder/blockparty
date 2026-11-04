# Тесты П17 сборка 3 «Поле травы» (пп. 6-8 плана docs/gfx_trees/PLAN_p17.md):
# детерминизм раскладки по мировым клеткам (не «плавает» за игроком),
# запретные зоны (вода/пляж, Площадь, дворы, руины, каньон, причал),
# кромка поля с плавным масштабом к нулю, пятна цветов двух видов,
# папоротники только в тени Леса, уровни HIGH/ULTRA (радиус и ½ плотности)
# и материал/шейдер (ветер по вершинной высоте, приминание, fade).
# Карта высот не менялась — сверка хешем, как test_water3.
extends GutTest

const ART: IslandArt = preload("res://gameplay/world/island_art.res")
const SCAN_SHADER: Shader = preload(
	"res://assets/shaders/grass_scan.gdshader")
## Контрольная сумма heights печёного арта (test_water3:19): поле садится
## ПОВЕРХ земли, карта высот (коллизия) обязана совпасть побитово.
const HEIGHTS_CHECKSUM: int = 2041845998


# --- Т4: детерминизм и уровни ---

func test_field_scatter_deterministic() -> void:
	# Раскладка — чистая функция мировых координат: повторный scatter той же
	# клетки даёт те же трансформы и цвета (поле не «плавает» за игроком),
	# бросок rng потребляется всегда — поток не зависит от уровня качества.
	var center := Vector2(20.0, 25.0)  # луг к востоку от Площади
	var ultra := GrassField.scatter(ART, GraphicsQuality.Tier.ULTRA, center)
	var again := GrassField.scatter(ART, GraphicsQuality.Tier.ULTRA, center)
	var total := 0
	for type: String in ultra:
		var first: Array = ultra[type]["transforms"]
		var second: Array = again[type]["transforms"]
		total += first.size()
		assert_eq(first.size(), second.size(),
			"повторная раскладка — то же число (%s)" % type)
		assert_eq((ultra[type]["colors"] as PackedColorArray).size(),
			first.size(), "цветов столько же, сколько пучков (%s)" % type)
		for i: int in mini(first.size(), second.size()):
			assert_true(
				(first[i] as Transform3D).origin.is_equal_approx(
					(second[i] as Transform3D).origin),
				"детерминизм позиций по мировым клеткам (%s)" % type)
	assert_gt(total, 100, "на лугу вокруг центра есть поле")
	# Плотность HIGH = ½ ULTRA на ОБЩЕЙ площади — сравниваем в круге
	# радиуса HIGH (сам радиус уровня проверен в test_field_tiers_*:
	# у HIGH пучки не дальше 30 м, у ULTRA есть и дальше 31 м).
	var radius_high := GrassField.radius_for_tier(GraphicsQuality.Tier.HIGH)
	var total_inside := 0
	for type: String in ultra:
		for xf: Transform3D in ultra[type]["transforms"]:
			if Vector2(xf.origin.x, xf.origin.z).distance_to(center) \
					<= radius_high:
				total_inside += 1
	var high := GrassField.scatter(ART, GraphicsQuality.Tier.HIGH, center)
	var total_high := 0
	for type: String in high:
		total_high += (high[type]["transforms"] as Array).size()
	assert_between(
		float(total_high) / float(maxi(total_inside, 1)), 0.3, 0.7,
		"плотность HIGH ≈ ½ ULTRA той же площади (факт %.2f)"
			% (float(total_high) / float(total_inside)))


func test_field_tiers_radius_and_density() -> void:
	# П17 п.13: поле на HIGH/ULTRA (SIMPLE/NORMAL — печёная подложка),
	# радиусы 30/45 м, HIGH = ½ плотности; луга гуще чащи.
	assert_true(GrassField.is_field_enabled(GraphicsQuality.Tier.ULTRA),
		"ULTRA: поле включено")
	assert_true(GrassField.is_field_enabled(GraphicsQuality.Tier.HIGH),
		"HIGH: поле включено")
	assert_false(GrassField.is_field_enabled(GraphicsQuality.Tier.NORMAL),
		"NORMAL: только печёная подложка rgrass")
	assert_almost_eq(GrassField.radius_for_tier(GraphicsQuality.Tier.ULTRA),
		45.0, 0.0001, "радиус ULTRA ~45 м")
	assert_almost_eq(GrassField.radius_for_tier(GraphicsQuality.Tier.HIGH),
		30.0, 0.0001, "радиус HIGH ~30 м")
	assert_almost_eq(GrassField.density_for_tier(GraphicsQuality.Tier.HIGH),
		0.5, 0.0001, "плотность HIGH = ½")
	assert_almost_eq(GrassField.density_for_tier(
		GraphicsQuality.Tier.ULTRA), 1.0, 0.0001, "плотность ULTRA — базовая")
	assert_gt(GrassField.MEADOW_DENSITY, GrassField.FOREST_DENSITY,
		"луга/опушки гуще чащи Леса")
	# Радиус уровня доезжает до раскладки: HIGH не дальше ~30 м, у ULTRA
	# пучки есть и за пределами круга HIGH.
	var center := Vector2(20.0, 25.0)
	var high := GrassField.scatter(ART, GraphicsQuality.Tier.HIGH, center)
	var radius_high := GrassField.radius_for_tier(GraphicsQuality.Tier.HIGH)
	var beyond_high := 0
	for type: String in high:
		for xf: Transform3D in high[type]["transforms"]:
			assert_lte(
				Vector2(xf.origin.x, xf.origin.z).distance_to(center),
				radius_high + 0.7, "пучок HIGH не дальше радиуса уровня")
	var ultra := GrassField.scatter(ART, GraphicsQuality.Tier.ULTRA, center)
	for type: String in ultra:
		for xf: Transform3D in ultra[type]["transforms"]:
			if Vector2(xf.origin.x, xf.origin.z).distance_to(center) \
					> radius_high + 1.0:
				beyond_high += 1
	assert_gt(beyond_high, 0,
		"ULTRA-поле шире круга HIGH (радиус уровня работает)")


func test_field_within_radius_and_shadow_off() -> void:
	# Пучки не дальше радиуса (дрожание ±0.45 м) и пока без теней —
	# ближнее кольцо ULTRA появится блоком 3, тест обновится там же.
	var center := Vector2(20.0, 25.0)
	var scattered := GrassField.scatter(
		ART, GraphicsQuality.Tier.ULTRA, center)
	for type: String in scattered:
		for xf: Transform3D in scattered[type]["transforms"]:
			assert_lte(
				Vector2(xf.origin.x, xf.origin.z).distance_to(center),
				GrassField.RADIUS_ULTRA + 0.7,
				"пучок не дальше радиуса поля")
	for tier: int in [
		GraphicsQuality.Tier.HIGH, GraphicsQuality.Tier.ULTRA,
	]:
		var nodes := GrassField.make_nodes(tier)
		for type: String in nodes:
			var node: MultiMeshInstance3D = nodes[type]
			assert_eq(node.multimesh.instance_count, 0,
				"ноды строятся пустыми — заполняет apply_field")
			assert_eq(node.cast_shadow,
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"тени поля выключены (блок 3 даст ULTRA-кольцо) (%s)" % type)


# --- Т5: запретные зоны ---

func test_field_blocks_forbidden_zones() -> void:
	# Те же зоны, что у травы-буста: вода/пляж, Площадь, дворы построек,
	# терраса руин, каньон, причал. Центр — чаща Леса в 42 м от Площади:
	# кольцо 45 м захватывает блокируемые клетки — проверка не холостая.
	var center := Vector2(-30.0, -30.0)
	var scattered := GrassField.scatter(ART, GraphicsQuality.Tier.ULTRA, center)
	var total := 0
	for type: String in scattered:
		total += (scattered[type]["transforms"] as Array).size()
	assert_gt(total, 50, "в чаще Леса вокруг есть поле (проба не пустая)")
	for type: String in scattered:
		for xf: Transform3D in scattered[type]["transforms"]:
			var pos := Vector2(xf.origin.x, xf.origin.z)
			assert_gt(xf.origin.y, GrassField.BEACH_H,
				"пучок выше линии пляжа/воды (%s)" % type)
			assert_lt(ForestGround._plaza_weight(pos.x, pos.y), 0.06,
				"поле не растёт на Площади (%s)" % type)
			assert_false(IslandGen.on_village_pad(pos),
				"поле не растёт во дворах построек (%s)" % type)
			assert_gte(pos.distance_to(GroundClutter.RUIN_CENTER), 24.0,
				"поле не растёт на террасе руин (%s)" % type)
			assert_false(
				pos.x >= IslandGen.CREVASSE_X0 - 2.0
				and pos.x <= IslandGen.CREVASSE_X1 + 2.0
				and pos.y >= IslandGen.CREVASSE_Z0 - 2.0
				and pos.y <= IslandGen.CREVASSE_Z1 + 2.0,
				"поле не растёт в каньоне (%s)" % type)
			assert_false(
				pos.x >= 1.5 and pos.x <= 9.5
				and pos.y >= 55.5 and pos.y <= 75.5,
				"поле не растёт на причале (%s)" % type)


# --- Т7: кромка поля — масштаб плавно к нулю ---

func test_field_edge_scale_fades_out() -> void:
	# П17 п.8: последние EDGE_M метров радиуса масштаб пучка уходит к нулю
	# (стык с пустым дальним планом не читается полосой), а не обрывается.
	var center := Vector2(20.0, 25.0)
	var radius := GrassField.radius_for_tier(GraphicsQuality.Tier.ULTRA)
	var scattered := GrassField.scatter(
		ART, GraphicsQuality.Tier.ULTRA, center)
	var near_max_scale := 0.0
	var far_scales: Array[float] = []
	for type: String in scattered:
		if String((scattered[type]["kind"] as Dictionary)["mode"]) == "flower":
			continue  # у цветов пятна и без того редки у кромки
		for xf: Transform3D in scattered[type]["transforms"]:
			var scale: float = xf.basis.x.length()
			# Клетку поля восстанавливаем из позиции: дрожание ±0.45 < 0.5.
			var cell := Vector2(float(roundi(xf.origin.x)),
				float(roundi(xf.origin.z)))
			var dist: float = cell.distance_to(center)
			assert_lte(dist, radius + 0.1, "клетка пучка внутри радиуса")
			if dist > radius - GrassField.EDGE_M:
				var edge: float = clampf(
					(radius - dist) / GrassField.EDGE_M, 0.0, 1.0)
				# база ≤ 1.4 (диапазоны видов), итог = база × edge.
				assert_lte(scale, 1.4 * edge + 0.01,
					"кромка: масштаб ≈ базе × edge (клетка %.1f м)" % dist)
				far_scales.append(scale)
			elif dist < radius - GrassField.EDGE_M - 2.0:
				near_max_scale = maxf(near_max_scale, scale)
	if not far_scales.is_empty():
		assert_true(far_scales.max() < near_max_scale,
			"дальние пучки мельче ближних (кромка садится, не обрывается)")


# --- П17 п.6: пятна цветов и папоротники Леса ---

func test_field_flower_patches_two_kinds() -> void:
	# Цветы пятнами: вид пятна детерминирован крупной клеткой — в одном
	# пятне celandine и dandelion не смешиваются; на карте есть оба вида.
	var found: Dictionary[String, int] = {"gf_celandine": 0, "gf_dandelion": 0}
	for i: int in 10:
		var angle: float = TAU * float(i) / 10.0
		var center := Vector2(60.0 * cos(angle), 60.0 * sin(angle))
		var scattered := GrassField.scatter(
			ART, GraphicsQuality.Tier.ULTRA, center)
		for type: String in ["gf_celandine", "gf_dandelion"]:
			for xf: Transform3D in scattered[type]["transforms"]:
				var cell := Vector2i(roundi(xf.origin.x), roundi(xf.origin.z))
				assert_eq(GrassField.flower_kind_for(cell.x, cell.y), type,
					"вид цветка согласован с клеткой пятна (%s)" % type)
				found[type] += 1
	assert_gt(found["gf_celandine"], 0, "celandine на карте встречается")
	assert_gt(found["gf_dandelion"], 0, "dandelion на карте встречается")


func test_field_ferns_forest_only() -> void:
	# Папоротники — только тень Леса (полуквадрант x < 0, z < 0),
	# дрожание ±0.45 м не должно заносить их за кромку.
	var center := Vector2(-30.0, -30.0)
	var scattered := GrassField.scatter(ART, GraphicsQuality.Tier.ULTRA, center)
	var ferns: Array = scattered["gf_fern"]["transforms"]
	assert_gt(ferns.size(), 3, "в чаще Леса есть папоротники (проба не пустая)")
	for xf: Transform3D in ferns:
		assert_lt(xf.origin.x, 0.5, "папоротник только в Лесу (x < 0)")
		assert_lt(xf.origin.z, 0.5, "папоротник только в Лесу (z < 0)")


# --- материал и шейдер ---

func test_field_shader_wind_press_fade() -> void:
	# Один материал на все виды: ветер — по вершинной высоте (формула
	# листвы), приминание возле персонажа одним uniform press_pos,
	# спад густоты к радиусу уровня; alpha scissor, без alpha blend.
	var code := SCAN_SHADER.code
	assert_true(code.contains("uniform vec3 press_pos"),
		"приминание — uniform press_pos (одна позиция на поле)")
	assert_true(code.contains("height_norm"),
		"сила ветра/приминания растёт с вершинной высотой пучка")
	assert_true(code.contains("VERTEX.y *= 1.0 -"),
		"приминание пригибает вершину к земле")
	assert_false(code.contains("alpha_blend"), "без alpha blend (прозрачность)")
	WorldMaterials.textured_headless = true
	for pair: Array in [
		["HIGH", GraphicsQuality.Tier.HIGH],
		["ULTRA", GraphicsQuality.Tier.ULTRA],
	]:
		var node: MultiMeshInstance3D = \
			GrassField.make_nodes(pair[1])["gf_tall"]
		var material := node.material_override as ShaderMaterial
		assert_eq(material.shader, SCAN_SHADER,
			"%s: материал поля — grass_scan" % pair[0])
		var radius: float = GrassField.radius_for_tier(pair[1])
		assert_almost_eq(float(material.get_shader_parameter("fade_start")),
			radius * 0.55, 0.0001,
			"%s: fade_start от радиуса уровня" % pair[0])
		assert_almost_eq(float(material.get_shader_parameter("fade_end")),
			radius * 0.92, 0.0001,
			"%s: fade_end от радиуса уровня" % pair[0])
	WorldMaterials.textured_headless = false


# --- Т12: земля не менялась ---

func test_field_heights_hash_unchanged() -> void:
	# П17 сборка 3: поле садится поверх земли (тинт подложки — единственная
	# правка ForestGround), карта высот и коллизия обязаны совпасть побитово.
	var checksum := 0
	for h: float in ART.heights:
		checksum = hash([checksum, h])
	assert_eq(checksum, HEIGHTS_CHECKSUM,
		"карта высот арта не изменилась (хеш)")
