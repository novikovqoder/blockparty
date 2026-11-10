# Район (постапокалипсис): заброшенный квартал по согласованной карте
# (10.11.2026), участок 200×200 м. Этап 1 «реальной графики»: природа
# Born Unblessed (деревья ez-tree, трава, небо и свет мира, вода), земля
# с чашей озера, асфальт и покрытия, панельные пятиэтажки и малые постройки
# с текстурами (CC0). Раскладка — DistrictLayout, дома — PanelHouse,
# природа — DistrictNature.
# Герой — робот RobotModelPA (вместо рыцаря в том же игроке).
# Чего пока нет: интерьеров (в дома зайти нельзя), уличного наполнения,
# настоящих машин (стоят машины под тентом; автобус и грузовики — ржавые
# коробки-заглушки).
# Запуск: аргумент --district. Выход в меню — Esc.
# Самопроверка анимаций робота: --district --selftest-anim (PASS/FAIL, код
# возврата 1 при FAIL) — те же проверки, что у рыцаря.
class_name DistrictLab
extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://gameplay/player/player.tscn")
const ENV_SCENE: PackedScene = preload("res://scenes/district_env.tscn")
const CAR_SCENE: PackedScene = preload(
	"res://assets/third_party/polyhaven.com/covered_car/covered_car_1k.gltf")
const GROUND_SHADER: Shader = preload("res://assets/shaders/ez_lab_ground.gdshader")

## Время суток района, с цикла мира (600 — вторая половина дня, солнце ~30°).
const TIME_SEC: float = 600.0
## Сторона клетки сетки земли, м, и запас земли за границей участка.
const GROUND_CELL: float = 2.0
const GROUND_MARGIN: float = 60.0
const SEED: int = 20261110

## Ставить ли игрока и применять ли уровень графики (тесты строят сцену без них).
@export var spawn_player: bool = true

var _player: Player
var _nature: DistrictNature
var _world_env: WorldEnvironment
var _sun: DirectionalLight3D
var _day_cycle: DayCycle
var _debug: DebugPanel


func _ready() -> void:
	DisplayServer.window_set_title("Born Unblessed — district")
	Log.info("Район: строю квартал", "DistrictLab")
	Session.world_time = TIME_SEC
	_build_env()
	_build_ground()
	_build_surfaces()
	_build_water()
	_build_houses()
	_build_buildings()
	_build_blocks()
	_build_cars()
	_build_borders()
	_build_tower()
	var tier: int = GraphicsQuality.tier_from_settings()
	_nature = DistrictNature.new()
	_nature.name = "Nature"
	add_child(_nature)
	_nature.setup(tier)
	if spawn_player:
		_apply_graphics(tier)
		_spawn_player()
		_debug = DebugPanel.new()
		add_child(_debug)
		_debug.watch_player(_player)
		_debug.watch_graphics(_world_env.environment, null, tier)
		_debug.watch_light(
			_world_env.environment, _sun,
			_world_env.get_node_or_null("SkyDome") as SkyDome)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	# Время района стоит: часы мира ведёт сеть, здесь её нет.
	Session.world_time = TIME_SEC
	if _player != null:
		_nature.update_viewer(_player.global_position)
		_day_cycle.set_fog_focus(_player.global_position)


## Небо, солнце и туман — как в мире (копия узла окружения), цикл дня ведёт
## их по часам, которые здесь стоят на TIME_SEC.
func _build_env() -> void:
	var env_root: Node3D = ENV_SCENE.instantiate()
	env_root.name = "Env"
	add_child(env_root)
	_world_env = env_root.get_node("WorldEnvironment") as WorldEnvironment
	_sun = _world_env.get_node("SunLight") as DirectionalLight3D
	_day_cycle = DayCycle.new()
	_day_cycle.name = "DayCycle"
	add_child(_day_cycle)
	_day_cycle.setup(_sun, _world_env)


func _apply_graphics(tier: int) -> void:
	_day_cycle.simple = tier == GraphicsQuality.Tier.SIMPLE
	GraphicsQuality.apply(
		_world_env.environment, _sun, tier, get_viewport(),
		_world_env.get_node_or_null("MoonLight") as DirectionalLight3D)
	var vignette: ColorRect = GraphicsQuality.make_vignette()
	vignette.visible = tier >= GraphicsQuality.Tier.HIGH
	add_child(vignette)
	for node: Node in get_tree().get_nodes_in_group("water_surface"):
		(node as WaterArea).set_tier_fade(tier)


## Земля: сетка с чашей озера, материал луга мира (трава/грунт пятнами),
## коллизия — по тем же треугольникам.
func _build_ground() -> void:
	var reach: float = DistrictLayout.HALF + GROUND_MARGIN
	var count: int = int(reach * 2.0 / GROUND_CELL)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz: int in count + 1:
		for ix: int in count + 1:
			var p := Vector2(-reach + float(ix) * GROUND_CELL, -reach + float(iz) * GROUND_CELL)
			st.add_vertex(Vector3(p.x, DistrictLayout.ground_height(p), p.y))
	var row: int = count + 1
	for iz: int in count:
		for ix: int in count:
			var a: int = iz * row + ix
			# По часовой стрелке при взгляде сверху — лицом вверх.
			for index: int in [a, a + 1, a + row, a + 1, a + row + 1, a + row]:
				st.add_index(index)
	st.generate_normals()
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	material.set_shader_parameter("grass_tex", load(
		"res://assets/third_party/ambientcg.com/Grass001/Grass001_1K-JPG_Color.jpg"))
	material.set_shader_parameter("dirt_tex", load(
		"res://assets/third_party/polyhaven.com/forest_ground_05/forest_ground_05_diffuse_2k.jpg"))
	material.set_shader_parameter("dirt_normal", load(
		"res://assets/third_party/polyhaven.com/forest_ground_05/forest_ground_05_nor_gl_2k.jpg"))
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = st.commit()
	ground.material_override = material
	add_child(ground)
	# Дальняя земля до горизонта (без коллизии): четыре полосы вокруг сетки —
	# за лесом не видно её края; над озером их нет.
	var far_reach: float = 2000.0
	var band: float = far_reach - reach
	var bands: Array = [
		[Vector3(0.0, -0.02, -(reach + band * 0.5)), Vector2(far_reach * 2.0, band)],
		[Vector3(0.0, -0.02, reach + band * 0.5), Vector2(far_reach * 2.0, band)],
		[Vector3(-(reach + band * 0.5), -0.02, 0.0), Vector2(band, reach * 2.0)],
		[Vector3(reach + band * 0.5, -0.02, 0.0), Vector2(band, reach * 2.0)],
	]
	for i: int in bands.size():
		var far_plane := PlaneMesh.new()
		far_plane.size = bands[i][1]
		var far := MeshInstance3D.new()
		far.name = "GroundFar%d" % i
		far.mesh = far_plane
		far.material_override = material
		far.position = bands[i][0]
		far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ground.add_child(far)
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = ground.mesh.create_trimesh_shape()
	body.add_child(collision)
	ground.add_child(body)


## Асфальт дороги и площадки, плитка двора, тропа — тонкие плиты поверх земли.
func _build_surfaces() -> void:
	var kit := MeshKit.new()
	var keys: Dictionary = {
		DistrictLayout.Surface.ASPHALT: &"asphalt",
		DistrictLayout.Surface.YARD: &"yard",
		DistrictLayout.Surface.PATH: &"path",
	}
	var lift: float = 0.02
	for strip: Array in DistrictLayout.STRIPS:
		var a := Vector2(strip[0], strip[1])
		var b := Vector2(strip[2], strip[3])
		var dir: Vector2 = b - a
		var basis := Basis(Vector3.UP, -atan2(dir.y, dir.x))
		var mid: Vector2 = (a + b) * 0.5
		kit.add_box(
			keys[strip[5]], Vector3(mid.x, lift * 0.5, mid.y),
			Vector3(dir.length(), lift, float(strip[4])), Color.WHITE, basis, true)
		lift += 0.006
	for pad: Array in DistrictLayout.PADS:
		kit.add_box(
			keys[pad[4]], Vector3(pad[0], lift * 0.5, pad[1]),
			Vector3(pad[2], lift, pad[3]), Color.WHITE, Basis.IDENTITY, true)
		lift += 0.006
	var surfaces := MeshInstance3D.new()
	surfaces.name = "Surfaces"
	surfaces.mesh = kit.commit({
		&"asphalt": DistrictMaterials.surface(
			"asphalt_02", 4.0, Color(0.8, 0.8, 0.8), 0.24, 0.0),
		&"yard": DistrictMaterials.surface(
			"grass_concrete_pavement", 2.2, Color(0.8, 0.8, 0.78), 0.4, 0.0),
		&"path": DistrictMaterials.surface(
			"brown_mud_dry", 2.5, Color(0.75, 0.72, 0.68), 0.2, 0.0),
	})
	surfaces.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surfaces)


## Озеро: вода мира (WaterArea) прямоугольником по габариту берега — вне
## чаши она лежит под землёй; в зоне можно плавать.
func _build_water() -> void:
	var bounds := Rect2(DistrictLayout.LAKE[0], Vector2.ZERO)
	for point: Vector2 in DistrictLayout.LAKE:
		bounds = bounds.expand(point)
	var water := WaterArea.new()
	water.name = "Lake"
	add_child(water)
	water.setup(bounds.get_center(), bounds.size, DistrictLayout.WATER_LEVEL)


func _place(node: Node3D, parent: Node3D, x: float, z: float, yaw_deg: float) -> void:
	node.position = Vector3(x, 0.0, z)
	node.rotation.y = deg_to_rad(yaw_deg)
	parent.add_child(node)


func _group(group_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = group_name
	add_child(root)
	return root


func _build_houses() -> void:
	var houses: Node3D = _group("Houses")
	for i: int in DistrictLayout.HOUSES.size():
		var h: Array = DistrictLayout.HOUSES[i]
		var open: int = DistrictLayout.OPEN_ENTRANCE \
			if String(h[0]) == DistrictLayout.OPEN_HOUSE else -1
		_place(
			PanelHouse.build(h[0], h[3], h[4], 5, h[6], open, SEED + i),
			houses, h[1], h[2], h[5])
	var ruins: Node3D = _group("Ruins")
	for i: int in DistrictLayout.RUINS.size():
		var r: Array = DistrictLayout.RUINS[i]
		_place(
			PanelHouse.build(r[0], r[3], r[4], r[6], 0, -1, SEED + 50 + i, true),
			ruins, r[1], r[2], r[5])


func _build_buildings() -> void:
	var root: Node3D = _group("Buildings")
	var brick: Material = DistrictMaterials.surface(
		"whitewashed_brick", 1.6, Color(0.85, 0.83, 0.8), 0.3, 1.6)
	var slab: Material = DistrictMaterials.surface(
		"concrete_slab_wall", 2.4, Color(0.6, 0.6, 0.58), 0.5, 0.0)
	var tin: Material = DistrictMaterials.surface(
		"rusty_corrugated_iron", 1.4, Color(0.8, 0.8, 0.8), 0.1, 0.0, 0.5)
	var doors: Array[Material] = [
		DistrictMaterials.surface("rusty_painted_metal", 1.6, Color.WHITE, 0.0, 0.0, 0.6),
		DistrictMaterials.surface("green_metal_rust", 1.6, Color.WHITE, 0.0, 0.0, 0.6),
	]
	for i: int in DistrictLayout.BUILDINGS.size():
		var b: Array = DistrictLayout.BUILDINGS[i]
		var size := Vector3(b[3], b[5], b[4])
		var node: Node3D
		match String(b[7]):
			"shop":
				node = DistrictProps.building(
					b[0], size, DistrictMaterials.surface(
						"worn_plaster_wall", 2.6, Color(0.9, 0.88, 0.82), 0.2, 1.5),
					slab, Vector2(1.1, 2.1), doors[1], 3, SEED + 100 + i)
			"garage":
				node = DistrictProps.building(
					b[0], size, brick, tin, Vector2(size.x - 1.2, size.y - 0.6),
					doors[i % 2], 0, SEED + 100 + i)
			_:
				node = DistrictProps.building(
					b[0], size, brick, slab, Vector2(1.5, 2.0), doors[i % 2], 0,
					SEED + 100 + i)
		_place(node, root, b[1], b[2], b[6])
	var garages: Node3D = _group("Garages")
	var step: float = (DistrictLayout.GARAGE_X1 - DistrictLayout.GARAGE_X0) \
		/ float(DistrictLayout.GARAGE_COUNT)
	for i: int in DistrictLayout.GARAGE_COUNT:
		var size := Vector3(step - 0.3, 2.8, DistrictLayout.GARAGE_DEPTH)
		_place(
			DistrictProps.building(
				"Garage%d" % i, size, brick, tin, Vector2(size.x - 1.0, 2.2),
				doors[(i * 7 + 1) % 2], 0, SEED + 200 + i),
			garages, DistrictLayout.GARAGE_X0 + step * (float(i) + 0.5),
			DistrictLayout.GARAGE_Z, 0.0)


func _build_blocks() -> void:
	var root: Node3D = _group("Blocks")
	var kinds: Dictionary = {
		"rust": DistrictMaterials.surface(
			"rusty_corrugated_iron", 1.2, Color(0.75, 0.75, 0.75), 0.05, 0.0, 0.5),
		"wood": DistrictMaterials.surface(
			"weathered_peeling_timber", 1.5, Color(0.7, 0.68, 0.64), 0.1, 0.0),
		"concrete": DistrictMaterials.surface(
			"concrete_slab_wall", 2.0, Color(0.7, 0.7, 0.68), 0.3, 0.8),
	}
	for b: Array in DistrictLayout.BLOCKS:
		_place(
			DistrictProps.block(b[0], Vector3(b[3], b[5], b[4]), kinds[b[7]]),
			root, b[1], b[2], b[6])


## Машины под тентом (модель Poly Haven) на местах машин с карты.
func _build_cars() -> void:
	var root: Node3D = _group("Cars")
	for i: int in DistrictLayout.CARS.size():
		var car: Array = DistrictLayout.CARS[i]
		var node := Node3D.new()
		node.name = "Car%d" % i
		node.add_child(CAR_SCENE.instantiate())
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.8, 1.4, 4.4)
		SolidBody.add(node, shape, Vector3(0.0, 0.7, 0.0))
		# Модель вытянута по Z, углы карты заданы для длины по X.
		_place(node, root, car[0], car[1], float(car[2]) + 90.0)


## Невидимые стены по границе участка: игрок не уходит за карту.
func _build_borders() -> void:
	var root: Node3D = _group("Borders")
	var half: float = DistrictLayout.HALF
	var long: float = half * 2.0 + 2.0
	var walls: Array = [
		[Vector3(0.0, 2.0, -half - 0.5), Vector3(long, 12.0, 1.0)],
		[Vector3(0.0, 2.0, half + 0.5), Vector3(long, 12.0, 1.0)],
		[Vector3(-half - 0.5, 2.0, 0.0), Vector3(1.0, 12.0, long)],
		[Vector3(half + 0.5, 2.0, 0.0), Vector3(1.0, 12.0, long)],
	]
	for wall: Array in walls:
		var shape := BoxShape3D.new()
		shape.size = wall[1]
		SolidBody.add(root, shape, wall[0])


## Башня Главного Компьютера: тёмный силуэт с холодными огнями в дымке.
func _build_tower() -> void:
	var kit := MeshKit.new()
	var h: float = DistrictLayout.TOWER_HEIGHT
	var parts: Array = [
		[Vector3(0.0, 0.0, 0.0), Vector3(56.0, h * 0.5, 56.0)],
		[Vector3(0.0, 0.0, 0.0), Vector3(28.0, h, 28.0)],
		[Vector3(30.0, 0.0, 6.0), Vector3(16.0, h * 0.82, 16.0)],
		[Vector3(-26.0, 0.0, -10.0), Vector3(14.0, h * 0.7, 14.0)],
	]
	for part: Array in parts:
		var size: Vector3 = part[1]
		kit.add_box(&"body", (part[0] as Vector3) + Vector3(0.0, size.y * 0.5, 0.0), size)
		# Вертикальные световые щели на гранях, обращённых к району.
		kit.add_box(
			&"light", (part[0] as Vector3) + Vector3(-size.x * 0.5 - 0.3, size.y * 0.55, 0.0),
			Vector3(0.6, size.y * 0.7, 1.6))
		kit.add_box(
			&"light", (part[0] as Vector3) + Vector3(0.0, size.y * 0.55, size.z * 0.5 + 0.3),
			Vector3(1.6, size.y * 0.7, 0.6))
	# Туман мира на таком расстоянии выбеливает силуэт — дымку башни
	# задаёт сам цвет, туман на неё не действует.
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.2, 0.25, 0.32)
	body.roughness = 0.7
	body.disable_fog = true
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(0.45, 0.85, 1.0)
	glow.disable_fog = true
	var tower := MeshInstance3D.new()
	tower.name = "Tower"
	tower.mesh = kit.commit({
		&"body": body,
		&"light": glow,
	})
	tower.position = DistrictLayout.TOWER_POS
	tower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tower)


func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = DistrictLayout.START
	put_robot(_player)
	add_child(_player)
	if Session.selftest_anim:
		_selftest_anim.call_deferred()


## Заменить визуал игрока (рыцарь BU) на робота. Звать до add_child игрока:
## player.gd берёт $Model/Visual в @onready.
static func put_robot(player: Player) -> RobotModelPA:
	var model: Node3D = player.get_node("Model") as Node3D
	var old: Node = model.get_node("Visual")
	model.remove_child(old)
	old.free()
	var robot := RobotModelPA.new()
	robot.name = "Visual"
	model.add_child(robot)
	return robot


## --district --selftest-anim: проверки анимаций (CLAUDE.md, «этапы с
## персонажами») на роботе — позы костей, резолв дорожек, скиннинг ног
## (AnimSelfCheckBU) и приземление на бегу (RealismCheck). PASS/FAIL и выход.
func _selftest_anim() -> void:
	for i: int in 40:
		await get_tree().physics_frame
	var reasons: PackedStringArray = PackedStringArray()
	var result: Dictionary = await AnimSelfCheckBU.run(_player.visual as HeroModelBU, true)
	if not result["ok"]:
		reasons.append_array(result["reasons"])
	print("SELFTEST-ANIM: робот района, приземление на бегу (сценарий Д2)")
	var landing: Dictionary = await RealismCheck.check_landing_blend(_player, "run", true)
	if not landing["ok"]:
		reasons.append_array(landing["reasons"])
	if reasons.is_empty():
		print("SELFTEST-ANIM: PASS (робот района)")
		get_tree().quit(0)
		return
	print("SELFTEST-ANIM: FAIL (робот района)")
	for reason: String in reasons:
		print("SELFTEST-ANIM: %s" % reason)
	get_tree().quit(1)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_exit_to_menu()


func _exit_to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(Dev.MENU_SCENE)
