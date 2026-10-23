class_name WeaponMountsBU
extends RefCounted
## Точки крепления оружия на скелете Mixamo. Godot при импорте меняет «:» на «_»,
## поэтому кости называются «mixamorig_RightHand». Префикс (mixamorig_, mixamorig1_,
## без префикса) определяется по кости *Hips. Всё считается из положения костей,
## поэтому подходит любой персонаж со скелетом Mixamo.
## Система координат меча: начало — центр рукояти, клинок вдоль +Y, кромки вдоль ±X.


## Префикс имён костей: всё, что стоит перед «Hips» («mixamorig_», «» и т. п.).
static func prefix_of(sk: Skeleton3D) -> String:
	for i: int in sk.get_bone_count():
		var n: String = sk.get_bone_name(i)
		if n.ends_with("Hips"):
			return n.substr(0, n.length() - 4)
	return "mixamorig_"


## Хват в ладони: рукоять лежит по диагонали ладони (от пятки ладони к основанию
## указательного пальца), клинок выходит со стороны большого пальца.
## diagonal_deg — наклон рукояти от поперечной линии ладони к пальцам.
## Возвращает трансформ относительно кости кисти (для BoneAttachment3D).
static func grip_in_hand(sk: Skeleton3D, side: String = "Right", diagonal_deg: float = 35.0) -> Transform3D:
	var prefix: String = prefix_of(sk) + side + "Hand"
	var hand_g: Transform3D = sk.get_bone_global_rest(sk.find_bone(prefix))
	var idx1: Vector3 = hand_g.affine_inverse() * sk.get_bone_global_rest(sk.find_bone(prefix + "Index1")).origin
	var pin1: Vector3 = hand_g.affine_inverse() * sk.get_bone_global_rest(sk.find_bone(prefix + "Pinky1")).origin
	var mid1: Vector3 = hand_g.affine_inverse() * sk.get_bone_global_rest(sk.find_bone(prefix + "Middle1")).origin
	var fingers: Vector3 = Vector3.UP
	var across: Vector3 = Vector3(idx1.x - pin1.x, 0.0, idx1.z - pin1.z).normalized()
	var palm: Vector3 = across.cross(fingers).normalized()
	if side == "Left":
		palm = -palm
	var a: float = deg_to_rad(diagonal_deg)
	var y_axis: Vector3 = (across * cos(a) + fingers * sin(a)).normalized()
	var x_axis: Vector3 = (fingers - y_axis * fingers.dot(y_axis)).normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	var origin: Vector3 = Vector3(0.0, mid1.y * 0.72, 0.0) + palm * 0.032
	return Transform3D(Basis(x_axis, y_axis, z_axis), origin)


## Положение меча на поясе, вычисленное из анимации «достать меч»: там, где правая
## рука берёт рукоять в момент contact_time. Ладонь ложится ровно на рукоять.
## Возвращает трансформ относительно кости таза (Hips).
static func sheath_from_draw(sk: Skeleton3D, anim: Animation, contact_time: float, side: String = "Right") -> Transform3D:
	var hand: int = sk.find_bone(prefix_of(sk) + side + "Hand")
	var hips: int = sk.find_bone(prefix_of(sk) + "Hips")
	var hand_g: Transform3D = _global_at(sk, anim, contact_time, hand)
	var hips_g: Transform3D = _global_at(sk, anim, contact_time, hips)
	return hips_g.affine_inverse() * (hand_g * grip_in_hand(sk, side))


## Глобальная (в системе скелета) поза кости в момент t анимации без её проигрывания.
static func _global_at(sk: Skeleton3D, anim: Animation, t: float, bone: int) -> Transform3D:
	var chain: Array[int] = []
	var b: int = bone
	while b >= 0:
		chain.push_front(b)
		b = sk.get_bone_parent(b)
	var g: Transform3D = Transform3D.IDENTITY
	for c: int in chain:
		var rest: Transform3D = sk.get_bone_rest(c)
		var rot: Quaternion = rest.basis.get_rotation_quaternion()
		var pos: Vector3 = rest.origin
		var name: String = sk.get_bone_name(c)
		for tr: int in anim.get_track_count():
			var path: String = String(anim.track_get_path(tr))
			if not path.ends_with(":" + name):
				continue
			if anim.track_get_type(tr) == Animation.TYPE_ROTATION_3D:
				rot = anim.rotation_track_interpolate(tr, t)
			elif anim.track_get_type(tr) == Animation.TYPE_POSITION_3D:
				pos = anim.position_track_interpolate(tr, t)
		g = g * Transform3D(Basis(rot), pos)
	return g


## Меч в ножнах на левом бедре: рукоять у пояса спереди, клинок вниз и назад.
## Возвращает трансформ относительно кости таза (Hips).
static func sheath_on_hip(sk: Skeleton3D, back_angle_deg: float = 28.0) -> Transform3D:
	var hips_g: Transform3D = sk.get_bone_global_rest(sk.find_bone(prefix_of(sk) + "Hips"))
	var leg_g: Transform3D = sk.get_bone_global_rest(sk.find_bone(prefix_of(sk) + "LeftUpLeg"))
	# «влево» и «вперёд» персонажа в позе покоя
	var left: Vector3 = (leg_g.origin - hips_g.origin)
	left.y = 0.0
	left = left.normalized()
	var forward: Vector3 = left.cross(Vector3.UP).normalized()
	var a: float = deg_to_rad(back_angle_deg)
	var blade: Vector3 = (Vector3.DOWN * cos(a) - forward * sin(a) + left * 0.12).normalized()
	var z_axis: Vector3 = left
	var x_axis: Vector3 = blade.cross(z_axis).normalized()
	z_axis = x_axis.cross(blade).normalized()
	var grip: Vector3 = hips_g.origin + left * 0.2 + forward * 0.13 + Vector3.UP * 0.07
	var global_t: Transform3D = Transform3D(Basis(x_axis, blade, z_axis), grip)
	return hips_g.affine_inverse() * global_t
