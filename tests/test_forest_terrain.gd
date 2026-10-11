# Тесты реалистичной земли Леса (П5.7, блок 1): сектор [−128..0)² красится
# материалом ForestGround поверх тех же чанков и той же коллизии — запечённый
# остров не меняется. Карты весов и края детерминированы (высоты, уклоны,
# фиксированный шум), правила покраски проверяются по точкам, цвет края —
# тем же TerrainBuilder.point_color, что у соседних low-poly чанков.
extends GutTest

const ART: IslandArt = preload("res://gameplay/world/island_art.res")
const ISLAND: PackedScene = preload("res://gameplay/world/island.tscn")


## Пиксель карты по мировым координатам (сектор — [-128..0)²).
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
	for z: int in ForestGround.SECTOR_M:
		for x: int in ForestGround.SECTOR_M:
			if x < 16 and z < 16:
				continue  # полоса края: оверлеи там гасятся
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


func test_material_textures_and_shader() -> void:
	# Все десять текстур ambientCG подключены, шейдер — лесная земля.
	var material := ForestGround.make_material(ART)
	assert_eq(
		material.shader.resource_path,
		"res://assets/shaders/forest_ground.gdshader",
		"материал на шейдере forest_ground")
	for slot: String in ["litter", "wet", "moss", "rock", "path"]:
		for kind: String in ["albedo", "normal"]:
			var texture: Texture2D = material.get_shader_parameter(
				slot + "_" + kind)
			assert_not_null(texture, "%s_%s подключена" % [slot, kind])
			assert_gt(texture.get_width(), 1024, "%s_%s — 2K-набор" % [slot, kind])
	assert_not_null(
		material.get_shader_parameter("weight_map"), "карта весов в материале")
	assert_not_null(
		material.get_shader_parameter("border_map"), "карта края в материале")


func test_island_uses_forest_material() -> void:
	# В сцене: 16 чанков сектора Леса с материалом ForestGround, остальные
	# 48 — low-poly; коллизия по-прежнему одна на весь остров.
	var island := ISLAND.instantiate() as Island
	add_child_autofree(island)
	var terrain := island.get_node("IslandView/Terrain") as StaticBody3D
	var forest := 0
	var low_poly := 0
	for node: Node in terrain.get_children():
		if node is MeshInstance3D:
			if (node as MeshInstance3D).material_override is ShaderMaterial:
				forest += 1
			else:
				low_poly += 1
	assert_eq(
		forest, 16, "16 чанков Леса с материалом ForestGround")
	assert_eq(
		low_poly,
		TerrainBuilder.CHUNKS_PER_SIDE * TerrainBuilder.CHUNKS_PER_SIDE - 16,
		"остальные чанки — low-poly")
	var shapes := 0
	for child: Node in terrain.get_children():
		if child is CollisionShape3D:
			shapes += 1
	assert_eq(shapes, 1, "коллизия одна на весь остров")
