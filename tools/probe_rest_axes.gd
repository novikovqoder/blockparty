# Д1 (фикс рук): rest-оси костей рига UBC в мировом пространстве — какая
# ось кости куда смотрит в T-pose (нужно, чтобы задавать ролл наведением
# «ось кости → dir, вторичная ось → aim_dir» без подбора углов руками).
#   godot --headless --path . -s res://tools/probe_rest_axes.gd
extends SceneTree

const UBC_SCENE: String = "res://assets/third_party/quaternius.com/" \
	+ "universal_base_characters/baked/ubc_male.res"
const BONES: PackedStringArray = [
	"upperarm_r", "lowerarm_r", "hand_r",
	"upperarm_l", "lowerarm_l", "hand_l",
	"thigh_l", "calf_l", "foot_l",
]


func _init() -> void:
	var scene := load(UBC_SCENE) as PackedScene
	var root := scene.instantiate()
	var sk := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	print("%-11s %-26s %-26s %s" % ["кость", "X (basis.x)", "Y (ось кости)",
		"Z (basis.z)"])
	for bone: String in BONES:
		var i := sk.find_bone(bone)
		var b := sk.get_bone_global_rest(i).basis
		print("%-11s (%+.2f,%+.2f,%+.2f)  (%+.2f,%+.2f,%+.2f)  (%+.2f,%+.2f,%+.2f)"
			% [bone,
			b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z])
	root.free()
	quit()
