# Район-заготовка (постапокалипсис, шаг 1): заброшенный квартал из серых
# коробок по согласованной карте (10.11.2026) — проверить расстояния и
# масштаб до того, как делать дома и ассеты. Участок 200×200 м, 1 ед. = 1 м,
# центр карты — (0, 0), север — −Z, восток — +X.
# Что есть: четыре пятиэтажки (три буквой «П» вокруг двора, четвёртая
# восточнее), подъезды со двора (открытый — янтарный, северный дом), гаражи,
# магазин, будка, дорога с автобусом и машинами, завалы на концах дороги,
# руины за забором на юго-востоке, озеро с причалом, условные деревья,
# башня Главного Компьютера вдали на северо-востоке.
# Чего нет: интерьеров, настоящих деревьев и травы, рельефа (земля ровная).
# Запуск: аргумент --district. Выход в меню — Esc.
class_name DistrictLab
extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://gameplay/player/player.tscn")

## Половина стороны участка, м (карта 200×200 м).
const HALF: float = 100.0
## Seed раскладки деревьев: картинка детерминирована.
const LAB_SEED: int = 20261110
## Высота пятиэтажки (5 × 2.8 м + цоколь и парапет), м.
const HOUSE_HEIGHT: float = 15.0
## Шаг подъездов панельного дома, м.
const ENTRANCE_STEP: float = 14.0
## Точка старта игрока (метка 7 на карте, у причала).
const START: Vector3 = Vector3(-7.2, 0.2, 57.6)
## Число условных деревьев (до отбраковки по занятым местам).
const TREE_TRIES: int = 900

const C_GROUND: Color = Color(0.33, 0.38, 0.27)
const C_YARD: Color = Color(0.40, 0.42, 0.33)
const C_ASPHALT: Color = Color(0.24, 0.24, 0.25)
const C_PATH: Color = Color(0.42, 0.37, 0.28)
const C_HOUSE: Color = Color(0.62, 0.62, 0.60)
const C_ENTRANCE: Color = Color(0.28, 0.28, 0.30)
const C_OPEN: Color = Color(0.95, 0.62, 0.15)
const C_SMALL: Color = Color(0.52, 0.50, 0.47)
const C_RUIN: Color = Color(0.50, 0.47, 0.44)
const C_CAR: Color = Color(0.45, 0.30, 0.22)
const C_WATER: Color = Color(0.16, 0.33, 0.42)
const C_WOOD: Color = Color(0.36, 0.28, 0.20)
const C_TRUNK: Color = Color(0.30, 0.24, 0.18)
const C_CROWN: Color = Color(0.24, 0.40, 0.20)
const C_TOWER: Color = Color(0.10, 0.11, 0.14)

## Дома: имя, центр X, центр Z, размер по X, размер по Z, сторона подъездов
## (единичный вектор X/Z наружу от фасада), число подъездов.
const HOUSES: Array = [
	["HouseNorth", 12.4, -72.9, 56.5, 13.4, 0.0, 1.0, 4],
	["HouseWest", -21.5, -44.7, 12.0, 44.5, 1.0, 0.0, 3],
	["HouseEast", 44.2, -41.9, 11.5, 49.1, -1.0, 0.0, 3],
	["HouseFar", 73.4, -34.4, 12.0, 49.0, -1.0, 0.0, 3],
]
## Открытый подъезд: дом и номер подъезда (с запада/севера, с нуля).
const OPEN_HOUSE: String = "HouseNorth"
const OPEN_ENTRANCE: int = 1

## Постройки-коробки: имя, X, Z, размер X, размер Z, высота, поворот (град), цвет.
const BOXES: Array = [
	["Shop", -15.0, 22.6, 14.4, 11.5, 4.0, 0.0, C_SMALL],
	["Transformer", -13.1, -16.3, 4.8, 4.8, 3.0, 0.0, C_SMALL],
	["YardShed", 21.2, -48.6, 4.8, 4.8, 2.5, 0.0, C_SMALL],
	["YardBox", 21.2, -21.4, 5.6, 4.0, 2.5, 0.0, C_SMALL],
	["Climber", 14.8, -34.6, 5.0, 4.0, 2.0, 0.0, C_SMALL],
	["Swing", 4.5, -49.0, 5.6, 0.4, 2.2, 0.0, C_SMALL],
	["GarageExtra", -37.3, -7.0, 4.8, 8.0, 2.8, 0.0, C_SMALL],
	["RuinA", 65.1, 47.5, 17.5, 13.6, 7.0, -15.0, C_RUIN],
	["RuinB", 79.4, 53.9, 13.6, 15.9, 7.0, -15.0, C_RUIN],
	["RuinC", 69.1, 35.6, 36.7, 7.2, 4.0, -15.0, C_RUIN],
	["Pier", -27.3, 64.6, 19.0, 4.5, 0.5, 19.7, C_WOOD],
	["Bus", 25.5, 6.1, 12.0, 3.0, 2.55, -21.0, C_CAR],
	["TruckA", -9.1, 0.8, 6.5, 2.4, 2.6, -5.0, C_CAR],
	["TruckB", -33.0, 13.6, 6.0, 2.4, 2.6, 85.0, C_CAR],
	# Завалы на концах дороги (граница района) и забор руин.
	["BarricadeWestA", -95.2, 4.0, 4.6, 2.0, 2.2, 35.0, C_CAR],
	["BarricadeWestB", -94.0, 9.0, 5.0, 2.0, 1.8, -50.0, C_CAR],
	["BarricadeWestLog", -92.5, 6.1, 1.0, 13.0, 1.0, 8.0, C_WOOD],
	["BarricadeEastA", 95.4, 19.0, 4.6, 2.0, 2.2, -40.0, C_CAR],
	["BarricadeEastB", 94.4, 24.0, 5.0, 2.0, 1.8, 55.0, C_CAR],
	["BarricadeEastLog", 92.6, 21.0, 1.0, 13.0, 1.0, -12.0, C_WOOD],
	["RuinFenceNorth", 66.0, 29.5, 46.0, 0.3, 2.2, -15.0, C_RUIN],
	["RuinFenceWest", 46.5, 46.0, 0.3, 30.0, 2.2, -15.0, C_RUIN],
]
## Гаражи: ряд из 8 боксов вдоль X.
const GARAGE_COUNT: int = 8
const GARAGE_X0: float = -90.4
const GARAGE_X1: float = -39.4
const GARAGE_Z: float = -19.5
## Легковые машины: X, Z, поворот (град).
const CARS: Array = [
	[-92.3, 9.6, 0.0], [-55.3, 7.7, -10.0], [-71.6, 18.0, 5.0],
	[-14.7, 6.5, 0.0], [12.4, 19.6, -50.0], [42.4, 22.0, -8.0],
	[71.1, 11.6, -15.0], [66.7, 21.5, -10.0], [-4.3, 39.6, 70.0],
	[-4.3, 27.1, 20.0], [75.4, 65.9, -15.0], [78.3, 70.3, -10.0],
]
## Полосы покрытия (без коллизии): начало X/Z, конец X/Z, ширина, цвет.
const STRIPS: Array = [
	[-100.0, 6.1, 11.6, 6.1, 11.2, C_ASPHALT],
	[11.6, 6.1, 100.0, 22.0, 11.2, C_ASPHALT],
	[8.5, 2.1, 8.5, -17.1, 7.0, C_ASPHALT],
	[-10.7, 28.4, -6.7, 57.9, 4.0, C_PATH],
]
## Площадки покрытия (без коллизии): X, Z, размер X, размер Z, цвет.
const PADS: Array = [
	[-62.5, -6.9, 46.3, 14.0, C_ASPHALT],
	[13.2, -38.6, 35.1, 43.1, C_YARD],
]
## Берег озера (метка 6): многоугольник по карте, X/Z.
const LAKE: Array[Vector2] = [
	Vector2(-100.0, 53.9), Vector2(-85.6, 43.5), Vector2(-68.1, 39.1),
	Vector2(-52.2, 41.1), Vector2(-39.4, 49.1), Vector2(-28.2, 55.5),
	Vector2(-17.1, 61.4), Vector2(-5.9, 71.5), Vector2(3.7, 81.8),
	Vector2(10.0, 91.4), Vector2(12.4, 100.0), Vector2(-100.0, 100.0),
]
## Башня Главного Компьютера (метка 8): далеко на северо-востоке.
const TOWER_POS: Vector3 = Vector3(650.0, 0.0, -650.0)
const TOWER_HEIGHT: float = 380.0

## Ставить ли игрока (тесты строят сцену без него).
@export var spawn_player: bool = true

var _player: Player
var _sun: DirectionalLight3D
var _env: Environment
var _debug: DebugPanel
## Занятые прямоугольники (X, Z, полуразмер X, полуразмер Z) — для деревьев.
var _blocked: Array[Rect2] = []


func _ready() -> void:
	DisplayServer.window_set_title("Born Unblessed — district")
	Log.info("Район-заготовка: строю квартал из коробок", "DistrictLab")
	_build_ground()
	_build_surfaces()
	_build_lake()
	_build_houses()
	_build_boxes()
	_build_garages()
	_build_cars()
	_build_borders()
	_build_trees()
	_build_tower()
	_build_light()
	if spawn_player:
		_spawn_player()
		_debug = DebugPanel.new()
		add_child(_debug)
		_debug.set_lab_mode(true)
		_debug.return_world_requested.connect(_exit_to_menu)
		_debug.watch_light(_env, _sun, null)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


## Коробка «ногами» на земле: видимый меш и (по желанию) коллизия слоя мира.
func _box(
	box_name: String, center: Vector2, size: Vector3, yaw_deg: float,
	color: Color, solid: bool = true, parent: Node3D = self
) -> Node3D:
	var node := Node3D.new()
	node.name = box_name
	node.position = Vector3(center.x, 0.0, center.y)
	node.rotation.y = deg_to_rad(yaw_deg)
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material(color)
	instance.position = Vector3(0.0, size.y * 0.5, 0.0)
	node.add_child(instance)
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		SolidBody.add(node, shape, Vector3(0.0, size.y * 0.5, 0.0))
	parent.add_child(node)
	return node


func _block(center: Vector2, half: Vector2) -> void:
	_blocked.append(Rect2(center - half, half * 2.0))


func _build_ground() -> void:
	# Земля с запасом за границей района (лес вокруг), верх — на y = 0.
	var size: float = HALF * 2.0 + 120.0
	var ground := Node3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	var instance := MeshInstance3D.new()
	instance.mesh = plane
	instance.material_override = _material(C_GROUND)
	ground.add_child(instance)
	var shape := BoxShape3D.new()
	shape.size = Vector3(size, 2.0, size)
	SolidBody.add(ground, shape, Vector3(0.0, -1.0, 0.0))
	add_child(ground)


func _build_surfaces() -> void:
	var root := Node3D.new()
	root.name = "Surfaces"
	add_child(root)
	for i: int in STRIPS.size():
		var strip: Array = STRIPS[i]
		var a := Vector2(strip[0], strip[1])
		var b := Vector2(strip[2], strip[3])
		var width: float = strip[4]
		var dir: Vector2 = b - a
		# rotate_y(θ) ведёт ось X в (cos θ, −sin θ) по X/Z.
		var yaw: float = rad_to_deg(-atan2(dir.y, dir.x))
		_box(
			"Strip%d" % i, (a + b) * 0.5,
			Vector3(dir.length(), 0.04, width), yaw, strip[5], false, root)
		# Грубо: деревья не растут на полосе (по габариту отрезка).
		_block((a + b) * 0.5, Vector2(
			absf(dir.x) * 0.5 + width * 0.5, absf(dir.y) * 0.5 + width * 0.5))
	for i: int in PADS.size():
		var pad: Array = PADS[i]
		_box(
			"Pad%d" % i, Vector2(pad[0], pad[1]),
			Vector3(pad[2], 0.03, pad[3]), 0.0, pad[4], false, root)
		_block(Vector2(pad[0], pad[1]), Vector2(pad[2], pad[3]) * 0.5)


func _build_lake() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(
		PackedVector2Array(LAKE))
	for point: Vector2 in LAKE:
		st.add_vertex(Vector3(point.x, 0.05, point.y))
	# Порядок обхода — лицом вверх: при взгляде сверху (Z на юг) нужен обход,
	# дающий нормаль +Y; двусторонний материал снимает вопрос.
	for index: int in indices:
		st.add_index(index)
	var material := _material(C_WATER)
	material.roughness = 0.15
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lake := MeshInstance3D.new()
	lake.name = "Lake"
	lake.mesh = st.commit()
	lake.material_override = material
	add_child(lake)


func _build_houses() -> void:
	var root := Node3D.new()
	root.name = "Houses"
	add_child(root)
	for house: Array in HOUSES:
		var house_name: String = house[0]
		var center := Vector2(house[1], house[2])
		var size := Vector2(house[3], house[4])
		var side := Vector2(house[5], house[6])
		var count: int = house[7]
		var node: Node3D = _box(
			house_name, center, Vector3(size.x, HOUSE_HEIGHT, size.y), 0.0,
			C_HOUSE, true, root)
		_block(center, size * 0.5 + Vector2(3.0, 3.0))
		# Подъезды: вдоль длинной стороны, с шагом панельного дома.
		var along := Vector2(absf(side.y), absf(side.x))
		for i: int in count:
			var offset: float = (float(i) - float(count - 1) * 0.5) * ENTRANCE_STEP
			var local: Vector2 = along * offset + side * (
				(size.x if side.x != 0.0 else size.y) * 0.5 + 0.8)
			var open: bool = house_name == OPEN_HOUSE and i == OPEN_ENTRANCE
			var porch_size := Vector3(
				2.4 if side.y != 0.0 else 1.6, 2.6,
				1.6 if side.y != 0.0 else 2.4)
			var porch: Node3D = _box(
				"EntranceOpen" if open else "Entrance%d" % i,
				local, porch_size, 0.0,
				C_OPEN if open else C_ENTRANCE, true, node)
			porch.add_to_group(&"district_entrance")


func _build_boxes() -> void:
	var root := Node3D.new()
	root.name = "Boxes"
	add_child(root)
	for box: Array in BOXES:
		var size := Vector3(box[3], box[5], box[4])
		_box(box[0], Vector2(box[1], box[2]), size, box[6], box[7], true, root)
		var reach: float = maxf(size.x, size.z) * 0.5 + 1.0
		_block(Vector2(box[1], box[2]), Vector2(reach, reach))


func _build_garages() -> void:
	var root := Node3D.new()
	root.name = "Garages"
	add_child(root)
	var step: float = (GARAGE_X1 - GARAGE_X0) / float(GARAGE_COUNT)
	for i: int in GARAGE_COUNT:
		var x: float = GARAGE_X0 + step * (float(i) + 0.5)
		_box(
			"Garage%d" % i, Vector2(x, GARAGE_Z),
			Vector3(step - 0.4, 2.8, 6.5), 0.0, C_SMALL, true, root)
	_block(
		Vector2((GARAGE_X0 + GARAGE_X1) * 0.5, GARAGE_Z),
		Vector2((GARAGE_X1 - GARAGE_X0) * 0.5 + 1.0, 4.5))


func _build_cars() -> void:
	var root := Node3D.new()
	root.name = "Cars"
	add_child(root)
	for i: int in CARS.size():
		var car: Array = CARS[i]
		_box(
			"Car%d" % i, Vector2(car[0], car[1]), Vector3(4.4, 1.4, 1.8),
			car[2], C_CAR, true, root)


## Невидимые стены по границе участка: игрок не уходит за карту.
func _build_borders() -> void:
	var root := Node3D.new()
	root.name = "Borders"
	add_child(root)
	var long: float = HALF * 2.0 + 2.0
	var walls: Array = [
		[Vector3(0.0, 4.0, -HALF - 0.5), Vector3(long, 8.0, 1.0)],
		[Vector3(0.0, 4.0, HALF + 0.5), Vector3(long, 8.0, 1.0)],
		[Vector3(-HALF - 0.5, 4.0, 0.0), Vector3(1.0, 8.0, long)],
		[Vector3(HALF + 0.5, 4.0, 0.0), Vector3(1.0, 8.0, long)],
	]
	for wall: Array in walls:
		var shape := BoxShape3D.new()
		shape.size = wall[1]
		SolidBody.add(root, shape, wall[0])


func _tree_allowed(point: Vector2) -> bool:
	if Geometry2D.is_point_in_polygon(point, PackedVector2Array(LAKE)):
		return false
	for rect: Rect2 in _blocked:
		if rect.has_point(point):
			return false
	return point.distance_to(Vector2(START.x, START.z)) > 14.0


## Условные деревья (ствол-цилиндр и крона-шар) вне построек, дорог и озера:
## только чтобы оценить, как лес закрывает район. Без коллизии.
func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = LAB_SEED
	var transforms: Array[Transform3D] = []
	var reach: float = HALF + 50.0
	for i: int in TREE_TRIES:
		var point := Vector2(
			rng.randf_range(-reach, reach), rng.randf_range(-reach, reach))
		var tree_scale: float = rng.randf_range(0.7, 1.4)
		if not _tree_allowed(point):
			continue
		transforms.append(Transform3D(
			Basis.IDENTITY.scaled(Vector3(tree_scale, tree_scale, tree_scale)),
			Vector3(point.x, 0.0, point.y)))
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.28
	trunk.height = 6.0
	var crown := SphereMesh.new()
	crown.radius = 3.2
	crown.height = 7.0
	crown.radial_segments = 12
	crown.rings = 6
	var root := Node3D.new()
	root.name = "Trees"
	add_child(root)
	_add_multimesh(root, "Trunks", trunk, C_TRUNK, transforms, 3.0)
	_add_multimesh(root, "Crowns", crown, C_CROWN, transforms, 8.5)


func _add_multimesh(
	parent: Node3D, mm_name: String, mesh: Mesh, color: Color,
	transforms: Array[Transform3D], lift: float
) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i: int in transforms.size():
		var xform: Transform3D = transforms[i]
		xform.origin.y = lift * xform.basis.get_scale().y
		multimesh.set_instance_transform(i, xform)
	var instance := MultiMeshInstance3D.new()
	instance.name = mm_name
	instance.multimesh = multimesh
	instance.material_override = _material(color)
	parent.add_child(instance)


func _build_tower() -> void:
	var tower := Node3D.new()
	tower.name = "Tower"
	tower.position = TOWER_POS
	add_child(tower)
	var parts: Array = [
		[Vector3(70.0, TOWER_HEIGHT * 0.55, 70.0), 0.0],
		[Vector3(34.0, TOWER_HEIGHT, 34.0), 0.0],
		[Vector3(18.0, TOWER_HEIGHT * 0.85, 18.0), 40.0],
	]
	for part: Array in parts:
		var size: Vector3 = part[0]
		var mesh := BoxMesh.new()
		mesh.size = size
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = _material(C_TOWER)
		instance.position = Vector3(float(part[1]), size.y * 0.5, 0.0)
		tower.add_child(instance)


func _build_light() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	# Вечернее солнце с запада, как на референсе.
	_sun.rotation_degrees = Vector3(-32.0, 115.0, 0.0)
	_sun.light_energy = 1.2
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 160.0
	add_child(_sun)
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.45, 0.55, 0.70)
	sky_material.sky_horizon_color = Color(0.80, 0.72, 0.62)
	sky_material.ground_horizon_color = Color(0.60, 0.58, 0.52)
	sky_material.ground_bottom_color = Color(0.30, 0.32, 0.28)
	var sky := Sky.new()
	sky.sky_material = sky_material
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.74, 0.72, 0.68)
	_env.fog_density = 0.0005
	_env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.name = "Environment"
	world_env.environment = _env
	add_child(world_env)


func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = START
	add_child(_player)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_exit_to_menu()


func _exit_to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(Dev.MENU_SCENE)
