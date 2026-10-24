# Тесты реалистичной земли в стиле Леса (П5.7, блок 1; доработка П5.13 —
# весь остров): чанки красятся материалом ForestGround поверх той же
# коллизии — запечённый остров не меняется. Карты весов и тона
# детерминированы (высоты, уклоны, фиксированный шум), правила покраски
# проверяются по точкам, цвет тона — тем же TerrainBuilder.point_color,
# что у low-poly граней и карты-миниатюры.
extends GutTest

const ART: IslandArt = preload("res://gameplay/world/island_art.res")
const ISLAND: PackedScene = preload("res://gameplay/world/island.tscn")


## Пиксель карты по мировым координатам (карта — весь остров, пиксель = 1 м).
static func _pixel(image: Image, wx: float, wz: float) -> Color:
	return image.get_pixel(int(wx) + 128, int(wz) + 128)


func test_weights_paint() -> void:
	# Правила покраски: гравий Площади в углу сектора, тропа от Площади,
	# морской угол низко — влажная земля, вдали от геометрии троп —
	# канал тропы чист.
	var weights := ForestGround._weights_image(ART)
	assert_gt(
		_pixel(weights, -8.0, -8.0)[ForestGround.CH_PATH], 0.9,
		"полоса Площади в секторе — утоптанный гравий до края")
	assert_gt(
		_pixel(weights, -34.0, -26.0)[ForestGround.CH_PATH], 0.5,
		"тропа от Площади вглубь Леса")
	# Самая низкая точка сектора — гарантированно сырая (вдали от краёв,
	# чтобы вес не гасилось смягчением). Индекс карты: пиксель (x, z)
	# сектора — это строка z, столбец x карты острова (мир = пиксель − 128).
	var lowest := Vector2i(-70, -60)
	for z: int in ForestGround.MAP_M:
		for x: int in ForestGround.MAP_M:
			if x < 16 and z < 16:
				continue  # полоса края: оверлеи там гасятся
			if x >= 128 or z >= 128:
				continue  # ищем по сектору Леса, как раньше
			var h: float = ART.heights[z * IslandGen.POINTS + x]
			var h_low: float = ART.heights[
				(lowest.y + 128) * IslandGen.POINTS + lowest.x + 128]
			if h < h_low:
				lowest = Vector2i(x - 128, z - 128)
	assert_gt(
		_pixel(weights, lowest.x, lowest.y)[ForestGround.CH_WET], 0.9,
		"самая низкая точка сектора — влажная земля")
	assert_almost_eq(
		_pixel(weights, -70.0, -60.0)[ForestGround.CH_PATH], 0.0, 0.01,
		"в глубине Леса тропы нет")


func test_border_paint() -> void:
	# Мягкий край: у внутренних границ вес 1 и цвет — ровно цвет соседнего
	# low-poly рельефа (point_color), вглубь сектора край гаснет и оверлеи
	# возвращаются.
	var border := ForestGround._border_image(ART)
	var weights := ForestGround._weights_image(ART)
	var edge := _pixel(border, -2.0, -40.0)
	assert_almost_eq(edge.a, 1.0, 0.05, "у самой границы вес края полный")
	var low_poly: Color = TerrainBuilder.point_color(
		ART.heights, IslandGen.tint_hints(), -2, -40)
	assert_almost_eq(edge.r, low_poly.r, 0.01, "цвет края = цвет соседа (r)")
	assert_almost_eq(edge.g, low_poly.g, 0.01, "цвет края = цвет соседа (g)")
	assert_almost_eq(edge.b, low_poly.b, 0.01, "цвет края = цвет соседа (b)")
	assert_almost_eq(
		maxf(
			_pixel(weights, -2.0, -40.0).r,
			maxf(
				_pixel(weights, -2.0, -40.0).g,
				maxf(
					_pixel(weights, -2.0, -40.0).b,
					_pixel(weights, -2.0, -40.0).a))),
		0.0, 0.1,
		"у самой границы оверлеи погашены")
	assert_almost_eq(
		_pixel(border, -40.0, -40.0).a, 0.0, 0.01,
		"в глубине сектора края нет")
	assert_almost_eq(
		_pixel(border, -127.0, -60.0).a, 0.0, 0.01,
		"морской край не смягчается (соседа нет)")


func test_paint_is_deterministic() -> void:
	# Две выпечки дают побайтно одинаковые карты: генерация детерминирована.
	var w1 := ForestGround._weights_image(ART)
	var w2 := ForestGround._weights_image(ART)
	assert_eq(w1.get_data(), w2.get_data(), "карта весов воспроизводима")
	var b1 := ForestGround._border_image(ART)
	var b2 := ForestGround._border_image(ART)
	assert_eq(b1.get_data(), b2.get_data(), "карта края воспроизводима")


func test_material_colors_and_shader() -> void:
	# П12 «Земля»: шесть PBR-слоёв по тем же весам — у каждого слоя
	# три карты (albedo/nor_gl/ORM) и тинт; карт покраски три. Сэмплеров
	# пустых нет (SPEC П12 приёмка: «шейдер земли получает все карты
	# слоёв»), тинты — константы BU из ForestGround.
	var material := ForestGround.make_material(ART, GraphicsQuality.Tier.HIGH)
	assert_eq(
		material.shader.resource_path,
		"res://assets/shaders/forest_ground.gdshader",
		"материал на шейдере forest_ground")
	for pair: Array in [
		["litter_tint", ForestGround.TINT_LITTER],
		["grass_tint", ForestGround.TINT_GRASS],
		["rock_tint", ForestGround.TINT_ROCK],
		["mud_tint", ForestGround.TINT_MUD],
		["moss_tint", ForestGround.TINT_MOSS],
		["gravel_tint", ForestGround.TINT_GRAVEL],
	]:
		var color: Color = material.get_shader_parameter(pair[0])
		assert_almost_eq(
			color.r, (pair[1] as Color).r, 0.001, "%s — константа BU (r)" % pair[0])
		assert_almost_eq(
			color.g, (pair[1] as Color).g, 0.001, "%s — константа BU (g)" % pair[0])
		assert_almost_eq(
			color.b, (pair[1] as Color).b, 0.001, "%s — константа BU (b)" % pair[0])
	assert_almost_eq(
		material.get_shader_parameter("tint_mix"),
		ForestGround.TINT_MIX, 0.001, "доля тинта — константа")
	for layer: String in ["litter", "grass", "rock", "mud", "moss", "gravel"]:
		for kind: String in ["tex", "normal", "orm"]:
			var uniform_name := "%s_%s" % [layer, kind]
			assert_not_null(
				material.get_shader_parameter(uniform_name),
				"%s в материале" % uniform_name)
	for uniform_name: String in ["weight_map", "border_map", "relief_normal"]:
		assert_not_null(
			material.get_shader_parameter(uniform_name),
			"%s в материале" % uniform_name)


func test_gully_path_is_erased() -> void:
	# П5.9 переделка, П3: в русле оврага тропы нет — утоптанная земля
	# по дну читалась коричневой лентой поперёк склонов. Подход к мостику
	# (точка на тропе в паре метров от русла) остаётся тропой.
	var weights := ForestGround._weights_image(ART)
	assert_almost_eq(
		_pixel(weights, IslandGen.GULLY_MID.x, IslandGen.GULLY_MID.y)[
			ForestGround.CH_PATH],
		0.0, 0.05, "дно русла — без тропы")
	assert_gt(
		_pixel(weights, -43.6, -39.2)[ForestGround.CH_PATH], 0.5,
		"подход к мостику — тропа")


func test_relief_normals_bend_on_gully_walls() -> void:
	# П5.9 переделка, П3: карта честных нормалей рельефа из карты высот —
	# на стенках оврага нормали заметно наклонены (сглаженное поле
	# заменяет сглаживание «к вертикали»: белая огранка low-poly граней
	# исчезает, объём остаётся), вдали от оврага поле почти вертикально.
	var normals := ForestGround._relief_image(ART)
	var min_up := 1.0
	for z: int in range(-52, -39):
		for x: int in range(-54, -42):
			min_up = minf(min_up, normals.get_pixel(x + 128, z + 128).g * 2.0 - 1.0)
	assert_lt(min_up, 0.8, "на склонах оврага нормали наклонены")
	var flat_min := 1.0
	for z: int in range(-110, -100):
		for x: int in range(-90, -80):
			flat_min = minf(flat_min, normals.get_pixel(x + 128, z + 128).g * 2.0 - 1.0)
	assert_gt(flat_min, 0.75, "лесные склоны вдали от оврага — мягкие")


func test_island_uses_forest_material() -> void:
	# В сцене: все 64 чанка острова с материалом ForestGround (доработка
	# П5.13 — текстурная земля в стиле Леса на весь остров, Terrain3D
	# больше не используется); коллизия по-прежнему одна на весь остров.
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	var terrain := island.get_node("IslandView/Terrain") as StaticBody3D
	var forest := 0
	var others := 0
	for node: Node in terrain.get_children():
		if node is MeshInstance3D:
			if (node as MeshInstance3D).material_override is ShaderMaterial:
				forest += 1
			else:
				others += 1
	assert_eq(
		forest, TerrainBuilder.CHUNKS_PER_SIDE * TerrainBuilder.CHUNKS_PER_SIDE,
		"все 64 чанка острова с материалом ForestGround")
	assert_eq(others, 0, "чанков с другим материалом нет")
	var shapes := 0
	for child: Node in terrain.get_children():
		if child is CollisionShape3D:
			shapes += 1
	assert_eq(shapes, 1, "коллизия одна на весь остров")


func test_maps_cover_whole_island() -> void:
	# Доработка П5.13: карты покраски — весь остров 256 × 256 (пиксель = 1 м),
	# не только сектор Леса.
	for image: Image in [
		ForestGround._weights_image(ART),
		ForestGround._border_image(ART),
		ForestGround._relief_image(ART),
	]:
		assert_eq(image.get_width(), ForestGround.MAP_M, "карта шириной 256")
		assert_eq(image.get_height(), ForestGround.MAP_M, "карта высотой 256")


func test_outside_tone_paints_zones() -> void:
	# Доработка П5.13: вне Леса вес тона — материал точки: пляж и террасы —
	# чистый цвет point_color (тон 1), луг — смесь с текстурной землёй
	# (тон MEADOW_TONE..ROCK_TONE по уклону). Граница Леса непрерывна:
	# у линии снаружи вес тоже 1 (обобщённый краевой вес).
	var border := ForestGround._border_image(ART)
	# Первая надводная точка пляжа вне Леса (высота между уровнем воды
	# и песчаной отметкой): тон полный — чистый цвет point_color.
	var beach := Vector2i.ZERO
	var found_beach := false
	for z: int in ForestGround.MAP_M:
		if found_beach:
			break
		for x: int in range(128, ForestGround.MAP_M):
			var h: float = ART.heights[z * IslandGen.POINTS + x]
			if h > IslandGen.SEA_LEVEL and h < TerrainBuilder.SAND_H:
				beach = Vector2i(x - 128, z - 128)
				found_beach = true
				break
	assert_true(found_beach, "надводный пляж вне Леса найден")
	assert_almost_eq(
		_pixel(border, beach.x, beach.y).a, 1.0, 0.01,
		"пляж вне Леса — чистый тон point_color")
	# Внутри острова, на лугу (не пляж, не терраса): тон в диапазоне
	# луг↔скала, не крайние значения.
	var meadow := Vector2i(40, -40)
	for z: int in range(-60, -20):
		var h: float = ART.heights[(z + 128) * IslandGen.POINTS + 40 + 128]
		var hint: Dictionary = IslandGen.tint_hints().get(
			Vector2i(40, z), {})
		if h > TerrainBuilder.SAND_H + 0.5 and h < 8.0 and hint.is_empty():
			meadow = Vector2i(40, z)
			break
	var meadow_a: float = _pixel(border, meadow.x, meadow.y).a
	assert_between(meadow_a, 0.3, 0.95,
		"луг вне Леса — смесь текстуры и тона, не крайние значения (a=%.2f)"
		% meadow_a)
	# Непрерывность через границу Леса: вес у линии с обеих сторон — 1.
	assert_almost_eq(
		_pixel(border, -1.0, -60.0).a, 1.0, 0.05, "у границы изнутри Леса")
	assert_almost_eq(
		_pixel(border, 1.0, -60.0).a, 1.0, 0.05, "у границы снаружи Леса")
