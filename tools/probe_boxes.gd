# Пробник (временный): карта полов сруба лучами сверху — где пол дома
# (0.16 → интерьер, камере сжиматься), где настил террасы/крыльца (0.62,
# камера свободна), где пола нет. Шаг 0.4 м.
extends SceneTree


func _initialize() -> void:
	_measure.call_deferred()


func _measure() -> void:
	var cabin: Node3D = load("res://gameplay/world/props/cabin_house.gd").new()
	root.add_child(cabin)
	await process_frame
	await process_frame
	var space := root.get_world_3d().direct_space_state
	var header := "        "
	for gx: int in range(-18, 19, 2):
		header += "%4.0f" % (float(gx) * 0.4)
	print(header)
	for gz: int in range(-20, 21, 2):
		var lz: float = float(gz) * 0.4
		var row := "z=%5.1f " % lz
		for gx: int in range(-18, 19, 2):
			var lx: float = float(gx) * 0.4
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(lx, 1.2, lz), Vector3(lx, -2.0, lz), 1)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				row += "    ."
				continue
			var y: float = hit["position"].y
			if y < 0.45:
				row += "    I"
			elif y < 0.85:
				row += "    t"
			else:
				row += "    ?"
		print(row)
	print("I — пол дома (0.16), t — терраса/крыльцо (0.62), . — пола нет; колонны x, строки z")
	quit()
