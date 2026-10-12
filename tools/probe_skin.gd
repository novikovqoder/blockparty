# Одноразовая диагностика (П5.8, часть E): как устроен Skin запечённой
# части (капюшон) — бинды и их позы, для сборки скинов новых уборов.
extends SceneTree

func _init() -> void:
	var skin := load("res://assets/third_party/quaternius.com/universal_base_characters/baked/meshes/hood_ranger_m_skin.res") as Skin
	print("binds: ", skin.get_bind_count())
	for i: int in mini(skin.get_bind_count(), 6):
		print(i, " bone=", skin.get_bind_bone(i), " pose=", skin.get_bind_pose(i))
	var scene := load("res://assets/third_party/quaternius.com/universal_base_characters/baked/ubc_male.res") as PackedScene
	var root := scene.instantiate()
	var sk := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	print("Head global_rest=", sk.get_bone_global_rest(6))
	quit(0)
