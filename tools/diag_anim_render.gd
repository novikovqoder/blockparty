# Решающий рендерный эксперимент (П5.8, возврат владельца): скелет в
# headless позируется, меши на скриншотах — T-поза. Три модели рядом:
#   A — покой (Idle играет), B — ходьба (Walk, прокрутка 0.3 с),
#   C — ручной поворот бедра/плеча set_bone_pose_rotation (без анимации).
# Если C не гнётся — скин не работает на рендере; если C гнётся, а B нет —
# разрыв анимация→скелет в рендерном рантайме.
#   xvfb-run -a godot --path . --resolution 1280x720 --rendering-driver opengl3 \
#     res://tools/diag_anim_render.tscn
extends Node3D

const MODEL: PackedScene = preload("res://gameplay/player/character_model.tscn")


func _ready() -> void:
	var world := Node3D.new()
	world.name = "AnimProbe"
	add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.17, 0.17, 0.20)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.65, 0.7)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, -30.0, 0.0)
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	ground.mesh = plane
	world.add_child(ground)

	var a := MODEL.instantiate() as CharacterModel
	var b := MODEL.instantiate() as CharacterModel
	var c := MODEL.instantiate() as CharacterModel
	for m: CharacterModel in [a, b, c]:
		world.add_child(m)
		m.setup_appearance(Appearance.default_for(0))
	a.position = Vector3(-2.2, 0.0, 0.0)
	b.position = Vector3(0.0, 0.0, 0.0)
	c.position = Vector3(2.2, 0.0, 0.0)

	# B: ходьба, прокрутить полшага.
	b.set_state(Protocol.AnimState.WALK)
	# C: отключить анимацию, согнуть бедро и плечо руками + ВОССТАНОВИТЬ
	# скиннинг: skeleton-путь у мешей (кандидат «..» — родитель-скелет).
	var sk_c := c.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	c._player.stop()
	var thigh := sk_c.find_bone("thigh_l")
	var arm := sk_c.find_bone("upperarm_l")
	sk_c.set_bone_pose_rotation(thigh,
		sk_c.get_bone_pose_rotation(thigh) * Quaternion(Vector3.LEFT, 0.9))
	sk_c.set_bone_pose_rotation(arm,
		sk_c.get_bone_pose_rotation(arm) * Quaternion(Vector3.FORWARD, 1.2))
	var fixed := 0
	for node in c.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.skin != null:
			mi.skeleton = ^".."
			fixed += 1
	print("C: skeleton-путь выставлен %d мешам" % fixed)

	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	for i: int in 10:
		await get_tree().process_frame
	# Каждый вариант крупно отдельно: A покой, B ходьба (полшага), C вручную.
	b.set_state(Protocol.AnimState.WALK)
	await get_tree().create_timer(0.3).timeout
	if b._player != null:
		b._player.advance(0.3)
	var shots := [["a_idle", a], ["b_walk", b], ["c_manual", c]]
	for shot in shots:
		var m := shot[1] as CharacterModel
		for other in [a, b, c]:
			other.visible = other == m
		m.position = Vector3.ZERO
		camera.global_position = Vector3(0.0, 0.95, 3.1)
		camera.look_at(Vector3(0.0, 0.9, 0.0))
		await get_tree().create_timer(0.15).timeout
		get_viewport().get_texture().get_image().save_png(
			"builds/screenshots/diag_%s.png" % shot[0])
		print("снято: diag_%s.png" % shot[0])
	# Контроль числом: глобальные позы ключевых костей всех трёх.
	for pair in [["A_idle", a], ["B_walk", b], ["C_manual", c]]:
		var sk: Skeleton3D = (pair[1] as CharacterModel).find_children(
			"*", "Skeleton3D", true, false)[0]
		var line := "%s: " % pair[0]
		for bone: String in ["thigh_l", "upperarm_l"]:
			var rest := sk.get_bone_global_rest(sk.find_bone(bone)).origin
			var pose := sk.get_bone_global_pose(sk.find_bone(bone)).origin
			line += "%s rest=(%.2f %.2f %.2f) pose=(%.2f %.2f %.2f) Δ=%.3f; " % [
				bone, rest.x, rest.y, rest.z, pose.x, pose.y, pose.z,
				(pose - rest).length()]
		print(line)
	get_tree().quit(0)
