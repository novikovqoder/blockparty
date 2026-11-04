# П18 Сборка 2 (docs/eztree_demo/PLAN_p18.md, исходник src/app/grass.js):
# поле травы и цветов КАК В ДЕМО EZ-TREE — пучки grass.glb (3 скрещенные
# плоскости, 6 треугольников, текстура 512², alphaTest 0.5, двусторонняя)
# и flower_{white,blue,yellow}.glb (~800 треугольников). Пучки дешёвые,
# поэтому поле крупнее печёной подложки П5.9: радиус 100–120 м против 40.
#
# Параметры — числа демо, пересчитанные через k = 0.38 (ель large,
# ориентир владельца в П18): масштаб size {5,4,5} ± variation {1,2,1} на
# осях, цвет экземпляра (0.25+0.1r, 0.3+0.3r, 0.1) × затемнение материала
# 0.6, эмиссия 0x308040 × 0.05 («небольшой свет, чтобы трава имела цвет
# там, где не освещена» — и лекарство от «угольных» клякс П17), ветер —
# формула листвы демо (три синуса, фаза симплекс-шума по миру; амплитуда
# и масштаб шума — те же, что у крон: трава качается вместе с деревьями),
# пятнистость patchiness 0.7 — тем же шумом, что земля (IslandGen.
# _grass_patch: в пустошах остаётся ~10 % пучков, как skip демо).
# Плотность — целевой счёт пучков на круг уровня (демо 5000–25000).
#
# Раскладка чанками по МИРОВЫМ клеткам 1 × 1 м (свой seed на клетку,
# бросок rng потребляется всегда — поток не зависит от уровня качества):
# чанк CHUNK × CHUNK м строится один раз при входе в поле и не
# пересобирается — трава не «плавает» за игроком. Плавное исчезновение
# края — масштабом к нулю в шейдере (grass_ez.gdshader), а не обрезкой
# раскладки. Зоны — карты ForestGround через GroundDetails.
# _grass_cell_state: нет на воде/пляже, Площади, дворах, террасе руин,
# каньоне, причале, крутой скале и гравии тропы; к тропе плотность
# плавно гаснет, глубина Леса реже лугов.
#
# Цветы (3 модели, по ~50 на круге HIGH) — пятнами того же шума земли
# (только гуща пятен), вид пятна детерминирован крупной клеткой
# FLOWER_CELL м — в одном пятне виды не смешиваются. Масштаб демо
# 0.02–0.05 на модель высотой ~86 ед. GLB (итог 0.65–1.63 м).
class_name GrassField
extends RefCounted

const SHADER: Shader = preload("res://assets/shaders/grass_ez.gdshader")
const GRASS_SCENE: PackedScene = preload(
	"res://assets/visual/grass_ez/grass.glb")
const FLOWER_SCENES: Dictionary = {
	"white": preload("res://assets/visual/grass_ez/flower_white.glb"),
	"blue": preload("res://assets/visual/grass_ez/flower_blue.glb"),
	"yellow": preload("res://assets/visual/grass_ez/flower_yellow.glb"),
}

## Свой seed слоя (не пересекается с мелочью и наполнением; П18 Сборка 2).
const SEED_GRASS_FIELD: int = 20261106
## Сторона чанка раскладки, м (шаг пересборки IslandView.update_viewer).
const CHUNK: float = 8.0
## Пересчёт демо-единиц в метры — k ели large (ориентир владельца, П18).
const K: float = 0.38
## Радиус поля и целевой счёт пучков по уровню (задание: «плотность как
## в демо (5000–25000) или гуще — пучки дешёвые»; радиус ~80–120 м).
## Счёт — базовая плотность COUNT/(π·R²) на клетку до зон и пятен:
## зоны и пятнистость гасят его суммарно до ~¼, поэтому цель задана
## с запасом — фактический счёт круга попадает в диапазон демо.
const RADIUS_HIGH: float = 100.0
const RADIUS_ULTRA: float = 120.0
const COUNT_HIGH: int = 24000
const COUNT_ULTRA: int = 48000
## Кромка поля в шейдере (масштаб к нулю), м — раскладку не трогает.
const EDGE_M: float = 12.0
## Масштаб пучка по осям: size {5,4,5} + случайно variation {1,2,1}
## (grass.js GrassOptions), ×k. Ширина итогового пучка ~3.7–4.5 м,
## высота ~3.0–4.6 м — буквально пропорции демо (трава ≈ ⅙ ели).
const SIZE: Vector3 = Vector3(5.0, 4.0, 5.0) * K
const SIZE_VAR: Vector3 = Vector3(1.0, 2.0, 1.0) * K
## Цветок: scale.set(s, s, s), s = 0.02 + 0.03·rand (grass.js:247) ×k.
const FLOWER_SCALE_FROM: float = 0.02 * K
const FLOWER_SCALE_TO: float = 0.05 * K
## Ниже этой отметки (после дрожания) травы нет: песок чистый.
const BEACH_H: float = 1.4
## Присыпка основания пучка, м (доля масштаба не нужна — основание
## модели в нуле, GLB травы стоит на y = 0).
const SINK: float = 0.03
## Минимальный уклон клетки, при котором пучок наклоняется по нормали
## рельефа: на плоских лугах нормаль ≈ вертикаль, четыре выборки высот
## ради неё — зря (замер: полный круг HIGH собирается ~1 с, каждая
## экономия на клетке — минус десятки миллисекунд).
const TILT_MIN: float = 0.03
## Глубина Леса реже лугов (луг = базовая плотность; у кромки — лерп).
const FOREST_DENSITY: float = 0.55
## Тропа: сам гравий (вес ≥ 0.2) уже блокирует GroundDetails.
## _grass_cell_state; к нему плотность плавно гаснет (задание: «тропы
## реже»).
const PATH_FADE_FULL: float = 0.2
## Цветы: базовая плотность на клетку — с запасом на зоны и пятна даёт
## ~150 цветков на круге R = 100 (по ~50 на вид, как flowerCount демо);
## зоны и гуща пятен гасят её суммарно до ~1/12 (замер прогона теста).
const FLOWER_DENSITY: float = 0.03
const FLOWER_PATCH_FROM: float = 0.45
const FLOWER_PATCH_TO: float = 0.75
## Вид пятна цветов — крупная клетка FLOWER_CELL м (детерминирован,
## в одном пятне виды не смешиваются, по канону П17).
const FLOWER_CELL: float = 16.0
## Эмиссия травы демо: 0x308040 (grass.js:133) × 0.05.
const EMISSION_COLOR: Color = Color(
	0x30 / 255.0, 0x80 / 255.0, 0x40 / 255.0)
const EMISSION_ENERGY: float = 0.05

static var _tuft: Dictionary = {}
static var _flowers: Dictionary = {}


## Поле включено на HIGH/ULTRA (SIMPLE/NORMAL — печёная подложка rgrass).
static func is_field_enabled(tier: int) -> bool:
	return tier >= GraphicsQuality.Tier.HIGH


## Радиус поля для уровня, м.
static func radius_for_tier(tier: int) -> float:
	return RADIUS_ULTRA if tier == GraphicsQuality.Tier.ULTRA \
		else RADIUS_HIGH


## Базовая плотность пучков на клетку 1 × 1 м (целевой счёт уровня).
static func density_for_tier(tier: int) -> float:
	var count: int = COUNT_ULTRA if tier == GraphicsQuality.Tier.ULTRA \
		else COUNT_HIGH
	return float(count) / (PI * radius_for_tier(tier) ** 2)


## Seed мировой клетки 1 × 1 м: та же схема, что у GroundClutter, со своим
## seed слоя — одна и та же клетка всегда даёт тот же поток.
static func cell_seed(x: int, z: int) -> int:
	return (SEED_GRASS_FIELD ^ (x * 73856093) ^ (z * 19349663)) & 0x7fffffff


## Наклон нормали рельефа в точке (полуметровые разности билинейной выборки
## — сглаженная нормаль, как карта нормалей ForestGround). Демо сажает
## пучки на плоскость (rotation.set(0, yaw, 0)); наш рельеф — наклон
## по нормали, чтобы 4-метровые плоскости не висели углами на склонах.
static func ground_normal(art: IslandArt, fx: float, fz: float) -> Vector3:
	var dx: float = IslandGen.ground_height(art.heights, fx + 0.5, fz) \
		- IslandGen.ground_height(art.heights, fx - 0.5, fz)
	var dz: float = IslandGen.ground_height(art.heights, fx, fz + 0.5) \
		- IslandGen.ground_height(art.heights, fx, fz - 0.5)
	return Vector3(-dx, 1.0, -dz).normalized()


## Вид цветов крупной клетки пятна — детерминирован координатами,
## в одном пятне виды не смешиваются.
static func flower_kind_for(x: int, z: int) -> String:
	# keys() даёт нетипизированный Array — в Array[String] его класть
	# нельзя (ошибка рантайма), поэтому сортируем как есть и берём ключ
	# с приведением к String.
	var names: Array = FLOWER_SCENES.keys()
	names.sort()
	var cell: int = (SEED_GRASS_FIELD + 2) \
		^ (int(floorf(float(x) / FLOWER_CELL)) * 2654435761) \
		^ (int(floorf(float(z) / FLOWER_CELL)) * 40503)
	return names[absi(cell) % names.size()] as String


## Пучок травы из grass.glb: меш (6 треугольников) + текстура + высота
## модели для паруса ветра. Кэш статический — сцена читается один раз.
static func tuft_data() -> Dictionary:
	if _tuft.is_empty():
		var mesh := _scene_mesh(GRASS_SCENE)
		var material := _std_material(mesh, 0)
		# Поверхностный материал GLB («GrassMaterial» демо, фильтр без
		# анизотропии — планка П5.9) снимаем: поле рендерит override
		# grass_ez, как у цветов — _surface_mesh без материала.
		mesh.surface_set_material(0, null)
		_tuft = {
			"mesh": mesh, "texture": material.albedo_texture,
			"height": maxf(mesh.get_aabb().size.y, 0.01),
		}
	return _tuft


## Цветы: список поверхностей модели (меш + albedo + текстура + шерохова-
## тость из GLB) — MultiMesh строится на каждую поверхность отдельно
## (у цветка 6–7 материалов, раскладка вида у поверхностей общая).
static func flower_data(kind: String) -> Array:
	if not _flowers.has(kind):
		var mesh := _scene_mesh(FLOWER_SCENES[kind])
		var surfaces: Array[Dictionary] = []
		for s: int in mesh.get_surface_count():
			var material := _std_material(mesh, s)
			surfaces.append({
				"mesh": _surface_mesh(mesh, s),
				"albedo": material.albedo_color,
				"texture": material.albedo_texture,
				"roughness": material.roughness,
			})
		_flowers[kind] = surfaces
	return _flowers[kind]


## Первый MeshInstance3D сцены GLB (у моделей демо он один).
static func _scene_mesh(scene: PackedScene) -> Mesh:
	var instance := scene.instantiate()
	var found: MeshInstance3D = null
	for child: Node in instance.find_children("*", "MeshInstance3D"):
		found = child
		break
	var mesh: Mesh = found.mesh if found != null else null
	instance.free()
	return mesh


## Стандартный материал поверхности (импортер GLB кладёт его в меш).
static func _std_material(mesh: Mesh, surface: int) -> StandardMaterial3D:
	var material := mesh.surface_get_material(surface)
	if material is StandardMaterial3D:
		return material
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = Color.WHITE
	return fallback


## Отдельный ArrayMesh одной поверхности (для MultiMesh).
static func _surface_mesh(source: Mesh, surface: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(surface))
	return mesh


## Ноды поля: «grass_tuft» (пучки, инстанс-цвета) и «flower_<вид>_s<i>»
## на каждую поверхность цветочных моделей. Буферы пустые — заполняет
## apply_field из gather. Тени — П18 Сборка 2 блок 4 (IslandView).
static func make_nodes(tier: int) -> Dictionary:
	var nodes: Dictionary = {}
	var fade := _fade_for_tier(tier)
	var tuft := tuft_data()
	nodes["grass_tuft"] = _make_node(
		"grass_tuft", tuft["mesh"], true,
		_tuft_material(tuft, fade), tier)
	for kind: String in FLOWER_SCENES:
		for s: int in flower_data(kind).size():
			var surface: Dictionary = flower_data(kind)[s]
			nodes["flower_%s_s%d" % [kind, s]] = _make_node(
				"flower_%s_s%d" % [kind, s], surface["mesh"], false,
				_flower_material(surface, fade), tier)
	return nodes


static func _make_node(
		type: String,
		mesh: Mesh,
		use_colors: bool,
		material: Material,
		_tier: int,
) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = use_colors
	mm.mesh = mesh
	var instance := MultiMeshInstance3D.new()
	instance.name = type
	instance.multimesh = mm
	instance.material_override = material
	# Тени: трава демо и отбрасывает, и принимает, но по заданию П18
	# Сборки 2 (блок 4) поле НЕ отбрасывает тени (кляксы у ног, цена);
	# принимает — PBR-материал без ручного light() получает тени сам.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## Кромка шейдера по уровню: масштаб к нулю в последних EDGE_M метрах.
static func _fade_for_tier(tier: int) -> Vector2:
	var radius := radius_for_tier(tier)
	return Vector2(radius - EDGE_M, radius)


## Материал пучков: текстура GLB × инстанс-тон (COLOR) × 0.6 демо,
## эмиссия 0x308040 × 0.05, ветер формулы крон (grass_ez.gdshader).
static func _tuft_material(tuft: Dictionary, fade: Vector2) -> Material:
	if WorldMaterials.want_flat():
		return LowPolyMat.flat_or_vertex()
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("albedo_tex", tuft["texture"])
	material.set_shader_parameter("albedo_color", Color.WHITE)
	material.set_shader_parameter("roughness_v", 1.0)
	material.set_shader_parameter("mat_dim", 0.6)
	material.set_shader_parameter(
		"emission_color", EMISSION_COLOR)
	material.set_shader_parameter(
		"emission_energy", EMISSION_ENERGY)
	_set_common(material, tuft["height"], fade)
	return material


## Материал поверхности цветка: albedo/текстура/шероховатость из GLB,
## без затемнения и эмиссии (в демо они только у травы), ветер — тот же.
static func _flower_material(surface: Dictionary, fade: Vector2) -> Material:
	if WorldMaterials.want_flat():
		return LowPolyMat.flat_or_vertex()
	var material := ShaderMaterial.new()
	material.shader = SHADER
	if surface["texture"] != null:
		material.set_shader_parameter("albedo_tex", surface["texture"])
		material.set_shader_parameter("albedo_color", Color.WHITE)
	else:
		# Поверхности без текстуры (лепестки, зелень): плоский albedo
		# материала GLB, нейтральная белая текстура (alpha = 1).
		material.set_shader_parameter(
			"albedo_tex", _white_texture())
		material.set_shader_parameter("albedo_color", surface["albedo"])
	material.set_shader_parameter("mat_dim", 1.0)
	material.set_shader_parameter("emission_energy", 0.0)
	material.set_shader_parameter("roughness_v", surface["roughness"])
	var height: float = (surface["mesh"] as ArrayMesh).get_aabb().size.y
	_set_common(material, maxf(height, 0.01), fade)
	return material


static func _set_common(
		material: ShaderMaterial, model_height: float, fade: Vector2) -> void:
	material.set_shader_parameter("model_height", model_height)
	material.set_shader_parameter("fade_start", fade.x)
	material.set_shader_parameter("fade_end", fade.y)
	material.set_shader_parameter("wind_strength", 0.5 * K)
	material.set_shader_parameter("wind_freq", 0.5)
	material.set_shader_parameter("wind_noise_scale", 70.0 * K)


static var _white: ImageTexture = null


## Нейтральная белая текстура для поверхностей без карты (alpha = 1).
static func _white_texture() -> ImageTexture:
	if _white == null:
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(image)
	return _white


## Раскладка одного чанка CHUNK × CHUNK м (мировые клетки x0..x0+7 ×
## z0..z0+7) — чистая функция мировых координат и уровня. Возвращает
## {«tuft»: {transforms, colors}, «flower_<вид>»: {transforms}}; чанк
## выходит пустым, если целиком за картой высот.
static func build_chunk(art: IslandArt, tier: int, cx: int, cz: int) -> Dictionary:
	var groups: Dictionary = {
		"tuft": {"transforms": Array(), "colors": PackedColorArray()},
	}
	# PackedColorArray — тип-значение: append во временную копию из словаря
	# в него не попадает, копию возвращают в словарь явно, в конце функции.
	var tuft_colors: PackedColorArray = groups["tuft"]["colors"]
	for kind: String in FLOWER_SCENES:
		groups["flower_%s" % kind] = {"transforms": Array()}
	var density := density_for_tier(tier)
	var x0: int = cx * int(CHUNK)
	var z0: int = cz * int(CHUNK)
	# Один поток на чанк (seed по мировым координатам чанка): клетки
	# обходятся в фиксированном порядке — раскладка остаётся чистой
	# функцией мировых координат, а RandomNumberGenerator создаётся один
	# раз на 64 клетки (создавать его на каждую клетку — главный тормоз
	# круга из ~500 чанков).
	var rng := RandomNumberGenerator.new()
	rng.seed = cell_seed(cx, cz)
	for z: int in range(z0, z0 + int(CHUNK)):
		for x: int in range(x0, x0 + int(CHUNK)):
			if absi(x) > IslandGen.HALF or absi(z) > IslandGen.HALF:
				continue
			# Броски потребляются всегда и в фиксированном порядке — до
			# любых вычислений (поток клетки не зависит от уровня
			# качества и зон). Множители зон ≤ 1, поэтому максимум
			# вероятности пучка — density, цветка — FLOWER_DENSITY:
			# клетку с двумя «пустыми» бросками можно пропустить до
			# дорогих карт зон и шума (~четверть клеток круга).
			var tuft_roll: float = rng.randf()
			var sx: float = rng.randf_range(SIZE.x, SIZE.x + SIZE_VAR.x)
			var sy: float = rng.randf_range(SIZE.y, SIZE.y + SIZE_VAR.y)
			var sz: float = rng.randf_range(SIZE.z, SIZE.z + SIZE_VAR.z)
			var cr: float = 0.25 + rng.randf() * 0.1
			var cg: float = 0.3 + rng.randf() * 0.3
			var yaw: float = rng.randf_range(0.0, TAU)
			var jx: float = rng.randf_range(-0.45, 0.45)
			var jz: float = rng.randf_range(-0.45, 0.45)
			var flower_roll: float = rng.randf()
			var flower_scale: float = rng.randf_range(
				FLOWER_SCALE_FROM, FLOWER_SCALE_TO)
			var flower_yaw: float = rng.randf_range(0.0, TAU)
			var fjx: float = rng.randf_range(-0.45, 0.45)
			var fjz: float = rng.randf_range(-0.45, 0.45)
			var may_tuft: bool = tuft_roll < density
			var may_flower: bool = flower_roll < FLOWER_DENSITY
			if not may_tuft and not may_flower:
				continue
			var cell := GroundDetails._grass_cell_state(art, x, z)
			if cell["blocked"]:
				continue
			# Зоны: луг — база, глубина Леса гасится к FOREST_DENSITY.
			var zone: float = 1.0
			if cell["forest"]:
				zone = lerpf(1.0, FOREST_DENSITY, clampf(
					ForestGround._forest_edge_dist(float(x), float(z))
					/ ForestGround.EDGE_SOFT, 0.0, 1.0))
			# Тропа: к гравию (блок в _grass_cell_state, вес ≥ 0.2)
			# плотность плавно гаснет.
			var path_fade: float = 1.0 - clampf(
				float(cell["path"]) / PATH_FADE_FULL, 0.0, 1.0) * 0.9
			# Скала: от мягкого уклона плотность плавно падает (жёсткий
			# блок — в _grass_cell_state, slope >= 0.7; уклон оттуда же).
			var rock_fade: float = 1.0 - smoothstep(
				ForestGround.ROCK_SLOPE_SOFT,
				ForestGround.ROCK_SLOPE_FULL, float(cell["slope"])) * 0.9
			# Пятнистость демо (patchiness 0.7): тем же шумом, что земля;
			# в пустошах остаётся ~10 % пучков (skip-доля демо).
			var patch: float = IslandGen._grass_patch(x, z)
			var fades: float = zone * path_fade * rock_fade
			if may_tuft and tuft_roll < density * fades \
					* (0.1 + 0.9 * patch):
				var placed := _place(
					art, x, z, Vector2(jx, jz), Vector3(sx, sy, sz),
					yaw, float(cell["slope"]))
				if not placed.is_empty():
					(groups["tuft"]["transforms"] as Array).append(
						placed["transform"])
					tuft_colors.append(Color(cr, cg, 0.1, 1.0))
			# Цветы: только гуща пятен, ~по 50 на вид на круге HIGH.
			if may_flower and flower_roll < FLOWER_DENSITY * fades \
					* smoothstep(FLOWER_PATCH_FROM, FLOWER_PATCH_TO, patch):
				var placed := _place(
					art, x, z, Vector2(fjx, fjz),
					Vector3.ONE * flower_scale, flower_yaw,
					float(cell["slope"]))
				if not placed.is_empty():
					var kind := flower_kind_for(x, z)
					(groups["flower_%s" % kind]["transforms"] as Array) \
						.append(placed["transform"])
	groups["tuft"]["colors"] = tuft_colors
	return groups


## Посадка инстанса в клетке: позиция по карте высот (с присыпкой),
## базис — нормаль рельефа (склоны) × случайный yaw, масштаб по осям.
## Пустой словарь, если дрожание занесло точку в запретную зону или
## под воду (клетка чистой не гарантирует чистоту точки).
static func _place(
		art: IslandArt,
		x: int,
		z: int,
		jitter: Vector2,
		scale3: Vector3,
		yaw: float,
		slope: float,
) -> Dictionary:
	var pos := Vector3(x + jitter.x, 0.0, z + jitter.y)
	var pos2 := Vector2(pos.x, pos.z)
	# Дрожание не должно заносить пучок в запретные зоны (как у мелочи
	# П14 3.3) — клетка была чистой, точка посадки обязана быть тоже.
	if IslandGen.on_village_pad(pos2):
		return {}
	if ForestGround._plaza_weight(pos2.x, pos2.y) > 0.05:
		return {}
	pos.y = IslandGen.ground_height(art.heights, pos.x, pos.z) - SINK
	if pos.y <= BEACH_H:
		return {}
	# Наклон по нормали — только на склонах (см. TILT_MIN).
	var basis := Basis(Vector3.UP, yaw)
	if slope > TILT_MIN:
		basis = Basis(
			Quaternion(Vector3.UP, ground_normal(art, pos.x, pos.z))) \
			* basis
	return {"transform": Transform3D(
		basis * Basis().scaled(scale3), pos)}


## Ключи чанков поля вокруг center (мировые метры) для уровня — центры
## чанков в радиусе уровня (+ пол-чанка диагонали на крайние клетки).
## Сортировка даёт стабильный порядок конкатенации буферов.
static func chunk_keys(tier: int, center: Vector2) -> Array[Vector2i]:
	var keys: Array[Vector2i] = []
	var radius := radius_for_tier(tier)
	var reach: int = int(ceilf((radius + CHUNK) / CHUNK))
	var base := Vector2i(
		int(floorf(center.x / CHUNK)), int(floorf(center.y / CHUNK)))
	for cz: int in range(base.y - reach, base.y + reach + 1):
		for cx: int in range(base.x - reach, base.x + reach + 1):
			var center_world := Vector2(
				(float(cx) + 0.5) * CHUNK, (float(cz) + 0.5) * CHUNK)
			if center_world.distance_to(center) > radius + CHUNK * 0.71:
				continue
			keys.append(Vector2i(cx, cz))
	keys.sort()
	return keys


## Собрать раскладку поля из кэша чанков (ключ Vector2i → build_chunk):
## конкатенация по видам — чистая функция, IslandView применяет её к нодам.
static func gather_from(chunks: Dictionary) -> Dictionary:
	var groups: Dictionary = {
		"tuft": {"transforms": Array(), "colors": PackedColorArray()},
	}
	# Цвета — PackedColorArray (тип-значение): копию возвращают в словарь.
	var tuft_colors: PackedColorArray = groups["tuft"]["colors"]
	for kind: String in FLOWER_SCENES:
		groups["flower_%s" % kind] = {"transforms": Array()}
	for key: Vector2i in chunks:
		var chunk: Dictionary = chunks[key]
		for type: String in groups:
			(groups[type]["transforms"] as Array).append_array(
				chunk[type]["transforms"])
			if type == "tuft":
				tuft_colors.append_array(chunk["tuft"]["colors"])
	groups["tuft"]["colors"] = tuft_colors
	return groups


## Перенести собранную раскладку в ноды (буферы MultiMesh целиком).
static func apply_field(nodes: Dictionary, groups: Dictionary) -> void:
	for type: String in nodes:
		var instance: MultiMeshInstance3D = nodes[type]
		var key := "tuft" if type == "grass_tuft" \
			else type.substr(0, type.rfind("_s"))
		var group: Dictionary = groups.get(key, {})
		var transforms: Array = group.get("transforms", [])
		var mm := instance.multimesh
		mm.instance_count = transforms.size()
		if key == "tuft":
			var colors: PackedColorArray = group.get(
				"colors", PackedColorArray())
			for i: int in transforms.size():
				mm.set_instance_transform(i, transforms[i])
				if i < colors.size():
					mm.set_instance_color(i, colors[i])
		else:
			for i: int in transforms.size():
				mm.set_instance_transform(i, transforms[i])
