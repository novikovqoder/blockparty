# Одноразовая диагностика (П5.8, B1): срез «голова+шея» из тела UBC
# Superhero — остаются треугольники, у которых ВСЕ вершины нагружены на
# кости Head/neck_01 (сумма весов ≥ порога); вершины компактируются,
# меш и скин сохраняются в .res для рендер-пробника. Остальное тело
# удаляется: одежда MCO закрывает торс/руки/ноги целиком (ридми MCO),
# полное тело под ней просвечивает и тратит полигоны.
# Запуск: godot --headless -s tools/probe_head_slice.gd -- <FullBody.gltf> <out.res>
extends SceneTree

const BONES_KEEP: PackedStringArray = ["Head", "neck_01"]
const THRESHOLD: float = 0.5
const VW: int = 4  # костей на вершину в ARRAY_BONES/ARRAY_WEIGHTS


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("аргументы: <FullBody.gltf> <out.res>")
		quit(1)
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(args[0], state) != OK:
		print("не читается")
		quit(1)
		return
	var root := doc.generate_scene(state)
	var skeleton := _find(root, "Skeleton3D") as Skeleton3D
	var bone_ok := {}
	for b in BONES_KEEP:
		var i := skeleton.find_bone(b)
		if i >= 0:
			bone_ok[i] = true
	for mi_node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_node as MeshInstance3D
		if mi.mesh == null or not String(mi.name).begins_with("SuperHero"):
			continue
		for surface in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surface)
			var tris_before := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var sliced := slice_keep_bones(arrays, bone_ok)
			if (sliced[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
				continue
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sliced)
			for dbg in [[Mesh.ARRAY_VERTEX, "vert"], [Mesh.ARRAY_NORMAL, "norm"],
					[Mesh.ARRAY_TANGENT, "tang"], [Mesh.ARRAY_TEX_UV, "uv"],
					[Mesh.ARRAY_COLOR, "col"], [Mesh.ARRAY_BONES, "bones"],
					[Mesh.ARRAY_WEIGHTS, "wts"], [Mesh.ARRAY_INDEX, "idx"]]:
				var sz: int = (sliced[dbg[0]] as Variant).size() if sliced[dbg[0]] != null else -1
				print("    %s: %d" % [dbg[1], sz])
			var err := ResourceSaver.save(am, args[1])
			print("%s: трис %d → %d, габарит %s → %s (err %d)" % [
				mi.name, tris_before,
				(sliced[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3,
				(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
				(sliced[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), err])
			print("  aabb среза: %s" % am.get_aabb())
			if mi.skin != null:
				var serr := ResourceSaver.save(mi.skin, args[1].replace(".res", "_skin.res"))
				print("  скин: err %d" % serr)
	root.free()
	quit(0)


## Оставить треугольники целиком на выбранных костях и компактить вершины.
func slice_keep_bones(arrays: Array, bone_ok: Dictionary) -> Array:
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
	var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
	var keep_vert := PackedByteArray()
	keep_vert.resize(verts.size())
	for v in verts.size():
		var s := 0.0
		for k in VW:
			if bone_ok.has(bones[v * VW + k]):
				s += weights[v * VW + k]
		keep_vert[v] = 1 if s >= THRESHOLD else 0
	var keep_indices := PackedInt32Array()
	for t in indices.size() / 3:
		var a: int = indices[t * 3]
		var b: int = indices[t * 3 + 1]
		var c: int = indices[t * 3 + 2]
		if keep_vert[a] and keep_vert[b] and keep_vert[c]:
			keep_indices.append_array(PackedInt32Array([a, b, c]))
	return compact(arrays, keep_indices)


## Пересобрать все атрибуты по подмножеству треугольников (общая для
## запекания: срез головы и децимация LOD используют один механизм).
func compact(arrays: Array, keep_indices: PackedInt32Array) -> Array:
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var remap := PackedInt32Array()
	remap.resize(verts.size())
	remap.fill(-1)
	var next := 0
	for i in keep_indices.size():
		var old: int = keep_indices[i]
		if remap[old] < 0:
			remap[old] = next
			next += 1
	var out := arrays.duplicate(true)
	_remap_v3(out, Mesh.ARRAY_VERTEX, remap, next)
	_remap_v3(out, Mesh.ARRAY_NORMAL, remap, next)
	_remap_v2(out, Mesh.ARRAY_TEX_UV, remap, next)
	_remap_v2(out, Mesh.ARRAY_TEX_UV2, remap, next)
	_remap_color(out, Mesh.ARRAY_COLOR, remap, next)
	_remap_v4i(out, Mesh.ARRAY_BONES, remap, next)
	_remap_v4f(out, Mesh.ARRAY_WEIGHTS, remap, next)
	_remap_v4f(out, Mesh.ARRAY_TANGENT, remap, next)
	var idx := PackedInt32Array()
	idx.resize(keep_indices.size())
	for i in keep_indices.size():
		idx[i] = remap[keep_indices[i]]
	out[Mesh.ARRAY_INDEX] = idx
	return out


func _remap_v3(arrays: Array, key: int, remap: PackedInt32Array, count: int) -> void:
	var src := arrays[key] as PackedVector3Array
	if src == null or src.is_empty():
		return
	var out := PackedVector3Array()
	out.resize(count)
	for i in src.size():
		if remap[i] >= 0:
			out[remap[i]] = src[i]
	arrays[key] = out


func _remap_v2(arrays: Array, key: int, remap: PackedInt32Array, count: int) -> void:
	var src := arrays[key] as PackedVector2Array
	if src == null or src.is_empty():
		return
	var out := PackedVector2Array()
	out.resize(count)
	for i in src.size():
		if remap[i] >= 0:
			out[remap[i]] = src[i]
	arrays[key] = out


func _remap_color(arrays: Array, key: int, remap: PackedInt32Array, count: int) -> void:
	var src := arrays[key] as PackedColorArray
	if src == null or src.is_empty():
		return
	var out := PackedColorArray()
	out.resize(count)
	for i in src.size():
		if remap[i] >= 0:
			out[remap[i]] = src[i]
	arrays[key] = out


func _remap_v4i(arrays: Array, key: int, remap: PackedInt32Array, count: int) -> void:
	var src := arrays[key] as PackedInt32Array
	if src == null or src.is_empty():
		return
	var out := PackedInt32Array()
	out.resize(count * VW)
	for i in src.size() / VW:
		if remap[i] >= 0:
			for k in VW:
				out[remap[i] * VW + k] = src[i * VW + k]
	arrays[key] = out


func _remap_v4f(arrays: Array, key: int, remap: PackedInt32Array, count: int) -> void:
	var src := arrays[key] as PackedFloat32Array
	if src == null or src.is_empty():
		return
	var out := PackedFloat32Array()
	out.resize(count * VW)
	for i in src.size() / VW:
		if remap[i] >= 0:
			for k in VW:
				out[remap[i] * VW + k] = src[i * VW + k]
	arrays[key] = out


func _find(node: Node, classname: String) -> Node:
	if node.is_class(classname):
		return node
	for child in node.get_children():
		var found := _find(child, classname)
		if found != null:
			return found
	return null
