# Земля Леса (П5.9 переделка, П2): сектор острова [-128..0)² красится
# поверх тех же low-poly чанков текстурной землёй по схеме демо ez-tree —
# трава и грунт (CC0-замены текстур демо, тон сведён к демо) смешиваются
# симплекс-шумом, меш, коллизия и запечённый island_art.res не меняются
# (хеш острова тот же). ForestGround печёт из карты высот две карты
# 128 × 128 (1 пиксель = 1 м): веса оверлеев (уклон → камень, низины →
# влажная земля, пятна мха — фиксированный шум FastNoiseLite, тропа и
# полоса Площади — утоптанная земля) и тон края (точный цвет соседних
# low-poly чанков тем же TerrainBuilder.point_color) — и собирает
# ShaderMaterial (assets/shaders/forest_ground.gdshader). Всё
# детерминировано: высоты, уклоны и фиксированный seed. Внутренние края
# сектора плавно растворяются в цвет соседей — шва на границе Леса нет.
class_name ForestGround
extends RefCounted

## Сторона сектора Леса, м (= стороне карты покраски).
const SECTOR_M: int = 128

## Камень на крутых склонах: тангенс уклона (dh на 1 м).
const ROCK_SLOPE_SOFT: float = 0.45
const ROCK_SLOPE_FULL: float = 0.75

## Влажная земля низин: ниже полной отметки — сыро, выше мягкой — сухо.
const WET_H_FULL: float = 0.8
const WET_H_SOFT: float = 3.2

## Тропа от Площади вглубь Леса: полилиния и полуширины (полная, мягкий край).
const PATH_POINTS: PackedVector2Array = [
	Vector2(-16.0, -10.0), Vector2(-34.0, -26.0), Vector2(-50.0, -48.0),
]
const PATH_HALF_FULL: float = 1.4
const PATH_HALF_SOFT: float = 3.0

## Утоптанный гравий Площади: круг зоны plaza (центр и радиус — как в IslandGen).
const PLAZA_CENTER: Vector2 = Vector2(0.0, 4.0)
const PLAZA_R_FULL: float = 20.0
const PLAZA_R_SOFT: float = 24.0

## Мягкий край сектора (SPEC 2.5: «на границе Леса — мягкий переход без
## шва»): у внутренних краёв x = 0 и z = 0 вес края 1 — текстура полностью
## тонирована точным цветом соседнего low-poly чанка, вглубь гаснет за
## EDGE_SOFT метров. Морские края (x/z = −128) не смягчаем — соседа нет.
const EDGE_FULL: float = 2.0
const EDGE_SOFT: float = 12.0

## Шум пятен мха (тот же принцип детерминизма, что у генератора).
const MOSS_SEED: int = 5707
const MOSS_FREQUENCY: float = 0.045

## Каналы карты весов (RGBA8): r камень, g влага, b мох, a тропа/гравий.
const CH_ROCK: int = 0
const CH_WET: int = 1
const CH_MOSS: int = 2
const CH_PATH: int = 3

const SHADER: Shader = preload("res://assets/shaders/forest_ground.gdshader")
const VPAL: VisualPalette = preload("res://assets/visual_palette.tres")

## Текстуры базы земли (П5.9 переделка, П2): трава ambientcg Grass001 и
## грунт polyhaven forest_ground_05 — CC0-замены текстур демо ez-tree
## (ground/*.jpg), чья лицензия не описана в репозитории. Смешивание
## и тайлинг — схема демо (симплекс-шум, константы в шейдере).
const GRASS_TEX: Texture2D = preload(
	"res://assets/third_party/ambientcg.com/Grass001/Grass001_1K-JPG_Color.jpg")
const DIRT_TEX: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/forest_ground_05/forest_ground_05_diffuse_2k.jpg")
const DIRT_NORMAL: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/forest_ground_05/forest_ground_05_nor_gl_2k.jpg")


## Материал земли Леса: карты покраски запекаются из высот запечённого
## острова, цвета пятен берутся из палитры. Детерминирован.
static func make_material(art: IslandArt) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("wet_color", VPAL.ground_wet)
	material.set_shader_parameter("moss_color", VPAL.ground_moss)
	material.set_shader_parameter("rock_color", VPAL.ground_rock)
	material.set_shader_parameter("path_color", VPAL.ground_path)
	material.set_shader_parameter("grass_tex", GRASS_TEX)
	material.set_shader_parameter("dirt_tex", DIRT_TEX)
	material.set_shader_parameter("dirt_normal", DIRT_NORMAL)
	material.set_shader_parameter("weight_map", _weights_texture(art))
	material.set_shader_parameter("border_map", _border_texture(art))
	material.set_shader_parameter("relief_normal", _relief_texture(art))
	return material


## Карта весов оверлеев: чистые функции высоты, уклона и фиксированного
## шума — одна и та же точка всегда даёт тот же вес.
static func _weights_image(art: IslandArt) -> Image:
	var image := Image.create_empty(SECTOR_M, SECTOR_M, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = MOSS_SEED
	noise.frequency = MOSS_FREQUENCY
	for z: int in SECTOR_M:
		for x: int in SECTOR_M:
			var wx: float = float(x) - 128.0
			var wz: float = float(z) - 128.0
			# Пиксель (x, z) — мир (x−128, z−128); индекс карты: (z)*POINTS + x.
			var h: float = art.heights[z * IslandGen.POINTS + x]
			var w_rock: float = smoothstep(
				ROCK_SLOPE_SOFT, ROCK_SLOPE_FULL, _slope(art, x, z))
			var w_wet: float = 1.0 - smoothstep(WET_H_FULL, WET_H_SOFT, h)
			var w_moss: float = _moss_weight(noise, x, z, w_rock, w_wet)
			# Тропа и гравий Площади — один слот утоптанной земли.
			var w_plaza: float = _plaza_weight(wx, wz)
			var w_path: float = maxf(_path_weight(wx, wz), w_plaza)
			# П5.9 переделка, П3: в русле оврага тропа гасится — утоптанная
			# земля по дну читалась коричневой лентой поперёк склонов. Дно
			# красят свои веса (камень стенок, влага низины), подходы
			# к мостику остаются тропой до самого настила.
			w_path *= smoothstep(
				IslandGen.GULLY_HALF_W + 0.5,
				IslandGen.GULLY_HALF_W + 1.5,
				IslandGen.gully_across(roundi(wx), roundi(wz)))
			# Край сектора гасит оверлеи: у границы — чистая тонированная
			# подстилка цветом соседней зоны. Вымощенная Площадь не гасится:
			# она и есть соседняя зона, гравий лежит до самого края,
			# тон края сводит цвет с низкополигональными плитами.
			var fade: float = 1.0 - _border_weight(wx, wz) * (1.0 - w_plaza)
			image.set_pixel(x, z, Color(
				w_rock * fade, w_wet * fade, w_moss * fade, w_path * fade))
	return image


## Карта края: RGB — цвет соседнего low-poly рельефа (та же функция, что
## красит чанки, включая подсказки террас Площади), A — вес края.
static func _border_image(art: IslandArt) -> Image:
	var image := Image.create_empty(SECTOR_M, SECTOR_M, false, Image.FORMAT_RGBA8)
	var tint: Dictionary = IslandGen.tint_hints()
	for z: int in SECTOR_M:
		for x: int in SECTOR_M:
			var wx: float = float(x) - 128.0
			var wz: float = float(z) - 128.0
			var low_poly: Color = TerrainBuilder.point_color(
				art.heights, tint, int(wx), int(wz))
			var weight: float = _border_weight(wx, wz)
			image.set_pixel(x, z, Color(low_poly.r, low_poly.g, low_poly.b, weight))
	return image


static func _weights_texture(art: IslandArt) -> ImageTexture:
	return ImageTexture.create_from_image(_weights_image(art))


static func _border_texture(art: IslandArt) -> ImageTexture:
	return ImageTexture.create_from_image(_border_image(art))


## Карта честных нормалей рельефа (П5.9 переделка, П3): сглаженные нормали
## склонов из карты высот конечными разностями (шаг сетки 1 м):
## n = normalize(h(x−1,z) − h(x+1,z), 2, h(x,z−1) − h(x,z+1)). В шейдере
## она заменяет сглаживание «к вертикали»: на крутых стенках оврага
## нормаль смотрит поперёк склона — белая огранка больших low-poly граней
## исчезает, объём рельефа остаётся. Кодируется как n·0.5+0.5 (данные,
## не цвет — без source_color); мип-мапы усредняют дальние склоны.
static func _relief_image(art: IslandArt) -> Image:
	var image := Image.create_empty(SECTOR_M, SECTOR_M, false, Image.FORMAT_RGB8)
	for z: int in SECTOR_M:
		for x: int in SECTOR_M:
			var left: float = art.heights[
				z * IslandGen.POINTS + maxi(x - 1, 0)]
			var right: float = art.heights[
				z * IslandGen.POINTS + mini(x + 1, SECTOR_M - 1)]
			var north: float = art.heights[
				maxi(z - 1, 0) * IslandGen.POINTS + x]
			var south: float = art.heights[
				mini(z + 1, SECTOR_M - 1) * IslandGen.POINTS + x]
			var n := Vector3(left - right, 2.0, north - south).normalized()
			image.set_pixel(x, z, Color(
				0.5 + n.x * 0.5, 0.5 + n.y * 0.5, 0.5 + n.z * 0.5))
	image.generate_mipmaps()
	return image


static func _relief_texture(art: IslandArt) -> ImageTexture:
	return ImageTexture.create_from_image(_relief_image(art))


## Максимальный тангенс уклона в точке по соседям карты высот (кламп на краях).
## x, z — пиксельные координаты сектора 0..127 (мир − 128).
static func _slope(art: IslandArt, x: int, z: int) -> float:
	var here: float = art.heights[z * IslandGen.POINTS + x]
	var worst := 0.0
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = clampi(x + offset.x, 0, SECTOR_M - 1)
		var nz: int = clampi(z + offset.y, 0, SECTOR_M - 1)
		var h: float = art.heights[nz * IslandGen.POINTS + nx]
		worst = maxf(worst, absf(h - here))
	return worst


## Вес тропы: расстояние до полилинии, полный внутри PATH_HALF_FULL,
## плавный ноль к PATH_HALF_SOFT.
static func _path_weight(wx: float, wz: float) -> float:
	var best := 1e9
	for i: int in PATH_POINTS.size() - 1:
		best = minf(
			best,
			Geometry2D.get_closest_point_to_segment(
				Vector2(wx, wz), PATH_POINTS[i], PATH_POINTS[i + 1],
			).distance_to(Vector2(wx, wz)),
		)
	return 1.0 - smoothstep(PATH_HALF_FULL, PATH_HALF_SOFT, best)


## Вес гравийной полосы Площади (круг зоны plaza, как в IslandGen).
static func _plaza_weight(wx: float, wz: float) -> float:
	return 1.0 - smoothstep(
		PLAZA_R_FULL, PLAZA_R_SOFT,
		Vector2(wx, wz).distance_to(PLAZA_CENTER))


## Вес мягкого края: 1 у внутренних границ сектора (x = 0, z = 0),
## 0 от EDGE_SOFT вглубь.
static func _border_weight(wx: float, wz: float) -> float:
	return 1.0 - smoothstep(EDGE_FULL, EDGE_SOFT, minf(-wx, -wz))


## Мох: пятна фиксированного шума, гуще во влажных местах, не на камне.
static func _moss_weight(
		noise: FastNoiseLite, x: int, z: int, w_rock: float, w_wet: float) -> float:
	var patch: float = smoothstep(0.05, 0.75, (noise.get_noise_2d(x, z) + 1.0) * 0.5)
	return patch * (1.0 - w_rock) * (0.45 + 0.55 * w_wet)
