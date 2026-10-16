# Аудит планки качества П5.9 (раздел Ж VISUAL_PLAN): обход всех
# используемых текстур и материалов проекта. FAIL при отсутствии мип-мапов,
# фильтре Nearest, анизотропии ниже 16x, разрешении ниже порога категории
# (1K — крупные объекты, 2K — земля и ключевые модели; исключения — с
# пояснением в CATEGORIES). Три среза:
#   1) файлы изображений res://assets + .import-сайдкары (мип-мапы, порог);
#   2) исходники шейдеров проекта и аддона неба (явный не-Nearest фильтр
#      у каждого сэмплера);
#   3) живое дерево острова и персонажей: материалы (filter без Nearest,
#      текстурные — анизотропные) и мип-мапы связанных текстур.
# Процедурные данные (карты весов земли 128×128) — не текстуры детализации:
# exempt-порог 256 px по короткой стороне.
extends GutTest

const ISLAND: PackedScene = preload("res://gameplay/world/island.tscn")
const WORLD: PackedScene = preload("res://scenes/world_scene.tscn")
const MODEL: PackedScene = preload(
	"res://gameplay/player/character_model.tscn")

## Правила категорий: min_side — минимальная короткая сторона в пикселях,
## mips — обязательность мип-мапов. Порядок важен: точные файлы раньше
## префиксов. Пояснения:
##   кора ambientcg — крупные деревья, 1K; у Bark001 сет «1K» — 512×1024,
##     в проекте 2K-сет (см. TreeGen.BARK_FILES);
##   персонажи Quaternius UBC — план П5.9 п.7 «люди не меняются»: кожа
##     головы и одежда 2K, руки/волосы 1K, глаза — мелкая деталь 256;
##   панорамы неба — купол Sky3D, процедурные CC0;
##   карта острова — UI-мини-карта;
##   colormap castle-kit — данные запекания: цвет уходит в вершины руин
##     (Cc0Meshes), в рендере не участвует — порога и мип-мапов нет.
const CATEGORIES: Array = [
	["assets/third_party/kenney.nl/castle-kit/Textures/colormap.png",
		{"min_side": 0, "mips": false}],
	["assets/third_party/quaternius.com/universal_base_characters/baked/textures/eyes",
		{"min_side": 256, "mips": true}],
	["assets/third_party/quaternius.com/universal_base_characters/baked/textures/",
		{"min_side": 1024, "mips": true}],
	["assets/third_party/ambientcg.com/", {"min_side": 1024, "mips": true}],
	["assets/visual/", {"min_side": 1024, "mips": true}],
	["assets/island_map.png", {"min_side": 256, "mips": true}],
]

## Короткая сторона, с которой связаны текстурой, требует мип-мапы:
## меньше — процедурные данные (карты весов/границ земли 128×128).
const RUNTIME_MIP_THRESHOLD: int = 256

## Шейдеры игры (сэмплеры обязаны объявлять не-Nearest фильтр явно).
const SHADER_DIRS: Array[String] = [
	"res://assets/shaders",
	"res://addons/sky_3d/shaders",
]
const SHADER_FILES: Array[String] = [
	"res://gameplay/world/water_wave.gdshader",
]

## Каталоги игрового кода: изображений быть не должно (все — в assets/).
const GAME_CODE_DIRS: Array[String] = [
	"res://gameplay", "res://scenes", "res://ui", "res://autoload", "res://net",
]


func test_project_filter_settings() -> void:
	# Анизотропная фильтрация проекта — 16x (планка Ж: «у всех текстур …
	# анизотропная фильтрация 16x»); фильтр UI-канвы — не Nearest.
	var aniso: int = ProjectSettings.get_setting_with_override(
		"rendering/textures/default_filters/anisotropic_filtering_level")
	assert_eq(aniso, 16, "анизотропия проекта 16x")
	var canvas: int = ProjectSettings.get_setting_with_override(
		"rendering/textures/canvas_textures/default_texture_filter")
	assert_ne(canvas, 0, "канва не Nearest")
	assert_ne(canvas, 3, "канва не Nearest с мип-мапами")


func test_image_files_meet_quality_bar() -> void:
	# Все изображения res://assets категоризированы и проходят порог:
	# мип-мапы в сайдкаре и в рантайме, короткая сторона ≥ min_side.
	var files: Array[String] = []
	_collect_images("res://assets", files)
	assert_gt(files.size(), 20, "аудит видит текстуры проекта (>20)")
	for path: String in files:
		var rule: Dictionary = _category_for(path)
		assert_ne(rule, {}, "текстура категоризирована: %s" % path)
		if rule.is_empty():
			continue
		if not rule["mips"] and rule["min_side"] == 0:
			continue  # чистые данные запекания: не ресурс текстуры вовсе
		var texture := load(path) as Texture2D
		assert_not_null(texture, "%s — текстура" % path)
		if texture == null:
			continue
		if rule["mips"]:
			assert_true(_sidecar_mipmaps(path),
				"%s: мип-мапы включены в .import" % path)
			var image := texture.get_image()
			assert_true(image != null and image.has_mipmaps(),
				"%s: мип-мапы есть в рантайме" % path)
		var min_side: int = rule["min_side"]
		if min_side > 0:
			var short_side: int = mini(texture.get_width(), texture.get_height())
			assert_true(short_side >= min_side,
				"%s: короткая сторона %d ≥%d" % [path, short_side, min_side])


func test_no_images_in_code_dirs() -> void:
	# Игровые изображения живут только в assets/ — в кодовых каталогах
	# ничего не прячется от аудита.
	for dir_path: String in GAME_CODE_DIRS:
		var files: Array[String] = []
		_collect_images(dir_path, files)
		assert_eq(files.size(), 0, "в %s нет изображений" % dir_path)


func test_shaders_declare_linear_filters() -> void:
	# Ни один сэмплер игры не фильтруется Nearest: filter_nearest запрещён,
	# у каждого uniform-сэмплера — явный хинт фильтра (без хинта фильтр
	# определяется молчаливым дефолтом, это не проходит планку).
	var paths: Array[String] = SHADER_FILES.duplicate()
	for dir_path: String in SHADER_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while not name.is_empty():
			if name.match("*.gdshader"):
				paths.append(dir_path + "/" + name)
			name = dir.get_next()
	assert_gt(paths.size(), 8, "аудит видит шейдеры проекта")
	for path: String in paths:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), "%s читается" % path)
		assert_false(text.contains("filter_nearest"),
			"%s: нет filter_nearest" % path)
		for line: String in text.split("\n"):
			var trimmed := line.strip_edges()
			if not trimmed.begins_with("uniform"):
				continue
			if not "sampler" in trimmed:
				continue
			assert_true(trimmed.contains("filter_"),
				"%s: у сэмплера явный фильтр — «%s»" % [path, trimmed])


func test_runtime_materials_meet_quality_bar() -> void:
	# Живое дерево острова (рельеф, предметы, деревья с запечённой корой)
	# и персонажи: материалы без Nearest; текстурные BaseMaterial3D —
	# анизотропные (мип-мапы + 16x); у текстур от 256 px — мип-мапы.
	var materials := _collect_world_materials()
	assert_gt(materials.size(), 300,
		"обход собрал материалы мира и персонажей")
	var textured := 0
	for entry: Dictionary in materials:
		var material: Material = entry["material"]
		var where: String = entry["where"]
		if material is BaseMaterial3D:
			var base := material as BaseMaterial3D
			var filter: int = base.texture_filter
			assert_false(filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST
					or filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
					or filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC,
				"%s: фильтр не Nearest (%s)" % [where, base.resource_name])
			var has_texture := false
			for prop: String in ["albedo_texture", "normal_texture",
					"roughness_texture", "orm_texture", "emission_texture"]:
				var tex: Texture2D = base.get(prop)
				if tex == null:
					continue
				has_texture = true
				_assert_texture_mips(tex, "%s %s" % [where, prop])
			if has_texture:
				textured += 1
				assert_eq(filter,
					BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC,
					"%s: текстурный материал анизотропный (%s)" % [
						where, base.resource_name])
		elif material is ShaderMaterial:
			var shader := (material as ShaderMaterial).shader
			if shader == null:
				continue
			for u: Dictionary in shader.get_shader_uniform_list():
				if not str(u["type"]).contains("sampler"):
					continue
				var value = (material as ShaderMaterial).get_shader_parameter(u["name"])
				if value is Texture2D:
					_assert_texture_mips(value as Texture2D,
						"%s %s" % [where, u["name"]])
	assert_gt(textured, 0, "в мире есть текстурные материалы (кора, кожа)")


## Материалы .res персонажей UBC — все 9, независимо от видимости частей.
func test_ubc_material_resources_meet_quality_bar() -> void:
	var dir := DirAccess.open(
		"res://assets/third_party/quaternius.com/universal_base_characters/baked/materials")
	assert_not_null(dir, "каталог материалов UBC на месте")
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	var count := 0
	while not name.is_empty():
		if name.match("*.res"):
			count += 1
			var base := load(
				"res://assets/third_party/quaternius.com/universal_base_characters/baked/materials/" + name) as BaseMaterial3D
			assert_not_null(base, "%s — BaseMaterial3D" % name)
			if base == null:
				continue
			assert_eq(base.texture_filter,
				BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC,
				"%s: анизотропная фильтрация" % name)
			for prop: String in ["albedo_texture", "normal_texture",
					"roughness_texture", "orm_texture"]:
				var tex: Texture2D = base.get(prop)
				if tex != null:
					_assert_texture_mips(tex, "%s.%s" % [name, prop])
		name = dir.get_next()
	assert_eq(count, 9, "материалы UBC на месте (9)")


# --- Служебное ---

func _category_for(path: String) -> Dictionary:
	var local := path.replace("res://", "")
	for entry: Array in CATEGORIES:
		var pattern: String = entry[0]
		if pattern.ends_with("/") and local.begins_with(pattern):
			return entry[1]
		if local == pattern or local.begins_with(pattern):
			return entry[1]
	return {}


func _sidecar_mipmaps(path: String) -> bool:
	var sidecar := path + ".import"
	if not FileAccess.file_exists(sidecar):
		return false
	var cfg := ConfigFile.new()
	if cfg.load(sidecar) != OK:
		return false
	return cfg.get_value("params", "mipmaps/generate", false)


func _collect_images(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var full := dir_path + "/" + name
		if dir.current_is_dir():
			if not name.begins_with("."):
				_collect_images(full, out)
		elif name.match("*.png") or name.match("*.jpg") \
				or name.match("*.webp"):
			out.append(full)
		name = dir.get_next()


## Материалы живого дерева: override/overlay, поверхности мешей, per-surface
## override персонажей, меши MultiMesh (кора/кроны запечены в арте).
func _collect_world_materials() -> Array[Dictionary]:
	var seen: Dictionary = {}
	var out: Array[Dictionary] = []
	var island := ISLAND.instantiate()
	add_child_autofree(island)
	# Сцена мира — риг неба Sky3D (купол со звёздными текстурами) поверх
	# того же острова: материалы дедуплицируются, добавляются только небесные.
	var world := WORLD.instantiate()
	add_child_autofree(world)
	for gender: int in [0, 1]:
		var model := MODEL.instantiate() as CharacterModel
		add_child_autofree(model)
		model.setup_appearance(Appearance.default_for(gender))
	_collect_materials(island, seen, out)
	_collect_materials(world, seen, out)
	# Персонажи — дети теста рядом с островом: обходим их поддеревья
	# (перекрашенные дубли материалов и текстура глаз — в per-surface
	# override, обычный обход их не видит).
	for child: Node in get_children():
		if child is CharacterModel:
			_collect_materials(child, seen, out)
	return out


func _collect_materials(node: Node, seen: Dictionary, out: Array[Dictionary]) -> void:
	if node is GeometryInstance3D:
		var geo := node as GeometryInstance3D
		for mat: Material in [geo.material_override, geo.material_overlay]:
			_note(mat, node, seen, out)
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh != null:
			for surface: int in mi.mesh.get_surface_count():
				_note(mi.mesh.surface_get_material(surface), node, seen, out)
				_note(mi.get_surface_override_material(surface), node, seen, out)
		var mmi := node as MultiMeshInstance3D
		if mmi != null and mmi.multimesh != null \
				and mmi.multimesh.mesh != null:
			var am := mmi.multimesh.mesh as ArrayMesh
			if am != null:
				for surface: int in am.get_surface_count():
					_note(am.surface_get_material(surface), node, seen, out)
	for child: Node in node.get_children():
		_collect_materials(child, seen, out)


func _note(mat: Material, node: Node, seen: Dictionary,
		out: Array[Dictionary]) -> void:
	if mat == null or seen.has(mat):
		return
	seen[mat] = true
	out.append({"material": mat, "where": str(node.get_path())})


func _assert_texture_mips(tex: Texture2D, where: String) -> void:
	var short_side := mini(tex.get_width(), tex.get_height())
	if short_side < RUNTIME_MIP_THRESHOLD:
		return  # процедурные данные (карты весов земли)
	var image := tex.get_image()
	assert_true(image != null and image.has_mipmaps(),
		"%s: текстура %dx%d с мип-мапами" % [where, tex.get_width(), tex.get_height()])
