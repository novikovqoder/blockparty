extends SceneTree
## Перенос анимаций Mixamo (FBX, «Without Skin») на героя со скелетом Mixamo,
## у которого другая поза покоя (A-поза, своя модель) — или та же T-поза.
## Запуск (из корня проекта):
##   xvfb-run -a godot --path . -s res://tools/retarget_mixamo_bu.gd -- \
##     <сцена героя .glb/.tscn> <папка FBX> <выход .res>
## Результат — AnimationLibrary с анимациями под скелет героя. Пути дорожек считаются
## от узла root_node первого AnimationPlayer героя (если его нет — от корня сцены героя).
##
## Имена анимаций берутся из имён файлов и упрощаются:
##   «sword and shield idle (2).fbx» -> ss_idle_2, «draw sword 2.fbx» -> draw_sword_2.
## Файл «X Bot.fbx» (персонаж без анимации) пропускается.
##
## Метод: для каждой кости поправка между позами покоя; для рук и ног — с выравниванием
## по направлению кости (A-поза ↔ T-поза), для таза, позвоночника, шеи и головы — без него
## (иначе голова задирается вверх, корпус гнётся). Каждый кадр переводится через мировые
## повороты: G_target = G_source · G_source_rest⁻¹ · Swing · G_target_rest.
## Запекание идёт в игровом цикле: вне его Godot не обновляет позу скелета при seek().

const FPS: float = 30.0
const LOOPED: Array[String] = ["idle", "walk", "run", "strafe", "crouching", "crouch_idle", "block_idle"]
## Для костей с несколькими детьми — какой ребёнок задаёт направление кости.
const MAIN_CHILD: Dictionary[String, String] = {
	"Hips": "Spine", "Spine2": "Neck", "LeftHand": "LeftHandMiddle1", "RightHand": "RightHandMiddle1",
}
## Кости без выравнивания по направлению (мировой поворот переносится как есть).
const NO_SWING: Array[String] = ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "HeadTop_End"]

var _out_path: String = ""
var _fbx_dir: String = ""
var _queue: Array[String] = []
var _sk_t: Skeleton3D
var _pre_t: String = "mixamorig_"
var _pre_s: String = "mixamorig_"
var _skel_path: String = ""
var _lib: AnimationLibrary = AnimationLibrary.new()
var _offsets: Dictionary[int, Quaternion] = {}
var _map_t2s: Dictionary[int, int] = {}
var _offsets_ready: bool = false
var _hip_t: int = -1
var _hip_scale: float = 1.0
var _src: Node3D
var _src_name: String = ""
var _wait: int = 0
var _static_count: int = 0


## Имя анимации по имени файла Mixamo.
static func anim_name(file_name: String) -> String:
	var n: String = file_name.get_basename().to_lower().strip_edges()
	n = n.replace("sword and shield ", "ss_")
	n = n.replace(" (", "_").replace(")", "").replace(" ", "_").replace("-", "_")
	return n


## Префикс костей скелета: всё, что стоит перед «Hips».
static func bone_prefix(sk: Skeleton3D) -> String:
	for i: int in sk.get_bone_count():
		var n: String = sk.get_bone_name(i)
		if n.ends_with("Hips"):
			return n.substr(0, n.length() - 4)
	return ""


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("нужно: <сцена героя> <папка FBX> <выход .res>")
		quit(1)
		return
	var hero: Node3D = (load(args[0]) as PackedScene).instantiate() as Node3D
	_fbx_dir = args[1]
	_out_path = args[2]
	root.add_child(hero)
	var sks: Array[Node] = hero.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		push_error("у героя нет Skeleton3D")
		quit(1)
		return
	_sk_t = sks[0] as Skeleton3D
	_pre_t = bone_prefix(_sk_t)
	_hip_t = _sk_t.find_bone(_pre_t + "Hips")
	if _hip_t < 0:
		push_error("у героя нет кости *Hips — это не скелет Mixamo")
		quit(1)
		return
	var aps: Array[Node] = hero.find_children("*", "AnimationPlayer", true, false)
	var ap_root: Node = hero
	if not aps.is_empty():
		var hero_ap: AnimationPlayer = aps[0] as AnimationPlayer
		ap_root = hero_ap.get_node(hero_ap.root_node)
	_skel_path = String(ap_root.get_path_to(_sk_t))
	for f: String in DirAccess.get_files_at(_fbx_dir):
		if f.to_lower().ends_with(".fbx") and not f.to_lower().begins_with("x bot") and not f.to_lower().begins_with("x_bot"):
			_queue.append(f)
	_queue.sort()
	print("герой: префикс костей '", _pre_t, "', файлов анимаций: ", _queue.size())


func _process(_delta: float) -> bool:
	if _src == null:
		if _queue.is_empty():
			var err: Error = ResourceSaver.save(_lib, _out_path)
			print("saved ", _out_path, " err=", err, " animations=", _lib.get_animation_list().size(), " static=", _static_count)
			return true
		var f: String = _queue.pop_front()
		_src_name = anim_name(f)
		_src = (load(_fbx_dir.path_join(f)) as PackedScene).instantiate() as Node3D
		root.add_child(_src)
		var ap0: AnimationPlayer = _src.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		ap0.play(ap0.get_animation_list()[0])
		_wait = 2
		return false
	if _wait > 0:
		_wait -= 1
		return false
	var sk_s: Skeleton3D = _src.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var ap_s: AnimationPlayer = _src.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	if not _offsets_ready:
		_pre_s = bone_prefix(sk_s)
		_build_offsets(sk_s)
		var hip_s: int = sk_s.find_bone(_pre_s + "Hips")
		_hip_scale = _sk_t.get_bone_global_rest(_hip_t).origin.y / sk_s.get_bone_global_rest(hip_s).origin.y
		_offsets_ready = true
	var src_anim: Animation = ap_s.get_animation(ap_s.get_animation_list()[0])
	var anim: Animation = _bake(sk_s, ap_s, src_anim)
	for l: String in LOOPED:
		if _src_name.contains(l):
			anim.loop_mode = Animation.LOOP_LINEAR
	_lib.add_animation(StringName(_src_name), anim)
	_src.queue_free()
	_src = null
	return false


func _short(sk: Skeleton3D, b: int, pre: String) -> String:
	return sk.get_bone_name(b).trim_prefix(pre)


func _dir(sk: Skeleton3D, b: int, pre: String) -> Vector3:
	var name: String = _short(sk, b, pre)
	var kids: PackedInt32Array = sk.get_bone_children(b)
	var child: int = -1
	if MAIN_CHILD.has(name):
		child = sk.find_bone(pre + MAIN_CHILD[name])
	elif kids.size() > 0:
		child = kids[0]
	if child < 0:
		return Vector3.ZERO
	return (sk.get_bone_global_rest(child).origin - sk.get_bone_global_rest(b).origin).normalized()


func _build_offsets(sk_s: Skeleton3D) -> void:
	var swing: Dictionary[int, Quaternion] = {}
	for bt: int in _sk_t.get_bone_count():
		var short: String = _short(_sk_t, bt, _pre_t)
		var bs: int = sk_s.find_bone(_pre_s + short)
		if bs < 0:
			continue
		_map_t2s[bt] = bs
		var sw: Quaternion = Quaternion.IDENTITY
		if short in NO_SWING:
			sw = Quaternion.IDENTITY
		else:
			var dt: Vector3 = _dir(_sk_t, bt, _pre_t)
			var ds: Vector3 = _dir(sk_s, bs, _pre_s)
			if dt != Vector3.ZERO and ds != Vector3.ZERO:
				sw = Quaternion(dt, ds)
			else:
				var p: int = _sk_t.get_bone_parent(bt)
				if p >= 0 and swing.has(p):
					sw = swing[p]
		swing[bt] = sw
		var gs_rest: Quaternion = sk_s.get_bone_global_rest(bs).basis.get_rotation_quaternion()
		var gt_rest: Quaternion = _sk_t.get_bone_global_rest(bt).basis.get_rotation_quaternion()
		_offsets[bt] = gs_rest.inverse() * sw * gt_rest


func _bake(sk_s: Skeleton3D, ap_s: AnimationPlayer, src_anim: Animation) -> Animation:
	var anim: Animation = Animation.new()
	anim.length = src_anim.length
	var rot_tracks: Dictionary[int, int] = {}
	for bt: int in _map_t2s.keys():
		var tr: int = anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tr, NodePath(_skel_path + ":" + _sk_t.get_bone_name(bt)))
		rot_tracks[bt] = tr
	var pos_track: int = anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos_track, NodePath(_skel_path + ":" + _sk_t.get_bone_name(_hip_t)))
	var hip_s: int = _map_t2s[_hip_t]
	var hs_rest: Vector3 = sk_s.get_bone_rest(hip_s).origin
	var ht_rest: Vector3 = _sk_t.get_bone_rest(_hip_t).origin
	var frames: int = int(ceil(src_anim.length * FPS))
	var hand_s: int = sk_s.find_bone(_pre_s + "RightHand")
	var first_hand: Vector3 = Vector3.INF
	var moved: float = 0.0
	for i: int in frames + 1:
		var t: float = minf(float(i) / FPS, src_anim.length)
		ap_s.seek(t, true)
		ap_s.advance(0.0)
		var hp_now: Vector3 = sk_s.get_bone_global_pose(hand_s).origin
		if first_hand == Vector3.INF:
			first_hand = hp_now
		moved = maxf(moved, hp_now.distance_to(first_hand))
		var g_t: Dictionary[int, Quaternion] = {}
		for bt: int in _sk_t.get_bone_count():
			if not _map_t2s.has(bt):
				continue
			var bs: int = _map_t2s[bt]
			var gs: Quaternion = sk_s.get_bone_global_pose(bs).basis.get_rotation_quaternion()
			var gt: Quaternion = (gs * _offsets[bt]).normalized()
			g_t[bt] = gt
			var p: int = _sk_t.get_bone_parent(bt)
			var parent_g: Quaternion = g_t[p] if (p >= 0 and g_t.has(p)) else Quaternion.IDENTITY
			anim.rotation_track_insert_key(rot_tracks[bt], t, (parent_g.inverse() * gt).normalized())
		var hp: Vector3 = sk_s.get_bone_pose_position(hip_s)
		anim.position_track_insert_key(pos_track, t, ht_rest + (hp - hs_rest) * _hip_scale)
	if moved < 0.01:
		_static_count += 1
	print("baked ", _src_name, " ", snappedf(anim.length, 0.01), "s, hand moved ", snappedf(moved, 0.01), " m")
	return anim
