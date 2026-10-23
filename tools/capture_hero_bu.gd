extends SceneTree
## Скриншоты комплекта: экран запуска, «Steam не запущен», экран загрузки, герой с разных сторон.
## Запуск: xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 \
##   -s res://tools/capture_hero_bu.gd -- <папка для png>

var _out: String
var _f: int = 0
var _step: int = 0
var _node: Node = null
var _cam: Camera3D = null
var _hero: Node3D = null
const HERO_VIEWS: Array = [["hero_front", Vector3(0, 1.0, 3.2), Vector3(0, 0.95, 0)],
	["hero_34", Vector3(2.2, 1.3, 2.3), Vector3(0, 0.95, 0)],
	["hero_back", Vector3(-0.6, 1.4, -3.0), Vector3(0, 1.0, 0)],
	["hero_face", Vector3(0.25, 1.7, 0.75), Vector3(0, 1.64, 0)]]


func _initialize() -> void:
	_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out)
	TranslationServer.set_locale("ru")


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(_out + "/" + name + ".png")


func _process(_d: float) -> bool:
	_f += 1
	match _step:
		0:
			_node = (load("res://scenes/boot_bu/boot_screen_bu.tscn") as PackedScene).instantiate()
			root.add_child(_node)
			_step = 1; _f = 0
		1:
			if _f == 70:
				_shot("01_boot_init")
				(_node as BootScreenBU).show_steam_missing()
			elif _f == 80:
				_shot("02_boot_steam_missing")
				_node.queue_free()
				var holder: Node = Node.new(); root.add_child(holder); current_scene = holder
				var ls: LoadingScreenBU = LoadingScreenBU.open(self, "res://tests/fixtures/slow_world_bu.tscn")
				ls.min_time = 999.0
				_node = ls
				_step = 2; _f = 0
		2:
			if _f == 90:
				_shot("03_loading")
				_node.queue_free()
				current_scene.queue_free()
				_build_hero()
				_step = 3; _f = 0
		3:
			var i: int = _f / 20
			if i >= HERO_VIEWS.size():
				return true
			var v: Array = HERO_VIEWS[i]
			if _f % 20 == 1:
				_cam.fov = 18.0 if String(v[0]) == "hero_face" else 32.0
				_cam.look_at_from_position(v[1], v[2])
			elif _f % 20 == 15:
				_shot("1%d_%s" % [i, v[0]])
	return false


func _build_hero() -> void:
	var r: Node3D = Node3D.new(); root.add_child(r)
	var env: WorldEnvironment = WorldEnvironment.new(); var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.09, 0.06, 0.065)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(1, 0.92, 0.9); e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e; r.add_child(env)
	var key: DirectionalLight3D = DirectionalLight3D.new(); key.light_energy = 1.5; r.add_child(key)
	key.look_at_from_position(Vector3(1.5, 3, 2.5), Vector3(0, 1, 0))
	var rim: DirectionalLight3D = DirectionalLight3D.new(); rim.light_energy = 1.0; rim.light_color = Color(1, 0.55, 0.5); r.add_child(rim)
	rim.look_at_from_position(Vector3(-2, 2.5, -2.5), Vector3(0, 1, 0))
	_hero = (load("res://assets/hero_bu/hero_bu.tscn") as PackedScene).instantiate() as Node3D
	r.add_child(_hero)
	_cam = Camera3D.new(); r.add_child(_cam)
