# Числовая самопроверка ретаргеченных анимаций (П5.7, блок 5): для каждого
# клипа anims_mpfb.res инстансит модель Финна, прогоняет клипы покадрово и
# печатает метрики поз — положение кистей/коленей/таза относительно головы,
# углы суставов. Для решения, какие клипы читаются, а какие править.
#   godot --headless --path . -s res://tools/check_anims.gd
extends SceneTree

## Момент клипа: применить и дождаться обновления скелета.
func _pose_at(player: AnimationPlayer, clip: String, t: float) -> void:
	player.play(clip)
	player.seek(t, true)
	for i in 2:
		await process_frame


const CLIPS: PackedStringArray = [
	"Idle", "Walk", "Jog_Fwd", "Jump_Start", "NinjaJump_Idle", "Jump_Land",
	"Hit_Chest", "Interact", "Sitting_Idle", "Idle_Talking", "Dance",
	"ClimbUp_1m", "Idle_Rail_Call", "Idle_No", "Hang_Pose", "Walk_Hand",
	"Wave_Hand", "Help_Call",
]


func _init() -> void:
	var lib := (load("res://assets/third_party/quaternius.com/"
		+ "universal_animation_library/anims_mpfb.res") as AnimationLibrary)
	var scene := load("res://assets/third_party/makehumancommunity.org/finn/finn.glb") \
		as PackedScene
	var root := scene.instantiate()
	self.root.add_child(root)
	await process_frame
	var sk := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player := AnimationPlayer.new()
	root.add_child(player)
	player.root_node = player.get_path_to(root)
	player.add_animation_library("", lib)

	for clip_name: String in CLIPS:
		var anim := lib.get_animation(clip_name) as Animation
		var pts := [0.0, anim.length * 0.25, anim.length * 0.5, anim.length * 0.9]
		print("== %s  len=%.2f loop=%d" % [clip_name, anim.length, anim.loop_mode])
		for t: float in pts:
			await _pose_at(player, clip_name, t)
			var head := sk.get_bone_global_pose(sk.find_bone("head")).origin
			var hand_l := _tip(sk, "hand_l")
			var hand_r := _tip(sk, "hand_r")
			var foot_l := _tip(sk, "foot_l")
			var pelvis := sk.get_bone_global_pose(sk.find_bone("pelvis")).origin
			print("  t=%.2f  голова y=%.2f | кисть L (%+.2f,%+.2f) R (%+.2f,%+.2f) | стопа L y=%.2f | таз y=%.2f" % [t, head.y,
				hand_l.x - head.x, hand_l.y - head.y, hand_r.x - head.x,
				hand_r.y - head.y, foot_l.y, pelvis.y])
	quit(0)


## Конец кости в пространстве скелета: глобальная поза + локальный сдвиг
## вдоль оси Y (направление кости).
func _tip(sk: Skeleton3D, bone: String) -> Vector3:
	var i := sk.find_bone(bone)
	var pose := sk.get_bone_global_pose(i)
	return pose.origin + pose.basis.y * sk.get_bone_rest(i).origin.length() * 0.5
