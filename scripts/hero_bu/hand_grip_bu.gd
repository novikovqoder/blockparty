class_name HandGripBU
extends SkeletonModifier3D
## Сжимает пальцы кисти в кулак поверх анимации (хват оружия).
## Ставится дочерним узлом Skeleton3D. strength: 0 — рука как в анимации, 1 — кулак.
## Ось сгиба каждого пальца вычисляется из положения костей, знак — чтобы
## кончик пальца шёл к ладони.

@export var side: String = "Right"
@export_range(0.0, 1.0) var strength: float = 1.0
## Углы сгиба фаланг, градусы: основная, средняя, ногтевая.
@export var finger_angles: Vector3 = Vector3(70, 85, 55)
@export var thumb_angles: Vector3 = Vector3(15, 35, 30)

const FINGERS: Array[String] = ["Index", "Middle", "Ring", "Pinky"]

var _bones: Array[int] = []
var _curls: Array[Quaternion] = []
var _ready_done: bool = false


func _setup() -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk == null:
		return
	var prefix: String = WeaponMountsBU.prefix_of(sk) + side + "Hand"
	var hand: int = sk.find_bone(prefix)
	if hand < 0:
		return
	var hand_g: Transform3D = sk.get_bone_global_rest(hand)
	var idx1: Vector3 = hand_g.affine_inverse() * sk.get_bone_global_rest(sk.find_bone(prefix + "Index1")).origin
	var pin1: Vector3 = hand_g.affine_inverse() * sk.get_bone_global_rest(sk.find_bone(prefix + "Pinky1")).origin
	var across: Vector3 = Vector3(idx1.x - pin1.x, 0.0, idx1.z - pin1.z).normalized()
	var fingers_dir: Vector3 = Vector3.UP
	var palm: Vector3 = across.cross(fingers_dir).normalized()
	if side == "Left":
		palm = -palm
	_bones.clear()
	_curls.clear()
	for f: String in FINGERS + ["Thumb"]:
		for seg: int in [1, 2, 3]:
			var b: int = sk.find_bone("%s%s%d" % [prefix, f, seg])
			if b < 0:
				continue
			var ang: float = (thumb_angles if f == "Thumb" else finger_angles)[seg - 1]
			var bg: Transform3D = hand_g.affine_inverse() * sk.get_bone_global_rest(b)
			var axis_hand: Vector3 = across if f != "Thumb" else fingers_dir
			var axis_local: Vector3 = (bg.basis.inverse() * axis_hand).normalized()
			# знак: кончик фаланги (ось Y кости) должен уйти в сторону ладони
			var tip_local: Vector3 = Vector3.UP * 0.03
			var q_pos: Quaternion = Quaternion(axis_local, deg_to_rad(ang))
			var moved: Vector3 = bg.basis * (q_pos * tip_local) - bg.basis * tip_local
			var sgn: float = 1.0 if moved.dot(palm) >= 0.0 else -1.0
			_bones.append(b)
			_curls.append(Quaternion(axis_local, deg_to_rad(ang) * sgn))
	_ready_done = true


func _process_modification_with_delta(_delta: float) -> void:
	if not _ready_done:
		_setup()
	var sk: Skeleton3D = get_skeleton()
	if sk == null or strength <= 0.0:
		return
	for i: int in _bones.size():
		var b: int = _bones[i]
		var base: Quaternion = sk.get_bone_rest(b).basis.get_rotation_quaternion()
		var target: Quaternion = base * _curls[i]
		var cur: Quaternion = sk.get_bone_pose_rotation(b)
		sk.set_bone_pose_rotation(b, cur.slerp(target, strength))
