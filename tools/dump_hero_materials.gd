# Одноразовая диагностика (П17 п.12): аудит материалов героя — какие
# альбедо-текстуры (средняя яркость: не слишком ли тёмные), metallic
# (MakeHuman часто даёт лишний блеск ткани/коже), roughness. Запуск:
# godot --headless -s tools/dump_hero_materials.gd
extends SceneTree


func _initialize() -> void:
	var hero: Node = load("res://assets/hero_bu/hero_bu.tscn").instantiate()
	root.add_child(hero)
	for node: Node in hero.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i: int in mi.get_surface_override_material_count():
			var mat := mi.get_active_material(i)
			if mat == null:
				continue
			_dump("%s/%d" % [node.name, i], mat)
	hero.queue_free()
	quit(0)


func _dump(path: String, mat: Material) -> void:
	if mat is not BaseMaterial3D:
		print("%s класс=%s" % [path, mat.get_class()])
		return
	var b := mat as BaseMaterial3D
	var tex := b.albedo_texture
	var brightness := -1.0
	var tex_note := "-"
	if tex != null:
		var img := tex.get_image()
		if img != null and not img.is_empty():
			var sum := 0.0
			var pixels := 0
			for y: int in range(0, img.get_height(), 16):
				for x: int in range(0, img.get_width(), 16):
					var c := img.get_pixel(x, y)
					sum += c.get_luminance()
					pixels += 1
			brightness = sum / maxf(pixels, 1.0)
			tex_note = "%s %dx%d" % [tex.resource_path.get_file(), img.get_width(), img.get_height()]
	print("%s albedo=(%.3f %.3f %.3f) tex=%s lum=%.3f metallic=%.3f roughness=%.3f metal_tex=%s rough_tex=%s norm=%s" % [
		path, b.albedo_color.r, b.albedo_color.g, b.albedo_color.b,
		tex_note, brightness, b.metallic, b.roughness,
		"да" if b.metallic_texture != null else "нет",
		"да" if b.roughness_texture != null else "нет",
		"да" if b.normal_texture != null else "нет",
	])
