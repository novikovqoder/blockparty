extends SceneTree
## Скриншоты проверки меча: на поясе → достаёт → стойка → удар → убирает → снова на поясе.
## Запуск (из корня проекта):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
##     --resolution 1280x960 --fixed-fps 30 -s res://tools/capture_sword_bu.gd -- \
##     <сцена героя> <библиотека анимаций .res> <папка для png>
## Библиотека подключается к AnimationPlayer героя под именем «sword»
## (если у героя нет AnimationPlayer — создаётся).

const SWORD: String = "res://assets/sword_bu/sword_bu.glb"

var _f: int = 0
var _out: String = ""
var _cam: Camera3D
var _ap: AnimationPlayer
var _eq: EquipControllerBU
var _sk: Skeleton3D
var _hero: Node3D
var _key: DirectionalLight3D
var _fill: DirectionalLight3D
## кадр (30 к/с) -> действие; «shot:имя» — сохранить снимок
var _plan: Dictionary[int, String] = {
	20: "shot:01_on_hip", 25: "draw", 27: "shot:02_draw_start", 40: "shot:03_draw_mid",
	75: "shot:04_armed_idle", 80: "attack", 95: "shot:05_attack", 140: "sheath",
	160: "shot:06_sheath_mid", 200: "shot:07_back_on_hip", 205: "quit",
}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out = args[2]
	DirAccess.make_dir_recursive_absolute(_out)
	var r: Node3D = Node3D.new()
	root.add_child(r)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.31, 0.33)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.45
	env.environment = e
	r.add_child(env)
	_key = DirectionalLight3D.new()
	_key.light_energy = 1.4
	r.add_child(_key)
	_fill = DirectionalLight3D.new()
	_fill.light_energy = 0.5
	r.add_child(_fill)
	_hero = (load(args[0]) as PackedScene).instantiate() as Node3D
	r.add_child(_hero)
	_sk = _hero.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var aps: Array[Node] = _hero.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		_ap = AnimationPlayer.new()
		_hero.add_child(_ap)
		_ap.root_node = _ap.get_path_to(_hero)
	else:
		_ap = aps[0] as AnimationPlayer
	if not _ap.has_animation_library(&"sword"):
		_ap.add_animation_library(&"sword", load(args[1]) as AnimationLibrary)
	_eq = EquipControllerBU.new()
	_eq.sword_scene = load(SWORD) as PackedScene
	_hero.add_child(_eq)
	_eq.skeleton_path = _eq.get_path_to(_sk)
	_eq.animation_player_path = _eq.get_path_to(_ap)
	_cam = Camera3D.new()
	_cam.fov = 36
	r.add_child(_cam)


func _process(_d: float) -> bool:
	_f += 1
	var pre: String = WeaponMountsBU.prefix_of(_sk)
	var hips: Vector3 = _sk.global_transform * _sk.get_bone_global_pose(_sk.find_bone(pre + "Hips")).origin
	var target: Vector3 = Vector3(hips.x, hips.y * 1.0, hips.z)
	var cp: Vector3 = target + Vector3(1.6, 0.45, 3.2)
	_cam.look_at_from_position(cp, target)
	_key.look_at_from_position(cp + Vector3(-2.0, 2.5, 0.0), target)
	_fill.look_at_from_position(cp + Vector3(2.5, 0.5, -1.0), target)
	if not _plan.has(_f):
		return false
	var a: String = _plan[_f]
	if a == "quit":
		return true
	if a == "draw":
		_eq.select(&"sword")
	elif a == "sheath":
		_eq.select(&"hands")
	elif a == "attack":
		if _ap.has_animation(&"sword/ss_slash"):
			_ap.play(&"sword/ss_slash", 0.1)
	elif a.begins_with("shot:"):
		var where: String = String(_eq.sword.get_parent().name) if _eq.sword else "-"
		print(a.substr(5), ": меч в ", where, ", анимация ", _ap.current_animation)
		root.get_texture().get_image().save_png(_out.path_join(a.substr(5) + ".png"))
	return false
