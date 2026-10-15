# Диагностика Д1 (возврат П5.8, попытка 2): руки выкручены. Гипотеза
# владельца — rest-поза рига UBC не совпадает с позой, под которую сделаны
# клипы UAL (углы плеч, ролл предплечья/кисти), а запечка копирует локальные
# повороты как есть — они ложатся «перекрученными». Пробник проверяет ФАКТАМИ:
#  1) rest-позы ригов UAL (родной манекен из исходного пака) и UBC: для общих
#     костей — угол между направлениями (конус) и ролл вокруг оси кости;
#  2) один и тот же клип в одних и тех же кадрах на родном скелете UAL
#     (локали из треков glb) и на UBC (запечённый anims_ubc.res): анатомические
#     углы руки по кадрам — подъём плеча от «вниз», угол локтя (180 = прямая),
#     угол кисти. Если запечка верна, цифры UBC ≈ цифры UAL.
# Запуск: godot --headless --path . -s res://tools/probe_arm_compare.gd
# [--clip=Idle] [frames=N]. Лог — в builds/probe_arm_compare.log (и stdout).
extends SceneTree

const UAL_GLB: PackedStringArray = [
	"res://builds/ual_probe/UAL1.glb",
	"res://builds/ual_probe/UAL2.glb",
]
const UBC_SCENE: String = "res://assets/third_party/quaternius.com/" \
	+ "universal_base_characters/baked/ubc_male.res"
const UBC_ANIMS: String = "res://assets/third_party/quaternius.com/" \
	+ "universal_animation_library/anims_ubc.res"

## Кости руки/ноги для сравнения rest-поз (регистронезависимо).
const CHAIN_BONES: PackedStringArray = [
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
	"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
	"thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r",
	"pelvis", "spine_01", "spine_02", "neck", "head",
]
## Клипы с руками для сравнения углов (имена в anims_ubc.res).
const ARM_CLIPS: PackedStringArray = [
	"Idle", "Idle_Talking", "Idle_Rail_Call", "Idle_No", "Dance",
	"Sitting_Idle", "Interact", "ClimbUp_1m", "Jump_Land", "Wave_Hand",
]


class Rig:
	var name: String
	var bones: PackedStringArray = []
	var parent: Array[int] = []
	var rest_local: Array[Quaternion] = []
	var rest_global: Array[Transform3D] = []
	var lower_to_bone: Dictionary = {}


	func _init(rig_name: String, sk: Skeleton3D) -> void:
		name = rig_name
		for i: int in sk.get_bone_count():
			bones.append(sk.get_bone_name(i))
			parent.append(sk.get_bone_parent(i))
			rest_local.append(sk.get_bone_rest(i).basis.get_rotation_quaternion())
			rest_global.append(sk.get_bone_global_rest(i))
			lower_to_bone[sk.get_bone_name(i).to_lower()] = i


	func idx(bone: String) -> int:
		return lower_to_bone.get(bone.to_lower(), -1)


	## Глобальные ориентации всех костей из локалей pose (нет записи — rest).
	func globals_of(locals: Array[Quaternion]) -> Array[Transform3D]:
		var out: Array[Transform3D] = []
		out.resize(bones.size())
		for i: int in bones.size():
			var p := Transform3D.IDENTITY
			if parent[i] >= 0:
				p = out[parent[i]]
			var tr := Transform3D(Basis(locals[i]),
				rest_global[i].origin)
			out[i] = p * tr
		return out


	## Локали полного кадра клипа в момент t (треки по именам костей UAL).
	func locals_at(anim: Animation, t: float, path_prefix_len: int) -> Array[Quaternion]:
		var locals := rest_local.duplicate()
		for i: int in anim.get_track_count():
			if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D:
				continue
			var bone := _bone_of(anim.track_get_path(i))
			var bi := idx(bone)
			if bi < 0:
				continue
			locals[bi] = anim.rotation_track_interpolate(i, t)
		return locals


	func _bone_of(path: NodePath) -> String:
		return String(path.get_subname(path.get_subname_count() - 1))


## Угол (°) между направлениями костей a и b (конусное отклонение).
func _dir_angle(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(acos(clampf(a.dot(b) / (a.length() * b.length()),
		-1.0, 1.0)))


## Ролл (°) поворота q вокруг оси axis (разложение swing-twist).
func _twist_of(q: Quaternion, axis: Vector3) -> float:
	var p := q * Vector3(0.0, 1.0, 0.0)
	var d := axis.dot(p)
	var cross := axis.cross(p)
	if cross.length_squared() < 1e-12:
		return rad_to_deg(2.0 * acos(clampf(absf(d), 0.0, 1.0))) * signf(d)
	var twist := Quaternion(cross.normalized(),
		atan2(cross.length(), d))
	return rad_to_deg(2.0 * atan2(twist.y, twist.w)) if twist.w != 0.0 else 0.0


func _find_skeleton(node: Node) -> Skeleton3D:
	var found := node.find_children("*", "Skeleton3D", true, false)
	assert(found.size() > 0, "нет Skeleton3D в %s" % node.name)
	return found[0] as Skeleton3D


func _find_player(node: Node) -> AnimationPlayer:
	var found := node.find_children("*", "AnimationPlayer", true, false)
	assert(found.size() > 0, "нет AnimationPlayer в %s" % node.name)
	return found[0] as AnimationPlayer


var _ual: Rig
var _ubc: Rig
var _ual_clips: Dictionary = {}  # имя -> Animation (нативные, из glb)
var _ubc_lib: AnimationLibrary


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var only_clip := ""
	for a: String in args:
		if a.begins_with("--clip="):
			only_clip = a.substr(7)
	_load_rigs()
	_list_ual_animations()
	_compare_rest()
	if only_clip != "":
		_compare_clip(only_clip)
	else:
		for clip: String in ARM_CLIPS:
			_compare_clip(clip)
	quit()


func _load_rigs() -> void:
	for path: String in UAL_GLB:
		var scene := load(path) as PackedScene
		var root := scene.instantiate()
		if _ual == null:
			_ual = Rig.new("UAL", _find_skeleton(root))
		var lib := _find_player(root).get_animation_library("")
		for n in lib.get_animation_list():
			_ual_clips[String(n)] = lib.get_animation(String(n))
		root.free()
	var ubc_scene := load(UBC_SCENE) as PackedScene
	var ubc_root := ubc_scene.instantiate()
	_ubc = Rig.new("UBC", _find_skeleton(ubc_root))
	ubc_root.free()
	_ubc_lib = load(UBC_ANIMS) as AnimationLibrary
	print("риг UAL: %d костей ; риг UBC: %d костей ; клипов UAL: %d"
		% [_ual.bones.size(), _ubc.bones.size(), _ual_clips.size()])


func _list_ual_animations() -> void:
	var names: PackedStringArray = []
	for n: String in _ual_clips:
		names.append(n)
	names.sort()
	print("\n== Клипы UAL Standard (все) ==")
	print("  ", ", ".join(names))


## 1) Сравнение rest-поз: конусный угол направления + ролл вокруг оси кости.
func _compare_rest() -> void:
	print("\n== REST-ПОЗЫ UAL против UBC (общие кости цепей) ==")
	print("%-12s %8s %8s   %s" % ["кость", "конус°", "ролл°", "dir UAL / dir UBC"])
	for bone: String in CHAIN_BONES:
		var ui := _ual.idx(bone)
		var bi := _ubc.idx(bone)
		if ui < 0 or bi < 0:
			print("%-12s нет в %s%s" % [bone,
				"UAL " if ui < 0 else "", "UBC" if bi < 0 else ""])
			continue
		var du := _ual.rest_global[ui].basis.y.normalized()
		var db := _ubc.rest_global[bi].basis.y.normalized()
		var cone := _dir_angle(du, db)
		# Полная разница ориентаций, ролл — вокруг оси кости UBC.
		var diff := (_ubc.rest_global[bi].basis.get_rotation_quaternion()
			* _ual.rest_global[ui].basis.get_rotation_quaternion().inverse())
		var roll := _twist_of(diff, db)
		print("%-12s %8.1f %8.1f   (%+.2f,%+.2f,%+.2f) / (%+.2f,%+.2f,%+.2f)"
			% [bone, cone, roll, du.x, du.y, du.z, db.x, db.y, db.z])


## 2) Углы руки по кадрам: родной UAL против запечённого UBC.
## Анатомия: подъём плеча = угол между dir(upperarm) и «вниз» (0,-1,0);
## локоть = угол между -dir(upperarm) и dir(lowerarm) (180 = прямая рука);
## кисть = угол между -dir(lowerarm) и dir(hand).
func _arm_angles(globals: Array[Transform3D], rig: Rig, side: String) -> Dictionary:
	var ua := rig.idx("upperarm_" + side)
	var la := rig.idx("lowerarm_" + side)
	var ha := rig.idx("hand_" + side)
	var du := globals[ua].basis.y.normalized()
	var dl := globals[la].basis.y.normalized()
	var dh := globals[ha].basis.y.normalized()
	return {
		"elev": _dir_angle(du, Vector3(0.0, -1.0, 0.0)),
		"elbow": _dir_angle(-du, dl),
		"wrist": _dir_angle(-dl, dh),
	}


## Максимальный угол (°) полной ориентации костей руки между мировыми
## позами UAL и UBC в один кадр (0 = ориентации совпадают, ролл тоже).
func _arm_orient_diff(gu: Array[Transform3D], gb: Array[Transform3D],
		side: String) -> float:
	var worst := 0.0
	for bone: String in ["upperarm_" + side, "lowerarm_" + side,
			"hand_" + side]:
		var ui := _ual.idx(bone)
		var bi := _ubc.idx(bone)
		var qu := gu[ui].basis.get_rotation_quaternion()
		var qb := gb[bi].basis.get_rotation_quaternion()
		worst = maxf(worst, rad_to_deg(qu.angle_to(qb)))
	return worst


func _compare_clip(clip_name: String) -> void:
	var native: Animation = null
	for n: String in _ual_clips:
		if n.to_lower() == clip_name.to_lower():
			native = _ual_clips[n]
			break
	if not _ubc_lib.has_animation(clip_name):
		print("\n== %s: нет в anims_ubc.res ==" % clip_name)
		return
	var baked := _ubc_lib.get_animation(clip_name) as Animation
	if native == null:
		# Процедурный клип: сравнивать не с чем — печатаем углы UBC как есть.
		print("\n== %s (процедурный, только UBC) ==" % clip_name)
		_print_frames(clip_name, null, baked)
		return
	print("\n== %s: UAL родной против UBC запечённый ==" % clip_name)
	_print_frames(clip_name, native, baked)


func _print_frames(clip_name: String, native: Animation, baked: Animation) -> void:
	var frames := 5
	var length := baked.length
	if native != null:
		length = minf(length, native.length)
	print("длина UBC %.2f с%s ; кадры 0…%.2f" % [baked.length,
		"" if native == null else " / UAL %.2f с" % native.length,
		length])
	print("%-6s %-24s %-24s %-24s %s" % ["t",
		"UAL R elev/elb/wrs", "UBC R elev/elb/wrs",
		"UAL L elev/elb/wrs", "UBC L elev/elb/wrs  (°)"])
	for k: int in frames:
		var t := length * k / float(frames - 1)
		var row := "%-6.2f" % t
		var gu: Array[Transform3D] = []
		if native != null:
			gu = _ual.globals_of(_ual.locals_at(native, t, 0))
			var ar := _arm_angles(gu, _ual, "r")
			row += "  %6.1f %6.1f %6.1f" % [ar["elev"], ar["elbow"], ar["wrist"]]
		else:
			row += "  %6s %6s %6s" % ["-", "-", "-"]
		var gb := _ubc.globals_of(_ubc.locals_at(baked, t, 0))
		var br := _arm_angles(gb, _ubc, "r")
		row += "   %6.1f %6.1f %6.1f" % [br["elev"], br["elbow"], br["wrist"]]
		if native != null:
			var al := _arm_angles(gu, _ual, "l")
			row += "   %6.1f %6.1f %6.1f" % [al["elev"], al["elbow"], al["wrist"]]
			var bl := _arm_angles(gb, _ubc, "l")
			row += "   %6.1f %6.1f %6.1f" % [bl["elev"], bl["elbow"], bl["wrist"]]
			row += "   Δориент R/L %.1f/%.1f" % [
				_arm_orient_diff(gu, gb, "r"), _arm_orient_diff(gu, gb, "l")]
		print(row)
