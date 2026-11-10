# Тесты робота района-постапокалипсиса (RobotModelPA) — правила CLAUDE.md
# «этапы с персонажами»: позы ключевых костей в ходьбе против покоя, резолв
# каждой дорожки каждого клипа, скиннинг ног; плюс подмена визуала игрока
# в районе и отсутствие меча.
extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://gameplay/player/player.tscn")


func _robot() -> RobotModelPA:
	var robot := RobotModelPA.new()
	robot.name = "Visual"
	add_child_autofree(robot)
	return robot


func test_robot_loads_with_skeleton_and_clips() -> void:
	var robot: RobotModelPA = _robot()
	var skel: Skeleton3D = robot.skeleton()
	assert_not_null(skel, "у робота есть скелет")
	assert_gt(skel.find_bone("mixamorig_Hips"), -1, "скелет Mixamo")
	var ap: AnimationPlayer = robot.anim_player()
	assert_not_null(ap, "у робота есть плеер")
	for clip: String in [
		"base_idle", "base_walk", "base_run", "base_turn",
		"base_jump_up", "base_jump_fly", "base_jump_land",
	]:
		assert_true(ap.has_animation("base/%s" % clip), "клип %s" % clip)
	assert_false(ap.has_animation_library(&"sword"), "боевой библиотеки нет")
	assert_null(robot.equip, "меча нет")


func test_robot_height_about_1_7m() -> void:
	var robot: RobotModelPA = _robot()
	var top: float = robot.head_top_height()
	assert_between(top, 1.6, 1.85, "рост робота (%.2f м)" % top)
	assert_almost_eq(robot.lowest_point(), 0.0, 0.05, "подошвы на земле")


func test_robot_walk_pose_tracks_and_leg_skinning() -> void:
	# Позы бедра/колена/плеча, резолв всех дорожек и сдвиг вершин ног —
	# та же проверка, что гоняет --district --selftest-anim.
	var result: Dictionary = await AnimSelfCheckBU.run(_robot(), true)
	assert_true(result["ok"], "робот: %s"
		% ";\n".join(PackedStringArray(result["reasons"])))
	var metrics: Dictionary = result["metrics"]
	assert_eq(int(metrics.get("tracks_unresolved", -1)), 0, "все дорожки нашли кость")


func test_robot_attack_and_landing_do_not_crash() -> void:
	# Удара мечом у робота нет — вызов пропускается; приземление играет.
	var robot: RobotModelPA = _robot()
	robot.play_attack(0.25)
	robot.play_one_shot(Protocol.AnimState.LAND, 0.3)
	await wait_frames(3)
	assert_eq(
		robot.anim_player().current_animation, "base/base_jump_land",
		"приземление — клип робота")


func test_district_puts_robot_into_player() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	var robot: RobotModelPA = DistrictLab.put_robot(player)
	add_child_autofree(player)
	await wait_frames(2)
	assert_eq(player.visual, robot, "визуал игрока — робот")
	assert_eq(player.get_node("Model").get_child_count(), 1, "рыцаря в игроке нет")
	assert_true(player.visual is RobotModelPA, "тип визуала")
