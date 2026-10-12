# Самопроверка anims_ubc.res (П5.8, часть C): для каждого клипа на обоих
# телах UBC — резолвятся ли треки в кости скелета, снимок поз (кисти/стопы/
# таз относительно головы). Решает, какие клипы читаются, а какие править.
#   godot --headless --path . -s res://tools/probe_ubc_anims.gd
extends SceneTree

const LIB_PATH: String = "res://assets/third_party/quaternius.com/" \
	+ "universal_animation_library/anims_ubc.res"
const SCENES: PackedStringArray = [
	"res://assets/third_party/quaternius.com/universal_base_characters/baked/ubc_male.res",
	"res://assets/third_party/quaternius.com/universal_base_characters/baked/ubc_female.res",
]


func _init() -> void:
	var lib := load(LIB_PATH) as AnimationLibrary
	print("клипов: ", lib.get_animation_list().size())
	for scene_path: String in SCENES:
		var scene := load(scene_path) as PackedScene
		var root := scene.instantiate()
		self.root.add_child(root)
		await process_frame
		var sk := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var names: PackedStringArray = []
		for i: int in sk.get_bone_count():
			names.append(sk.get_bone_name(i))
		print("кости: ", " ".join(names))
		var player := AnimationPlayer.new()
		root.add_child(player)
		player.root_node = player.get_path_to(root)
		player.add_animation_library("", lib)
		print("\n===== %s (костей %d) =====" % [scene_path.get_file(),
			sk.get_bone_count()])

		# Резолв треков: путь «Armature/Skeleton3D:кость» + кость существует.
		var bad: PackedStringArray = []
		for clip_name: StringName in lib.get_animation_list():
			var anim := lib.get_animation(clip_name) as Animation
			for i: int in anim.get_track_count():
				var path := anim.track_get_path(i)
				var node_path := NodePath(str(path).get_slice(":", 0))
				if root.get_node_or_null(node_path) == null:
					bad.append("%s: нет узла %s" % [clip_name, node_path])
					continue
				var bone := str(path).get_slice(":", 1)
				if sk.find_bone(bone) < 0:
					bad.append("%s: нет кости %s" % [clip_name, bone])
		print("нерезолвящихся треков: ", bad.size())
		for line: String in bad:
			print("  ", line)

		# Снимок поз ключевых клипов.
		for clip_name: String in ["Idle", "Walk", "Jog_Fwd", "Jump_Start",
				"NinjaJump_Idle", "Jump_Land", "Sitting_Idle", "Hang_Pose",
				"Walk_Hand", "Wave_Hand", "Help_Call", "ClimbUp_1m"]:
			var anim := lib.get_animation(clip_name) as Animation
			player.play(clip_name)
			player.seek(anim.length * 0.5, true)
			for i in 2:
				await process_frame
			var head := _tip(sk, "Head")
			var pelvis := sk.get_bone_global_pose(sk.find_bone("pelvis")).origin
			print("%-14s таз y=%+.3f  голова y=%+.3f  кистьL y=%+.3f  кистьR y=%+.3f  стопаL y=%+.3f"
				% [clip_name, pelvis.y, head.y,
					_tip(sk, "hand_l").y - head.y, _tip(sk, "hand_r").y - head.y,
					_tip(sk, "foot_l").y])
		root.free()
	quit(0)


## Конец кости: глобальная поза + сдвиг вдоль оси Y на длину половины кости.
func _tip(sk: Skeleton3D, bone: String) -> Vector3:
	var i := sk.find_bone(bone)
	var pose := sk.get_bone_global_pose(i)
	return pose.origin + pose.basis.y * sk.get_bone_rest(i).origin.length() * 0.5
