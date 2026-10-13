# Процедурные головные уборы жителей (П5.8, часть E): панама с веточкой
# (Тимьян), шляпа с полями и ракушкой (Луми), кепка с меховыми «ушками»
# (Финн). В паков Quaternius уборов нет (UBC — тела/причёски, MCO Fantasy —
# одежда и капюшон), поэтому меши строятся здесь из примитивов (остров
# и персонажи проекта — процедурные, раздел «Решения владельца» SPEC).
# Что делает:
# - для каждого пола (посадка по AABB головы и rest-позе кости Head,
#   индекс 6 у обоих тел) строит hat_panama/hat_brim/hat_cap:
#   полная версия ~300–500 треугольников и _lod1 с половинной детализацией;
# - skin — один бинд на кость Head (bind = global_rest⁻¹, как у запечённых
#   частей): убор едет с головой в анимациях, в покое стоит как в rest;
# - патчит готовые сцены ubc_male.res/ubc_female.res: добавляет узлы
#   MeshInstance3D уборов (visible=false, как все части) — существующие
#   части не трогаются.
#   godot --headless --path . -s res://tools/make_hats.gd
# Материалы — плоские цвета (тонирование внешности уборы не получает),
# запекаются прямо в поверхности меша.
extends SceneTree

const BAKED: String = "res://assets/third_party/quaternius.com/" \
	+ "universal_base_characters/baked"
const MESH_DIR: String = BAKED + "/meshes"

## Индекс кости Head в риге UBC (root pelvis spine_01..03 neck_01 Head).
const HEAD_BONE: int = 6
## Посадка уборов: поля/тулья на этой высоте от верха меша головы, м.
const CROWN_DROP: float = 0.09

## Части {имя_убора: builder} — builder(center, crown_y, seg, lod: bool)
## возвращает Array[SurfaceTool] (поверхность на материал).
var _builders: Dictionary = {}


func _init() -> void:
	_builders = {
		"panama": _build_panama,
		"brim": _build_brim,
		"cap": _build_cap,
	}
	for gender: String in ["male", "female"]:
		var g := gender[0]
		var head := _head_params(gender)
		print("%s: голова верх y=%.3f, центр %s" % [gender, head["top"],
			head["center"]])
		var skin := _head_skin(gender)
		ResourceSaver.save(skin, "%s/hat_head_%s_skin.res" % [MESH_DIR, g])
		for hat in _builders:
			var full: Array = _builders[hat].call(head, false)
			var lod: Array = _builders[hat].call(head, true)
			_save_mesh("hat_%s_%s" % [hat, g], full, lod)
			print("  hat_%s_%s: %d / %d трис" % [hat, g,
				_tris(full), _tris(lod)])
		_patch_scene(gender)
	quit(0)


# --- Параметры головы и skin ---

## Верх и центр меша головы пола: посадка уборов и bind-поза кости Head.
func _head_params(gender: String) -> Dictionary:
	var scene := load("%s/ubc_%s.res" % [BAKED, gender]) as PackedScene
	var root := scene.instantiate()
	var mi := root.find_children("head_%s" % gender[0], "MeshInstance3D",
		true, false)[0] as MeshInstance3D
	var aabb := mi.mesh.get_aabb()
	root.free()
	return {
		"center": aabb.get_center(),
		"top": aabb.end.y,
		"crown": aabb.end.y - CROWN_DROP,
	}


## Skin с одним биндом на Head: bind = global_rest⁻¹ (как у запечённых
## частей UBC) — в покое тождество, в анимации вращение вокруг Head.
func _head_skin(gender: String) -> Skin:
	var scene := load("%s/ubc_%s.res" % [BAKED, gender]) as PackedScene
	var root := scene.instantiate()
	var sk := root.find_children("*", "Skeleton3D", true,
		false)[0] as Skeleton3D
	var skin := Skin.new()
	skin.add_bind(HEAD_BONE, sk.get_bone_global_rest(HEAD_BONE).affine_inverse())
	root.free()
	return skin


## Добавить уборы в готовую сцену пола (меш уже сохранён в meshes/).
func _patch_scene(gender: String) -> void:
	var g := gender[0]
	var path := "%s/ubc_%s.res" % [BAKED, gender]
	var scene := load(path) as PackedScene
	var root := scene.instantiate()
	var skeleton := root.find_children("*", "Skeleton3D", true,
		false)[0] as Skeleton3D
	# Идемпотентность: повторный запуск заменяет уборы, а не плодит дубли.
	for node in root.find_children("hat_*", "MeshInstance3D", true, false):
		node.free()
	# Мусор ранних прогонов: узлы без имени получают автоимена @MeshInstance3D@N
	# и под шаблон hat_* не подпадают.
	for node in root.find_children("@MeshInstance3D*", "MeshInstance3D",
			true, false):
		node.free()
	var added := 0
	for hat in _builders:
		for suffix in ["", "_LOD"]:
			var res := "%s/hat_%s_%s%s.res" % [MESH_DIR, hat, g,
				"" if suffix.is_empty() else "_lod1"]
			var mesh := load(res) as ArrayMesh
			assert(mesh != null, "нет меша %s" % res)
			var mi := MeshInstance3D.new()
			mi.name = "hat_%s_%s%s" % [hat, g, suffix]
			mi.mesh = mesh
			mi.skin = load("%s/hat_head_%s_skin.res" % [MESH_DIR, g]) as Skin
			# skeleton-путь обязателен (как у частей make_ubc_characters):
			# без него убор не скиннится — см. комментарий там (фикс П5.8).
			mi.skeleton = ^".."
			mi.visible = false
			skeleton.add_child(mi)
			mi.owner = root
			added += 1
	var packed := PackedScene.new()
	assert(packed.pack(root) == OK, "не запаковалась сцена %s" % path)
	root.free()
	assert(ResourceSaver.save(packed, path) == OK, "не сохранилась %s" % path)
	print("  ubc_%s.res: +%d узлов уборов" % [gender, added])


# --- Панама (Тимьян): поля-диск, тулья, веточка мяты у тульи ---

func _build_panama(head: Dictionary, lod: bool) -> Array:
	var seg := 8 if lod else 16
	var c: Vector3 = head["center"]
	var flat := Vector3(c.x, 0.0, c.z)
	var crown: float = head["crown"]
	var straw := _mat("hat_straw", Color("d2a95f"))
	var leaf := _mat("hat_leaf", Color("4f7a38"))
	var stemb := _mat("hat_stem", Color("586b3a"))
	var out: Array = []
	var brim := _st(straw)
	_ring(brim, flat, crown, 0.145, 0.27, 0.012, seg, straw)
	_tube(brim, flat, crown - 0.012, crown + 0.10, 0.145, 0.148, seg, straw)
	_disk(brim, flat, crown + 0.10, 0.145, seg, straw)
	out.append(brim)
	if not lod:
		# Веточка у тульи: стебель наклонён наружу, два листа-ромба.
		var stem := _st(stemb)
		var anchor := Vector3(c.x + 0.10, crown + 0.04, c.z + 0.115)
		var tip := anchor + Vector3(0.05, 0.085, 0.05)
		_stick(stem, anchor, tip, 0.008, stemb)
		out.append(stem)
		var leaves := _st(leaf)
		_leaf(leaves, tip, Vector3(0.05, 0.035, 0.02), leaf)
		_leaf(leaves, tip + Vector3(0.02, 0.0, 0.01),
			Vector3(-0.045, 0.02, 0.03), leaf)
		out.append(leaves)
	return out


# --- Шляпа с полями и ракушкой (Луми) ---

func _build_brim(head: Dictionary, lod: bool) -> Array:
	var seg := 8 if lod else 16
	var c: Vector3 = head["center"]
	var flat := Vector3(c.x, 0.0, c.z)
	var crown: float = head["crown"]
	var felt := _mat("hat_felt_sea", Color("7d9db2"))
	var shell := _mat("hat_shell", Color("e8ddc4"))
	var out: Array = []
	var brim := _st(felt)
	_ring(brim, flat, crown, 0.155, 0.30, 0.010, seg, felt)
	_tube(brim, flat, crown - 0.012, crown + 0.12, 0.152, 0.156, seg, felt)
	_disk(brim, flat, crown + 0.12, 0.152, seg, felt)
	out.append(brim)
	if not lod:
		# Раковина-веер спереди на тулье: лопасти из точки, как створка.
		var fan := _st(shell)
		var base := Vector3(c.x, crown + 0.005, c.z + 0.152)
		var lobes := 7
		for i: int in lobes:
			var a := -0.5 + float(i) / float(lobes - 1)
			var dir := Vector3(a * 0.55, 0.75 - absf(a) * 0.25, 0.35).normalized()
			var length := 0.075 * (1.0 - absf(a) * 0.45)
			_leaf(fan, base, dir * length, shell, 0.014)
		out.append(fan)
	return out


# --- Кепка с меховыми «ушками» (Финн) ---

func _build_cap(head: Dictionary, lod: bool) -> Array:
	var seg := 8 if lod else 12
	var rings := 3 if lod else 5
	var c: Vector3 = head["center"]
	var crown: float = head["crown"]
	var cloth := _mat("hat_cap_cloth", Color("6b7a4f"))
	var fur := _mat("hat_cap_fur", Color("8a6a45"))
	var out: Array = []
	var cap := _st(cloth)
	_dome(cap, Vector3(c.x, crown - 0.02, c.z), 0.155, 0.10, seg, rings, cloth)
	# Козырёк: сектор кольца, внешний край ниже — козырёк опущен.
	var visor := _st(cloth)
	_sector(visor, Vector3(c.x, crown - 0.015, c.z + 0.03), 0.09, 0.235,
		deg_to_rad(52.0), 0.02, seg if lod == false else 6, cloth)
	out.append(cap)
	out.append(visor)
	if not lod:
		# Ушки: меховые диски по бокам тульи (второй — чуть выше по нормали,
		# объём).
		var ears := _st(fur)
		for side: float in [-1.0, 1.0]:
			var normal := Vector3(side * 0.35, 0.0, 0.0)
			var center := Vector3(c.x + side * 0.148, crown + 0.015, c.z + 0.01)
			_disk(ears, center, 0.0, 0.05, 10, fur, true, normal)
			_disk(ears, center + normal.normalized() * 0.006, 0.0, 0.036,
				10, fur, true, normal)
		out.append(ears)
	return out


# --- Примитивы (SurfaceTool, плоские грани: треугольник = 3 вершины) ---

## Новая поверхность с материалом: begin() обязателен до add_vertex; один
## SurfaceTool = одна поверхность (повторный begin затирает накопленное,
## поэтому кольцо+тулья+дно пишутся в одну поверхность последовательно).
func _st(mat: StandardMaterial3D) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	return st


func _mat(name: String, color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = name
	m.albedo_color = color
	m.roughness = 0.9
	# Тонкие примитивы (поля, листья, козырёк) — без отсечения задней
	# стороны: порядок обхода у частей колец разный, вывернутая грань
	# не должна делать деталь невидимой.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## Плоское кольцо (поля шляпы): верхняя и нижняя поверхность, внешний
## обод толщиной thickness. Внешний край на толщину ниже — поля «легли».
func _ring(st: SurfaceTool, center: Vector3, y: float, r_in: float,
		r_out: float, thickness: float, seg: int,
		mat: StandardMaterial3D) -> void:
	st.set_material(mat)
	var c := Vector3(center.x, 0, center.z)
	for i: int in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var in0 := c + Vector3(cos(a0), 0, sin(a0)) * r_in
		var in1 := c + Vector3(cos(a1), 0, sin(a1)) * r_in
		var out0 := c + Vector3(cos(a0), 0, sin(a0)) * r_out
		var out1 := c + Vector3(cos(a1), 0, sin(a1)) * r_out
		var y_top := y + thickness
		var y_out := y_top - thickness * 1.6  # внешний край ниже
		# верх (нормаль вверх): от внутреннего к внешнему
		_tri(st, in0 + Vector3(0, y_top, 0), out0 + Vector3(0, y_out, 0),
			out1 + Vector3(0, y_out, 0))
		_tri(st, in0 + Vector3(0, y_top, 0), out1 + Vector3(0, y_out, 0),
			in1 + Vector3(0, y_top, 0))
		# низ (нормаль вниз)
		_tri(st, out0 + Vector3(0, y_out - thickness, 0),
			in0 + Vector3(0, y, 0), in1 + Vector3(0, y, 0))
		_tri(st, out0 + Vector3(0, y_out - thickness, 0),
			in1 + Vector3(0, y, 0), out1 + Vector3(0, y_out - thickness, 0))
		# внешний обод
		_tri(st, out0 + Vector3(0, y_out, 0), out0 + Vector3(0, y_out - thickness, 0),
			out1 + Vector3(0, y_out - thickness, 0))
		_tri(st, out0 + Vector3(0, y_out, 0), out1 + Vector3(0, y_out - thickness, 0),
			out1 + Vector3(0, y_out, 0))


## Труба переменного радиуса (тулья).
func _tube(st: SurfaceTool, center: Vector3, y0: float, y1: float,
		r0: float, r1: float, seg: int, mat: StandardMaterial3D) -> void:
	st.set_material(mat)
	var c := Vector3(center.x, 0, center.z)
	for i: int in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var b00 := c + Vector3(cos(a0), 0, sin(a0)) * r0 + Vector3(0, y0, 0)
		var b01 := c + Vector3(cos(a1), 0, sin(a1)) * r0 + Vector3(0, y0, 0)
		var t10 := c + Vector3(cos(a0), 0, sin(a0)) * r1 + Vector3(0, y1, 0)
		var t11 := c + Vector3(cos(a1), 0, sin(a1)) * r1 + Vector3(0, y1, 0)
		_tri(st, b00, b01, t11)
		_tri(st, b00, t11, t10)


## Диск (дно/крышка); normal ≠ UP — диск в наклонной плоскости (ушки).
func _disk(st: SurfaceTool, center: Vector3, y: float, r: float, seg: int,
		mat: StandardMaterial3D, double_sided: bool = false,
		normal: Vector3 = Vector3.UP) -> void:
	st.set_material(mat)
	var up := normal == Vector3.UP
	var out := center + Vector3(0, y, 0) if up else center
	var basis := Basis.looking_at(normal, Vector3.UP) if not up \
		else Basis.IDENTITY
	for i: int in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := out + (basis * Vector3(cos(a0), 0, sin(a0))) * r
		var p1 := out + (basis * Vector3(cos(a1), 0, sin(a1))) * r
		_tri(st, out, p0, p1)
		if double_sided:
			_tri(st, out, p1, p0)


## Купол (тулья кепки): пояс полусферы.
func _dome(st: SurfaceTool, center: Vector3, r: float, height: float,
		seg: int, rings: int, mat: StandardMaterial3D) -> void:
	st.set_material(mat)
	var prev: Array[Vector3] = []
	prev.resize(seg)
	for i: int in seg:
		var a := TAU * i / seg
		prev[i] = center + Vector3(cos(a) * r, 0, sin(a) * r)
	for ring: int in rings:
		var t0 := float(ring) / rings
		var t1 := float(ring + 1) / rings
		var r0 := r * cos(t0 * PI * 0.5)
		var r1 := r * cos(t1 * PI * 0.5)
		var y0 := height * sin(t0 * PI * 0.5)
		var y1 := height * sin(t1 * PI * 0.5)
		for i: int in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var next0 := center + Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var next1 := center + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			if ring == rings - 1:
				var apex := center + Vector3(0, height, 0)
				_tri(st, prev[i], prev[(i + 1) % seg], apex)
				if i == seg - 1:
					break
			else:
				_tri(st, prev[i], prev[(i + 1) % seg], next1)
				_tri(st, prev[i], next1, next0)
			prev[i] = next0
		if ring < rings - 1:
			for i: int in seg:
				var a := TAU * i / seg
				prev[i] = center + Vector3(cos(a) * r1, y1, sin(a) * r1)
	_disk(st, center, 0.0, r, seg, mat, true)  # дно купола


## Сектор кольца (козырёк): углы от -half до +half вокруг 0 (0 — прямо,
## +Z), внешний край ниже внутреннего — козырёк опущен.
func _sector(st: SurfaceTool, center: Vector3, r_in: float, r_out: float,
		half: float, thickness: float, seg: int,
		mat: StandardMaterial3D) -> void:
	st.set_material(mat)
	for i: int in seg:
		var a0 := -half + (2.0 * half) * i / seg
		var a1 := -half + (2.0 * half) * (i + 1) / seg
		var in0 := center + Vector3(sin(a0) * r_in, 0, cos(a0) * r_in)
		var in1 := center + Vector3(sin(a1) * r_in, 0, cos(a1) * r_in)
		var out0 := center + Vector3(sin(a0) * r_out, -thickness * 1.4,
			cos(a0) * r_out)
		var out1 := center + Vector3(sin(a1) * r_out, -thickness * 1.4,
			cos(a1) * r_out)
		_tri(st, in0, out0, out1)
		_tri(st, in0, out1, in1)
		# нижняя сторона козырька
		var below := Vector3(0, -thickness, 0)
		_tri(st, out0 + below, in0 + below, in1 + below)
		_tri(st, out0 + below, in1 + below, out1 + below)
		# толщина по кромке
		_tri(st, out0, out0 + below, out1 + below)
		_tri(st, out0, out1 + below, out1)


## Тонкая палка между точками (стебель веточки).
func _stick(st: SurfaceTool, from: Vector3, to: Vector3, r: float,
		mat: StandardMaterial3D) -> void:
	st.set_material(mat)
	var dir := (to - from).normalized()
	var side := dir.cross(Vector3.UP).normalized() * r
	var up := dir.cross(side).normalized() * r
	var a := from - side
	var b := from + side
	var c := to + side
	var d := to - side
	_tri(st, a, b, c); _tri(st, a, c, d)
	_tri(st, b, from + up, to + up); _tri(st, b, to + up, c)
	_tri(st, a, d, to - up); _tri(st, a, to - up, from - up)


## Плоский лист-ромб от точки в направлении dir (длина = dir.length()).
func _leaf(st: SurfaceTool, from: Vector3, dir: Vector3,
		mat: StandardMaterial3D, width: float = 0.018) -> void:
	st.set_material(mat)
	var length := dir.length()
	var d := dir.normalized()
	var side := d.cross(Vector3.UP).normalized() * width
	if side.length() < width * 0.5:
		side = d.cross(Vector3(1, 0, 0)).normalized() * width
	var tip := from + d * length
	var mid := from + d * (length * 0.4)
	_tri(st, from, mid + side, tip)
	_tri(st, from, tip, mid - side)
	# обратная сторона
	_tri(st, from, tip, mid + side)
	_tri(st, from, mid - side, tip)


# --- Сохранение ---

func _save_mesh(part: String, full: Array, lod: Array) -> void:
	for pair in [[part, full], [part + "_lod1", lod]]:
		var mesh := ArrayMesh.new()
		mesh.resource_name = pair[0]
		for st: SurfaceTool in pair[1]:
			if _tris_of(st) == 0:  # пустой SurfaceTool (декор без LOD)
				continue
			st.generate_normals()
			# Материал пишет только commit() (commit_to_arrays его терял —
			# уборы запекались белыми); раздельные вершины (плоские грани)
			# commit не индексирует — ARRAY_INDEX дописываем сами, как у
			# запечённых glb-мешей (тесты считают трисы через ARRAY_INDEX).
			var baked := ArrayMesh.new()
			st.commit(baked)
			var arrays := baked.surface_get_arrays(0)
			var index := PackedInt32Array()
			index.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			for i: int in index.size():
				index[i] = i
			arrays[Mesh.ARRAY_INDEX] = index
			var surface := mesh.get_surface_count()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(surface, baked.surface_get_material(0))
		ResourceSaver.save(mesh, "%s/%s.res" % [MESH_DIR, pair[0]])


func _tris(list: Array) -> int:
	var total := 0
	for st: SurfaceTool in list:
		total += _tris_of(st)
	return total


func _tris_of(st: SurfaceTool) -> int:
	# Геометрия не индексируется: треугольник = 3 вершины.
	var vertices := st.commit_to_arrays()[Mesh.ARRAY_VERTEX] as PackedVector3Array
	return vertices.size() / 3
