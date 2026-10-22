# Пробник (временный): нормали пола по пути входа — земля подушки,
# ступени крыльца (декимированный меш), крыльцо, лесенка порога, пол.
extends SceneTree


func _init() -> void:
	var root := get_root()
	var cabin: Node3D = load("res://gameplay/world/props/cabin_house.gd").new()
	root.add_child(cabin)
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	for gz: int in range(-56, -49, 2):
		var lz: float = float(gz) * 0.1
		var row := "lz%5.1f:" % lz
		for gx: int in range(-20, 26, 2):
			var lx: float = float(gx) * 0.1
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(lx, 1.5, lz), Vector3(lx, -2.0, lz), 1)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				row += "   ---"
			else:
				var n: Vector3 = hit["normal"]
				row += " %.2f" % n.y
		print(row)
	print("строки lz -5.6…-4.9, колонки lx -2.0…+2.5 (шаг 0.2): нормаль.y пола")
	quit()
