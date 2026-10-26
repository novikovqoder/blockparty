# Земля острова в стиле Леса (доработка П5.13): весь остров красится
# поверх low-poly чанков текстурной землёй по схеме демо ez-tree — трава
# и грунт (CC0-замены текстур демо, тон сведён к демо) смешиваются
# симплекс-шумом, меш, коллизия и запечённый island_art.res не меняются
# (хеш острова тот же; Terrain3D больше не используется). ForestGround
# печёт из карты высот три карты 256 × 256 (1 пиксель = 1 м, весь остров):
# веса оверлеев (уклон → камень, низины → влажная земля, пятна мха —
# фиксированный шум FastNoiseLite, тропа и полоса Площади — утоптанный
# гравий), тон (RGB — цвет «материала» точки по TerrainBuilder.point_color:
# пляж, снег, террасы, зональные луга; A — вес тона) и нормали рельефа.
# В секторе Леса [−128..0)² формулы те же, что в принятом П5.9/П5.13 —
# вид Леса не меняется. Вне Леса вес тона — max(краевой вес границы Леса,
# вес материала: пляж/снег/террасы 1, луг 0.35 → скала 0.9; терраса
# Площади — исключение, PLAZA_TONE, фикс П12), поэтому
# переходы между зонами и через границу Леса плавные, без шва. Всё
# детерминировано: высоты, уклоны и фиксированный seed.
class_name ForestGround
extends RefCounted

## Сторона карты покраски, м (= стороне всего острова).
const MAP_M: int = 256

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

## Мягкий край (SPEC 2.5: «на границе Леса — мягкий переход без шва»):
## у границы сектора Леса (с обеих сторон — внутри и снаружи) вес края 1 —
## текстура полностью тонирована точным цветом point_color, вглубь гаснет
## за EDGE_SOFT метров. Морские края (x/z = −128) не смягчаем — соседа нет.
const EDGE_FULL: float = 2.0
const EDGE_SOFT: float = 12.0

## Вес тона вне Леса (доработка П5.13): доля цвета point_color в albedo.
## Луг чуть тонирован текстурной землёй, крутые склоны — почти чистый камень
## (smoothstep до ROCK_TONE по уклону вокруг STONE_SLOPE террас TerrainBuilder).
const MEADOW_TONE: float = 0.35
const ROCK_TONE: float = 0.9

## Тон гравийной Площади (фикс-задача П12, «коричневое пятно»): терраса
## Площади — не плоский камень зоны (тон 1, как у прочих террас), а утоптанный
## гравий: тон снижен до доли луга, текстура rocky_trail читается, цвет лишь
## сводится с низкополигональными плитами зоны.
const PLAZA_TONE: float = 0.35
const ROCK_TONE_FROM: float = TerrainBuilder.STONE_SLOPE - 0.2
const ROCK_TONE_TO: float = TerrainBuilder.STONE_SLOPE + 0.2

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

# --- П12 «Земля»: слои с полным PBR (albedo + nor_gl + ORM) ---
# Текстуры CC0: polyhaven (forest_ground_05, leafy_grass, mud_forest,
# rock_face_03, rocky_trail), ambientcg (Moss001); ORM (R AO / G Roughness /
# B Height) собирает tools/make_orm_textures.gd из карт локальной библиотеки.

const LITTER_TEX: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/forest_ground_05/forest_ground_05_diffuse_2k.jpg")
const LITTER_NORMAL: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/forest_ground_05/forest_ground_05_nor_gl_2k.jpg")
const LITTER_ORM: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/forest_ground_05/forest_ground_05_orm_2k.jpg")
const GRASS_TEX: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/leafy_grass/leafy_grass_diffuse_1k.jpg")
const GRASS_NORMAL: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/leafy_grass/leafy_grass_nor_gl_1k.jpg")
const GRASS_ORM: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/leafy_grass/leafy_grass_orm_1k.jpg")
const ROCK_TEX: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/rock_face_03/rock_face_03_diffuse_2k.jpg")
const ROCK_NORMAL: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/rock_face_03/rock_face_03_nor_gl_2k.jpg")
const ROCK_ORM: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/rock_face_03/rock_face_03_orm_2k.jpg")
const MUD_TEX: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/mud_forest/mud_forest_diffuse_1k.jpg")
const MUD_NORMAL: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/mud_forest/mud_forest_nor_gl_1k.jpg")
const MUD_ORM: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/mud_forest/mud_forest_orm_1k.jpg")
const MOSS_TEX: Texture2D = preload(
	"res://assets/third_party/ambientcg.com/Moss001/Moss001_1K-JPG_Color.jpg")
const MOSS_NORMAL: Texture2D = preload(
	"res://assets/third_party/ambientcg.com/Moss001/Moss001_1K-JPG_NormalGL.jpg")
const MOSS_ORM: Texture2D = preload(
	"res://assets/third_party/ambientcg.com/Moss001/Moss001_1K-JPG_ORM.jpg")
const GRAVEL_TEX: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/rocky_trail/rocky_trail_diffuse_2k.jpg")
const GRAVEL_NORMAL: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/rocky_trail/rocky_trail_nor_gl_2k.jpg")
const GRAVEL_ORM: Texture2D = preload(
	"res://assets/third_party/polyhaven.com/rocky_trail/rocky_trail_orm_2k.jpg")

# --- П14 1.1: реальный размер тайла слоя — по полю real-world size
# страницы набора (Poly Haven); где метаданных нет — правило ТЗ 2–3 м.
# Раньше один tile_m = 30 м растягивал фотоскан в 10–15 раз («картинка,
# натянутая на поверхность»). ---
const TILE_M_LITTER: float = 2.0    # forest_ground_05 — «2m wide»
const TILE_M_GRASS: float = 2.0    # leafy_grass — «2m wide»
const TILE_M_ROCK: float = 2.7      # rock_face_03 — «2.7m wide»
const TILE_M_MUD: float = 2.3       # mud_forest — «2.3m wide»
const TILE_M_MOSS: float = 2.0      # Moss001 ambientCG — нет данных, ТЗ 2–3 м
const TILE_M_GRAVEL: float = 2.0    # rocky_trail — «2m wide»

# --- П14 1.2: второй крупный масштаб того же слоя против сетки повторов
# (SPEC П14 1.2): с расстояния MACRO_NEAR до MACRO_FAR мелкая фактура
# подмешивается к тому же слою в MACRO_SCALE раз крупнее. ---
const MACRO_SCALE: float = 5.0
const MACRO_NEAR: float = 15.0
const MACRO_FAR: float = 40.0

# --- Тинты Born Unblessed (П14 1.3): нейтральные ≈ белые, без каналов > 1 —
# цвет даёт фотоскан; «мрачнее» — через яркость/насыщенность тинта.
# Значения стартовые, тон подбирает владелец в сборке. ---
## Подстилка: тёплый нейтрал, чуть притемнён.
const TINT_LITTER: Color = Color(0.88, 0.86, 0.82)
## Трава лугов: нейтрально-зелёная, без пастельной сочности.
const TINT_GRASS: Color = Color(0.82, 0.88, 0.80)
## Скала склонов: нейтрально-серая, чуть холодная.
const TINT_ROCK: Color = Color(0.82, 0.83, 0.85)
## Грязь низин: тёмный тёплый нейтрал.
const TINT_MUD: Color = Color(0.76, 0.70, 0.64)
## Мох: приглушённый зелёный.
const TINT_MOSS: Color = Color(0.78, 0.88, 0.74)
## Гравий тропы и Площади: серо-тёплый.
const TINT_GRAVEL: Color = Color(0.84, 0.80, 0.74)
## Доля плоского тинта в цвете слоя (0 — чистая карта, 1 — плоский цвет).
const TINT_MIX: float = 0.10

## Шаги POM (П14 3.2): марш по карте высот слоя; NORMAL/SIMPLE — без
## POM (ветка quality >= HIGH в шейдере).
const POM_STEPS_HIGH: int = 8
const POM_STEPS_ULTRA: int = 16


## Шаги POM для уровня (SIMPLE/NORMAL не используются — POM выключен).
static func pom_steps_for_tier(quality: int) -> int:
	return POM_STEPS_ULTRA if quality == GraphicsQuality.Tier.ULTRA \
		else POM_STEPS_HIGH

## Мокрая земля (SPEC П12 2.5): затемнение albedo и падение roughness
## по весу влаги; лужи начинаются от того же порога, что FootFx
## (PUDDLE_WET ниже) — всплески совпадают с лужами.
const WET_DARKEN: float = 0.65
const WET_ROUGH_FACTOR: float = 0.55


## Материал земли острова (П12): шесть PBR-слоёв по тем же весам, карты
## покраски запекаются из высот запечённого острова (детерминированно),
## тон слоёв — константами-тинтами BU. quality — уровень графики
## (GraphicsQuality.Tier, читает IslandView._build_terrain): на SIMPLE
## шейдер не сэмплит слой травы, AO-канал, лужи и параллакс.
static func make_material(art: IslandArt, quality: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("quality", quality)
	# Параллакс (П13 1.9): на HIGH гаснет ближе (10–15 м), на ULTRA —
	# прежние 15–25 м (движковые значения шейдера).
	if quality == GraphicsQuality.Tier.HIGH:
		material.set_shader_parameter(
			"parallax_near", GraphicsQuality.HIGH_PARALLAX_NEAR)
		material.set_shader_parameter(
			"parallax_far", GraphicsQuality.HIGH_PARALLAX_FAR)
	# П14 3.2: шаги POM по уровню (8 HIGH / 16 ULTRA; ниже HIGH ветка
	# шейдера не заходит в марш). Берег — тот же уровень воды, что у
	# моря/озера (дефолт шейдера совпадает, ставим явно для явности).
	material.set_shader_parameter("pom_steps",
		float(pom_steps_for_tier(quality)))
	material.set_shader_parameter("shore_level", IslandGen.SEA_LEVEL)
	# Явное false у чанков (дефолт шейдера не виден через
	# get_shader_parameter — null ломает bool() в тестах и инструментах).
	material.set_shader_parameter("detail_ring", false)
	# П14 3.1: карта высот (uniform кольца; у чанков detail_ring = false —
	# ветка не заходит, но сэмплер у материала задан, как у остальных карт).
	# Строится здесь же, без TerrainDetail — иначе цикл зависимостей
	# ForestGround ↔ TerrainDetail ломает -s-инструменты.
	var heights_image := Image.create_from_data(
		IslandGen.POINTS, IslandGen.POINTS, false,
		Image.FORMAT_RF, art.heights.to_byte_array())
	material.set_shader_parameter("height_tex",
		ImageTexture.create_from_image(heights_image))
	material.set_shader_parameter("litter_tint", TINT_LITTER)
	material.set_shader_parameter("grass_tint", TINT_GRASS)
	material.set_shader_parameter("rock_tint", TINT_ROCK)
	material.set_shader_parameter("mud_tint", TINT_MUD)
	material.set_shader_parameter("moss_tint", TINT_MOSS)
	material.set_shader_parameter("gravel_tint", TINT_GRAVEL)
	material.set_shader_parameter("tint_mix", TINT_MIX)
	# П14 1.1/1.2: реальный размер тайла каждого слоя и второй крупный
	# масштаб против сетки повторов.
	material.set_shader_parameter("tile_m_litter", TILE_M_LITTER)
	material.set_shader_parameter("tile_m_grass", TILE_M_GRASS)
	material.set_shader_parameter("tile_m_rock", TILE_M_ROCK)
	material.set_shader_parameter("tile_m_mud", TILE_M_MUD)
	material.set_shader_parameter("tile_m_moss", TILE_M_MOSS)
	material.set_shader_parameter("tile_m_gravel", TILE_M_GRAVEL)
	material.set_shader_parameter("macro_scale", MACRO_SCALE)
	material.set_shader_parameter("macro_near", MACRO_NEAR)
	material.set_shader_parameter("macro_far", MACRO_FAR)
	material.set_shader_parameter("wet_darken", WET_DARKEN)
	material.set_shader_parameter("wet_rough_factor", WET_ROUGH_FACTOR)
	material.set_shader_parameter("litter_tex", LITTER_TEX)
	material.set_shader_parameter("litter_normal", LITTER_NORMAL)
	material.set_shader_parameter("litter_orm", LITTER_ORM)
	material.set_shader_parameter("grass_tex", GRASS_TEX)
	material.set_shader_parameter("grass_normal", GRASS_NORMAL)
	material.set_shader_parameter("grass_orm", GRASS_ORM)
	material.set_shader_parameter("rock_tex", ROCK_TEX)
	material.set_shader_parameter("rock_normal", ROCK_NORMAL)
	material.set_shader_parameter("rock_orm", ROCK_ORM)
	material.set_shader_parameter("mud_tex", MUD_TEX)
	material.set_shader_parameter("mud_normal", MUD_NORMAL)
	material.set_shader_parameter("mud_orm", MUD_ORM)
	material.set_shader_parameter("moss_tex", MOSS_TEX)
	material.set_shader_parameter("moss_normal", MOSS_NORMAL)
	material.set_shader_parameter("moss_orm", MOSS_ORM)
	material.set_shader_parameter("gravel_tex", GRAVEL_TEX)
	material.set_shader_parameter("gravel_normal", GRAVEL_NORMAL)
	material.set_shader_parameter("gravel_orm", GRAVEL_ORM)
	material.set_shader_parameter("weight_map", _weights_texture(art))
	material.set_shader_parameter("border_map", _border_texture(art))
	material.set_shader_parameter("relief_normal", _relief_texture(art))
	return material


## Карта весов оверлеев: чистые функции высоты, уклона и фиксированного
## шума — одна и та же точка всегда даёт тот же вес.
static func _weights_image(art: IslandArt) -> Image:
	var image := Image.create_empty(MAP_M, MAP_M, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = MOSS_SEED
	noise.frequency = MOSS_FREQUENCY
	for z: int in MAP_M:
		for x: int in MAP_M:
			var wx: float = float(x) - 128.0
			var wz: float = float(z) - 128.0
			# Пиксель (x, z) — мир (x−128, z−128); индекс карты: (z)*POINTS + x.
			var h: float = art.heights[z * IslandGen.POINTS + x]
			var w_rock: float = smoothstep(
				ROCK_SLOPE_SOFT, ROCK_SLOPE_FULL, _slope(art, x, z))
			# Тропа и гравий Площади — один слот утоптанной земли.
			var w_plaza: float = _plaza_weight(wx, wz)
			var w_path: float = maxf(_path_weight(wx, wz), w_plaza)
			# Фикс-задача П12: вымощенная Площадь — сухая утоптанная терраса:
			# полувлажный вес низины (h = PLAZA_H даёт g = 0.5) красил гравий
			# сырой грязью; влага на террасе гасится, мох редеет вместе с ней.
			# Низины Леса и остальных зон не тронуты.
			var w_wet: float = (1.0 - smoothstep(WET_H_FULL, WET_H_SOFT, h)) \
				* (1.0 - w_plaza)
			var w_moss: float = _moss_weight(noise, x, z, w_rock, w_wet)
			# П5.9 переделка, П3: в русле оврага тропа гасится — утоптанная
			# земля по дну читалась коричневой лентой поперёк склонов. Дно
			# красят свои веса (камень стенок, влага низины), подходы
			# к мостику остаются тропой до самого настила.
			w_path *= smoothstep(
				IslandGen.GULLY_HALF_W + 0.5,
				IslandGen.GULLY_HALF_W + 1.5,
				IslandGen.gully_across(roundi(wx), roundi(wz)))
			# Край границы Леса гасит оверлеи (с обеих сторон): у линии —
			# чистая тонированная подстилка цветом point_color. Вымощенная
			# Площадь не гасится: она и есть соседняя зона, гравий лежит
			# до самого края, тон сводит цвет с низкополигональными плитами.
			var fade: float = 1.0 - _border_weight(wx, wz) * (1.0 - w_plaza)
			image.set_pixel(x, z, Color(
				w_rock * fade, w_wet * fade, w_moss * fade, w_path * fade))
	return image


## Карта тона: RGB — цвет «материала» точки (та же функция, что красит
## грани low-poly чанков и карту-миниатюру, включая подсказки террас
## Площади), A — вес тона. В секторе Леса вес — прежний краевой (у границы
## 1, вглубь 0), вне Леса — max(краевой, вес материала точки). Фикс-задача
## П12: на диске Площади краевой вес гасится (как уже гасится в карте
## весов) — угол границы сектора Леса (0, 0) проходит в 4 м от центра
## Площади, и краевая полоса держала бы на ней плоский камень зоны.
static func _border_image(art: IslandArt) -> Image:
	var image := Image.create_empty(MAP_M, MAP_M, false, Image.FORMAT_RGBA8)
	var tint: Dictionary = IslandGen.tint_hints()
	for z: int in MAP_M:
		for x: int in MAP_M:
			var wx: float = float(x) - 128.0
			var wz: float = float(z) - 128.0
			var low_poly: Color = TerrainBuilder.point_color(
				art.heights, tint, int(wx), int(wz))
			# Вымощенная Площадь не гасится краем Леса — она сама себе сосед:
			# тон на ней задаёт материал точки (гравий читается, фикс П12).
			var edge: float = _border_weight(wx, wz) \
				* (1.0 - _plaza_weight(wx, wz))
			var weight: float
			if wx < 0.0 and wz < 0.0:
				# Сектор Леса: прежний краевой вес (вне Площади — в точности
				# тот же, вид принятого Леса не меняется).
				weight = edge
			else:
				weight = maxf(
					edge,
					_material_tone_weight(art, tint, x, z))
			image.set_pixel(x, z, Color(low_poly.r, low_poly.g, low_poly.b, weight))
	return image


## Вес тона материала точки вне Леса: пляж, снег вершин и террасы — чистый
## цвет point_color; луг и склоны — смесь с текстурной землёй по уклону.
## Фикс-задача П12: тон 1 на террасе Площади превращал её в сплошное
## коричневое пятно — плоский камень зоны закрывал слой гравия (w.a = 1)
## целиком. На гравийной зоне Площади тон снижен до PLAZA_TONE (гравий
## читается, цвет сведён с плитами зоны), прочие террасы — как прежде,
## плоский камень своей зоны.
static func _material_tone_weight(
	art: IslandArt, tint: Dictionary, x: int, z: int,
) -> float:
	if not tint.get(Vector2i(x - 128, z - 128), {}).is_empty():
		return lerpf(
			1.0, PLAZA_TONE,
			_plaza_weight(float(x) - 128.0, float(z) - 128.0))
	var h: float = art.heights[z * IslandGen.POINTS + x]
	if h < TerrainBuilder.SAND_H or h >= TerrainBuilder.SNOW_H:
		return 1.0
	return lerpf(MEADOW_TONE, ROCK_TONE,
		smoothstep(ROCK_TONE_FROM, ROCK_TONE_TO, _slope(art, x, z)))


static func _weights_texture(art: IslandArt) -> ImageTexture:
	var image := _weights_image(art)
	# Мип-мапы (П8): карты сэмплятся на весь остров, без них дальние склоны
	# рябят; рельефная карта уже строилась с мип-мапами — карты весов и тона
	# выравниваем под неё.
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func _border_texture(art: IslandArt) -> ImageTexture:
	var image := _border_image(art)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## Карта честных нормалей рельефа (П5.9 переделка, П3): сглаженные нормали
## склонов из карты высот конечными разностями (шаг сетки 1 м):
## n = normalize(h(x−1,z) − h(x+1,z), 2, h(x,z−1) − h(x,z+1)). В шейдере
## она заменяет сглаживание «к вертикали»: на крутых стенках оврага
## нормаль смотрит поперёк склона — белая огранка больших low-poly граней
## исчезает, объём рельефа остаётся. Кодируется как n·0.5+0.5 (данные,
## не цвет — без source_color); мип-мапы усредняют дальние склоны.
static func _relief_image(art: IslandArt) -> Image:
	var image := Image.create_empty(MAP_M, MAP_M, false, Image.FORMAT_RGB8)
	for z: int in MAP_M:
		for x: int in MAP_M:
			var left: float = art.heights[
				z * IslandGen.POINTS + maxi(x - 1, 0)]
			var right: float = art.heights[
				z * IslandGen.POINTS + mini(x + 1, MAP_M - 1)]
			var north: float = art.heights[
				maxi(z - 1, 0) * IslandGen.POINTS + x]
			var south: float = art.heights[
				mini(z + 1, MAP_M - 1) * IslandGen.POINTS + x]
			var n := Vector3(left - right, 2.0, north - south).normalized()
			image.set_pixel(x, z, Color(
				0.5 + n.x * 0.5, 0.5 + n.y * 0.5, 0.5 + n.z * 0.5))
	image.generate_mipmaps()
	return image


static func _relief_texture(art: IslandArt) -> ImageTexture:
	return ImageTexture.create_from_image(_relief_image(art))


## Максимальный тангенс уклона в точке по соседям карты высот (кламп на краях).
## x, z — пиксельные координаты карты 0..255 (мир − 128).
static func _slope(art: IslandArt, x: int, z: int) -> float:
	var here: float = art.heights[z * IslandGen.POINTS + x]
	var worst := 0.0
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = clampi(x + offset.x, 0, MAP_M - 1)
		var nz: int = clampi(z + offset.y, 0, MAP_M - 1)
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


## Вес мягкого края границы Леса: 1 у самой линии (x = 0 при z ≤ 0 и
## z = 0 при x ≤ 0, с углом в нуле), 0 от EDGE_SOFT в обе стороны.
## Расстояние до границы непрерывно склеивается через все квадранты —
## шва «Лес кончился» нет ни внутри, ни снаружи сектора.
static func _border_weight(wx: float, wz: float) -> float:
	return 1.0 - smoothstep(EDGE_FULL, EDGE_SOFT, _forest_edge_dist(wx, wz))


## Расстояние до границы сектора Леса, м: внутри — до ближайшей из стенок
## x = 0 / z = 0; в соседних квадрантах — до продолжения той же стенки,
## в диагональном — до угла (0, 0). Функция непрерывна на всех швах.
static func _forest_edge_dist(wx: float, wz: float) -> float:
	if wx >= 0.0 and wz >= 0.0:
		return sqrt(wx * wx + wz * wz)
	if wx >= 0.0:
		return wx
	if wz >= 0.0:
		return wz
	return minf(-wx, -wz)


## Мох: пятна фиксированного шума, гуще во влажных местах, не на камне.
static func _moss_weight(
	noise: FastNoiseLite, x: int, z: int, w_rock: float, w_wet: float) -> float:
	var patch: float = smoothstep(0.05, 0.75, (noise.get_noise_2d(x, z) + 1.0) * 0.5)
	return patch * (1.0 - w_rock) * (0.45 + 0.55 * w_wet)


# --- Покрытие под ногами (переделка П9: частицы шагов) ---

## Покрытие земли: земля/трава/камень + грязь и лужа (влажные низины).
## Значения выбирает FootFx: камень — частиц нет, грязь/лужа — капли
## и всплеск, трава — травинки, земля/тропа — крупинки и пыль.
enum Surface { DIRT, GRASS, STONE, MUD, PUDDLE }

## Порог влажности «лужи» (веса WET_H_*): сырая земля темнеет раньше,
## стоячая вода — в самых низинах (w_wet ≥ 0.9).
const PUDDLE_WET: float = 0.9
const MUD_WET: float = 0.6

## Покрытие точки мира по тем же весам, что красят землю (_weights_image):
## крутой склон — камень (сухой, частиц нет), тропа/гравий Площади —
## утоптанная земля (пыль), самые низкие точки — лужа (всплеск), влажные
## низины — грязь (капли), мшистые пятна — трава (травинки), остальное —
## земля. Вызов дешёвый (пять выборок высот + шум), FootFx зовёт его
## раз на шаг — по точке под самой стопой.
static func surface_kind(art: IslandArt, world_pos: Vector3) -> int:
	var x := clampi(roundi(world_pos.x) + MAP_M / 2, 0, MAP_M - 1)
	var z := clampi(roundi(world_pos.z) + MAP_M / 2, 0, MAP_M - 1)
	var wx := float(x) - float(MAP_M / 2)
	var wz := float(z) - float(MAP_M / 2)
	if smoothstep(ROCK_SLOPE_SOFT, ROCK_SLOPE_FULL, _slope(art, x, z)) >= 0.5:
		return Surface.STONE
	var h: float = art.heights[z * IslandGen.POINTS + x]
	var w_wet: float = 1.0 - smoothstep(WET_H_FULL, WET_H_SOFT, h)
	if maxf(_path_weight(wx, wz), _plaza_weight(wx, wz)) >= 0.5:
		return Surface.DIRT
	if w_wet >= PUDDLE_WET:
		return Surface.PUDDLE
	if w_wet >= MUD_WET:
		return Surface.MUD
	var noise := FastNoiseLite.new()
	noise.seed = MOSS_SEED
	noise.frequency = MOSS_FREQUENCY
	if _moss_weight(noise, x, z, 0.0, w_wet) >= 0.35:
		return Surface.GRASS
	return Surface.DIRT


## Цвет частиц — цвет поверхности в точке, затемнённый: база — тот же
## point_color, что красит low-poly грани и карту тона, поверх — подтон
## палитры покрытия (влажная земля / мох / тропа — те же цвета, которыми
## красит землю шейдер ForestGround). darken — доля затемнения (баланс).
static func surface_color(art: IslandArt, kind: int, world_pos: Vector3,
	darken: float) -> Color:
	var x := clampi(roundi(world_pos.x) + MAP_M / 2, 0, MAP_M - 1)
	var z := clampi(roundi(world_pos.z) + MAP_M / 2, 0, MAP_M - 1)
	var base: Color = TerrainBuilder.point_color(
		art.heights, IslandGen.tint_hints(), x - MAP_M / 2, z - MAP_M / 2)
	match kind:
		Surface.MUD, Surface.PUDDLE:
			base = base.lerp(VPAL.ground_wet, 0.55)
		Surface.GRASS:
			base = base.lerp(VPAL.ground_moss, 0.35)
		Surface.DIRT:
			base = base.lerp(VPAL.ground_path, 0.3)
	return base.darkened(darken)
