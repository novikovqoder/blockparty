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

## Срез тела (Д4) — «по одежде», не плоскостью: вершина кожи удаляется,
## только если она гарантированно закрыта — на внутренней стороне ткани
## и дальше HIDE_RIM_CLEAR от открытых кантов — и так в КАЖДОМ наряде
## (Peasant и Ranger). Всё, что выступает из одежды или стоит у кромки,
## остаётся целиком: одежда MCO построена на своём манекене, тело UBC в
## плечах/груди местами шире — плоскостной срез проходил по «торчащей»
## зоне и оставлял на плечах открытые края-дыры. Край среза по этому
## правилу всегда под тканью и не виден. Прежний весовой срез
## (Head/neck_01 ≥0.5) оставлял край над воротом (низ 1.535 при вороте
## 1.474) — сквозь вырез было видно «насквозь».
const HIDE_DEPTH_MIN: float = 0.008
## Запас от проекции вершины до открытого канта ткани (ворот, проймы,
## манжеты; у самой кромки кожа видна и остаётся).
const HIDE_RIM_CLEAR: float = 0.012
## Подгонка топа (Д4): тело UBC в груди/плечах шире манекена MCO, топ
## прилегает вплотную и не может закрыть кожу срезом. Топ подгоняется —
## вершины ткани сдвигаются по своим нормалям до равномерного зазора
## CLOTH_CLEAR до торса (зазор > HIDE_DEPTH_MIN — срез получает запас).
## Смещения сглаживаются (FIT_SMOOTH_PASSES с затуханием FIT_SMOOTH_DECAY
## — локальная шишка расплывается в плавный баллон), кап CLOTH_INFLATE_MAX.
## Подгоняются только топы: рукава, штаны и обувь сидят на коже MCO —
## сдвиг разъединит манжеты и голенища. Зазор меряется до торса без
## конечностей — проймы не раздуваются вокруг рук; у кантов топа
## нарастание от соседей гасится (ворот/пройма не расходятся с шеей и
## рукавом).
const CLOTH_CLEAR: float = 0.012
const CLOTH_INFLATE_MAX: float = 0.04
const FIT_SMOOTH_PASSES: int = 3
const FIT_SMOOTH_DECAY: float = 0.55
## Перенос весов (Д4): MCO шьёт одежду по своим весовым полям (топ Ranger
## взвешен на clavicle_l/r), кожа UBC — по своим (spine_*); при махе руки
## ткань груди уезжала от кожи до 72 мм. На ткань ТОПА переносятся веса
## ближайшей точки торса без цепочек рук (барицентрическая смесь, топ-4;
## ноги в индексе остаются — подол peasant клеится на бёдра, как шьются
## юбки), на РУКАВА — веса ближайшей вершины кожи рук своего пака (bind
## совпадает точно; авторское поле MCO шило рукав почти жёстко на плечо
## и при взмахе отставало от руки на 30 мм). Штаны/обувь/капюшон весов
## не меняют: со своей кожей MCO они делят одно авторское поле. Скин
## топа остаётся MCO: его бинды пересаживают геометрию на скелет UBC
## (ресты различаются до 24 мм), bind_bone у всех скинов identity —
## слоты костей совместимы без ремапа.
const TRANSFER_BONES: int = 4

## Ячейка сетки поиска ткани для среза (м).
const HIDE_CELL: float = 0.05
## Максимальный суммарный вес вершины на цепочках конечностей: руки и ноги
## ведут свои части (arms_* со своей кожей MCO, legs_*), в head-часть они
## не входят вовсе — иначе куски UBC-конечностей торчат из одежды в позах
## (замер: до 75 мм). Дельтоиды уходят вместе с рукой — пройму прикрывает
## кожа части arms.
const LIMB_WEIGHT_MAX: float = 0.01

## Целевые треугольники ближних вариантов (LOD — половина): худшая
## комбинация (Ranger + капюшон + пышная причёска) остаётся в бюджете
## ~13–20 тыс. на игрока (раздел «Этап П5.8» SPEC). Шаг децимации
## грубый (~50 %/18 %/4 %), поэтому берётся LOD, ближайший к цели.
const TOP_TARGET: int = 3700
const ARMS_TARGET: int = 3900
const ARMS_F_RANGER_TARGET: int = 5500  # жен. руки Ranger со встроенными наручами
const BOOTS_TARGET: int = 2900
const HOOD_TARGET: int = 1800
const HEAD_TARGET: int = 1700
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
# Статистика Д4 за текущий пол: подгонка топов и перенос весов.
var _fit_max: float = 0.0
var _fit_moved: int = 0
var _fit_total: int = 0
var _wt_missing: int = 0
var _wt_total: int = 0


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
			# Внутренняя сторона ткани видна у ворота, рукавов, капюшона и
			# под подолом (Д4): без этого взгляд внутрь ворот проходил
			# сквозь дальнюю стенку «насквозь» (backface culling).
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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

	var body := _collect_body(root)
	# Индексы тела (bind-позы): подгонка топа — до торса без конечностей;
	# веса топа — барицентрическая смесь по торсу без цепочек рук (с
	# ногами). Замеры П5.8 Д4 (probe_body_fit, 61 поза × 4 комбинации):
	# смесь держит выезды кожи ≤17.2 мм, а перенос ближайшей вершиной
	# (и по торсу, и по полному телу) прилипал к одной «не той» вершине
	# у ворота/пройм и уносил ткань до 63.7 мм в Sprint — сглаженная
	# смесь устойчивее на стыке зон влияния разных костей.
	var fit_body := _body_index(body.body, skeleton,
		["upperarm_l", "upperarm_r", "thigh_l", "thigh_r"], false)
	var torso_wt := _body_index(body.body, skeleton,
		["upperarm_l", "upperarm_r"], true)

	# Наряды грузятся по одному разу: поверхности топа подгоняются, все
	# поверхности получают веса тела — и в ЭТУ ЖЕ геометрию режется голова,
	# и она же сохраняется (раньше часть грузилась дважды и раздувалась
	# независимо — срез и меш могли разойтись).
	var outfits := {}
	for outfit in OUTFITS:
		var by_slot := {}
		for slot in ["top", "arms", "legs", "feet", "hood"]:
			if slot == "hood" and outfit != "ranger":
				continue
			var arrays: Array = []
			var mats: Array[String] = []
			var skin: Skin = null
			var missing := false
			for path in _gender_files(gender, outfit, slot):
				var packed := _load_part(path)
				if packed.is_empty():
					missing = true
					break
				var part_mats: Array[String] = packed["mats"]
				for i: int in packed["arrays"].size():
					var arr := _stripped(packed["arrays"][i])
					var is_cloth: bool = MAT_MAP.has(part_mats[i]) \
						and String(MAT_MAP[part_mats[i]]).begins_with("cloth_")
					if slot == "top" and is_cloth:
						arr = _fit_cloth(arr, fit_body)
						arr = _transfer_weights(arr, torso_wt)
					arrays.append(arr)
					mats.append(part_mats[i])
				if skin == null:
					skin = packed["skin"]
			if not missing and not arrays.is_empty():
				if slot == "arms":
					arrays = _transfer_arms_weights(arrays, mats, skeleton)
				by_slot[slot] = {"arrays": arrays, "mats": mats, "skin": skin}
		outfits[outfit] = by_slot

	# Голова (срез «по одежде», Д4): всё, что гарантированно закрыто
	# одеждой каждого наряда, удаляется. Ткань ВСЕХ слотов накрывает кожу
	# (рукава глотают кольцо проймы, пояс штанов и голенища — таз и икры);
	# строгий запас (глубина+кант) — только у топа: его канты граничат с
	# видимой кожей ворота и подола, у прочих слотов видимой кожи нет.
	# Тест — в позе Idle (скиннингом, как в BodyFitCheck): bind-поза
	# держит руки в стороны, и кольцо проймы, закрытое в Idle рукавом,
	# оставалось жить — и протыкалось им в Jog на 47–83 мм.
	var hide_sets: Array = []
	for outfit in OUTFITS:
		var strict: Array = []
		var loose: Array = []
		var by_slot: Dictionary = outfits[outfit]
		for slot in ["top", "arms", "legs", "feet", "hood"]:
			if not by_slot.has(slot):
				continue
			var slot_data: Dictionary = by_slot[slot]
			var mats: Array[String] = slot_data["mats"]
			var slot_skin: Skin = slot_data["skin"]
			for i: int in mats.size():
				if MAT_MAP.has(mats[i]) \
						and String(MAT_MAP[mats[i]]).begins_with("cloth_"):
					var target := strict if slot == "top" else loose
					target.append({"arrays": (slot_data["arrays"] as Array)[i],
						"skin": slot_skin})
		hide_sets.append({"strict": strict, "loose": loose})
	_save_part("head_%s" % g, _cull_hidden(body.body, body.body_skin,
		hide_sets, skeleton), HEAD_TARGET, body.body_skin, body.body_mats)
	_save_part("eyes_%s" % g, body.eyes, EYES_TARGET, body.eyes_skin, body.eyes_mats)
	_save_part("brows_%s" % g, body.brows, BROWS_TARGET, body.brows_skin,
		body.brows_mats)

	# Одежда MCO по слотам — из кэша.
	for outfit in OUTFITS:
		var by_slot: Dictionary = outfits[outfit]
		for slot in ["top", "arms", "legs", "feet", "hood"]:
			if not by_slot.has(slot):
				continue
			var slot_data: Dictionary = by_slot[slot]
			_save_part("%s_%s_%s" % [slot, outfit, g], slot_data["arrays"],
				_slot_target(slot, gender, outfit), slot_data["skin"],
				slot_data["mats"])
	_reports.append("  Д4 %s: подгонка топов — макс %.1f мм, вершин %d из %d;"
		% [gender, _fit_max * 1000.0, _fit_moved, _fit_total]
		+ " веса — без тела %d из %d" % [_wt_missing, _wt_total])
	_fit_max = 0.0
	_fit_moved = 0
	_fit_total = 0
	_wt_missing = 0
	_wt_total = 0
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


## Срез тела «по одежде» (Д4, комментарий к HIDE_DEPTH_MIN): конечности
## уходят по весам (LIMB_WEIGHT_MAX), из оставшегося удаляются только
## вершины, скрытые в КАЖДОМ наряде — под топом строго (глубина+кант),
## под прочей тканью (рукава, пояс, голенища) — достаточно «внутри»:
## видимой кожи там нет, а fringe-кольца у их кантов машут с конечностями
## и протыкались тканью на 47–83 мм в Jog/Sprint. Тест скрытости идёт
## в позе Idle (см. _idle_pose): bind держит руки врозь, и кольцо
## проймы, закрытое опущенным рукавом, оставалось жить. Остаётся голова,
## шея и видимые части торса; край среза — под тканью.
func _cull_hidden(body_arrays: Array, body_skin: Skin,
		hide_sets: Array, skeleton: Skeleton3D) -> Array:
	var limb_bones := {}
	for bone_name: String in ["upperarm_l", "upperarm_r", "thigh_l", "thigh_r"]:
		var root_bone: int = skeleton.find_bone(bone_name)
		if root_bone >= 0:
			_bone_subtree(skeleton, root_bone, limb_bones)
	var pose := _idle_pose(skeleton)
	var gear_strict: Array = []
	var gear_loose: Array = []
	for sets: Dictionary in hide_sets:
		gear_strict.append(_hide_index(sets["strict"], true, pose))
		gear_loose.append(_hide_index(sets["loose"], false, pose))
	var out: Array = []
	var dropped := 0
	var total := 0
	for arrays in body_arrays:
		var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		var bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
		var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
		var vw: int = weights.size() / maxi(verts.size(), 1)
		var posed := _posed_verts(arrays, body_skin, pose)
		var drop_vert := PackedByteArray()
		drop_vert.resize(verts.size())
		for v: int in verts.size():
			total += 1
			var limb_w := 0.0
			for k: int in vw:
				if limb_bones.has(bones[v * vw + k]):
					limb_w += weights[v * vw + k]
			var hidden: bool = limb_w > LIMB_WEIGHT_MAX
			if not hidden:
				for h: int in gear_strict.size():
					if not (_hidden_in(posed[v], gear_strict[h], true) \
							or _hidden_in(posed[v], gear_loose[h], false)):
						hidden = false
						break
			drop_vert[v] = 1 if hidden else 0
			if hidden:
				dropped += 1
		var keep_indices := PackedInt32Array()
		for t: int in indices.size() / 3:
			var a: int = indices[t * 3]
			var b: int = indices[t * 3 + 1]
			var c: int = indices[t * 3 + 2]
			if not (drop_vert[a] and drop_vert[b] and drop_vert[c]):
				keep_indices.append_array(PackedInt32Array([a, b, c]))
		out.append(compact(arrays, keep_indices))
	_reports.append("  срез головы: удалено %d из %d вершин тела (%.0f%%)"
		% [dropped, total, 100.0 * dropped / maxf(total, 1)])
	return out


## Кость и все её потомки (рекурсивно) — цепочка конечности целиком.
func _bone_subtree(skeleton: Skeleton3D, bone: int, out: Dictionary) -> void:
	out[bone] = true
	for child: int in skeleton.get_bone_children(bone):
		_bone_subtree(skeleton, child, out)


## Глобальные позы костей в позе Idle (t=0): ротации из клипа anims_ubc,
## трансляции — рест, как в BodyFitCheck._clip_globals. Срез «по одежде»
## должен видеть персонажа так же, как игрок и чекер, а не в bind-позе
## с руками врозь.
func _idle_pose(skeleton: Skeleton3D) -> Array[Transform3D]:
	var lib := load("res://assets/third_party/quaternius.com/"
		+ "universal_animation_library/anims_ubc.res") as AnimationLibrary
	var anim := lib.get_animation(&"Idle") as Animation
	var tracks := {}
	for i: int in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var path := anim.track_get_path(i)
		tracks[str(path).get_slice(":", 1)] = i
	var out: Array[Transform3D] = []
	out.resize(skeleton.get_bone_count())
	for i: int in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(i)
		var q := rest.basis.get_rotation_quaternion()
		if tracks.has(skeleton.get_bone_name(i)):
			q = anim.track_get_key_value(tracks[skeleton.get_bone_name(i)], 0)
		var local := Transform3D(Basis(q), rest.origin)
		var parent: int = skeleton.get_bone_parent(i)
		out[i] = local if parent == -1 else out[parent] * local
	return out


## Вершины поверхности, скиннутые в позу (Σ w·(global·bind)·v, формула
## рендера, как BodyFitCheck._skinned). Веса у топа уже перенесены с тела,
## bind-позы берутся из скина самой поверхности.
func _posed_verts(arrays: Array, skin: Skin,
		pose: Array[Transform3D]) -> PackedVector3Array:
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
	var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
	var vw: int = weights.size() / maxi(verts.size(), 1)
	var bind := {}
	for i: int in skin.get_bind_count():
		bind[skin.get_bind_bone(i)] = skin.get_bind_pose(i)
	var out := PackedVector3Array()
	out.resize(verts.size())
	for v: int in verts.size():
		var acc := Vector3.ZERO
		var total := 0.0
		for k: int in vw:
			var w: float = weights[v * vw + k]
			if w <= 0.0:
				continue
			total += w
			var bone: int = bones[v * vw + k]
			acc += (pose[bone] * (bind[bone] as Transform3D)) * verts[v] * w
		out[v] = acc / maxf(total, 1e-06)
	return out


## Индекс наряда для проверки скрытости: вершины и треугольники ткани
## в позе Idle (скиннинг каждой поверхности), сетка по AABB и открытые
## канты (рёбра, встреченные один раз по объединению поверхностей
## набора). strict=false — канты не строятся (достаточно «внутри»,
## см. _cull_hidden).
func _hide_index(surfaces: Array, strict: bool,
		pose: Array[Transform3D]) -> Dictionary:
	var verts := PackedVector3Array()
	var tri := PackedInt32Array()
	for surface: Dictionary in surfaces:
		var arrays: Array = surface["arrays"]
		var base: int = verts.size()
		verts.append_array(_posed_verts(arrays, surface["skin"], pose))
		var idx := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		for t: int in idx.size() / 3:
			for k: int in 3:
				tri.append(base + idx[t * 3 + k])
	if not strict:
		return {"vert": verts, "tri": tri, "rim": PackedInt32Array(),
			"grid": _build_tri_grid(verts, tri), "strict": false}
	# Канты: ребро один раз по объединению поверхностей (позиционный ключ);
	# для проверки запаса нужны только вершины канта.
	var edge_count := {}
	for t: int in tri.size() / 3:
		for e: int in 3:
			var a := verts[tri[t * 3 + e]]
			var b := verts[tri[t * 3 + (e + 1) % 3]]
			edge_count[_edge_key(a, b)] = int(edge_count.get(_edge_key(a, b), 0)) + 1
	var rim_set := {}
	for t: int in tri.size() / 3:
		for e: int in 3:
			var ia: int = tri[t * 3 + e]
			var ib: int = tri[t * 3 + (e + 1) % 3]
			if edge_count[_edge_key(verts[ia], verts[ib])] == 1:
				rim_set[ia] = true
				rim_set[ib] = true
	var rim := PackedInt32Array()
	for v: int in rim_set.keys():
		rim.append(v)
	# Сетка CELL по AABB треугольников.
	var grid := _build_tri_grid(verts, tri)
	return {"vert": verts, "tri": tri, "rim": rim, "grid": grid}


## Сетка HIDE_CELL по AABB треугольников: ячейка → candidate-треугольники
## (общая для среза, подгонки и переноса весов).
func _build_tri_grid(verts: PackedVector3Array, tri: PackedInt32Array) -> Dictionary:
	var grid := {}
	for t: int in tri.size() / 3:
		var a := verts[tri[t * 3]]
		var b := verts[tri[t * 3 + 1]]
		var c := verts[tri[t * 3 + 2]]
		var mn := Vector3(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)),
			minf(a.z, minf(b.z, c.z)))
		var mx := Vector3(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)),
			maxf(a.z, maxf(b.z, c.z)))
		for x: int in range(int(floor(mn.x / HIDE_CELL)), int(floor(mx.x / HIDE_CELL)) + 1):
			for y: int in range(int(floor(mn.y / HIDE_CELL)), int(floor(mx.y / HIDE_CELL)) + 1):
				for z: int in range(int(floor(mn.z / HIDE_CELL)), int(floor(mx.z / HIDE_CELL)) + 1):
					var key: int = (x * 4096 + y) * 4096 + z
					if not grid.has(key):
						grid[key] = PackedInt32Array()
					var cell: PackedInt32Array = grid[key]
					cell.append(t)
					grid[key] = cell
	return grid


## Ключ ребра по квантованным координатам концов (порядок не важен).
func _edge_key(a: Vector3, b: Vector3) -> String:
	var ka := Vector3i(roundi(a.x * 10000), roundi(a.y * 10000),
		roundi(a.z * 10000))
	var kb := Vector3i(roundi(b.x * 10000), roundi(b.y * 10000),
		roundi(b.z * 10000))
	if kb < ka:
		var tmp := ka
		ka = kb
		kb = tmp
	return "%d|%d|%d|%d|%d|%d" % [ka.x, ka.y, ka.z, kb.x, kb.y, kb.z]


## Скрыта ли вершина в этом наряде: ближайший треугольник ткани найден
## (поиск расширяется, пока не встретится ткань), вершина на внутренней
## стороне; strict — ещё глубина и удалённость от кантов с запасом.
func _hidden_in(p: Vector3, gear: Dictionary, strict: bool) -> bool:
	var verts := gear["vert"] as PackedVector3Array
	var tri := gear["tri"] as PackedInt32Array
	var best_d := 1e9
	var best_t := -1
	var best_q := Vector3.ZERO
	for reach: float in [HIDE_CELL * 2.0, 0.25, 0.6]:
		for x: int in range(int(floor((p.x - reach) / HIDE_CELL)),
				int(floor((p.x + reach) / HIDE_CELL)) + 1):
			for y: int in range(int(floor((p.y - reach) / HIDE_CELL)),
					int(floor((p.y + reach) / HIDE_CELL)) + 1):
				for z: int in range(int(floor((p.z - reach) / HIDE_CELL)),
						int(floor((p.z + reach) / HIDE_CELL)) + 1):
					var key: int = (x * 4096 + y) * 4096 + z
					if not gear["grid"].has(key):
						continue
					for t: int in gear["grid"][key] as PackedInt32Array:
						var q := _closest_on_tri(p, verts[tri[t * 3]],
							verts[tri[t * 3 + 1]], verts[tri[t * 3 + 2]])
						var d := p.distance_to(q)
						if d < best_d:
							best_d = d
							best_t = t
							best_q = q
		if best_t >= 0:
			break
	if best_t < 0:
		return false
	var a := verts[tri[best_t * 3]]
	var b := verts[tri[best_t * 3 + 1]]
	var c := verts[tri[best_t * 3 + 2]]
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return false
	var side: float = (p - best_q).dot(n.normalized())
	# Наружу одежду держит нормаль треугольника: скрытая вершина — на
	# внутренней стороне.
	if side >= 0.0:
		return false
	if not strict:
		return true
	if best_d < HIDE_DEPTH_MIN:
		return false
	for r: int in (gear["rim"] as PackedInt32Array).size():
		if best_q.distance_to(verts[(gear["rim"] as PackedInt32Array)[r]]) \
				< HIDE_RIM_CLEAR:
			return false
	return true


## Ближайшая к точке точка треугольника (Ericson, Real-Time Collision
## Detection, разбор областей): независимый кламп барицентрических
## координат выводит точку из плоскости и занижает расстояние в разы.
func _closest_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1: float = ab.dot(ap)
	var d2: float = ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3: float = ab.dot(bp)
	var d4: float = ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc: float = d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5: float = ab.dot(cp)
	var d6: float = ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb: float = d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va: float = d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denom := 1.0 / (va + vb + vc)
	var v: float = vb * denom
	var w: float = vc * denom
	return a + ab * v + ac * w


# ---------------------------------------------------------------------------
# Подгонка топа и перенос весов (Д4)
# ---------------------------------------------------------------------------

## Индекс тела (bind-поза): вершины и треугольники; кости цепочек
## drop_names (по весам, как в _cull_hidden) выбрасываются — подгонка
## меряет зазор до торса (проймы не раздуваются вокруг рук), перенос
## весов топа берёт торс и ноги. with_weights — нормализованные веса
## вершин (stride TRANSFER_BONES) для переноса на ткань.
func _body_index(body_arrays: Array, skeleton: Skeleton3D,
		drop_names: Array, with_weights: bool) -> Dictionary:
	var drop_bones := {}
	for bone_name: String in drop_names:
		var root_bone: int = skeleton.find_bone(bone_name)
		if root_bone >= 0:
			_bone_subtree(skeleton, root_bone, drop_bones)
	var verts := PackedVector3Array()
	var tri := PackedInt32Array()
	var bones_out := PackedInt32Array()
	var weights_out := PackedFloat32Array()
	for arrays in body_arrays:
		var part_verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var idx := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		var bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
		var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
		var vw: int = weights.size() / maxi(part_verts.size(), 1)
		var base := verts.size()
		verts.append_array(part_verts)
		var drop := PackedByteArray()
		drop.resize(part_verts.size())
		for i: int in part_verts.size():
			var drop_w := 0.0
			for k: int in vw:
				if drop_bones.has(bones[i * vw + k]):
					drop_w += weights[i * vw + k]
			drop[i] = 1 if drop_w > LIMB_WEIGHT_MAX else 0
			if with_weights:
				var pairs: Array = []
				for k: int in vw:
					pairs.append([weights[i * vw + k], bones[i * vw + k]])
				pairs.sort_custom(func(x: Array, y: Array) -> bool:
					return x[0] > y[0])
				var total := 0.0
				for k: int in mini(TRANSFER_BONES, pairs.size()):
					total += pairs[k][0]
				for k: int in TRANSFER_BONES:
					if k < pairs.size() and total > 0.0:
						bones_out.append(pairs[k][1])
						weights_out.append(pairs[k][0] / total)
					else:
						bones_out.append(0)
						weights_out.append(0.0)
		for t: int in idx.size() / 3:
			var a: int = base + idx[t * 3]
			var b: int = base + idx[t * 3 + 1]
			var c: int = base + idx[t * 3 + 2]
			if not (drop[a] or drop[b] or drop[c]):
				tri.append_array(PackedInt32Array([a, b, c]))
	var out := {"vert": verts, "tri": tri,
		"grid": _build_tri_grid(verts, tri)}
	if with_weights:
		out["bones"] = bones_out
		out["weights"] = weights_out
	return out


## Ближайший треугольник индекса тела (расширяющийся поиск по сетке):
## {t, q, d} либо {}.
func _nearest_body_tri(p: Vector3, index: Dictionary) -> Dictionary:
	var verts := index["vert"] as PackedVector3Array
	var tri := index["tri"] as PackedInt32Array
	var best_d := 1e9
	var best_t := -1
	var best_q := Vector3.ZERO
	for reach: float in [HIDE_CELL * 2.0, 0.25, 0.6]:
		for x: int in range(int(floor((p.x - reach) / HIDE_CELL)),
				int(floor((p.x + reach) / HIDE_CELL)) + 1):
			for y: int in range(int(floor((p.y - reach) / HIDE_CELL)),
					int(floor((p.y + reach) / HIDE_CELL)) + 1):
				for z: int in range(int(floor((p.z - reach) / HIDE_CELL)),
						int(floor((p.z + reach) / HIDE_CELL)) + 1):
					var key: int = (x * 4096 + y) * 4096 + z
					if not index["grid"].has(key):
						continue
					for t: int in index["grid"][key] as PackedInt32Array:
						var q := _closest_on_tri(p, verts[tri[t * 3]],
							verts[tri[t * 3 + 1]], verts[tri[t * 3 + 2]])
						var d := p.distance_to(q)
						if d < best_d:
							best_d = d
							best_t = t
							best_q = q
		if best_t >= 0:
			break
	if best_t < 0:
		return {}
	return {"t": best_t, "q": best_q, "d": best_d}


## Подгонка топа (Д4, комментарий к CLOTH_CLEAR): вершины сдвигаются по
## своим нормалям до зазора CLOTH_CLEAR до торса, поле смещений
## сглаживается распространением на соседей с затуханием, у открытых
## кантов нарастание гасится (своё смещение — обычно ноль: кант дальше
## от торса, чем CLOTH_CLEAR).
func _fit_cloth(arrays: Array, fit_body: Dictionary) -> Array:
	var verts := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var norms := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var idx := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var body_verts := fit_body["vert"] as PackedVector3Array
	var body_tri := fit_body["tri"] as PackedInt32Array
	var needed := PackedFloat32Array()
	needed.resize(verts.size())
	for v: int in verts.size():
		var hit := _nearest_body_tri(verts[v], fit_body)
		if hit.is_empty():
			continue
		var t: int = hit["t"]
		var a := body_verts[body_tri[t * 3]]
		var b := body_verts[body_tri[t * 3 + 1]]
		var c := body_verts[body_tri[t * 3 + 2]]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			continue
		# Зазор вдоль нормали тела: >0 — ткань снаружи торса.
		var gap: float = (verts[v] - hit["q"]).dot(n.normalized())
		needed[v] = clampf(CLOTH_CLEAR - gap, 0.0, CLOTH_INFLATE_MAX)
	# Сглаживание: смещение соседа распространяется с затуханием, своё
	# смещение не уменьшается (зазор обязан держаться всюду).
	var neigh := _adjacency(idx, verts.size())
	var cur := needed.duplicate()
	for pass_i: int in FIT_SMOOTH_PASSES:
		var next := cur.duplicate()
		for v: int in verts.size():
			var m := 0.0
			for u: int in neigh[v] as PackedInt32Array:
				m = maxf(m, cur[u])
			next[v] = maxf(cur[v], m * FIT_SMOOTH_DECAY)
		cur = next
	for v: int in _rim_verts_of(idx):
		cur[v] = needed[v]
	var moved := 0
	for v: int in verts.size():
		if cur[v] > 0.0005:
			verts[v] += norms[v] * cur[v]
			moved += 1
		_fit_max = maxf(_fit_max, cur[v])
	_fit_moved += moved
	_fit_total += verts.size()
	var out := arrays.duplicate()
	out[Mesh.ARRAY_VERTEX] = verts
	return out


## Перенос весов тела на поверхность MCO-части (Д4, комментарий к
## TRANSFER_BONES): веса ближайшей точки тела, барицентрическая смесь,
## топ-4 с нормировкой. Дальше 0.6 м от тела (подолы, свисающие ремни)
## остаются исходные веса.
func _transfer_weights(arrays: Array, body: Dictionary) -> Array:
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var body_verts := body["vert"] as PackedVector3Array
	var body_tri := body["tri"] as PackedInt32Array
	var body_bones := body["bones"] as PackedInt32Array
	var body_weights := body["weights"] as PackedFloat32Array
	var src_bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
	var src_weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
	var vw: int = src_weights.size() / maxi(verts.size(), 1)
	var bones_out := PackedInt32Array()
	bones_out.resize(verts.size() * TRANSFER_BONES)
	var weights_out := PackedFloat32Array()
	weights_out.resize(verts.size() * TRANSFER_BONES)
	for v: int in verts.size():
		var hit := _nearest_body_tri(verts[v], body)
		var pairs: Array = []
		if hit.is_empty():
			_wt_missing += 1
			for k: int in vw:
				pairs.append([src_weights[v * vw + k], src_bones[v * vw + k]])
		else:
			var t: int = hit["t"]
			var bary := _bary(body_verts[body_tri[t * 3]],
				body_verts[body_tri[t * 3 + 1]], body_verts[body_tri[t * 3 + 2]],
				hit["q"])
			var acc := {}
			for k: int in 3:
				var gv: int = body_tri[t * 3 + k]
				for j: int in TRANSFER_BONES:
					var w: float = body_weights[gv * TRANSFER_BONES + j] * bary[k]
					if w <= 0.0:
						continue
					var bone: int = body_bones[gv * TRANSFER_BONES + j]
					acc[bone] = float(acc.get(bone, 0.0)) + w
			for bone: int in acc.keys():
				pairs.append([acc[bone], bone])
		pairs.sort_custom(func(x: Array, y: Array) -> bool:
			return x[0] > y[0])
		var total := 0.0
		for k: int in mini(TRANSFER_BONES, pairs.size()):
			total += pairs[k][0]
		for k: int in TRANSFER_BONES:
			if k < pairs.size() and total > 0.0:
				bones_out[v * TRANSFER_BONES + k] = pairs[k][1]
				weights_out[v * TRANSFER_BONES + k] = pairs[k][0] / total
	_wt_total += verts.size()
	var out := arrays.duplicate()
	out[Mesh.ARRAY_BONES] = bones_out
	out[Mesh.ARRAY_WEIGHTS] = weights_out
	return out


## Перенос весов на ткань РУКАВОВ (Д4): MCO шьёт рукава почти жёстко на
## плечо (замер: lowerarm 0.07 при коже локтя 0.41), и при взмахе рукав
## отставал от руки на 30 мм. Рукав и кожа рук одного пака шьются на
## один манекен — bind-позиции совпадают точно, поэтому веса ближайшей
## точки кожи руки переносятся на ткань (как у топа, но источник — кожа
## рук СВОЕГО пака, без bind-расхождений UBC↔MCO). Штаны и обувь весов
## не меняют: там авторские веса и кожа ног согласованы.
func _transfer_arms_weights(arrays: Array, mats: Array[String],
		skeleton: Skeleton3D) -> Array:
	var skin_arrays: Array = []
	for i: int in mats.size():
		if MAT_MAP.has(mats[i]) \
				and String(MAT_MAP[mats[i]]).begins_with("skin_arms_"):
			skin_arrays.append(arrays[i])
	if skin_arrays.is_empty():
		return arrays
	var arm_wt := _body_index(skin_arrays, skeleton, [], true)
	for i: int in arrays.size():
		if MAT_MAP.has(mats[i]) \
				and String(MAT_MAP[mats[i]]).begins_with("cloth_"):
			arrays[i] = _transfer_weights_nearest(arrays[i], arm_wt)
	return arrays


## Перенос весов «по ближайшей вершине» (рукава): барицентрическая смесь
## из _transfer_weights размывает весовое поле — доля lowerarm у ткани
## выходила 0.54 против 0.41 у кожи, и шов расходился на 21.7 мм в
## Wave_Hand. Кожа рук и рукав одного пака в bind совпадают точно, поэтому
## вершина ткани берёт веса БЛИЖАЙШЕЙ вершины кожи как есть — поле
## сохраняется без размывания (для топа так нельзя: bind UBC↔MCO
## расходится до 24 мм, там смесь сглаживает).
func _transfer_weights_nearest(arrays: Array, body: Dictionary) -> Array:
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var body_verts := body["vert"] as PackedVector3Array
	var body_bones := body["bones"] as PackedInt32Array
	var body_weights := body["weights"] as PackedFloat32Array
	var src_bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
	var src_weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
	var vw: int = src_weights.size() / maxi(verts.size(), 1)
	var cell := 0.02
	var vgrid := {}
	for i: int in body_verts.size():
		var key: int = _vert_cell(body_verts[i], cell)
		if not vgrid.has(key):
			vgrid[key] = PackedInt32Array()
		var bucket: PackedInt32Array = vgrid[key]
		bucket.append(i)
		vgrid[key] = bucket
	var bones_out := PackedInt32Array()
	bones_out.resize(verts.size() * TRANSFER_BONES)
	var weights_out := PackedFloat32Array()
	weights_out.resize(verts.size() * TRANSFER_BONES)
	for v: int in verts.size():
		var best := -1
		var best_d := 1e9
		for reach: float in [cell * 3.0, 0.2, 0.6]:
			for x: int in range(int(floor((verts[v].x - reach) / cell)),
					int(floor((verts[v].x + reach) / cell)) + 1):
				for y: int in range(int(floor((verts[v].y - reach) / cell)),
						int(floor((verts[v].y + reach) / cell)) + 1):
					for z: int in range(int(floor((verts[v].z - reach) / cell)),
							int(floor((verts[v].z + reach) / cell)) + 1):
						var key: int = (x * 4096 + y) * 4096 + z
						if not vgrid.has(key):
							continue
						for i: int in vgrid[key] as PackedInt32Array:
							var d := verts[v].distance_to(body_verts[i])
							if d < best_d:
								best_d = d
								best = i
			if best >= 0:
				break
		var pairs: Array = []
		if best < 0:
			_wt_missing += 1
			for k: int in vw:
				pairs.append([src_weights[v * vw + k], src_bones[v * vw + k]])
		else:
			for j: int in TRANSFER_BONES:
				var w: float = body_weights[best * TRANSFER_BONES + j]
				if w > 0.0:
					pairs.append([w, body_bones[best * TRANSFER_BONES + j]])
		pairs.sort_custom(func(x: Array, y: Array) -> bool:
			return x[0] > y[0])
		var total := 0.0
		for k: int in mini(TRANSFER_BONES, pairs.size()):
			total += pairs[k][0]
		for k: int in TRANSFER_BONES:
			if k < pairs.size() and total > 0.0:
				bones_out[v * TRANSFER_BONES + k] = pairs[k][1]
				weights_out[v * TRANSFER_BONES + k] = pairs[k][0] / total
	_wt_total += verts.size()
	var out := arrays.duplicate()
	out[Mesh.ARRAY_BONES] = bones_out
	out[Mesh.ARRAY_WEIGHTS] = weights_out
	return out


## Ключ ячейки сетки для точки (перенос весов по ближайшей вершине).
func _vert_cell(p: Vector3, cell: float) -> int:
	return (int(floor(p.x / cell)) * 4096 + int(floor(p.y / cell))) * 4096 \
		+ int(floor(p.z / cell))


## Барицентрические координаты точки p в треугольнике abc.
func _bary(a: Vector3, b: Vector3, c: Vector3, p: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d00 := ab.dot(ab)
	var d01 := ab.dot(ac)
	var d11 := ac.dot(ac)
	var d20 := ap.dot(ab)
	var d21 := ap.dot(ac)
	var den := d00 * d11 - d01 * d01
	if absf(den) < 1e-12:
		return Vector3(1.0, 0.0, 0.0)
	var v: float = (d11 * d20 - d01 * d21) / den
	var w: float = (d00 * d21 - d01 * d20) / den
	return Vector3(1.0 - v - w, v, w)


## Соседство вершин по рёбрам треугольников.
func _adjacency(idx: PackedInt32Array, count: int) -> Array:
	var lists: Array = []
	lists.resize(count)
	for i: int in count:
		lists[i] = []
	for t: int in idx.size() / 3:
		for e: int in 3:
			var a: int = idx[t * 3 + e]
			var b: int = idx[t * 3 + (e + 1) % 3]
			(lists[a] as Array).append(b)
			(lists[b] as Array).append(a)
	var out: Array = []
	out.resize(count)
	for i: int in count:
		var packed := PackedInt32Array()
		for u: int in lists[i] as Array:
			packed.append(u)
		out[i] = packed
	return out


## Вершины открытых кантов поверхности (рёбра одного треугольника,
## соединение по индексам).
func _rim_verts_of(idx: PackedInt32Array) -> PackedInt32Array:
	var count := {}
	for t: int in idx.size() / 3:
		for e: int in 3:
			var a: int = idx[t * 3 + e]
			var b: int = idx[t * 3 + (e + 1) % 3]
			var key: int = mini(a, b) * 4294967296 + maxi(a, b)
			count[key] = int(count.get(key, 0)) + 1
	var rim := {}
	for t: int in idx.size() / 3:
		for e: int in 3:
			var a: int = idx[t * 3 + e]
			var b: int = idx[t * 3 + (e + 1) % 3]
			var key: int = mini(a, b) * 4294967296 + maxi(a, b)
			if count[key] == 1:
				rim[a] = true
				rim[b] = true
	var out := PackedInt32Array()
	for v: int in rim.keys():
		out.append(v)
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
			# skeleton-путь обязателен: у созданного кодом MeshInstance3D он
			# пуст, скелет не резолвится и скиннинг не включается — меши
			# рендерятся байнд-позой (T-pose) при живом скелете. Меш — ребёнок
			# Skeleton3D, путь «..» и есть скелет (возврат П5.8, фикс).
			mi.skeleton = ^".."
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
