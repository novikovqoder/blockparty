# П12 «Земля» (SPEC 1.2): упаковка PBR-карт слоёв земли в ORM-текстуру
# R: AO, G: Roughness, B: Height(displacement) — три карты в одном файле,
# на слой земли остаётся 3 текстуры (diffuse + nor_gl + ORM). Исходники —
# локальная библиотека CC0-наборов (polyhaven/ambientcg, ~/blockparty/library),
# в git попадают только результаты: diffuse/nor_gl копируются как есть,
# ORM собирается из ao/rough/displacement попиксельно. Повторный запуск
# идемпотентен (перезаписывает те же файлы).
# Запуск:
#   godot --headless -s res://tools/make_orm_textures.gd       # файлы + ORM
#   godot --headless --import                                   # .import
#   godot --headless -s res://tools/make_orm_textures.gd -- --mips # мипы
#   godot --headless --import                                   # переприём
extends SceneTree

const LIBRARY: String = "blockparty/library"

## Копируемые карты цвета и нормалей: исходник в библиотеке → имя в проекте.
const COPY: Array = [
	["polyhaven/textures/forest_ground_05/forest_ground_05_diffuse_2k.jpg",
		"polyhaven.com/forest_ground_05/forest_ground_05_diffuse_2k.jpg"],
	["polyhaven/textures/forest_ground_05/forest_ground_05_nor_gl_2k.jpg",
		"polyhaven.com/forest_ground_05/forest_ground_05_nor_gl_2k.jpg"],
	["polyhaven/textures/leafy_grass/leafy_grass_diffuse_1k.jpg",
		"polyhaven.com/leafy_grass/leafy_grass_diffuse_1k.jpg"],
	["polyhaven/textures/leafy_grass/leafy_grass_nor_gl_1k.jpg",
		"polyhaven.com/leafy_grass/leafy_grass_nor_gl_1k.jpg"],
	["polyhaven/textures/mud_forest/mud_forest_diffuse_1k.jpg",
		"polyhaven.com/mud_forest/mud_forest_diffuse_1k.jpg"],
	["polyhaven/textures/mud_forest/mud_forest_nor_gl_1k.jpg",
		"polyhaven.com/mud_forest/mud_forest_nor_gl_1k.jpg"],
	["polyhaven/textures/rock_face_03/rock_face_03_diffuse_2k.jpg",
		"polyhaven.com/rock_face_03/rock_face_03_diffuse_2k.jpg"],
	["polyhaven/textures/rock_face_03/rock_face_03_nor_gl_2k.jpg",
		"polyhaven.com/rock_face_03/rock_face_03_nor_gl_2k.jpg"],
	["polyhaven/textures/rocky_trail/rocky_trail_diffuse_2k.jpg",
		"polyhaven.com/rocky_trail/rocky_trail_diffuse_2k.jpg"],
	["polyhaven/textures/rocky_trail/rocky_trail_nor_gl_2k.jpg",
		"polyhaven.com/rocky_trail/rocky_trail_nor_gl_2k.jpg"],
	["ambientcg/Moss/Moss001/Moss001_1K-JPG_Color.jpg",
		"ambientcg.com/Moss001/Moss001_1K-JPG_Color.jpg"],
	["ambientcg/Moss/Moss001/Moss001_1K-JPG_NormalGL.jpg",
		"ambientcg.com/Moss001/Moss001_1K-JPG_NormalGL.jpg"],
]

## ORM-наборы: ao/rough/disp (R/G/B) → результат в проекте.
const ORM: Array = [
	{
		"ao": "polyhaven/textures/forest_ground_05/forest_ground_05_ao_2k.jpg",
		"rough": "polyhaven/textures/forest_ground_05/forest_ground_05_rough_2k.jpg",
		"disp": "polyhaven/textures/forest_ground_05/forest_ground_05_displacement_2k.jpg",
		"out": "polyhaven.com/forest_ground_05/forest_ground_05_orm_2k.jpg",
	},
	{
		"ao": "polyhaven/textures/leafy_grass/leafy_grass_ao_1k.jpg",
		"rough": "polyhaven/textures/leafy_grass/leafy_grass_rough_1k.jpg",
		"disp": "polyhaven/textures/leafy_grass/leafy_grass_displacement_1k.jpg",
		"out": "polyhaven.com/leafy_grass/leafy_grass_orm_1k.jpg",
	},
	{
		"ao": "polyhaven/textures/mud_forest/mud_forest_ao_1k.jpg",
		"rough": "polyhaven/textures/mud_forest/mud_forest_rough_1k.jpg",
		"disp": "polyhaven/textures/mud_forest/mud_forest_displacement_1k.jpg",
		"out": "polyhaven.com/mud_forest/mud_forest_orm_1k.jpg",
	},
	{
		"ao": "polyhaven/textures/rock_face_03/rock_face_03_ao_2k.jpg",
		"rough": "polyhaven/textures/rock_face_03/rock_face_03_rough_2k.jpg",
		"disp": "polyhaven/textures/rock_face_03/rock_face_03_displacement_2k.jpg",
		"out": "polyhaven.com/rock_face_03/rock_face_03_orm_2k.jpg",
	},
	{
		"ao": "polyhaven/textures/rocky_trail/rocky_trail_ao_2k.jpg",
		"rough": "polyhaven/textures/rocky_trail/rocky_trail_rough_2k.jpg",
		"disp": "polyhaven/textures/rocky_trail/rocky_trail_displacement_2k.jpg",
		"out": "polyhaven.com/rocky_trail/rocky_trail_orm_2k.jpg",
	},
	{
		"ao": "ambientcg/Moss/Moss001/Moss001_1K-JPG_AmbientOcclusion.jpg",
		"rough": "ambientcg/Moss/Moss001/Moss001_1K-JPG_Roughness.jpg",
		"disp": "ambientcg/Moss/Moss001/Moss001_1K-JPG_Displacement.jpg",
		"out": "ambientcg.com/Moss001/Moss001_1K-JPG_ORM.jpg",
	},
]

const OUT_ROOT: String = "res://assets/third_party"
## Качество JPEG результата: карты данных — без заметных ступенек.
const JPG_QUALITY: float = 0.92


func _init() -> void:
	if PackedStringArray(OS.get_cmdline_user_args()).has("--mips"):
		_patch_mips()
		quit(0)
		return
	var lib := "/".join([OS.get_environment("HOME"), LIBRARY])
	var made := 0
	for pair: Array in COPY:
		var src: String = "/".join([lib, pair[0]])
		var dst: String = "/".join([OUT_ROOT, pair[1]])
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(dst.get_base_dir()))
		if DirAccess.copy_absolute(src, ProjectSettings.globalize_path(dst)) != OK:
			push_error("не скопировался %s" % src)
			quit(1)
			return
		made += 1
	for job: Dictionary in ORM:
		if not _make_orm(
			"/".join([lib, job["ao"]]),
			"/".join([lib, job["rough"]]),
			"/".join([lib, job["disp"]]),
			"/".join([OUT_ROOT, job["out"]]),
		):
			quit(1)
			return
		made += 1
	print("make_orm_textures: готово файлов — %d" % made)
	quit(0)


## ORM: каналы трёх монохромных карт складываются в один RGB-файл
## (байтовая сборка, быстрый путь без Color-объектов).
func _make_orm(ao_path: String, rough_path: String, disp_path: String, out_path: String) -> bool:
	var ao := Image.load_from_file(ao_path)
	var rough := Image.load_from_file(rough_path)
	var disp := Image.load_from_file(disp_path)
	if ao == null or rough == null or disp == null:
		push_error("нет исходника ORM (%s / %s / %s)" % [ao_path, rough_path, disp_path])
		return false
	var w := ao.get_width()
	var h := ao.get_height()
	if rough.get_width() != w or rough.get_height() != h \
			or disp.get_width() != w or disp.get_height() != h:
		push_error("размеры карт ORM не совпадают: %s" % out_path)
		return false
	ao.convert(Image.FORMAT_RGB8)
	rough.convert(Image.FORMAT_RGB8)
	disp.convert(Image.FORMAT_RGB8)
	var ao_d := ao.get_data()
	var rough_d := rough.get_data()
	var disp_d := disp.get_data()
	var out_d := PackedByteArray()
	out_d.resize(w * h * 3)
	for i: int in w * h:
		var p := i * 3
		out_d[p] = ao_d[p]
		out_d[p + 1] = rough_d[p]
		out_d[p + 2] = disp_d[p]
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGB8, out_d)
	var global_out := ProjectSettings.globalize_path(out_path)
	if img.save_jpg(global_out, JPG_QUALITY) != OK:
		push_error("не записался %s" % out_path)
		return false
	print("ORM: %s (%dx%d)" % [out_path, w, h])
	return true


## Включить мип-мапы в .import-сайдкарах созданных файлов (как
## make_vfx_textures --mips): планка качества — текстуры земли сэмплятся
## на весь остров, без мипов дальние склоны рябят.
func _patch_mips() -> void:
	var patched := 0
	for pair: Array in COPY:
		patched += _patch_one("%s/%s.import" % [OUT_ROOT, pair[1]])
	for job: Dictionary in ORM:
		patched += _patch_one("%s/%s.import" % [OUT_ROOT, job["out"]])
	print("make_orm_textures --mips: мипы включены у %d" % patched)


func _patch_one(import_path: String) -> int:
	var file := FileAccess.open(import_path, FileAccess.READ)
	if file == null:
		return 0
	var text := file.get_as_text()
	file.close()
	if not text.contains("mipmaps/generate=false"):
		return 0
	text = text.replace("mipmaps/generate=false", "mipmaps/generate=true")
	file = FileAccess.open(import_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return 1
