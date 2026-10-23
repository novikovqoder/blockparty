extends GutTest
## Герой Born Unblessed: модель, скелет Mixamo, веки, моргание, экраны запуска и загрузки.

const HERO: String = "res://assets/hero_bu/hero_bu.tscn"


func _hero() -> Node3D:
	var h: Node3D = (load(HERO) as PackedScene).instantiate() as Node3D
	add_child_autofree(h)
	return h


func _skel(h: Node) -> Skeleton3D:
	return h.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D


func test_hero_loads_with_all_parts() -> void:
	var h: Node3D = _hero()
	var names: PackedStringArray = []
	for m: Node in h.find_children("*", "MeshInstance3D", true, false):
		names.append(String(m.name))
	for part: String in ["Body", "Eyes", "Brows", "Lashes", "Hair", "Hood", "Mantle", "Tunic", "Pants", "Boots", "Gloves"]:
		assert_has(names, part, "есть часть %s" % part)


func test_mixamo_skeleton() -> void:
	var sk: Skeleton3D = _skel(_hero())
	for b: String in ["mixamorig_Hips", "mixamorig_Spine2", "mixamorig_Head", "mixamorig_RightHand", "mixamorig_LeftHand"]:
		assert_gt(sk.find_bone(b), -1, "кость %s" % b)
	assert_gt(sk.find_bone("mixamorig_LeftEyelidUpper"), -1)
	assert_gt(sk.find_bone("mixamorig_RightEyelidUpper"), -1)


func test_height_about_1_8m() -> void:
	var h: Node3D = _hero()
	var box: AABB = AABB()
	var first: bool = true
	for m: Node in h.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	assert_between(box.size.y, 1.7, 1.95, "рост ~1.8 м")
	assert_almost_eq(box.position.y, 0.0, 0.05, "ступни на земле")


func test_blink_closes_lids() -> void:
	var h: Node3D = _hero()
	var sk: Skeleton3D = _skel(h)
	var bl: BlinkLidsBU = sk.find_children("*", "", false, false).filter(func(n: Node) -> bool: return n is BlinkLidsBU)[0] as BlinkLidsBU
	assert_not_null(bl)
	bl.auto_blink = false
	bl.squint = 0.0
	bl.blink_time = 6.0                         # медленно — чтобы поймать середину моргания
	var b: int = sk.find_bone("mixamorig_LeftEyelidUpper")
	var rest: Quaternion = sk.get_bone_rest(b).basis.get_rotation_quaternion()
	bl.blink()
	await wait_seconds(2.5)
	await bl.modification_processed           # поза с поправкой модификатора
	var now: Quaternion = sk.get_bone_pose_rotation(b)
	assert_gt(rad_to_deg(rest.angle_to(now)), 15.0, "веко повернулось при моргании")
	await wait_frames(1)                        # выйти из обработчика сигнала до удаления героя


func test_boot_screen_steam_missing() -> void:
	var bs: BootScreenBU = (load("res://scenes/boot_bu/boot_screen_bu.tscn") as PackedScene).instantiate() as BootScreenBU
	add_child_autofree(bs)
	await wait_frames(2)
	assert_false(bs.is_steam_missing_shown())
	watch_signals(bs)
	bs.show_steam_missing()
	assert_true(bs.is_steam_missing_shown())
	var btns: Array = bs.find_children("*", "Button", true, false)
	assert_eq(btns.size(), 2, "две кнопки")
	(btns[0] as Button).pressed.emit()
	assert_signal_emitted(bs, "offline_requested")
	(btns[1] as Button).pressed.emit()
	assert_signal_emitted(bs, "quit_requested")


func test_loading_screen_swaps_scene_and_waits_world_ready() -> void:
	var holder: Node = Node.new()
	get_tree().root.add_child(holder)
	get_tree().current_scene = holder
	var ls: LoadingScreenBU = LoadingScreenBU.open(get_tree(), "res://tests/fixtures/slow_world_bu.tscn")
	ls.min_time = 0.3
	ls.fade_out_time = 0.2
	var got: Array[Node] = []
	ls.finished.connect(func(n: Node) -> void: got.append(n))
	await wait_until(func() -> bool: return got.size() > 0, 15.0)
	assert_eq(got.size(), 1, "экран загрузки завершился")
	assert_eq(String(get_tree().current_scene.name), "SlowWorldBU", "текущая сцена — мир")
	assert_false(is_instance_valid(ls), "экран загрузки убран")
	get_tree().current_scene.queue_free()


func test_loading_screen_bad_path_fails() -> void:
	var ls: LoadingScreenBU = LoadingScreenBU.new()
	ls.scene_path = "res://nope/missing_world.tscn"
	watch_signals(ls)
	get_tree().root.add_child(ls)
	await wait_frames(5)
	assert_signal_emitted(ls, "failed")
	ls.queue_free()


func _model() -> HeroModelBU:
	var m: HeroModelBU = HeroModelBU.new()
	m.name = "Visual"
	add_child_autofree(m)
	return m


func test_walk_pose_and_leg_mesh_deform() -> void:
	# Правила CLAUDE.md (этапы с персонажами): позы ключевых костей
	# (бедро, колено, плечо) в ходьбе ≥0.5 с отличаются от покоя в числах
	# с порогом; вершины меша ног едут за костями (скиннинг живой).
	var result: Dictionary = await AnimSelfCheckBU.run(_model(), true)
	assert_true(result["ok"], "позы/скиннинг: %s"
		% ";\n".join(PackedStringArray(result["reasons"])))


func test_sword_library_tracks_resolve() -> void:
	# Правила CLAUDE.md (этапы с персонажами): каждая дорожка каждого
	# клипа библиотеки sword находит узел и кость на риге героя.
	var model: HeroModelBU = _model()
	await wait_frames(2)
	var ap: AnimationPlayer = model.anim_player()
	assert_not_null(ap, "у героя есть плеер")
	var skel: Skeleton3D = model.skeleton()
	assert_not_null(skel, "у героя есть скелет")
	var root: Node = ap.get_node(ap.root_node)
	var unresolved: PackedStringArray = PackedStringArray()
	var tracks: int = 0
	for lib_name: StringName in ap.get_animation_library_list():
		var lib: AnimationLibrary = ap.get_animation_library(lib_name)
		for anim_name: StringName in lib.get_animation_list():
			var anim: Animation = lib.get_animation(anim_name)
			for tr: int in anim.get_track_count():
				tracks += 1
				var path := String(anim.track_get_path(tr))
				var node := root.get_node_or_null(NodePath(path.get_slice(":", 0)))
				if node == null:
					unresolved.append("%s/%s: узел «%s»" % [lib_name, anim_name, path])
				elif node is Skeleton3D \
						and (node as Skeleton3D).find_bone(path.get_slice(":", 1)) < 0:
					unresolved.append("%s/%s: кость «%s»" % [lib_name, anim_name, path])
	assert_gt(tracks, 0, "в библиотеке есть дорожки")
	assert_eq(unresolved.size(), 0, "дорожки без узла/кости: %s"
		% ", ".join(unresolved))
