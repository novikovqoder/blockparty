# Одноразовая диагностика (П5.8, часть B): риг и меши Universal Base
# Characters и Modular Character Outfits — кости, треугольники, габариты,
# материалы поверхностей. Запуск:
#   godot --headless -s tools/probe_ubc.gd -- <файл.gltf> [...]
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("нет файлов")
		quit(1)
		return
	for path in args:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) != OK:
			print("%s: не читается" % path)
			continue
		var root := doc.generate_scene(state)
		print("%s\n%s" % [path, _walk(root, Transform3D.IDENTITY)])
		root.free()
	quit(0)


func _walk(node: Node3D, parent_xf: Transform3D) -> String:
	var xf := parent_xf * node.transform
	var report := ""
	if node is Skeleton3D:
		var skeleton := node as Skeleton3D
		var bones := skeleton.get_bone_count()
		var names: Array[String] = []
		for i: int in mini(bones, 10):
			names.append(skeleton.get_bone_name(i))
		report += "  риг: %d костей, начало: %s\n" % [bones, ", ".join(names)]
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			var tris := 0
			var surfaces: Array[String] = []
			for surface: int in mesh.get_surface_count():
				var indices: PackedInt32Array = \
					mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
				tris += indices.size() / 3
				var material: Material = mesh.surface_get_material(surface)
				surfaces.append(material.resource_name if material != null \
					else "<без материала>")
			var aabb := xf * mesh.get_aabb()
			report += "  меш %s: %d трис, поверхности [%s], габарит %.2f×%.2f×%.2f\n" % [
				(node as MeshInstance3D).name, tris, ", ".join(surfaces),
				aabb.size.x, aabb.size.y, aabb.size.z,
			]
	for child: Node in node.get_children():
		if child is Node3D:
			report += _walk(child as Node3D, xf)
	return report
