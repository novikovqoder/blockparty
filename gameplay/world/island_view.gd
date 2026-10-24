# Визуал острова (раздел 6 SPEC): строит в _ready статичный мир из
# запечённого ресурса IslandArt — StaticBody3D рельефа с HeightMapShape3D
# и мешами чанков, MultiMeshInstance3D предметов (по одному на тип и
# вариант; трава и цветы исчезают вдали — раздел 16) и боксы коллизий
# предметов. Логики нет: остров генерируется одинаково у всех, по сети не
# передаётся. «Простая графика» (set_simple_graphics) прячет траву
# и приближает дальность прорисовки мелких предметов.
class_name IslandView
extends Node3D

## Запечённый остров (island_art.res): высоты, меши чанков, MultiMesh.
@export var art: IslandArt

## MultiMesh предметов по типу (для «Простой графики»).
var _props_by_type: Dictionary = {}
## Базовая дальность видимости типов (для «Простой графики»).
var _base_ranges: Dictionary = {}
## Меши чанков рельефа (для адаптивной тесселяции, П1).
var _chunk_instances: Array[MeshInstance3D] = []
## Текущий шаг тесселяции чанка (1.0 — печёный меш, NEAR_STEP — ближний).
var _chunk_steps: Array[float] = []
## Центр последней перестройки (быстрый выход, если игрок не сдвинулся).
var _lod_center: Vector2 = Vector2(1e9, 1e9)
## Карты производных рельефа для нормалей ближних чанков (строятся лениво
## при первой перестройке — боты и сервер без перестроек за них не платят).
var _slope_maps: Dictionary = {}


## Радиус ближней тесселяции (доработка-2 П5.13, П1): чанки ближе этого
## расстояния (по центру чанка, от игрока в плоскости XZ) тесселируются
## квадом 0.5 м, дальше остаются печёными 1-метровыми. Гистерезис не даёт
## чанку дёргаться между уровнями, стоя на границе.
const LOD_RADIUS: float = 50.0
const LOD_HYSTERESIS: float = 6.0


func _ready() -> void:
	_build_terrain()
	_build_props()
	_build_colliders()


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
	var forest_material := ForestGround.make_material(
		art, GraphicsQuality.tier_from_settings())
	for chunk: Mesh in art.chunks:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = chunk
		mesh_instance.material_override = forest_material
		body.add_child(mesh_instance)
		_chunk_instances.append(mesh_instance)
		_chunk_steps.append(1.0)
	add_child(body)


## Адаптивная тесселяция (доработка-2 П5.13, П1): вокруг игрока чанки
## перестраиваются с квадом 0.5 м (TerrainBuilder.build_near_chunk), при
## удалении возвращается печёный 1-метровый меш. Стык уровней без щелей:
## высоты подквадов — та же билинейная выборка карты, нормали — из той же
## карты. Перестройки идут с бюджетом времени на вызов, ближние — вперёд:
## при ходьбе меняется один-два чанка, после телепорта весь набор
## достраивается сразу.
func update_viewer(viewer_pos: Vector3) -> void:
	var center := Vector2(viewer_pos.x, viewer_pos.z)
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
		add_child(instance)
		_props_by_type[type] = instance


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
			_props_by_type[type] = instance


## Коллизии предметов: бокс с нижней гранью в точке предмета.
func _build_colliders() -> void:
	if art.colliders.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "PropsCollision"
	for collider: Dictionary in art.colliders:
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


## «Простая графика» (раздел 15): без травы (включая пучки Леса, П5.9),
## мелкие предметы ближе.
func set_simple_graphics(simple: bool) -> void:
	for type: String in ["rgrass", "rflower", "riris", "reed"]:
		if _props_by_type.has(type):
			(_props_by_type[type] as MultiMeshInstance3D).visible = not simple
	for type: String in _base_ranges:
		var instance: MultiMeshInstance3D = _props_by_type[type]
		instance.visibility_range_end = maxf(25.0, float(_base_ranges[type]) * 0.6) \
			if simple else float(_base_ranges[type])
