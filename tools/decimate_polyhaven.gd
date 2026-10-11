# Одноразовая обработка (П5.7, блок 2): децимация фотосканов Poly Haven
# под бюджет рантайма без внешних инструментов — упрощением самого Godot
# (ImporterMesh.generate_lods, meshoptimizer; Blender на сервере недоступен).
# Исходные glTF 1k лежат вне git в .downloads/ph/<набор>/ (см. LICENSES.md),
# результат — «сырой» меш с запечёнными вершинными цветами:
#   assets/third_party/polyhaven.com/<набор>/<имя>.res
# Меш нормируется до эталонных размеров позже, при запекании острова
# (Cc0Meshes._build_res → _normalized), поэтому здесь только геометрия,
# цвет по диффузной текстуре (сэмпл по UV, sRGB → линейный) и индексы.
# Нормали не сохраняются: шейдер lowpoly/wind считает нормаль грани сам.
# Запуск (по одному набору за раз — сканы до 5 млн треугольников):
#   godot --headless --script tools/decimate_polyhaven.gd --path . \
#     -- <набор> <целевые_треугольники> <имя_файла>
# Пример: -- island_tree_02 6000 island_tree_02_lo
# Проход generate_lods даёт три LOD (~50 %, ~18 %, ~4 % базового числа
# треугольников); проходы повторяются, пока поверхность не попадёт в свою
# долю общего бюджета (бюджет делится по вкладу поверхности). Цвет
# сэмплируется после децимации — текстура исходника нужна только на этом
# шаге, в проект не копируется.
extends SceneTree


func _init() -> void:
	await create_timer(0.01).timeout
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("аргументы: <набор> <целевые_треугольники> <имя_файла>")
		quit(1)
		return
	var asset: String = args[0]
	var target_total: int = int(args[1])
	var out_name: String = args[2]
	var started := Time.get_ticks_msec()
	var src := "res://.downloads/ph/%s/%s_1k.gltf" % [asset, asset]
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(src, state) != OK:
		push_error("glTF не читается: " + src)
		quit(1)
		return
	var root := doc.generate_scene(state)
	var parts: Array = []
	_collect(root, Transform3D.IDENTITY, parts)
	root.free()
	if parts.is_empty():
		push_error("в модели нет треугольных поверхностей: " + src)
		quit(1)
		return
	var total_before := 0
	for part: Dictionary in parts:
		total_before += (part["indices"] as PackedInt32Array).size() / 3
	for part: Dictionary in parts:
		var share: float = float((part["indices"] as PackedInt32Array).size() / 3) \
			/ maxf(total_before, 1)
		_decimate(part, maxi(24, roundi(target_total * share)))
		_bake_colors(part)
	var total_after := 0
	for part: Dictionary in parts:
		total_after += (part["indices"] as PackedInt32Array).size() / 3
	var mesh := _merge(parts)
	var dir := "res://assets/third_party/polyhaven.com/%s" % asset
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := "%s/%s.res" % [dir, out_name]
	var save_error := ResourceSaver.save(mesh, path)
	if save_error != OK:
		push_error("не удалось сохранить %s (код %d)" % [path, save_error])
		quit(1)
		return
	print("%s: %s → %s треугольников, поверхностей %d, %s, %.1f с" % [
		out_name, _fmt(total_before), _fmt(total_after), parts.size(), path,
		(Time.get_ticks_msec() - started) / 1000.0,
	])
	quit()


func _fmt(n: int) -> String:
	var text := str(n)
	var out := ""
	while text.length() > 3:
		out = " " + text.substr(text.length() - 3) + out
		text = text.substr(0, text.length() - 3)
	return (text + out).strip_edges()


## Обход сцены glTF: каждая треугольная поверхность — «деталь» с вершинами
## в общем базисе, нормалями и UV (нужны децимации и сэмплу цвета).
func _collect(node: Node3D, parent_xf: Transform3D, parts: Array) -> void:
	var xf := parent_xf * node.transform
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			for surface: int in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(surface)
				if arrays.is_empty() or mesh.surface_get_primitive_type(surface) \
						!= Mesh.PRIMITIVE_TRIANGLES:
					continue
				var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
				if verts.is_empty() or indices == null or indices.is_empty():
					continue
				var world_verts := PackedVector3Array()
				world_verts.resize(verts.size())
				for i: int in verts.size():
					world_verts[i] = xf * verts[i]
				var material: Material = mesh.surface_get_material(surface)
				parts.append({
					"verts": world_verts,
					"normals": arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array,
					"uv": arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array,
					"indices": indices,
					"material": material,
					"colors": PackedColorArray(),
				})
	for child: Node in node.get_children():
		if child is Node3D:
			_collect(child as Node3D, xf, parts)


## Децимация детали до целевого бюджета: цикл проходов generate_lods,
## на каждом берём самый глубокий LOD, ещё не тонущий ниже доли бюджета
## детали (бюджет делится по вкладу поверхности в общее число
## треугольников). Фиксированная глубина LOD («50 %, 18 %, 4 %») на это
## не годится: поверхности модели разного размера — мелкие за два прохода
## схлопывались до десятков треугольников, а крупные оставались слишком
## густыми. Выход — если ни один LOD не подходит (бюджет уже достигнут
## или самый грубый всё ещё густ), остановиться.
func _decimate(part: Dictionary, target: int) -> void:
	for pass_i: int in 4:
		var tris: int = (part["indices"] as PackedInt32Array).size() / 3
		if tris <= target * 2:
			break
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = part["verts"]
		arrays[Mesh.ARRAY_NORMAL] = part["normals"]
		arrays[Mesh.ARRAY_TEX_UV] = part["uv"]
		arrays[Mesh.ARRAY_INDEX] = part["indices"]
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, null, "")
		im.generate_lods(60.0, 25.0, [])
		var lod_count := im.get_surface_lod_count(0)
		var chosen := PackedInt32Array()
		for lod: int in range(lod_count - 1, -1, -1):
			chosen = im.get_surface_lod_indices(0, lod)
			if chosen.size() / 3 >= target:
				break
		# Ни один LOD не даёт бюджета (самый мелкий всё ещё густ) — берём
		# самый глубокий и идём на следующий проход.
		if chosen.is_empty() or chosen.size() / 3 >= tris:
			break
		_compact(part, chosen)


## Пересобрать вершины/нормали/UV детали по новому индексному буферу.
func _compact(part: Dictionary, indices: PackedInt32Array) -> void:
	var verts := part["verts"] as PackedVector3Array
	var normals := part["normals"] as PackedVector3Array
	var uv := part["uv"] as PackedVector2Array
	var remap := PackedInt32Array()
	remap.resize(verts.size())
	remap.fill(-1)
	var new_verts := PackedVector3Array()
	var new_normals := PackedVector3Array()
	var new_uv := PackedVector2Array()
	var new_indices := PackedInt32Array()
	new_indices.resize(indices.size())
	for i: int in indices.size():
		var old: int = indices[i]
		var mapped: int = remap[old]
		if mapped < 0:
			mapped = new_verts.size()
			remap[old] = mapped
			new_verts.append(verts[old])
			if normals.size() == verts.size():
				new_normals.append(normals[old])
			if uv.size() == verts.size():
				new_uv.append(uv[old])
		new_indices[i] = mapped
	part["verts"] = new_verts
	part["normals"] = new_normals
	part["uv"] = new_uv
	part["indices"] = new_indices


## Цвет вершин по диффузной текстуре материала (после децимации — вершин
## мало, сэмпл дёшев). Без текстуры — белый: тон даст IslandGen.
func _bake_colors(part: Dictionary) -> void:
	var verts := part["verts"] as PackedVector3Array
	var colors := PackedColorArray()
	colors.resize(verts.size())
	colors.fill(Color.WHITE)
	part["colors"] = colors
	var material := part["material"] as StandardMaterial3D
	if material == null or material.albedo_texture == null:
		return
	var uv := part["uv"] as PackedVector2Array
	if uv.size() != verts.size():
		return
	var image := material.albedo_texture.get_image()
	for i: int in verts.size():
		var pixel := image.get_pixel(
			clampi(roundi(uv[i].x * image.get_width()), 0, image.get_width() - 1),
			clampi(roundi((1.0 - uv[i].y) * image.get_height()), 0,
				image.get_height() - 1),
		)
		colors[i] = pixel.srgb_to_linear()


## Склеить детали в один ArrayMesh (вершины + цвета + индексы).
func _merge(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for part: Dictionary in parts:
		var base: int = verts.size()
		verts.append_array(part["verts"])
		colors.append_array(part["colors"])
		for index: int in part["indices"]:
			indices.append(base + index)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
