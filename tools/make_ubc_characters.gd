# Запекание персонажей П5.8 из CC0-паков Quaternius (лицензии CC0 —
# assets/third_party/LICENSES.md): Universal Base Characters (Standard)
# даёт скелет 65 костей, срез «голова+шея», глаза и брови; Modular
# Character Outfits (Standard) — модульную одежду (верх/руки/низ/обувь/
# капюшон). Ридми MCO: под одеждой нужна только голова базовой модели —
# остальное тело удаляется (просвечивания, лишние полигоны), пропорции
# одетого персонажа задаёт одежда. Выход:
#   assets/third_party/quaternius.com/universal_base_characters/baked/
#     textures/ — карты материалов (кожа обесцвечена под тонирование)
#     materials/ — StandardMaterial3D по именам материалов glTF
#     meshes/ — меши .res + _lod1.res + _skin.res, поверхности уже
#       с материалами (руки с открытыми участками несут «кожу»)
#     ubc_male.res / ubc_female.res — PackedScene: скелет + все части
#       (visible=false) + точки крепления (кисти, спина).
# Кожа обесцвечивается в яркость: палитра оттенков кожи — простое
# умножение albedo (тон + детали затенения), один и тот же приём для
# головы (Superhero) и открытых рук (Regular).
# Конвейер (каждый шаг — отдельный запуск):
#   godot --headless -s tools/make_ubc_characters.gd -- textures
#   godot --headless --import --path .        # .import для новых png
#   godot --headless -s tools/make_ubc_characters.gd -- meshes
# Анимации — UAL на риге UBC (часть C), отдельным шагом.
extends SceneTree

const UBC := ".downloads/ubc/Universal Base Characters[Standard]"
const MCO := ".downloads/mco/Modular Character Outfits - Fantasy[Standard]" \
	+ "/Exports/glTF (Godot-Unreal)"
const HAIR_DIR := UBC + "/Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)"
const BODIES := UBC + "/Base Characters/Godot - UE"
const PARTS := MCO + "/Modular Parts"

const OUT_UBC := "res://assets/third_party/quaternius.com/universal_base_characters"
const BAKED := OUT_UBC + "/baked"
const TEX_DIR := BAKED + "/textures"
const MAT_DIR := BAKED + "/materials"
const MESH_DIR := BAKED + "/meshes"

## Кости среза головы: всё ниже закрыто одеждой MCO.
const HEAD_BONES: PackedStringArray = ["Head", "neck_01"]
const HEAD_WEIGHT: float = 0.5

## Целевые треугольники ближних вариантов (LOD — половина): худшая
## комбинация (Ranger + капюшон + пышная причёска) остаётся в бюджете
## ~13–20 тыс. на игрока (раздел «Этап П5.8» SPEC). Шаг децимации
## грубый (~50 %/18 %/4 %), поэтому берётся LOD, ближайший к цели.
const TOP_TARGET: int = 3700
const ARMS_TARGET: int = 3900
const ARMS_F_RANGER_TARGET: int = 5500  # жен. руки Ranger со встроенными наручами
const BOOTS_TARGET: int = 2900
const HOOD_TARGET: int = 1800
const HEAD_TARGET: int = 1800
const HAIR_TARGET: int = 2000
const EYES_TARGET: int = 400
const BROWS_TARGET: int = 480

const OUTFITS: PackedStringArray = ["peasant", "ranger"]
const HAIRS: PackedStringArray = ["Long", "Buns", "Buzzed", "BuzzedFemale",
	"SimpleParted", "Beard"]

## Текстуры паков → файлы в baked/textures: источник, выход, максимальная
## сторона, обесцветить (кожа красится палитрой умножением albedo).
const TEX_SOURCES: Array[Array] = [
	[BODIES + "/T_Superhero_Male_Dark.png", "skin_head_m", 2048, true],
	[BODIES + "/T_Superhero_Male_Normal.png", "skin_head_m_nrm", 2048, false],
	[BODIES + "/T_Superhero_Male_Roughness.png", "skin_head_m_rgh", 1024, false],
	[BODIES + "/T_Superhero_Female_Dark_BaseColor.png", "skin_head_f", 2048, true],
	[BODIES + "/T_Superhero_Female_Normal.png", "skin_head_f_nrm", 2048, false],
	[BODIES + "/T_Superhero_Female_Roughness.png", "skin_head_f_rgh", 1024, false],
	[BODIES + "/T_Eye_Brown.png", "eyes", 1024, false],
	[BODIES + "/T_Eye_Normal.png", "eyes_nrm", 1024, false],
	[HAIR_DIR + "/T_Hair_1_BaseColor.png", "hair_1", 1024, false],
	[HAIR_DIR + "/T_Hair_1_Normal.png", "hair_1_nrm", 1024, false],
	[HAIR_DIR + "/T_Hair_2_BaseColor.png", "hair_2", 1024, false],
	[HAIR_DIR + "/T_Hair_2_Normal.png", "hair_2_nrm", 1024, false],
	[PARTS + "/T_Regular_Male_Dark_BaseColor.png", "skin_arms_m", 1024, true],
	[PARTS + "/T_Regular_Male_Normal.png", "skin_arms_m_nrm", 1024, false],
	[PARTS + "/T_Regular_Male_Roughness.png", "skin_arms_m_rgh", 1024, false],
	[PARTS + "/T_Regular_Female_Dark_BaseColor.png", "skin_arms_f", 1024, true],
	[PARTS + "/T_Regular_Female_Normal.png", "skin_arms_f_nrm", 1024, false],
	[PARTS + "/T_Regular_Female_Roughness.png", "skin_arms_f_rgh", 1024, false],
	[PARTS + "/T_Peasant_BaseColor.png", "cloth_peasant", 2048, false],
	[PARTS + "/T_Peasant_Normal.png", "cloth_peasant_nrm", 2048, false],
	[PARTS + "/T_Peasant_ORM.png", "cloth_peasant_orm", 2048, false],
	[PARTS + "/T_Ranger_BaseColor.png", "cloth_ranger", 2048, false],
	[PARTS + "/T_Ranger_Normal.png", "cloth_ranger_nrm", 2048, false],
	[PARTS + "/T_Ranger_ORM.png", "cloth_ranger_orm", 2048, false],
]

## Имя материала glTF → материал baked/materials. Рантайм различает
## категории по префиксу имени (skin_*/hair_*/eyes/cloth_*): палитры
## тонируют кожу, волосы и брови, цвет игрока — только одежду.
const MAT_MAP: Dictionary = {
	"MI_Superhero_Male": "skin_head_m",
	"MI_Superhero_Female": "skin_head_f",
	"MI_Regular_Male": "skin_arms_m",
	"MI_Regular_Female": "skin_arms_f",
	"MI_Eyes": "eyes",
	"MI_Hair_1": "hair_1",
	"MI_Hair_2": "hair_2",
	"MI_Peasant": "cloth_peasant",
	"MI_Ranger": "cloth_ranger",
}

var _reports: PackedStringArray = []


func _init() -> void:
	await create_timer(0.01).timeout
	var args := OS.get_cmdline_user_args()
	var step: String = args[0] if not args.is_empty() else "meshes"
	var started := Time.get_ticks_msec()
	match step:
		"textures":
			DirAccess.make_dir_recursive_absolute(
				ProjectSettings.globalize_path(TEX_DIR))
			_bake_textures()
		"meshes":
			DirAccess.make_dir_recursive_absolute(
				ProjectSettings.globalize_path(MESH_DIR))
			DirAccess.make_dir_recursive_absolute(
				ProjectSettings.globalize_path(MAT_DIR))
			_bake_materials()
			_bake_meshes()
		_:
			push_error("шаг неизвестен: " + step)
	if not _reports.is_empty():
		print("\n".join(_reports))
	print("готово (%.1f с)" % [float(Time.get_ticks_msec() - started) / 1000.0])
	quit(0)


# ---------------------------------------------------------------------------
# Текстуры
# ---------------------------------------------------------------------------

func _bake_textures() -> void:
	for row: Array in TEX_SOURCES:
		var img := Image.load_from_file(row[0]) as Image
		if img == null:
			push_error("не читается текстура " + row[0])
			continue
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var side: int = maxi(img.get_width(), img.get_height())
		if side > row[2]:
			var k: float = float(row[2]) / float(side)
			img.resize(maxi(1, roundi(img.get_width() * k)),
				maxi(1, roundi(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
		if row[3]:
			_desaturate(img)
		var out := "%s/%s.png" % [TEX_DIR, row[1]]
		img.save_png(out)
		_reports.append("  %-22s %dx%d" % [row[1], img.get_width(), img.get_height()])


## Кожа → яркость: тон задаёт палитра рантайма (albedo_color × текстура),
## детали затенения остаются. Губы/тени различаются светлотой — читаются
## и после перекраски.
func _desaturate(img: Image) -> void:
	for y: int in img.get_height():
		for x: int in img.get_width():
			var c := img.get_pixel(x, y)
			var l := c.get_luminance()
			img.set_pixel(x, y, Color(l, l, l, c.a))


# ---------------------------------------------------------------------------
# Материалы
# ---------------------------------------------------------------------------

func _bake_materials() -> void:
	for mat_name: String in MAT_MAP.values():
		_bake_material(mat_name)


func _bake_material(mat_name: String) -> void:
	var mat := StandardMaterial3D.new()
	mat.resource_name = mat_name
	match mat_name:
		"skin_head_m", "skin_head_f", "skin_arms_m", "skin_arms_f":
			_fill_surface_material(mat, mat_name, true)
		"hair_1", "hair_2":
			_fill_surface_material(mat, mat_name, false)
			mat.roughness = 0.62
		"eyes":
			_fill_surface_material(mat, mat_name, false)
			mat.roughness = 0.2
		"cloth_peasant", "cloth_ranger":
			_fill_cloth_material(mat, mat_name)
	var err := ResourceSaver.save(mat, "%s/%s.res" % [MAT_DIR, mat_name])
	_reports.append("  материал %-16s err %d" % [mat_name, err])


## Кожа/глаза/волосы: альбедо + нормаль + отдельная карта шероховатости
## (УБЦ кладёт её отдельным файлом, а не в ORM).
func _fill_surface_material(mat: StandardMaterial3D, mat_name: String,
		is_skin: bool) -> void:
	mat.albedo_texture = _tex(mat_name)
	var nrm := _tex(mat_name + "_nrm")
	if nrm != null:
		mat.normal_enabled = true
		mat.normal_texture = nrm
	var rgh := _tex(mat_name + "_rgh")
	if rgh != null:
		mat.roughness_texture = rgh
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	if is_skin:
		mat.roughness = 1.0


## Одежда MCO: ORM-атлас (R — AO, G — шероховатость, B — металл).
func _fill_cloth_material(mat: StandardMaterial3D, mat_name: String) -> void:
	mat.albedo_texture = _tex(mat_name)
	var nrm := _tex(mat_name + "_nrm")
	if nrm != null:
		mat.normal_enabled = true
		mat.normal_texture = nrm
	var orm := _tex(mat_name + "_orm")
	if orm != null:
		mat.ao_enabled = true
		mat.ao_texture = orm
		mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.roughness_texture = orm
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		mat.metallic_texture = orm
		mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE


func _tex(name: String) -> Texture2D:
	if not ResourceLoader.exists("%s/%s.png" % [TEX_DIR, name]):
		return null
	return load("%s/%s.png" % [TEX_DIR, name]) as Texture2D


# ---------------------------------------------------------------------------
# Меши
# ---------------------------------------------------------------------------

func _bake_meshes() -> void:
	_bake_hair_meshes()
	for gender in ["male", "female"]:
		_bake_gender(gender)
	_report_budget()


func _part_file(prefix: String, piece: String) -> String:
	return PARTS + "/%s_%s.gltf" % [prefix, piece]


func _gender_files(gender: String, outfit: String, slot: String) -> Array:
	# Имена файлов MCO: Male_Peasant_Body, Female_Ranger_Feet,
	# Male_Ranger_Feet_Boots. Ремни и наручи — не отдельные файлы, а меши
	# внутри Body/Arms.gltf, _load_part собирает их вместе с прочими.
	var cap := "Male" if gender == "male" else "Female"
	var prefix := "%s_%s" % [cap, outfit.capitalize()]
	var files: Array = []
	match slot:
		"top":
			files = [_part_file(prefix, "Body")]
		"arms":
			files = [_part_file(prefix, "Arms")]
		"legs":
			files = [_part_file(prefix, "Legs")]
		"feet":
			files = [_part_file(prefix, "Feet_Boots" if outfit == "ranger" \
				and gender == "male" else "Feet")]
		"hood":
			files = [_part_file(prefix, "Head_Hood")]
	return files


func _slot_target(slot: String, gender: String, outfit: String) -> int:
	match slot:
		"top":
			return TOP_TARGET
		"arms":
			if gender == "female" and outfit == "ranger":
				return ARMS_F_RANGER_TARGET
			return ARMS_TARGET
		"feet":
			return BOOTS_TARGET
		"hood":
			return HOOD_TARGET
		_:
			return -1  # ноги и мелочь оставляем как есть


func _bake_gender(gender: String) -> void:
	var cap := "Male" if gender == "male" else "Female"
	var g := gender[0]
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var body_path := BODIES + "/Superhero_%s_FullBody.gltf" % cap
	if doc.append_from_file(body_path, state) != OK:
		push_error("не читается " + body_path)
		return
	var root := doc.generate_scene(state)
	var skeleton := _find_of(root, "Skeleton3D") as Skeleton3D
	var bone_ok := {}
	for bone in HEAD_BONES:
		bone_ok[skeleton.find_bone(bone)] = true

	# Голова (срез), глаза, брови — из FullBody; тело больше не нужно.
	var body := _collect_body(root)
	_save_part("head_%s" % g, _slice_head(body.body, bone_ok),
		HEAD_TARGET, body.body_skin, body.body_mats)
	_save_part("eyes_%s" % g, body.eyes, EYES_TARGET, body.eyes_skin, body.eyes_mats)
	_save_part("brows_%s" % g, body.brows, BROWS_TARGET, body.brows_skin,
		body.brows_mats)

	# Одежда MCO по слотам.
	for outfit in OUTFITS:
		for slot in ["top", "arms", "legs", "feet", "hood"]:
			if slot == "hood" and outfit != "ranger":
				continue
			var files := _gender_files(gender, outfit, slot)
			var arrays: Array = []
			var mats: Array[String] = []
			var skin: Skin = null
			var missing := false
			for path in files:
				var packed := _load_part(path)
				if packed.is_empty():
					missing = true
					break
				arrays.append_array(packed["arrays"])
				mats.append_array(packed["mats"])
				if skin == null:
					skin = packed["skin"]
			if missing or arrays.is_empty():
				continue
			_save_part("%s_%s_%s" % [slot, outfit, g], arrays,
				_slot_target(slot, gender, outfit), skin, mats)
	_build_gender_scene(gender, skeleton)
	root.free()


func _bake_hair_meshes() -> void:
	# Причёски универсальны: риг у паков общий (65 костей, проверено).
	for hair in HAIRS:
		var packed := _load_part(HAIR_DIR + "/Hair_%s.gltf" % hair)
		if packed.is_empty():
			continue
		var name := "hair_%s" % hair.to_snake_case()
		_save_part(name, packed["arrays"], HAIR_TARGET, packed["skin"],
			packed["mats"])


## Загрузить gltf части: поверхности (массивы вершин), имена материалов
## поверхностей и скин первой модели.
func _load_part(path: String) -> Dictionary:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("не читается " + path)
		return {}
	var root := doc.generate_scene(state)
	var arrays_list: Array = []
	var mats: Array[String] = []
	var skin: Skin = null
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for surface: int in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surface)
			if (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
				continue
			arrays_list.append(_stripped(arrays))
			var material := mi.mesh.surface_get_material(surface)
			mats.append(material.resource_name if material != null else "")
		if skin == null and mi.skin != null:
			skin = mi.skin
	root.free()
	if arrays_list.is_empty():
		push_error("нет поверхностей: " + path)
		return {}
	return {"arrays": arrays_list, "mats": mats, "skin": skin}


## Сохранить часть: ближний меш (децимация до target, если задан),
## LOD-копия (половина), скин; поверхности получают материалы по именам
## из glTF (руки несут «кожу» на открытых участках). Отчёт — одной строкой.
func _save_part(part_name: String, arrays_list: Array, target: int,
		skin: Skin, mats: Array[String]) -> void:
	var tris_before := 0
	var total := 0
	for arrays in arrays_list:
		total += _tris_of(arrays)
	tris_before = total
	var prepared: Array = []
	for arrays in arrays_list:
		var copy := _stripped(arrays)
		if target > 0:
			var share := float(_tris_of(arrays)) / maxf(total, 1)
			copy = _decimate(copy, maxi(24, roundi(float(target) * share)))
		prepared.append(copy)
	var mesh := ArrayMesh.new()
	mesh.resource_name = part_name
	for i: int in prepared.size():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, prepared[i])
		_assign_material(mesh, i, mats, part_name)
	var err := ResourceSaver.save(mesh, MESH_DIR + "/%s.res" % part_name)
	var lod_mesh := ArrayMesh.new()
	lod_mesh.resource_name = part_name + "_lod1"
	for i: int in prepared.size():
		var lod := _decimate(_stripped(prepared[i]), _tris_of(prepared[i]) / 2)
		lod_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, lod)
		_assign_material(lod_mesh, i, mats, part_name)
	ResourceSaver.save(lod_mesh, MESH_DIR + "/%s_lod1.res" % part_name)
	if skin != null:
		ResourceSaver.save(skin, MESH_DIR + "/%s_skin.res" % part_name)
	_reports.append("  %-20s %6d → %6d (+LOD %5d) err %d" % [
		part_name, tris_before, _mesh_tris(mesh), _mesh_tris(lod_mesh), err])


## Материал glTF-имени → ресурс baked/materials; пустое имя (срез) —
## категория по типу части.
func _assign_material(mesh: ArrayMesh, surface: int, mats: Array[String],
		part_name: String) -> void:
	var gltf_name: String = mats[surface] if surface < mats.size() else ""
	if gltf_name.is_empty() or not MAT_MAP.has(gltf_name):
		push_error("часть %s: материал поверхностей %d не отображён (%s)" % [
			part_name, surface, gltf_name])
		return
	var path := "%s/%s.res" % [MAT_DIR, MAT_MAP[gltf_name]]
	if not ResourceLoader.exists(path):
		push_error("нет материала " + path)
		return
	mesh.surface_set_material(surface, load(path) as Material)


# ---------------------------------------------------------------------------
# Срез головы
# ---------------------------------------------------------------------------

class BodyMeshes:
	var body: Array = []
	var body_skin: Skin = null
	var body_mats: Array[String] = []
	var eyes: Array = []
	var eyes_skin: Skin = null
	var eyes_mats: Array[String] = []
	var brows: Array = []
	var brows_skin: Skin = null
	var brows_mats: Array[String] = []


func _collect_body(root: Node3D) -> BodyMeshes:
	var out := BodyMeshes.new()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		# Женское тело называется Superhero_Female, мужское — SuperHero_Male:
		# сравнение регистронезависимо.
		var lower := String(mi.name).to_lower()
		var slot_name := ""
		if lower.begins_with("superhero"):
			slot_name = "body"
		elif lower == "eyes":
			slot_name = "eyes"
		elif lower.begins_with("eyebrows"):
			slot_name = "brows"
		else:
			continue
		var slot := out.body if slot_name == "body" \
			else out.eyes if slot_name == "eyes" else out.brows
		var slot_mats := out.body_mats if slot_name == "body" \
			else out.eyes_mats if slot_name == "eyes" else out.brows_mats
		for surface: int in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surface)
			var idx := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
			if idx == null or idx.is_empty():
				continue
			slot.append(_stripped(arrays))
			var material := mi.mesh.surface_get_material(surface)
			slot_mats.append(material.resource_name if material != null else "")
		if slot.size() > 0 and mi.skin != null:
			match slot_name:
				"body":
					out.body_skin = mi.skin
				"eyes":
					out.eyes_skin = mi.skin
				"brows":
					out.brows_skin = mi.skin
	return out


## Голова и шея: остаются треугольники, у которых ВСЕ вершины нагружены
## на Head/neck_01 (сумма весов ≥ HEAD_WEIGHT); вершины компактируются.
## Число весов на вершину берётся из самого массива (паки дают 4 или 8).
func _slice_head(body_arrays: Array, bone_ok: Dictionary) -> Array:
	var out: Array = []
	for arrays in body_arrays:
		var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		var bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
		var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
		var vw: int = weights.size() / verts.size()
		var keep_vert := PackedByteArray()
		keep_vert.resize(verts.size())
		for v: int in verts.size():
			var s := 0.0
			for k: int in vw:
				if bone_ok.has(bones[v * vw + k]):
					s += weights[v * vw + k]
			keep_vert[v] = 1 if s >= HEAD_WEIGHT else 0
		var keep_indices := PackedInt32Array()
		for t: int in indices.size() / 3:
			var a: int = indices[t * 3]
			var b: int = indices[t * 3 + 1]
			var c: int = indices[t * 3 + 2]
			if keep_vert[a] and keep_vert[b] and keep_vert[c]:
				keep_indices.append_array(PackedInt32Array([a, b, c]))
		out.append(compact(arrays, keep_indices))
	return out


# ---------------------------------------------------------------------------
# Децимация (meshoptimizer через ImporterMesh, приём из П5.7) и компакция
# ---------------------------------------------------------------------------

## Упростить поверхность до ~target треугольников: цикл проходов
## generate_lods (приём П5.7 — урезанная копия VERTEX/NORMAL/UV/INDEX,
## кости дециматору не передаются). Список LOD не содержит полного меша:
## уровень 0 — уже ~50 %, дальше примерно вдвое; на каждом проходе берётся
## набор индексов, БЛИЖАЙШИЙ к цели — в том числе чуть ниже неё (лучше
## потерять немного деталей, чем вылезти из бюджета персонажа). Выбранные
## индексы переносятся на полный массив компакцией — скининговые
## атрибуты сохраняются точно.
func _decimate(arrays: Array, target: int) -> Array:
	for pass_i: int in 6:
		var tris := _tris_of(arrays)
		if tris <= maxi(target, 24):
			break
		var probe: Array = []
		probe.resize(Mesh.ARRAY_MAX)
		probe[Mesh.ARRAY_VERTEX] = arrays[Mesh.ARRAY_VERTEX]
		probe[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
		probe[Mesh.ARRAY_TEX_UV] = arrays[Mesh.ARRAY_TEX_UV]
		probe[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, probe, [], {}, null, "")
		im.generate_lods(60.0, 25.0, [])
		var lod_count := im.get_surface_lod_count(0)
		if lod_count <= 0:
			break
		var best := PackedInt32Array()
		var best_diff := tris - target  # полный набор — стартовое отклонение
		for lod: int in range(0, lod_count):
			var cand := im.get_surface_lod_indices(0, lod)
			var diff := absi(cand.size() / 3 - target)
			if diff < best_diff and cand.size() / 3 >= 24:
				best = cand
				best_diff = diff
		if best.is_empty() or best.size() / 3 >= tris:
			break
		arrays = compact(arrays, best)
	return arrays


func _stripped(arrays: Array) -> Array:
	# материал в массивах не хранится (surface_get_material отдельно);
	# поверхности без индексного буфера (глаза/брови/причёски UBC)
	# получают последовательные индексы — децимации и компакции нужен
	# индексный буфер. CUSTOM0 у глаз/бровей Quaternius не кратен четырём
	# и ломает add_surface_from_arrays — красим их шейдером, атрибут
	# выбрасываем.
	var out := arrays.duplicate(true)
	for key: int in range(Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM3 + 1):
		if key < out.size() and out[key] != null:
			out[key] = null
	if out.size() <= Mesh.ARRAY_INDEX or out[Mesh.ARRAY_INDEX] == null:
		var verts: PackedVector3Array = out[Mesh.ARRAY_VERTEX]
		var idx := PackedInt32Array()
		idx.resize(verts.size())
		for i: int in verts.size():
			idx[i] = i
		out.resize(Mesh.ARRAY_INDEX + 1)
		out[Mesh.ARRAY_INDEX] = idx
	return out


## Пересобрать все атрибуты по подмножеству треугольников: вершины,
## нормали, UV/UV2, цвет, тангенты, кости и веса. Типы проверяются по
## факту; «четырёхкомпонентные» атрибуты (тангенты, кости, веса) имеют
## stride = размер / число вершин — у части поверхностей Quaternius
## 8 весов на вершину, а не 4.
func compact(arrays: Array, keep_indices: PackedInt32Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var remap := PackedInt32Array()
	remap.resize(verts.size())
	remap.fill(-1)
	var next := 0
	for i: int in keep_indices.size():
		var old: int = keep_indices[i]
		if remap[old] < 0:
			remap[old] = next
			next += 1
	var out := arrays.duplicate(true)
	for key: int in arrays.size():
		if arrays[key] == null:
			continue
		match typeof(arrays[key]):
			TYPE_PACKED_VECTOR3_ARRAY:
				_pack_v3(out, key, remap, next)  # вершины и нормали
			TYPE_PACKED_VECTOR2_ARRAY:
				_pack_v2(out, key, remap, next)
			TYPE_PACKED_COLOR_ARRAY:
				_pack_color(out, key, remap, next)
			TYPE_PACKED_FLOAT32_ARRAY:
				if key == Mesh.ARRAY_INDEX:
					continue
				_pack_strided_f(out, key, remap, next)
			TYPE_PACKED_INT32_ARRAY:
				if key == Mesh.ARRAY_INDEX:
					continue
				_pack_strided_i(out, key, remap, next)
	var idx := PackedInt32Array()
	idx.resize(keep_indices.size())
	for i: int in keep_indices.size():
		idx[i] = remap[keep_indices[i]]
	out[Mesh.ARRAY_INDEX] = idx
	return out


func _pack_v3(arrays: Array, key: int, remap: PackedInt32Array, count: int) -> void:
	var src: PackedVector3Array = arrays[key]
	var out := PackedVector3Array()
	out.resize(count)
	for i: int in src.size():
		if remap[i] >= 0:
			out[remap[i]] = src[i]
	arrays[key] = out


func _pack_v2(arrays: Array, key: int, remap: PackedInt32Array, count: int) -> void:
	var src: PackedVector2Array = arrays[key]
	var out := PackedVector2Array()
	out.resize(count)
	for i: int in src.size():
		if remap[i] >= 0:
			out[remap[i]] = src[i]
	arrays[key] = out


func _pack_color(arrays: Array, key: int, remap: PackedInt32Array, count: int) -> void:
	var src: PackedColorArray = arrays[key]
	var out := PackedColorArray()
	out.resize(count)
	for i: int in src.size():
		if remap[i] >= 0:
			out[remap[i]] = src[i]
	arrays[key] = out


func _pack_strided_f(arrays: Array, key: int, remap: PackedInt32Array,
		count: int) -> void:
	var src: PackedFloat32Array = arrays[key]
	var stride: int = src.size() / remap.size()
	var out := PackedFloat32Array()
	out.resize(count * stride)
	for i: int in remap.size():
		if remap[i] >= 0:
			for k: int in stride:
				out[remap[i] * stride + k] = src[i * stride + k]
	arrays[key] = out


func _pack_strided_i(arrays: Array, key: int, remap: PackedInt32Array,
		count: int) -> void:
	var src: PackedInt32Array = arrays[key]
	var stride: int = src.size() / remap.size()
	var out := PackedInt32Array()
	out.resize(count * stride)
	for i: int in remap.size():
		if remap[i] >= 0:
			for k: int in stride:
				out[remap[i] * stride + k] = src[i * stride + k]
	arrays[key] = out


# ---------------------------------------------------------------------------
# Сцены полов: скелет + все части + точки крепления
# ---------------------------------------------------------------------------

func _build_gender_scene(gender: String, skeleton: Skeleton3D) -> void:
	var armature := Node3D.new()
	armature.name = "Armature"
	var scene_root := Node3D.new()
	scene_root.name = "UbcRoot"
	scene_root.add_child(armature)
	armature.owner = scene_root
	skeleton.reparent(armature)
	skeleton.owner = scene_root
	# Точки крепления предметов (задел на бой после MVP): кисти и спина.
	for marker in [["HandL", "hand_l"], ["HandR", "hand_r"], ["Back", "spine_02"]]:
		var attach := BoneAttachment3D.new()
		attach.name = marker[0]
		attach.bone_name = marker[1]
		skeleton.add_child(attach)
		attach.owner = scene_root
	for part in _scene_parts(gender):
		var mesh := load(MESH_DIR + "/%s.res" % part) as ArrayMesh
		var lod := load(MESH_DIR + "/%s_lod1.res" % part) as ArrayMesh
		var skin := load(MESH_DIR + "/%s_skin.res" % part) as Skin
		if mesh == null or lod == null:
			push_error("нет ресурсов части %s" % part)
			continue
		for pair in [[part, mesh], [part + "_LOD", lod]]:
			var mi := MeshInstance3D.new()
			mi.name = pair[0]
			mi.mesh = pair[1]
			mi.skin = skin
			mi.visible = false
			skeleton.add_child(mi)
			mi.owner = scene_root
	var packed := PackedScene.new()
	packed.pack(scene_root)
	var err := ResourceSaver.save(packed, BAKED + "/ubc_%s.res" % gender)
	_reports.append("  сцена ubc_%s.tscn: err %d" % [gender, err])


## Части сцены пола: имена ресурсов .res (муж. m / жен. f).
func _scene_parts(gender: String) -> PackedStringArray:
	var g := gender[0]
	var out := PackedStringArray([
		"head_%s" % g, "eyes_%s" % g, "brows_%s" % g,
		"hair_long", "hair_buns", "hair_buzzed", "hair_buzzed_female",
		"hair_simple_parted", "hair_beard",
	])
	for outfit in OUTFITS:
		for slot in ["top", "arms", "legs", "feet"]:
			out.append("%s_%s_%s" % [slot, outfit, g])
	out.append("hood_ranger_%s" % g)
	return out


## Худшие комбинации бюджета: Ranger (руки с наручами, сапоги) + капюшон +
## самая тяжёлая причёска + голова/глаза/брови. Печатается в отчёт, чтобы
## видеть запас до 20 тыс. треугольников (SPEC, «Этап П5.8»).
func _report_budget() -> void:
	for gender: String in ["male", "female"]:
		var g := gender[0]
		var worst := {
			"top": "top_ranger_%s" % g, "arms": "arms_ranger_%s" % g,
			"legs": "legs_ranger_%s" % g, "feet": "feet_ranger_%s" % g,
			"hood": "hood_ranger_%s" % g, "hair": "hair_long",
			"head": "head_%s" % g, "eyes": "eyes_%s" % g,
			"brows": "brows_%s" % g,
		}
		var total := 0
		var missing := false
		for part: String in worst.values():
			var mesh := load(MESH_DIR + "/%s.res" % part) as ArrayMesh
			if mesh == null:
				missing = true
				break
			total += _mesh_tris(mesh)
		if not missing:
			_reports.append("  бюджет худшей комбинации (%s): %d трис" % [gender, total])


func _tris_of(arrays: Array) -> int:
	return (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3


func _mesh_tris(mesh: ArrayMesh) -> int:
	var tris := 0
	for surface: int in mesh.get_surface_count():
		tris += _tris_of(mesh.surface_get_arrays(surface))
	return tris


func _find_of(node: Node, classname: String) -> Node:
	if node.is_class(classname):
		return node
	for child in node.get_children():
		var found := _find_of(child, classname)
		if found != null:
			return found
	return null
