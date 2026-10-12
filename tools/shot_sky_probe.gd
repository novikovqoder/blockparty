# Диагностика HDRI-неба (П5.8, часть A: «серое небо»): снимает одно и то же
# место острова при трёх временах суток (день/закат/ночь) и печатает средние
# цвета верха кадра — видно, работает ли панорама, без просмотра глазами.
# Запуск (сервер без экрана):
#   xvfb-run -a godot --path . --resolution 1280x720 \
#     --rendering-driver opengl3 res://tools/shot_sky_probe.tscn -- <каталог> [nofog]
# nofog — выключить влияние тумана на небо (fog_sky_affect = 0), по умолчанию
# туман включён как в сцене мира (проверка гипотезы «серое небо = туман»).
# (в Forward+ под llvmpipe сегфолтит на get_image() — см. tools/screenshots.sh)
extends Node

const B: Balance = preload("res://gameplay/balance.tres")
const ISLAND: PackedScene = preload("res://gameplay/world/island.tscn")
const SKY_SHADER: Shader = preload("res://assets/shaders/sky.gdshader")
const HDRI_DAY := "res://assets/third_party/polyhaven.com/kloofendal_48d_partly_cloudy_puresky/kloofendal_48d_partly_cloudy_puresky_2k.hdr"
const HDRI_DUSK := "res://assets/third_party/polyhaven.com/grasslands_sunset/grasslands_sunset_2k.hdr"
const HDRI_NIGHT := "res://assets/third_party/polyhaven.com/rogland_clear_night/rogland_clear_night_2k.hdr"

## Точка в Лесу на уровне глаз, взгляд вдаль чуть вверх — в кадре небо.
const EYE := Vector3(-80.0, 8.5, -80.0)
const LOOK_AT := Vector3(-70.0, 12.0, -30.0)

const SHOTS: Array[Dictionary] = [
	{"name": "sky_day", "fraction": 0.3, "mixes": Vector3(1, 0, 0)},
	{"name": "sky_dusk", "fraction": 0.45, "mixes": Vector3(0, 1, 0)},
	{"name": "sky_night", "fraction": 0.75, "mixes": Vector3(0, 0, 1)},
]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "builds/screenshots"
	var fog_sky: float = 0.0 if args.size() > 1 and args[1] == "nofog" else 1.0
	DirAccess.make_dir_recursive_absolute(out_dir)
	_probe.call_deferred(out_dir, fog_sky)


func _probe(out_dir: String, fog_sky: float) -> void:
	var root := get_tree().root
	var island := ISLAND.instantiate()
	root.add_child(island)

	var mat := ShaderMaterial.new()
	mat.shader = SKY_SHADER
	mat.set_shader_parameter("hdri_day", load(HDRI_DAY))
	mat.set_shader_parameter("hdri_dusk", load(HDRI_DUSK))
	mat.set_shader_parameter("hdri_night", load(HDRI_NIGHT))
	mat.set_shader_parameter("hdri_mix", 1.0)
	var sky := Sky.new()
	sky.sky_material = mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Туман как в world_scene.tscn; силу его влияния на небо варьируем.
	env.fog_enabled = true
	env.fog_density = 0.0025
	env.fog_light_color = Color(0.78, 0.85, 0.91)
	env.fog_sky_affect = fog_sky
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)

	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	var cycle := DayCycle.new()
	root.add_child(cycle)
	cycle.setup(sun, world_env)
	# Веса панорам задаём вручную (проверяем каждую отдельно) — DayCycle
	# выключаем, иначе его _process перезапишет миксы за время ожидания.
	cycle.set_process(false)

	var camera := Camera3D.new()
	camera.fov = 70.0
	root.add_child(camera)
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout  # IslandView строит рельеф

	for shot: Dictionary in SHOTS:
		Session.world_time = B.day_cycle_sec * float(shot["fraction"])
		var world_time := Session.world_time
		sun.basis = Basis.looking_at(
			-DayMath.sun_direction(world_time), Vector3.UP)
		sun.light_energy = DayMath.sun_energy(world_time)
		mat.set_shader_parameter("sun_direction", DayMath.sun_direction(world_time))
		mat.set_shader_parameter("day_mix", shot["mixes"].x)
		mat.set_shader_parameter("dusk_mix", shot["mixes"].y)
		mat.set_shader_parameter("night_mix", shot["mixes"].z)
		mat.set_shader_parameter("sky_yaw", DayMath.sky_yaw(world_time))
		# Экспозиция как у DayCycle (ночь светлее — «глаза адаптировались»).
		env.tonemap_exposure = lerpf(
			1.9, 1.0, DayMath.dayness(world_time))
		camera.global_position = EYE
		camera.look_at(LOOK_AT)
		await get_tree().create_timer(0.5).timeout
		var img := get_viewport().get_texture().get_image()
		var path := out_dir.path_join(String(shot["name"]) + ".png")
		img.save_png(path)
		print("%s: верх=%s середина=%s" % [
			path, _avg(img, 0.0, 0.25), _avg(img, 0.35, 0.2)])
	get_tree().quit(0)


func _avg(img: Image, from: float, h: float) -> Color:
	var w := img.get_width()
	var sum := Color()
	var n := 0
	for y in range(int(img.get_height() * from), int(img.get_height() * (from + h)), 3):
		for x in range(0, w, 3):
			sum += img.get_pixel(x, y)
			n += 1
	return sum / maxf(1.0, float(n))
