# Лаборатория ezTree (П18-ЛАБОРАТОРИЯ, п. 4 владельца): тестовая сцена —
# копия демо www.eztree.dev (src/app/scene.js, исходники в docs/eztree_demo):
# ровная земля 2000×2000 ед. с пятнами травы по шуму демо, ясень в центре,
# ~100 лиственных деревьев на 175–675 ед. (×k), трава и цветы демо,
# камера в точке демо (100, 20, 0 → цель (0, 25, 0), FOV 60) с орбитой
# мышью, простое небо-градиент демо без наших облаков. СВЕТ — дефолты
# нашего мира (AgX, экспозиция 1.0, солнце 0.3, ambient из неба, туман
# 0.0035): владелец подгоняет картинку к демо ползунками F3 → «Свет»
# (живой рендер, ничего не сохраняется). Запуск: --ez-lab или кнопка F3.
class_name EzLab
extends Node3D

const B: Balance = preload("res://gameplay/balance.tres")
const VPAL: VisualPalette = preload("res://assets/visual_palette.tres")

const GROUND_SHADER: Shader = preload("res://assets/shaders/ez_lab_ground.gdshader")
const SKY_SHADER: Shader = preload("res://assets/shaders/ez_lab_sky.gdshader")

## Пересчёт демо-единиц в метры — k ели large (ориентир владельца П18,
## тот же, что у поля травы Сборки 2): все пропорции сцены демо сохраняются.
const K: float = 0.38
## Seed раскладок лаборатории: картинка детерминирована (лес и трава).
const LAB_SEED: int = 20261104
## Плоскость земли демо (PlaneGeometry 2000×2000), м.
const GROUND_SIZE: float = 2000.0 * K
## Центр сцены демо — ясень Medium (пресет 'Ash Medium' scene.js).
const CENTER_BASE: String = "ash_medium_v0"
## Лес демо: treeCount 100, r = 175 + rand·500 ед. (scene.js:61-63);
## пресеты демо — случайные, у нас только лиственные (П18-фикс 3).
const FOREST_COUNT: int = 100
const FOREST_R_MIN: float = 175.0 * K
const FOREST_R_SPAN: float = 500.0 * K
## Граница LOD демо 250 ед. (defaultLODLevels) → ближняя половина леса
## стоит на LOD1, дальняя — на LOD2, как переключил бы их three.js.
const FOREST_LOD2_FROM: float = 250.0 * K
const FOREST_BASES: PackedStringArray = [
	"ash_large_v0", "ash_medium_v0", "ash_medium_v1", "ash_medium_v2",
	"aspen_large_v0", "aspen_medium_v0", "aspen_medium_v1",
	"aspen_small_v0", "aspen_small_v1",
	"oak_large_v0", "oak_large_v1", "oak_large_v2",
	"oak_medium_v0", "oak_medium_v1", "oak_medium_v2",
]
## Камера демо (OrbitControls): позиция (100, 20, 0), цель (0, 25, 0),
## FOV 60, дистанция 10–150 ед., полярные углы π/2−0.2 … π/2+0.13.
## Здесь pitch — высотный угол орбиты (−0.13 … +0.2 рад).
const ORIGIN_TARGET: Vector3 = Vector3(0.0, 25.0, 0.0) * K
const ORIGIN_POS: Vector3 = Vector3(100.0, 20.0, 0.0) * K
const FOV_DEG: float = 60.0
const FAR_M: float = 2000.0 * K
const DIST_MIN: float = 10.0 * K
const DIST_MAX: float = 150.0 * K
const PITCH_MIN: float = -0.13
const PITCH_MAX: float = 0.2
## Чувствительность орбиты: рад на пиксель (drag) и шаг зума колесом.
const ORBIT_SENS: float = 0.005
const ZOOM_STEP: float = 0.9
## Высота солнца полудня мира (Balance.sun_max_elevation = 62°) и азимут
## полудня (0 — север): стартовое положение лабораторного солнца — как
## дневное в мире, чтобы «до ползунков» картинка совпадала с игрой.
const SUN_ELEVATION_DEG: float = 62.0
const SUN_AZIMUTH: float = 0.0

var _camera: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _sky_material: ShaderMaterial
var _debug: DebugPanel
## Орбита: дистанция до цели, азимут и высотный угол.
var _dist: float
var _yaw: float
var _pitch: float
var _dragging: bool = false


func _ready() -> void:
	DisplayServer.window_set_title("Born Unblessed — ezTree lab")
	Log.info("ezTree-лаборатория: строю сцену-копию демо", "EzLab")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ground()
	_build_trees()
	_build_grass()
	_build_light()
	_build_camera()
	_debug = DebugPanel.new()
	add_child(_debug)
	_debug.set_lab_mode(true)
	_debug.return_world_requested.connect(_on_return_world)


## Ровная земля с пятнами травы: плоскость 760×760 м, материал демо —
# микс травы/грунта по пятнистости шума (ez_lab_ground.gdshader).
func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	material.set_shader_parameter("grass_tex", load(
		"res://assets/third_party/ambientcg.com/Grass001/Grass001_1K-JPG_Color.jpg"))
	material.set_shader_parameter("dirt_tex", load(
		"res://assets/third_party/polyhaven.com/forest_ground_05/forest_ground_05_diffuse_2k.jpg"))
	material.set_shader_parameter("dirt_normal", load(
		"res://assets/third_party/polyhaven.com/forest_ground_05/forest_ground_05_nor_gl_2k.jpg"))
	var mesh := MeshInstance3D.new()
	mesh.name = "LabGround"
	mesh.mesh = plane
	mesh.material_override = material
	add_child(mesh)


## Ясень в центре (гибрид: полная листва LOD0 + ветки LOD1) и лес — 100
## лиственных деревьев по кругу 66.5–190 м; уровень меша — по дистанции
## посадки (LOD1 ближе 95 м, LOD2 дальше), деревья одной базы и уровня
## сливаются в MultiMesh (материал общий — ползунки листвы красят всех).
func _build_trees() -> void:
	var center := MeshInstance3D.new()
	center.name = "LabTree"
	center.mesh = EzTreeMeshes.build_lab_set(CENTER_BASE, K)["mesh"]
	add_child(center)

	var rng := RandomNumberGenerator.new()
	rng.seed = LAB_SEED
	# Ключ «база:уровень» → меш и трансформы; MultiMesh на каждый ключ.
	var buckets: Dictionary = {}
	for i: int in FOREST_COUNT:
		var r: float = rng.randf_range(FOREST_R_MIN, FOREST_R_MIN + FOREST_R_SPAN)
		var theta: float = rng.randf_range(0.0, TAU)
		var base: String = FOREST_BASES[rng.randi_range(
			0, FOREST_BASES.size() - 1)]
		var lod: int = 0 if r < FOREST_LOD2_FROM else 1
		var key := "%s:%d" % [base, lod]
		if not buckets.has(key):
			buckets[key] = {
				"mesh": EzTreeMeshes.build_lab_set(base, K)["lods"][lod],
				"transforms": Array(),
			}
		(buckets[key]["transforms"] as Array).append(Transform3D(
			Basis.IDENTITY, Vector3(r * cos(theta), 0.0, r * sin(theta))))
	var forest := Node3D.new()
	forest.name = "LabForest"
	add_child(forest)
	for key: String in buckets:
		var bucket: Dictionary = buckets[key]
		var transforms: Array = bucket["transforms"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = bucket["mesh"]
		mm.instance_count = transforms.size()
		for i: int in transforms.size():
			mm.set_instance_transform(i, transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = "Forest_%s" % key.replace(":", "_")
		instance.multimesh = mm
		forest.add_child(instance)
	Log.info("ezTree-лаборатория: лес — %d деревьев, %d мешей-групп"
		% [FOREST_COUNT, buckets.size()], "EzLab")


## Трава и цветы демо (ассеты Сборки 2): 5000 показываемых пучков в круге
## 3.8–193.8 м и по ~50 цветов вида в круге 3.8–79.8 м, пятнистость —
## формулы grass.js (GrassField.lab_layout).
func _build_grass() -> void:
	var nodes: Dictionary = GrassField.lab_make_nodes()
	for type: String in nodes:
		add_child(nodes[type])
	GrassField.apply_field(nodes, GrassField.lab_layout(LAB_SEED + 1))


## Свет и небо: параметры — дефолты мира днём (Balance/VisualPalette),
## солнце на высоте полудня; небо-градиент демо без облаков. Дальше живой
## рендер крутят ползунки F3 → «Свет» (LightTuner).
func _build_light() -> void:
	var elevation := deg_to_rad(SUN_ELEVATION_DEG)
	var dir := Vector3(
		sin(SUN_AZIMUTH) * cos(elevation),
		sin(elevation),
		cos(SUN_AZIMUTH) * cos(elevation)).normalized()
	_sun = DirectionalLight3D.new()
	_sun.name = "LabSun"
	_sun.light_color = VPAL.day_sun
	_sun.light_energy = B.sun_energy_noon
	_sun.shadow_enabled = true
	_sun.shadow_blur = 1.4
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = 120.0
	add_child(_sun)
	_sun.position = dir * 100.0
	_sun.look_at(Vector3.ZERO, Vector3.UP)

	_sky_material = ShaderMaterial.new()
	_sky_material.shader = SKY_SHADER
	_sky_material.set_shader_parameter("sun_dir", dir)
	var sky := Sky.new()
	sky.sky_material = _sky_material
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_color = VPAL.day_ambient
	_env.ambient_light_energy = DayMath.ambient_energy_sky(
		B.day_cycle_sec * 0.3)
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.tonemap_white = 6.0
	_env.tonemap_exposure = 1.0
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.05
	_env.adjustment_saturation = 1.15
	_env.fog_enabled = true
	_env.fog_sky_affect = 0.0
	_env.fog_light_color = VPAL.day_fog
	_env.fog_density = B.fog_density
	_env.fog_height = B.fog_height_m
	_env.fog_height_density = B.fog_height_density
	var world_env := WorldEnvironment.new()
	world_env.name = "LabEnvironment"
	world_env.environment = _env
	add_child(world_env)


## Камера-орбита (OrbitControls демо): старт в точке демо, ЛКМ — вращение
## вокруг дерева, колесо — дистанция; pitch и дистанция ограничены как
## minPolar/maxPolar/minDistance/maxDistance демо.
func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "LabCamera"
	_camera.fov = FOV_DEG
	_camera.near = 0.1
	_camera.far = FAR_M
	add_child(_camera)
	var offset := ORIGIN_POS - ORIGIN_TARGET
	_dist = clampf(offset.length(), DIST_MIN, DIST_MAX)
	_yaw = atan2(offset.x, offset.z)
	_pitch = clampf(asin(offset.y / maxf(offset.length(), 0.001)),
		PITCH_MIN, PITCH_MAX)
	_camera.current = true
	_apply_orbit()


func _apply_orbit() -> void:
	_camera.global_position = ORIGIN_TARGET + _dist * Vector3(
		cos(_pitch) * sin(_yaw), sin(_pitch), cos(_pitch) * cos(_yaw))
	_camera.look_at(ORIGIN_TARGET, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
		elif button.pressed \
				and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(_dist * ZOOM_STEP, DIST_MIN)
			_apply_orbit()
		elif button.pressed \
				and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(_dist / ZOOM_STEP, DIST_MAX)
			_apply_orbit()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * ORBIT_SENS
		_pitch = clampf(
			_pitch - motion.relative.y * ORBIT_SENS, PITCH_MIN, PITCH_MAX)
		_apply_orbit()
	elif event.is_action_pressed("pause"):
		# Esc — в главное меню (лаборатория из мира закрывается кнопкой F3).
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file(Dev.MENU_SCENE)


## Кнопка «Вернуться в мир» (П18-ЛАБОРАТОРИЯ): тот же путь входа, что у
## меню, — через экран загрузки, офлайн-мир без сети (свет подбирали, мир
## пересоздаётся чистым).
func _on_return_world() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	LoadingScreenBU.open(get_tree(), "res://scenes/world_scene.tscn")
