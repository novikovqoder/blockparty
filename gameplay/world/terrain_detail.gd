# П14 3.1: кольцо детальной сетки земли вокруг камеры. Ближние чанки —
# квад 0.5 м без смещения вершин: сантиметровых бугров, колеи и камней
# из земли нет. Кольцо — плоская сетка (вершины только XZ, топология
# строится один раз), нода снапится к камере с шагом сетки, а высоту
# вершинам ставит vertex() шейдера forest_ground (uniform detail_ring):
# height_at по карте высот + смещение по ORM.B слоёв с height-blend
# весами ForestGround. Смещение центрировано (средняя карта высоты слоя
# вычитается) — средняя высота кольца над чанками ≈ 0, коллизия
# (HeightMapShape3D) не меняется, ступни не проваливаются. К краю кольца
# смещение и подъём гаснут — стык с чанками без шва. SIMPLE/NORMAL —
# кольца нет (как раньше). Хеш острова не меняется: кольцо — рантайм.
class_name TerrainDetail
extends RefCounted

## Шаг сетки кольца и радиус по уровням (SPEC П14 3.1; П16 п. 3 радиус
## HIGH 12 м — вчетверо меньше вершин, чем при 24): HIGH 0.25 м / 12 м,
## ULTRA 0.125 м / 24 м.
const STEP_HIGH: float = 0.25
const STEP_ULTRA: float = 0.125
const RADIUS_HIGH: float = 12.0
const RADIUS_ULTRA: float = 24.0

## Амплитуды смещения слоёв, м (SPEC П14 3.1): подстилка/гравий ±3–5 см,
## грязь и колея до 8–10 см, скала до 15 см; трава почти плоская.
## Те же значения использует POM во fragment (общая глубина рельефа слоя).
const AMP_LITTER: float = 0.04
const AMP_GRASS: float = 0.02
const AMP_ROCK: float = 0.15
const AMP_MUD: float = 0.09
const AMP_MOSS: float = 0.03
const AMP_GRAVEL: float = 0.05

## Подъём кольца над чанками (мм): кольцо всегда чуть выше печёной
## поверхности (расхождение интерполяций до сантиметров), к кромке
## гаснет вместе со смещением — перекрытие без z-fighting.
const RING_LIFT: float = 0.004
## Полоса гашения смещения у кромки, м (смещение → 0 раньше подъёма).
const EDGE_FADE: float = 1.5


## Кольцо включено на HIGH/ULTRA (SPEC П14 3.1: NORMAL/SIMPLE — как раньше).
static func is_ring_enabled(tier: int) -> bool:
	return tier >= GraphicsQuality.Tier.HIGH


static func step_for_tier(tier: int) -> float:
	return STEP_ULTRA if tier == GraphicsQuality.Tier.ULTRA else STEP_HIGH


static func radius_for_tier(tier: int) -> float:
	return RADIUS_ULTRA if tier == GraphicsQuality.Tier.ULTRA else RADIUS_HIGH


## Плоская сетка кольца: вершины XZ от -radius до radius с шагом step
## (y = 0 — высоту поставит шейдер), индексы — два треугольника на квад.
## Нормали и UV не нужны: фрагментный шейдер читает всё по world_pos.
static func build_mesh(step: float, radius: float) -> ArrayMesh:
	var side: int = int(roundf(radius * 2.0 / step)) + 1
	var vertices := PackedVector3Array()
	vertices.resize(side * side)
	var row: PackedFloat32Array = PackedFloat32Array()
	row.resize(side)
	for i: int in side:
		row[i] = -radius + float(i) * step
	var index: int = 0
	for z: int in side:
		for x: int in side:
			vertices[index] = Vector3(row[x], 0.0, row[z])
			index += 1
	var indices := PackedInt32Array()
	indices.resize((side - 1) * (side - 1) * 6)
	index = 0
	for z: int in side - 1:
		for x: int in side - 1:
			var a: int = z * side + x
			var b: int = a + 1
			var c: int = a + side
			var d: int = c + 1
			indices[index] = a
			indices[index + 1] = c
			indices[index + 2] = b
			indices[index + 3] = b
			indices[index + 4] = c
			indices[index + 5] = d
			index += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Карта высот острова одной RFloat-текстурой (257 × 257, как
## HeightMapShape3D): vertex() кольца ставит вершинам высоту чанков,
## uv = (world.xz + 128) / 256 — та же схема, что карты покраски.
## art.heights уже PackedFloat32Array — байты пикселей RF те же.
static func height_texture(art: IslandArt) -> ImageTexture:
	var image := Image.create_from_data(
		IslandGen.POINTS, IslandGen.POINTS, false,
		Image.FORMAT_RF, art.heights.to_byte_array())
	return ImageTexture.create_from_image(image)


## Средние значения канала высоты (ORM.b) слоёв — центрирование смещения
## (средняя высота кольца ≈ 0) и CPU-копия для тестов. Даунсэмпл 64×64:
## среднее устойчиво к локальным пятнам, цена — миллисекунды.
## Порядок: litter, grass, rock, mud, moss, gravel.
static func orm_means() -> PackedFloat32Array:
	var means := PackedFloat32Array()
	for orm: Texture2D in [
		ForestGround.LITTER_ORM, ForestGround.GRASS_ORM,
		ForestGround.ROCK_ORM, ForestGround.MUD_ORM,
		ForestGround.MOSS_ORM, ForestGround.GRAVEL_ORM,
	]:
		var image := orm.get_image()
		image.resize(64, 64)
		var sum := 0.0
		for y: int in 64:
			for x: int in 64:
				sum += image.get_pixel(x, y).b
		means.append(sum / (64.0 * 64.0))
	return means


## Материал кольца: копия материала чанков (все текстуры и тинты уже
## стоят) с включённым detail_ring, картой высот, средними и радиусом.
static func make_material(
	base: ShaderMaterial, art: IslandArt, tier: int,
) -> ShaderMaterial:
	var material := base.duplicate() as ShaderMaterial
	material.set_shader_parameter("detail_ring", true)
	material.set_shader_parameter("height_tex", height_texture(art))
	var means := orm_means()
	material.set_shader_parameter("orm_mean_a", Vector3(
		means[0], means[2], means[3]))
	material.set_shader_parameter("orm_mean_b", Vector3(
		means[4], means[5], means[1]))
	material.set_shader_parameter("ring_radius", radius_for_tier(tier))
	return material


## CPU-копия смещения шейдера кольца (без tile_break — повороты не меняют
## распределение высот; nearest-выборка): для теста «средняя высота
## смещения ≈ 0 (±1 см)» и отладки. Веса — та же карта weight_map
## ForestGround, база — подстилка (трава в кольце не выделена).
static func displacement_at(
	art: IslandArt, weights: Image, orm_images: Array, means: PackedFloat32Array,
	wx: float, wz: float,
) -> float:
	var px: int = clampi(roundi(wx) + 128, 0, 255)
	var pz: int = clampi(roundi(wz) + 128, 0, 255)
	var w := weights.get_pixel(px, pz)
	var w_base: float = clampf(1.0 - (w.r + w.g + w.b + w.a), 0.0, 1.0)
	var tiles: Array[float] = [
		ForestGround.TILE_M_LITTER, ForestGround.TILE_M_GRASS,
		ForestGround.TILE_M_ROCK, ForestGround.TILE_M_MUD,
		ForestGround.TILE_M_MOSS, ForestGround.TILE_M_GRAVEL,
	]
	var amps: Array[float] = [
		AMP_LITTER, AMP_GRASS, AMP_ROCK, AMP_MUD, AMP_MOSS, AMP_GRAVEL,
	]
	var weights_layer: Array[float] = [
		w_base, 0.0, w.r, w.g, w.b, w.a,
	]
	var total := 0.0
	for i: int in 6:
		var layer_w: float = weights_layer[i]
		if layer_w <= 0.004:
			continue
		var image: Image = orm_images[i]
		var size: float = float(image.get_width())
		var uvx: int = wrapf(
			int(wx / tiles[i] * size), 0, image.get_width() - 1)
		var uvz: int = wrapf(
			int(wz / tiles[i] * size), 0, image.get_height() - 1)
		var h: float = image.get_pixel(uvx, uvz).b
		total += layer_w * (h - means[i]) * amps[i]
	return total


## Загруженные ORM-карты слоёв (для displacement_at в тестах).
static func orm_images() -> Array:
	return [
		ForestGround.LITTER_ORM.get_image(),
		ForestGround.GRASS_ORM.get_image(),
		ForestGround.ROCK_ORM.get_image(),
		ForestGround.MUD_ORM.get_image(),
		ForestGround.MOSS_ORM.get_image(),
		ForestGround.GRAVEL_ORM.get_image(),
	]
