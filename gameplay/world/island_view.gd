# Визуал острова (раздел 6 SPEC): строит в _ready статичный мир из
# запечённого ресурса IslandArt — StaticBody3D рельефа с HeightMapShape3D
# и мешами чанков, MultiMeshInstance3D предметов (по одному на тип и
# вариант; трава и цветы исчезают вдали — раздел 16) и боксы коллизий
# предметов. Логики нет: остров генерируется одинаково у всех, по сети не
# передаётся. «Простая графика» (set_quality, П12 E) прячет траву
# и приближает дальность прорисовки мелких предметов; ULTRA отодвигает
# дальность травы и мелочи ×1.5 (П11 2.8). П12 E добавляет наполнение
# земли — сканы Poly Haven (GroundDetails): валуны, пни, корни, ветки,
# папоротник и трава-буст на HIGH/ULTRA.
class_name IslandView
extends Node3D

## Запечённый остров (island_art.res): высоты, меши чанков, MultiMesh.
@export var art: IslandArt

## MultiMesh предметов по типу (для «Простой графики»); типов с вариантами
## несколько (rgrass:0..2 — три группы), поэтому список.
var _props_by_type: Dictionary = {}
## Базовая дальность видимости типов (для «Простой графики» и ULTRA ×1.5).
var _base_ranges: Dictionary = {}
## Базовый спад густоты травы в шейдере (fade_start, fade_end) — на ULTRA
## отодвигается ×1.5 (П11 2.8, передано в П12 E).
var _grass_fade: Dictionary = {}
## Меши чанков рельефа (для адаптивной тесселяции, П1).
var _chunk_instances: Array[MeshInstance3D] = []
## Материал земли всех чанков (общий; панель замера F3 гасит им параллакс).
var _ground_material: ShaderMaterial = null
## Текущий шаг тесселяции чанка (1.0 — печёный меш, NEAR_STEP — ближний).
var _chunk_steps: Array[float] = []
## Центр последней перестройки (быстрый выход, если игрок не сдвинулся).
var _lod_center: Vector2 = Vector2(1e9, 1e9)
## Карты производных рельефа для нормалей ближних чанков (строятся лениво
## при первой перестройке — боты и сервер без перестроек за них не платят).
var _slope_maps: Dictionary = {}
## Коллизии наполнения П12 E (валуны и пни) — ставятся вместе с коллизиями
## печёных предметов в _ready.
var _detail_colliders: Array[Dictionary] = []
## П14 3.1: кольцо детальной сетки вокруг зрителя (HIGH/ULTRA) — нода
## снапится к камере в update_viewer, высоту вершинам ставит шейдер.
var _detail_ring: MeshInstance3D = null
## Материал кольца (копия материала чанков с detail_ring = true).
var _ring_material: ShaderMaterial = null
## П16 п. 3: последнее место установки кольца и признак «установлено» —
## нода двигается только при уходе зрителя дальше RING_MOVE_MIN_M.
var _ring_last_pos: Vector2 = Vector2.ZERO
var _ring_placed: bool = false
## Шаг сетки кольца (снап ноды к камере — с этим же шагом, вершины
## не плавают).
var _ring_step: float = 0.25
## П14 3.3: слой мелочи вокруг зрителя (ноды MultiMesh по видам).
var _clutter_nodes: Dictionary = {}
## Клетка последней пересборки мелочи (быстрый выход).
var _clutter_center: Vector2 = Vector2(1e9, 1e9)
## Уровень, по которому мелочь построена (тени/плотность).
var _clutter_tier: int = 0
## П16 п. 5: трансформы наполнения по видам (из GroundDetails.build) —
## по ним ставятся окклюдеры крупных валунов и пней.
var _detail_transforms: Dictionary = {}
## П15-ДОП2, п. 1: юбка морского дна за краем карты (глубина растёт
## плавно до горизонта); ползунки F3 меняют склон.
var _seafloor: SeafloorSkirt = null


## Радиус ближней тесселяции (доработка-2 П5.13, П1): чанки ближе этого
## расстояния (по центру чанка, от игрока в плоскости XZ) тесселируются
## квадом 0.5 м, дальше остаются печёными 1-метровыми. Гистерезис не даёт
## чанку дёргаться между уровнями, стоя на границе.
const LOD_RADIUS: float = 50.0
const LOD_HYSTERESIS: float = 6.0
## П16 п. 3: кольцо детальной сетки двигается только когда зритель
## ушёл от места последней установки дальше этого порога, м.
const RING_MOVE_MIN_M: float = 1.5
## П16 п. 5: минимальная сторона окклюдера, м — щебень и кладка-обломки
## не окклюдируются (проверка дороже пользы).
const OCCLUDER_MIN_M: float = 0.5
## П16 п. 5: печёные типы с окклюдером — кладка и скальные стены
## (руины, каньон, смотровые уступы).
const OCCLUDER_PROP_TYPES: PackedStringArray = [
	"ruin_tower", "ruin_arch", "ruin_column", "rock_wall",
]
## П16 п. 5: виды наполнения с окклюдером — крупные валуны и пни
## (масштаб ≥1.0, см. detail_occluder).
const OCCLUDER_DETAIL_TYPES: PackedStringArray = [
	"gd_boulder02", "gd_boulder03", "gd_stump01", "gd_stump02",
]
## Базовая сила параллакса земли (движковое значение uniform шейдера
## forest_ground; сюда панель F3 возвращает параллакс после замера).
const FOREST_PARALLAX_SCALE: float = 0.06


func _ready() -> void:
	_build_terrain()
	_build_props()
	_build_details()
	_build_colliders(_detail_colliders)
	_build_occluders()


## Рельеф: одна карта высот и на коллизию (HeightMapShape3D — вся физика
## и механики), и на визуал. Все 64 чанка 32 × 32 рисует один материал
## ForestGround (доработка П5.13): текстурная земля в стиле принятого Леса
## на весь остров, карты покраски 256 × 256 с плавными границами зон.
## Доработка-2 П5.13 (П1): чанки вокруг игрока (update_viewer) тесселируются
## квадом 0.5 м — печёные меши 1 м остаются дальним уровнем.
func _build_terrain() -> void:
	var body := StaticBody3D.new()
	body.name = "Terrain"
	var collision := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = IslandGen.POINTS
	shape.map_depth = IslandGen.POINTS
	shape.map_data = art.heights
	collision.shape = shape
	body.add_child(collision)
	# П12: уровень качества (SIMPLE — упрощённая земля, HIGH/ULTRA —
	# параллакс и AO-каналы) читается при постройке материала; смена
	# уровня применяется при следующем входе в мир, как у воды.
	var tier := GraphicsQuality.tier_from_settings()
	var forest_material := ForestGround.make_material(art, tier)
	_ground_material = forest_material
	for chunk: Mesh in art.chunks:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = chunk
		mesh_instance.material_override = forest_material
		body.add_child(mesh_instance)
		_chunk_instances.append(mesh_instance)
		_chunk_steps.append(1.0)
	# П15 9.1: береговая полоса — визуальная сетка вдоль всей береговой
	# линии (земля ±1 м от уровня воды, шаг 0.25 м, бикубическая высота
	# из той же карты высот): кромка воды — плавная кривая, не рёбра
	# треугольников. Только визуал: генератор, карта высот, коллизия
	# и хеш острова не меняются; тень не отбрасывает (рельеф уже в
	# тенях чанков). Материал — чанковый (покраска по world_pos).
	var band := MeshInstance3D.new()
	band.name = "ShoreBand"
	band.mesh = ShoreBand.build_band_mesh(art, IslandGen.SEA_LEVEL)
	band.material_override = forest_material
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(band)
	add_child(body)
	# П15-ДОП2, п. 1: юбка дна — морское дно за краем карты до горизонта
	# (глубина растёт плавно от края). Только визуал: без коллизии
	# (за ограждением мира не ходят) и без тени.
	var skirt := SeafloorSkirt.new()
	skirt.setup(art.heights)
	add_child(skirt)
	_seafloor = skirt
	# П14 3.1: кольцо детальной сетки (HIGH/ULTRA, SIMPLE/NORMAL — как
	# раньше). Сетка плоская, высоту вершинам ставит vertex() шейдера
	# (detail_ring); тень не отбрасывает — рельеф уже в тенях чанков.
	if TerrainDetail.is_ring_enabled(tier):
		_ring_step = TerrainDetail.step_for_tier(tier)
		_ring_material = TerrainDetail.make_material(
			forest_material, art, tier)
		var ring := MeshInstance3D.new()
		ring.name = "DetailRing"
		ring.mesh = TerrainDetail.build_mesh(
			_ring_step, TerrainDetail.radius_for_tier(tier))
		ring.material_override = _ring_material
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		_detail_ring = ring


## Адаптивная тесселяция (доработка-2 П5.13, П1): вокруг игрока чанки
## перестраиваются с квадом 0.5 м (TerrainBuilder.build_near_chunk), при
## удалении возвращается печёный 1-метровый меш. Стык уровней без щелей:
## высоты подквадов — та же билинейная выборка карты, нормали — из той же
## карты. Перестройки идут с бюджетом времени на вызов, ближние — вперёд:
## при ходьбе меняется один-два чанка, после телепорта весь набор
## достраивается сразу.
func update_viewer(viewer_pos: Vector3) -> void:
	var center := Vector2(viewer_pos.x, viewer_pos.z)
	# Кольцо детальной сетки (П14 3.1; П16 п. 3): снап к камере с шагом
	# сетки — вершины всегда в узлах одной решётки, бугры не «плывут»
	# при ходьбе. Сдвиг не каждый кадр: только когда снапнутый центр ушёл
	# от места последней установки дальше RING_MOVE_MIN_M (присвоение
	# position двигает AABB ноды и будит рендер-сервер).
	if _detail_ring != null:
		var ring_pos := center.snapped(Vector2(_ring_step, _ring_step))
		if not _ring_placed \
				or _ring_last_pos.distance_squared_to(ring_pos) \
				>= RING_MOVE_MIN_M * RING_MOVE_MIN_M:
			_detail_ring.position = Vector3(ring_pos.x, 0.0, ring_pos.y)
			_ring_last_pos = ring_pos
			_ring_placed = true
	# Мелочь (П14 3.3): пересборка при смене клетки CELL_M.
	if not _clutter_nodes.is_empty():
		var cell := (center / GroundClutter.CELL_M).floor()
		if cell != _clutter_center:
			_clutter_center = cell
			GroundClutter.apply_clutter(_clutter_nodes,
				GroundClutter.scatter(art, _clutter_tier, center))
	if center.distance_to(_lod_center) < 2.0:
		return
	_lod_center = center
	var rebuilds: Array[Dictionary] = []
	for i: int in _chunk_instances.size():
		var chunk_center := _chunk_center(i)
		var dist: float = chunk_center.distance_to(center)
		var near: bool = dist < LOD_RADIUS \
			if _chunk_steps[i] == 1.0 else dist < LOD_RADIUS + LOD_HYSTERESIS
		if near == (_chunk_steps[i] != 1.0):
			continue
		rebuilds.append({"index": i, "dist": dist, "near": near})
	if rebuilds.is_empty():
		return
	rebuilds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["dist"]) < float(b["dist"]))
	# Бюджет кадра: при обычной ходьбе меняется один-два чанка; при первом
	# вызове или телепорте (много перестроек сразу) — полная перестройка
	# за один вызов, чтобы вокруг зрителя не оставалось грубых «дыр».
	var budget_ms: int = Time.get_ticks_msec() + (600 if rebuilds.size() > 6 else 40)
	for rebuild: Dictionary in rebuilds:
		_rebuild_chunk(int(rebuild["index"]), bool(rebuild["near"]))
		if Time.get_ticks_msec() > budget_ms and rebuild != rebuilds.back():
			break


func _rebuild_chunk(index: int, near: bool) -> void:
	var instance := _chunk_instances[index]
	if near:
		if _slope_maps.is_empty():
			_slope_maps = TerrainBuilder.slope_maps(art.heights)
		var cz: int = index / TerrainBuilder.CHUNKS_PER_SIDE
		var cx: int = index % TerrainBuilder.CHUNKS_PER_SIDE
		instance.mesh = TerrainBuilder.build_near_chunk(
			art.heights, _slope_maps, art.chunks[index] as ArrayMesh, cx, cz)
		_chunk_steps[index] = TerrainBuilder.NEAR_STEP
	else:
		instance.mesh = art.chunks[index]
		_chunk_steps[index] = 1.0


func _chunk_center(index: int) -> Vector2:
	var cz: int = index / TerrainBuilder.CHUNKS_PER_SIDE
	var cx: int = index % TerrainBuilder.CHUNKS_PER_SIDE
	return Vector2(
		float(-IslandGen.HALF + cx * TerrainBuilder.CHUNK + TerrainBuilder.CHUNK / 2),
		float(-IslandGen.HALF + cz * TerrainBuilder.CHUNK + TerrainBuilder.CHUNK / 2),
	)


## Предметы: MultiMesh собирается в рантайме из групп ресурса (инстанс-данные
## MultiMesh не сериализуются при headless-запекании — PropGroup), дальность
## видимости — по типу.
func _build_props() -> void:
	var material := LowPolyMat.flat_or_vertex()
	for key: String in art.prop_groups:
		var type := String(key.split(":")[0])
		var group: PropGroup = art.prop_groups[key]
		# Деревья Леса (П5.9, переделка): уровни детализации ez-tree —
		# отдельные MultiMesh на дистанционных диапазонах; материалы
		# запечены в меши (кора + листва), override не ставится.
		if not group.lods.is_empty():
			_build_tree_lods(key, type, group)
			continue
		var instance := MultiMeshInstance3D.new()
		instance.name = "Props_" + key.replace(":", "_")
		instance.multimesh = group.to_multimesh()
		# Растительность Леса (П5.9) — материалы ForestMat (градиент травы,
		# ветер, спад густоты от камеры, мох камней); остальная растительность
		# качается на ветру (vfx-fix, блок б); прочие предметы — статичный.
		var type_name := StringName(type)
		if ForestMat.handles(type_name):
			instance.material_override = ForestMat.for_type(type_name)
		elif RuinMat.handles(type_name):
			# Доработка-2 П5.13, П4: кладка руин и каменных стен —
			# текстурный камень (polyhaven + ambientCG), не белый блок.
			instance.material_override = RuinMat.for_type(type_name)
		elif WoodMat.handles(type_name):
			# Доработка-2 П5.13, П5: дерево настилов у воды (причал,
			# сваи, кнехты) — текстура плах ambientCG.
			instance.material_override = WoodMat.for_type(type_name)
		elif PropMeshes.has_baked_material(type_name):
			# Доработка-2 П5.13, П6: коряги и мостик из брёвен несут кору
			# ambientCG прямо в меше (surface material) — override плоским
			# материалом закрывал текстуру («белые цилиндры»).
			pass
		elif not PropMeshes.wind_params(type_name).is_empty():
			instance.material_override = LowPolyMat.wind_or_vertex(type_name)
		else:
			instance.material_override = material
		var range: float = PropMeshes.visibility_range(type_name)
		if range > 0.0:
			instance.visibility_range_end = range
			_base_ranges[type] = range
		# П16 п. 2: трава и мелкие типы — без тени солнца/луны на HIGH
		# (деревья, валуны и постройки остаются с тенью).
		if PropMeshes.small_shadowless(
				type_name, GraphicsQuality.tier_from_settings()):
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		_register(String(type), instance)


## Деревья по уровням дальности (раздел 16): полная модель до 45 м, LOD1 —
## до 90, LOD2 (как в демо ez-tree — прореженные секции и одиночные
## карточки листьев) — до 220 м: практически всегда виден, но дальше
## растворяется в дымке. Диапазоны перекрываются загибом (margin 6 м) —
## переключения без «мигания».
func _build_tree_lods(key: String, type: String, group: PropGroup) -> void:
	var levels: Array = [
		{"mesh": group.mesh, "begin": 0.0, "end": 45.0, "shadow": true},
		{"mesh": group.lods[0], "begin": 45.0, "end": 90.0, "shadow": true},
		{"mesh": group.lods[1], "begin": 90.0, "end": 220.0, "shadow": false},
	]
	for index: int in levels.size():
		var level: Dictionary = levels[index]
		var instance := MultiMeshInstance3D.new()
		instance.name = "Props_%s_%s_lod%d" % [
			type, key.get_slice(":", 1), index]
		instance.multimesh = group.to_multimesh(level["mesh"])
		instance.visibility_range_begin = float(level["begin"])
		instance.visibility_range_end = float(level["end"])
		instance.visibility_range_begin_margin = 6.0
		instance.visibility_range_end_margin = 6.0
		instance.cast_shadow = \
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
			if level["shadow"] \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		if index == 0:
			_register(type, instance)


## Коллизии предметов: бокс с нижней гранью в точке предмета. extra —
## коллизии рантайм-наполнения П12 E (валуны и пни), тот же формат.
func _build_colliders(extra: Array[Dictionary] = []) -> void:
	var colliders: Array[Dictionary] = []
	colliders.append_array(art.colliders)
	colliders.append_array(extra)
	if colliders.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "PropsCollision"
	for collider: Dictionary in colliders:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = collider["size"]
		shape.shape = box
		var transform := Transform3D(
			Basis(Vector3.UP, float(collider["yaw"])), collider["pos"]
		)
		transform.origin += transform.basis * Vector3(0.0, float(collider["size"].y) * 0.5, 0.0)
		shape.transform = transform
		body.add_child(shape)
	add_child(body)


## Запомнить группу типа: у rgrass их три (rgrass:0..2), у травы-буста
## три варианта меша — «Простая графика» и ULTRA применяются ко всем группам
## типа. Заодно фиксируется базовый спад густоты травы её материала
## (fade_start/fade_end шейдера grass_field) — ULTRA отодвигает его ×1.5.
func _register(type: String, instance: MultiMeshInstance3D) -> void:
	if not _props_by_type.has(type):
		_props_by_type[type] = [] as Array[MultiMeshInstance3D]
	(_props_by_type[type] as Array[MultiMeshInstance3D]).append(instance)
	if type == "rgrass" or type.begins_with("gd_grass"):
		var material := instance.material_override
		if material is ShaderMaterial:
			var shader := material as ShaderMaterial
			var fade_start: Variant = shader.get_shader_parameter("fade_start")
			if fade_start != null:
				_grass_fade[type] = Vector2(
					float(fade_start),
					float(shader.get_shader_parameter("fade_end")))


## Наполнение земли П12 E (SPEC 3.1–3.2, GroundDetails): сканы Poly Haven —
## валуны, россыпь камней, пни, корни, ветки, щепа, папоротник (гуще в Лесу
## и у руин, коллизия у крупных) и слой травы-буста на HIGH/ULTRA. Строится
## один раз при входе в мир по текущему уровню (как вода); дальности
## регистрируются в общих таблицах — set_quality применяет к ним те же
## правила, что к печёным предметам.
func _build_details() -> void:
	var built: Dictionary = GroundDetails.build(
		art, GraphicsQuality.tier_from_settings())
	for node: Variant in built["instances"]:
		var instance := node as MultiMeshInstance3D
		add_child(instance)
		var type := String(instance.name)
		_base_ranges[type] = built["ranges"][type]
		_register(type, instance)
	for node: Variant in built["grass"]:
		var instance := node as MultiMeshInstance3D
		add_child(instance)
		var type := String(instance.name)
		_base_ranges[type] = instance.visibility_range_end
		_register(type, instance)
	_detail_colliders = built["colliders"]
	_detail_transforms = built["transforms"]
	# П14 3.3: слой мелочи вокруг игрока (HIGH/ULTRA): ноды строятся здесь,
	# буферы заполняет первый update_viewer (когда известна позиция
	# зрителя); плотность и тени — по уровню входа, как у травы-буста.
	_clutter_tier = GraphicsQuality.tier_from_settings()
	if GroundClutter.is_clutter_enabled(_clutter_tier):
		_clutter_nodes = GroundClutter.make_nodes(_clutter_tier)
		for type: String in _clutter_nodes:
			add_child(_clutter_nodes[type])


## Окклюдеры статичного мира (П16 п. 5, SPEC п. 5 «отсечение невидимого»):
## по BoxOccluder3D на крупный печёный предмет (кладка руин, скальные
## стены каньона и уступов) и крупное наполнение (валуны, пни ≥1.0
## масштаба) — рендер не рисует то, что за ними. Ставятся один раз при
## входе в мир и живут на всех уровнях: построение разовое, сама
## проверка отсечения дешевле лишних Draw Call'ов. Мелочь (трава, щебень,
## скамейки) окклюдерами не становится — порог OCCLUDER_MIN_M.
func _build_occluders() -> void:
	var root := Node3D.new()
	root.name = "Occluders"
	for key: String in art.prop_groups:
		var type := String(key.split(":")[0])
		if not prop_occluder(type):
			continue
		var group: PropGroup = art.prop_groups[key]
		for xf: Transform3D in group.transforms:
			_add_occluder_box(root, group.mesh, xf)
	for type: String in OCCLUDER_DETAIL_TYPES:
		if not _detail_transforms.has(type):
			continue
		var mesh: Mesh = GroundDetails.kind_mesh(StringName(type))
		if mesh == null:
			continue
		for xf: Transform3D in _detail_transforms[type]:
			if detail_occluder(type, xf.basis.x.length()):
				_add_occluder_box(root, mesh, xf)
	add_child(root)


## П16 п. 5: размер окклюдера предмета — AABB меша в масштабе трансформа
## (у «метровых» типов вроде rock_wall длины уже в базисе); Vector3.ZERO —
## предмет мелкий, окклюдер не ставится (порог OCCLUDER_MIN_M).
static func occluder_size(mesh: Mesh, xf: Transform3D) -> Vector3:
	var aabb: AABB = mesh.get_aabb()
	var size := Vector3(
		aabb.size.x * xf.basis.x.length(),
		aabb.size.y * xf.basis.y.length(),
		aabb.size.z * xf.basis.z.length(),
	)
	if size.x < OCCLUDER_MIN_M or size.y < OCCLUDER_MIN_M \
			or size.z < OCCLUDER_MIN_M:
		return Vector3.ZERO
	return size


## П16 п. 5: окклюдер-бокс по трансформу предмета — меш «ногами» в origin,
## поворот только по yaw (кладка и валуны не наклоняются). Размер — AABB
## меша в масштабе предмета (у «метровых» типов scale уже в длинах базиса),
## центр — через полный трансформ; нода без масштаба, чтобы BoxOccluder3D
## остался в метрах. Мелкий предмет не окклюдируется.
static func _add_occluder_box(
	parent: Node3D, mesh: Mesh, xf: Transform3D
) -> void:
	var size := occluder_size(mesh, xf)
	if size == Vector3.ZERO:
		return
	var occluder_node := OccluderInstance3D.new()
	var box := BoxOccluder3D.new()
	box.size = size
	occluder_node.occluder = box
	occluder_node.position = xf * mesh.get_aabb().get_center()
	occluder_node.rotation.y = atan2(-xf.basis.x.z, xf.basis.x.x)
	parent.add_child(occluder_node)


## П16 п. 5: печёный тип получает окклюдер (кладка руин и скальные стены).
static func prop_occluder(type: String) -> bool:
	return OCCLUDER_PROP_TYPES.has(type)


## П16 п. 5: вид наполнения получает окклюдер — валуны и пни крупного
## масштаба; мелкие сканы и лёгкая мелочь не окклюдируются.
static func detail_occluder(type: String, scale: float) -> bool:
	return OCCLUDER_DETAIL_TYPES.has(type) and scale >= 1.0


## Уровень качества мира (П12 E; переданный из П11 пункт 2.8): SIMPLE —
## без травы (печёные пучки, буст и папоротники наполнения) и с дальностью
## мелких предметов ×0.6 (минимум 25 м); ULTRA — дальность травы и мелких
## предметов ×1.5 и спад густоты травы отодвинут ×1.5; HIGH (П13 1.9) —
## дальность и спад как в базе, но спад травы-буста начинается ближе
## (×HIGH_GRASS_FADE_MULT); NORMAL — база. П16 п. 4: на HIGH трава-буст
## и лёгкая мелочь наполнения видны ближе базы (×0.85/×0.8) и исчезают
## мягко (fade), уход с HIGH возвращает резкую границу, как в базе.
## Применяется ко всем группам типа и к наполнению земли.
func set_quality(tier: int) -> void:
	var simple := tier == GraphicsQuality.Tier.SIMPLE
	var hi := tier == GraphicsQuality.Tier.HIGH
	for type: String in ["rgrass", "rflower", "riris", "reed", "gd_fern"]:
		_set_type_visible(type, not simple)
	for type: String in _props_by_type:
		if String(type).begins_with("gd_grass"):
			_set_type_visible(String(type), not simple)
	for type: String in _base_ranges:
		var base: float = float(_base_ranges[type])
		var range := maxf(25.0, base * 0.6) \
			if simple else base * range_mult(type, tier)
		for instance: MultiMeshInstance3D in _props_by_type.get(type, []):
			instance.visibility_range_end = range
			if soft_fade_type(type):
				instance.visibility_range_fade_mode = (
					GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if hi
					else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED)
	_apply_grass_fade(_grass_fade_mult(tier))


## Множитель дальности видимости типа по уровню (П16 п. 4): ULTRA ×1.5,
## HIGH — трава-буст ×0.85 и лёгкая мелочь ×0.8 (ближе базы), прочие
## уровни и прочие типы — база.
static func range_mult(type: String, tier: int) -> float:
	if tier == GraphicsQuality.Tier.ULTRA:
		return 1.5
	if tier != GraphicsQuality.Tier.HIGH:
		return 1.0
	if type.begins_with("gd_grass"):
		return GraphicsQuality.HIGH_GRASS_RANGE_MULT
	if GroundDetails.light_clutter(StringName(type)):
		return GraphicsQuality.HIGH_CLUTTER_RANGE_MULT
	return 1.0


## Типы с мягким исчезновением на границе видимости на HIGH (П16 п. 4):
## трава-буст и лёгкая мелочь наполнения; на прочих уровнях fade выключен.
static func soft_fade_type(type: String) -> bool:
	return type.begins_with("gd_grass") \
		or GroundDetails.light_clutter(StringName(type))


## Множитель спада густоты травы по уровню (П13 1.9): ULTRA ×1.5,
## HIGH — ближе базы, прочие — база.
func _grass_fade_mult(tier: int) -> float:
	if tier == GraphicsQuality.Tier.ULTRA:
		return 1.5
	if tier == GraphicsQuality.Tier.HIGH:
		return GraphicsQuality.HIGH_GRASS_FADE_MULT
	return 1.0


## Панель замера F3 (П13 3.2): показать/спрятать слой травы-буста
## (gd_grass_*) без смены уровня — печёные пучки не трогаются.
func set_grass_boost_visible(on: bool) -> void:
	for type: String in _props_by_type:
		if String(type).begins_with("gd_grass"):
			_set_type_visible(String(type), on)


## Панель замера F3 (П13 3.2, П14 3.2 — теперь POM): выключить/вернуть
## рельефную выборку земли (parallax_scale в 0 — марш POM не делается);
## ставится и материалу чанков, и материалу кольца детальной сетки.
func set_parallax(on: bool) -> void:
	if _ground_material == null:
		return
	var value: float = FOREST_PARALLAX_SCALE if on else 0.0
	_ground_material.set_shader_parameter("parallax_scale", value)
	if _ring_material != null:
		_ring_material.set_shader_parameter("parallax_scale", value)


## Панель замера F3 (П14 3.5): показать/спрятать кольцо детальной сетки
## (мгновенно, без пересборки — переключатель замера).
func set_detail_ring_visible(on: bool) -> void:
	if _detail_ring != null:
		_detail_ring.visible = on


## Панель замера F3 (П14 3.5): показать/спрятать слой мелочи.
func set_clutter_visible(on: bool) -> void:
	for type: String in _clutter_nodes:
		(_clutter_nodes[type] as MultiMeshInstance3D).visible = on


## Ползунки F3, вкладка «Вода» (П15-ДОП2, п. 1): сменить склон юбки
## морского дна (ширина шельфа и глубина вдали) — пересборка меша.
func set_seafloor_slope(shelf: float, far_depth: float) -> void:
	if _seafloor != null:
		_seafloor.set_slope(shelf, far_depth)


## Видимость всех групп типа («Простая графика» прячет траву и цветы).
func _set_type_visible(type: String, visible: bool) -> void:
	for instance: MultiMeshInstance3D in _props_by_type.get(type, []):
		instance.visible = visible


## Спад густоты травы шейдера (трава «садится» в землю от fade_start до
## fade_end): на ULTRA отодвигается ×1.5 — вместе с дальностью MultiMesh
## (П11 2.8); на HIGH начинается ближе базы (П13 1.9). Материалы
## кэшируются по типу — достаточно одной записи.
func _apply_grass_fade(mult: float) -> void:
	for type: String in _grass_fade:
		var instances: Array = _props_by_type.get(type, [])
		if instances.is_empty():
			continue
		var material := (instances[0] as MultiMeshInstance3D).material_override
		if material is ShaderMaterial:
			var base: Vector2 = _grass_fade[type]
			(material as ShaderMaterial).set_shader_parameter(
				"fade_start", base.x * mult)
			(material as ShaderMaterial).set_shader_parameter(
				"fade_end", base.y * mult)


## «Простая графика» (раздел 15): обёртка над set_quality (П12 E) — прежние
## вызовы работают; снятие флага возвращает уровень из настроек.
func set_simple_graphics(simple: bool) -> void:
	set_quality(
		GraphicsQuality.Tier.SIMPLE if simple
		else GraphicsQuality.tier_from_settings())
