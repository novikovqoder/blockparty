extends GutTest
## Тесты меча героя: префикс костей, хват в ладони, место на поясе, смена слотов
## колёсиком (без анимаций — плавный перенос), имена анимаций Mixamo, модель меча.
## Скелет собирается прямо в тесте (упрощённый Mixamo в T-позе), поэтому тесты
## не зависят от модели героя.

const SWORD: String = "res://assets/sword_bu/sword_bu.glb"
const RETARGET: String = "res://tools/retarget_mixamo_bu.gd"


func _make_skeleton(prefix: String) -> Skeleton3D:
	var sk: Skeleton3D = Skeleton3D.new()
	# имя, родитель, позиция в мире (T-поза, герой смотрит на +Z, левая сторона — +X)
	var spec: Array = [
		["Hips", "", Vector3(0, 1.0, 0)],
		["Spine", "Hips", Vector3(0, 1.1, 0)],
		["LeftUpLeg", "Hips", Vector3(0.1, 0.92, 0)],
		["RightUpLeg", "Hips", Vector3(-0.1, 0.92, 0)],
		["RightShoulder", "Spine", Vector3(-0.06, 1.42, 0)],
		["RightArm", "RightShoulder", Vector3(-0.18, 1.42, 0)],
		["RightForeArm", "RightArm", Vector3(-0.45, 1.42, 0)],
		["RightHand", "RightForeArm", Vector3(-0.70, 1.42, 0)],
		["RightHandIndex1", "RightHand", Vector3(-0.79, 1.42, 0.03)],
		["RightHandMiddle1", "RightHand", Vector3(-0.795, 1.42, 0.0)],
		["RightHandPinky1", "RightHand", Vector3(-0.78, 1.42, -0.035)],
	]
	var world: Dictionary[String, Transform3D] = {}
	for e: Array in spec:
		var n: String = e[0]
		var parent: String = e[1]
		var pos: Vector3 = e[2]
		# у кисти и пальцев ось Y кости смотрит вдоль руки (к пальцам), как в Mixamo
		var basis: Basis = Basis(Vector3.BACK, deg_to_rad(90.0)) if n.begins_with("RightHand") else Basis.IDENTITY
		var g: Transform3D = Transform3D(basis, pos)
		world[n] = g
		var idx: int = sk.add_bone(prefix + n)
		if parent != "":
			sk.set_bone_parent(idx, sk.find_bone(prefix + parent))
			sk.set_bone_rest(idx, world[parent].affine_inverse() * g)
		else:
			sk.set_bone_rest(idx, g)
	sk.reset_bone_poses()
	return sk


func test_prefix_detection() -> void:
	var a: Skeleton3D = _make_skeleton("mixamorig_")
	var b: Skeleton3D = _make_skeleton("")
	assert_eq(WeaponMountsBU.prefix_of(a), "mixamorig_", "префикс mixamorig_")
	assert_eq(WeaponMountsBU.prefix_of(b), "", "скелет без префикса")
	a.free()
	b.free()


func test_grip_in_hand_is_orthonormal_and_in_palm() -> void:
	var sk: Skeleton3D = _make_skeleton("mixamorig_")
	var g: Transform3D = WeaponMountsBU.grip_in_hand(sk)
	assert_almost_eq(g.basis.x.length(), 1.0, 0.001, "ось X единичная")
	assert_almost_eq(g.basis.y.length(), 1.0, 0.001, "ось Y единичная")
	assert_almost_eq(g.basis.x.dot(g.basis.y), 0.0, 0.001, "оси X и Y перпендикулярны")
	assert_lt(g.origin.length(), 0.12, "рукоять в ладони, не дальше 12 см от кости кисти")
	# клинок выходит со стороны указательного (большого) пальца — по диагонали ладони
	var hand: int = sk.find_bone("mixamorig_RightHand")
	var hand_g: Transform3D = sk.get_bone_global_rest(hand)
	var idx1: Vector3 = hand_g.affine_inverse() * sk.get_bone_global_rest(sk.find_bone("mixamorig_RightHandIndex1")).origin
	var pin1: Vector3 = hand_g.affine_inverse() * sk.get_bone_global_rest(sk.find_bone("mixamorig_RightHandPinky1")).origin
	assert_gt(g.basis.y.dot(idx1 - pin1), 0.0, "клинок смотрит в сторону указательного пальца")
	sk.free()


func test_sheath_on_left_hip() -> void:
	var sk: Skeleton3D = _make_skeleton("mixamorig_")
	var hips_g: Transform3D = sk.get_bone_global_rest(sk.find_bone("mixamorig_Hips"))
	var xf: Transform3D = hips_g * WeaponMountsBU.sheath_on_hip(sk)
	assert_gt(xf.origin.x, hips_g.origin.x + 0.1, "рукоять на левом бедре (+X)")
	assert_lt(xf.basis.y.y, -0.5, "клинок смотрит вниз")
	sk.free()


func test_equip_cycle_without_animations() -> void:
	var hero: Node3D = Node3D.new()
	var sk: Skeleton3D = _make_skeleton("mixamorig_")
	hero.add_child(sk)
	var eq: EquipControllerBU = EquipControllerBU.new()
	eq.sword_scene = load(SWORD) as PackedScene
	eq.move_time = 0.1
	hero.add_child(eq)
	eq.skeleton_path = eq.get_path_to(sk)
	add_child_autofree(hero)
	await wait_physics_frames(2)
	assert_not_null(eq.sword, "меч создан")
	assert_eq(String(eq.sword.get_parent().name), "HipMount", "меч висит на поясе")
	watch_signals(eq)
	eq.cycle(1)
	assert_eq(eq.slot, &"sword", "колёсико вверх — слот меча")
	assert_signal_emitted(eq, "slot_changed")
	await wait_seconds(0.4)
	assert_eq(String(eq.sword.get_parent().name), "RightHandMount", "меч в правой руке")
	assert_false(eq.busy, "переход закончен")
	assert_signal_emitted(eq, "equip_finished")
	eq.cycle(1)
	await wait_seconds(0.4)
	assert_eq(String(eq.sword.get_parent().name), "HipMount", "меч вернулся на пояс")


func test_mixamo_file_names_to_animation_names() -> void:
	var r: GDScript = load(RETARGET) as GDScript
	assert_eq(r.call("anim_name", "sword and shield idle (2).fbx"), "ss_idle_2")
	assert_eq(r.call("anim_name", "sword and shield block idle.fbx"), "ss_block_idle")
	assert_eq(r.call("anim_name", "draw sword 2.fbx"), "draw_sword_2")
	assert_eq(r.call("anim_name", "sheath sword 1.fbx"), "sheath_sword_1")


func test_sword_model() -> void:
	var packed: PackedScene = load(SWORD) as PackedScene
	assert_not_null(packed, "модель меча загружается")
	var sw: Node3D = packed.instantiate() as Node3D
	add_child_autofree(sw)
	var meshes: Array[Node] = sw.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 0, "у меча есть сетка")
	var mi: MeshInstance3D = meshes[0] as MeshInstance3D
	var box: AABB = mi.get_aabb()
	assert_almost_eq(box.size.y, 1.1, 0.08, "длина меча около 1,1 м вдоль +Y")
	assert_lt(absf(box.position.y + box.size.y * 0.5) , 0.6, "начало координат — у рукояти, клинок вдоль +Y")
