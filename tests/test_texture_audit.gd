# Аудит планки качества П5.9 (раздел Ж VISUAL_PLAN): обход всех
# используемых текстур и материалов проекта. FAIL при отсутствии мип-мапов,
# фильтре Nearest, анизотропии ниже 16x, разрешении ниже порога категории
# (1K — крупные объекты, 2K — земля и ключевые модели; исключения — с
# пояснением в CATEGORIES). Четыре среза:
#   1) файлы изображений res://assets + .import-сайдкары (мип-мапы, порог);
#   2) исходники шейдеров проекта и аддона неба (явный не-Nearest фильтр
#      у каждого сэмплера);
#   3) живое дерево острова и персонажей: материалы (filter без Nearest,
#      текстурные — анизотропные) и мип-мапы связанных текстур;
#   4) П5.9 переделка П2: в шейдерах запрещён решётчатый value-noise
#      (hash12/hash21 + билинейная ячейка) — источник осевых «полос»
#      на земле и боках камней, который текстурные срезы не видели;
#   5) доработка-2 П5.13, П8: «нет меша без текстуры» — каждая поверхность
#      мира (включая процедуры и MultiMesh) несёт текстуру либо входит
#      в списки легитимных нетекстурных; материал null = белый дефолт = FAIL.
#      Прежний аудит молчал о «белых блоках» по двум причинам: _note
#      пропускал null-материалы, а проверка сэмплеров шейдеров сравнивала
#      int-тип uniform'а со строкой «sampler» и не срабатывала никогда —
#      нетекстурный материал проходил аудит без замечаний.
#   6) доработка П9: «ни одной частицы без текстуры» — каждый пасс каждого
#      эмиттера мира несёт спрайт (нетекстурный квад на экране = белый
#      квадрат из замечания владельца).
# Процедурные данные (карты весов земли 128×128) — не текстуры детализации:
# exempt-порог 256 px по короткой стороне.
extends GutTest

const ISLAND: PackedScene = preload("res://gameplay/world/island.tscn")
const WORLD: PackedScene = preload("res://scenes/world_scene.tscn")
## Запечённые данные острова — включить частицы бега игрока (срез 6).
const ART: IslandArt = preload("res://gameplay/world/island_art.res")

## Правила категорий: min_side — минимальная короткая сторона в пикселях,
## mips — обязательность мип-мапов. Порядок важен: точные файлы раньше
## префиксов. Пояснения:
##   кора ambientcg — крупные деревья, 1K; у Bark001 сет «1K» — 512×1024,
##     в проекте 2K-сет (см. EzTreeMeshes.BARK);
##   панорамы неба — купол Sky3D, процедурные CC0;
##   карта острова — UI-мини-карта;
##   polyhaven.com — земля Леса (2K, категория сайта);
##   menu_bu — 2D-иллюстрации главного меню Born Unblessed (П9): панорама
##     собора и вырезанные слои CanvasItem, планка UI-графики 256 px;
##     мип-мапы комплект не включает (спрайты канвы, экранный масштаб
##     0.6–1.6 от исходного — мерцание не проявляется);
##   hero_bu — герой Born Unblessed (MakeHuman, П10): кожа/одежда 2–4K,
##     глаза 1K, брови/ресницы — мелкая деталь 512; всё с мип-мапами;
##   sword_bu — меч героя (П10): кладка 1K с мип-мапами;
##   loading_bu — картина экрана загрузки (П10): канва 2D 1920×1080 без
##     мип-мапов, как menu_bu;
##   vfx — спрайты частиц (доработка П9): нарезки 40–96 px с прозрачной
##     кромкой, билборды 3D — с мип-мапами, чтобы на отдалении не рябили;
##     порог 40 px — размер наименьшего спрайта (лист).
const CATEGORIES: Array = [
	["assets/third_party/ambientcg.com/", {"min_side": 1024, "mips": true}],
	["assets/third_party/polyhaven.com/", {"min_side": 1024, "mips": true}],
	["assets/visual/", {"min_side": 1024, "mips": true}],
	["assets/menu_bu/", {"min_side": 256, "mips": false}],
	["assets/hero_bu/", {"min_side": 512, "mips": true}],
	["assets/sword_bu/", {"min_side": 1024, "mips": true}],
	["assets/loading_bu/", {"min_side": 256, "mips": false}],
	["assets/island_map.png", {"min_side": 256, "mips": true}],
	["assets/vfx/", {"min_side": 40, "mips": true}],
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
	"res://addons/boujie_water_shader/shader/water.gdshader",
]

## Каталоги игрового кода: изображений быть не должно (все — в assets/).
const GAME_CODE_DIRS: Array[String] = [
	"res://gameplay", "res://scenes", "res://ui", "res://autoload", "res://net",
]

## Слот текстур BaseMaterial3D (срез 5): хотя бы один занят — материал
## текстурный.
const TEXTURE_SLOTS: Array[String] = [
	"albedo_texture", "normal_texture", "roughness_texture",
	"orm_texture", "emission_texture",
]

## Легитимно нетекстурные поверхности (срез 5): путь узла содержит ключ.
## Это принятый владельцем вид, а не забытая заглушка:
##   флора Леса и листва деревьев — шейдеры градиента/ветра и цвета
##     (кора при этом текстурная), П5.9/П5.13 приняты;
##   деревня — вершинно-цветные предметы low-poly (не белые: цвет в вершинах);
##   костёр — VFX огня и фотосканы polyhaven, раскрашенные вершинами;
##   сундук руин — свечение нутра (VFX, доработка-2 П4);
##   небо — меш дымки Sky3D;
##   тросы лестниц — тонкие планки цвета коры (верёвочный примитив,
##     доработка-2 П5: ступени при этом текстурные, WoodMat);
##   сруб деревни — оконное стекло (прозрачность без карты) и светящийся
##     фонарь крыльца (emission); брёвна/доски/камень/ткани текстурные.
## Если предмет из списка убирают из мира — запись удалить вместе с ним.
const ALWAYS_UNTEXTURED: Array[String] = [
	"Props_rgrass_", "Props_rflower_", "Props_riris_", "Props_reed_",
	"Props_fern_", "Props_etree_",
	"Props_bench_", "Props_boat_", "Props_canopy_",
	"Flame", "FirePit", "/Logs", "/Ember",
	"/Glow",
	"/Rope",
	"_FogMeshI",
	"/EXT_glass", "/INT_glass", "/EXT_lamp",
]

## Переходные нетекстурные поверхности (срез 5): закрываются пунктами
## доработки-2 П5.13, по мере закрытия записи УДАЛЯТЬ (тест следит, чтобы
## каждая запись реально встречалась в мире — устаревшая ломает прогон).
## Все пункты доработки-2 закрыты, список пуст; механика списка остаётся
## для будущих переделок.
## П3 закрыт: вода Boujie Water текстурна (альбедо и пена), записи воды
## удалены. П4 закрыт: руины (блоки, башни, колонны, арки, ворота, плиты,
## сундук-дерево, каменные стены) — текстурная кладка RuinMat и Planks007.
## П5 закрыт: причал (настил, сваи, кнехты) и ступени лестниц смотровых —
## WoodMat (плахи ambientCG); камни духа — кладка RuinMat + огонёк «/Glow»;
## маячки HangPoint — сфера «/Glow».
## П6 закрыт: коряги и мостик несут кору ambientCG в меше (override плоским
## материалом снят), пень Тимьяна — PropMeshes._stump с той же корой.
## П7 закрыт: мох камней (mrock/rrock/boulder/rock_pillar/pebble) — текстура
## ambientCG Moss001 по верхним граням с мягким переходом (rock_moss.gdshader).
const TRANSITIONAL_UNTEXTURED: Array[String] = []


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
	var paths := _shader_paths()
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


func test_shaders_no_lattice_value_noise() -> void:
	# П5.9 переделка П2: «полосы» и рябь на земле Леса (прогон владельца
	# после П5.7) давал НЕ конвейер текстур — шейдерный value-noise на
	# квадратной решётке (hash12 + билинейная интерполяция ячеек): на
	# склонах и растянутых поверхностях решётка читалась осевыми полосами.
	# Прежний аудит проверял только текстуры, фильтры и материалы — источник
	# шума в коде шейдера не контролировался, поэтому дефект проходил.
	# Планка качества: «никаких полосатых паттернов в шейдере» — решётчатый
	# value-noise в игровых шейдерах запрещён; допустимые шумы — симплекс
	# (simplex/snoise) и выборки текстур.
	# Признаки решётчатой реализации: хеш ячейки `hash12(`/`hash21(`
	# (патенты Ashima не использует, имена характерны именно решётке) и
	# фирменная билинейная развёртка ячейки `f * f * (3.0 - 2.0 * f)`
	# (smoothstep-интерполяция floor-сетки). Симплекс floor использует, но
	# без решёточного сглаживания — пара признаков его не ловит.
	var paths := _shader_paths()
	for path: String in paths:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), "%s читается" % path)
		assert_false(text.contains("hash12("),
			"%s: нет решётчатого хеша hash12 (value-noise на квадратной сетке)" % path)
		assert_false(text.contains("hash21("),
			"%s: нет решётчатого хеша hash21" % path)
		assert_false(text.contains("3.0 - 2.0 * f"),
			"%s: нет билинейной интерполяции решётки value-noise" % path)


## Срез 5, П8: каждая поверхность мира текстурна или легитимно нетекстурна.
## Мир инстанцируется в текстурном режиме (WorldMaterials.textured_headless):
## фабрики отдают те же материалы, что в Windows-сборке, а не headless-плоские
## заглушки, — аудит видит картинку игрока. Прогон с переменной окружения
## AUDIT_STRICT=1 вычищает переходный список: тест обязан FAIL'ить на руинах,
## корягах и светокубах (доказательство, что ловит, — STATUS.md).
func test_world_surfaces_textured_or_whitelisted() -> void:
	WorldMaterials.textured_headless = true
	var surfaces := _collect_world_surfaces()
	WorldMaterials.textured_headless = false
	# Порог опущен с 800 до 600 (born-unblessed): из мира ушли жители
	# UBC (каждый нёс десятки поверхностей) — фактический обход 681;
	# порог по-прежнему ловит вырождение мира в нетекстурные плоскости.
	assert_gt(surfaces.size(), 600, "обход видит все поверхности мира")
	var strict := OS.get_environment("AUDIT_STRICT") == "1"
	var allow: Array[String] = ALWAYS_UNTEXTURED.duplicate()
	if not strict:
		allow.append_array(TRANSITIONAL_UNTEXTURED)
	var offenders: Array[String] = []
	var matched: Dictionary = {}
	for entry: Dictionary in surfaces:
		var path: String = entry["path"]
		var allowed := false
		for pattern: String in allow:
			if path.contains(pattern):
				allowed = true
				matched[pattern] = true
		if allowed:
			continue
		var material: Material = entry["material"]
		if material == null:
			offenders.append("%s: материала нет — белый дефолт" % path)
		elif not _material_has_texture(material):
			offenders.append("%s: %s без текстуры" % [path, material.get_class()])
	assert_eq(offenders.size(), 0,
		"нетекстурные поверхности — только из списков разрешений:\n"
		+ "\n".join(offenders))
	if strict:
		return
	for pattern: String in TRANSITIONAL_UNTEXTURED:
		assert_true(matched.has(pattern),
			"переходная запись «%s» в мире не встречается — удалить" % pattern)


## Срез 6, доработка П9 («квадратики при беге» из прогона владельца):
## ни одна частица мира — нетекстурный квад (белый квадрат). Каждый пасс
## каждого эмиттера живого дерева мира несёт спрайт-текстуру (костёр и его
## процедурный дым удалены с наследием Blockparty, born-unblessed).
## Частицы бега включаем вручную: мир строит их по арту острова, тест
## передаёт запечённый ресурс.
func test_world_particles_textured() -> void:
	WorldMaterials.textured_headless = true
	var world := WORLD.instantiate()
	add_child_autofree(world)
	WorldMaterials.textured_headless = false
	for node: Node in get_tree().get_nodes_in_group(Player.GROUP):
		(node as Player).setup_foot_fx(ART)
	var offenders: Array[String] = []
	var emitters := _collect_particle_offenders(world, offenders)
	assert_gt(emitters, 4, "обход видит эмиттеры мира (атмосфера, бег)")
	assert_eq(offenders.size(), 0,
		"частицы без текстуры (белые квадраты) запрещены:\n"
		+ "\n".join(offenders))


## Обход дерева: каждый пасс каждого GPUParticles3D/CPUParticles3D —
## материал с текстурой. Возвращает число найденных эмиттеров, нарушения
## дописывает в out.
func _collect_particle_offenders(node: Node, out: Array[String]) -> int:
	var emitters := 0
	if node is GPUParticles3D or node is CPUParticles3D:
		emitters += 1
		var count := int(node.get("draw_passes"))
		for i: int in count:
			var mesh: Mesh = node.get("draw_pass_%d" % (i + 1)) as Mesh
			if mesh == null or mesh.get_surface_count() == 0:
				out.append("%s: пасс %d без меша" % [node.get_path(), i + 1])
				continue
			var mat := mesh.surface_get_material(0)
			if mat == null:
				out.append("%s: пасс %d без материала" % [node.get_path(), i + 1])
			elif mat is ShaderMaterial:
				if not _material_has_texture(mat):
					out.append("%s: пасс %d — ShaderMaterial без текстуры"
						% [node.get_path(), i + 1])
			elif mat is StandardMaterial3D:
				if (mat as StandardMaterial3D).albedo_texture == null:
					out.append("%s: пасс %d — StandardMaterial3D без текстуры"
						% [node.get_path(), i + 1])
			else:
				out.append("%s: пасс %d — неожидаемый класс материала %s"
					% [node.get_path(), i + 1, mat.get_class()])
	for child: Node in node.get_children():
		emitters += _collect_particle_offenders(child, out)
	return emitters


func test_runtime_materials_meet_quality_bar() -> void:
	# Живое дерево острова (рельеф, предметы, деревья с запечённой корой)
	# и героя BU внутри сцены мира: материалы без Nearest; текстурные
	# BaseMaterial3D — анизотропные (мип-мапы + 16x); у текстур от 256 px —
	# мип-мапы.
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
			# П8: тип uniform'а в get_shader_uniform_list() — int, прежняя
			# строковая проверка «sampler» не срабатывала никогда. Текстуру
			# определяем по значению: bool/цвет/число Texture2D'ом не бывают.
			var shader := (material as ShaderMaterial).shader
			if shader == null:
				continue
			for u: Dictionary in shader.get_shader_uniform_list():
				var value = (material as ShaderMaterial).get_shader_parameter(u["name"])
				if value is Texture2D:
					_assert_texture_mips(value as Texture2D,
						"%s %s" % [where, u["name"]])
	assert_gt(textured, 0, "в мире есть текстурные материалы (кора, кожа)")


# --- Служебное ---


## Поверхности живого дерева (срез 5): эффективный материал каждой
## поверхности — override узла, затем материал поверхности меша, затем
## per-surface override; null допустим только после них (белый дефолт).
func _collect_world_surfaces() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var island := ISLAND.instantiate()
	add_child_autofree(island)
	var world := WORLD.instantiate()
	add_child_autofree(world)
	_collect_surfaces(island, out)
	_collect_surfaces(world, out)
	return out


func _collect_surfaces(node: Node, out: Array[Dictionary]) -> void:
	var path := str(node.get_path())
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for surface: int in mi.mesh.get_surface_count():
				var material: Material = mi.material_override
				if material == null:
					material = mi.mesh.surface_get_material(surface)
				if material == null:
					material = mi.get_surface_override_material(surface)
				out.append({"path": "%s#%d" % [path, surface], "material": material})
	elif node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		if mmi.multimesh != null and mmi.multimesh.mesh != null:
			var am := mmi.multimesh.mesh as ArrayMesh
			if am != null:
				for surface: int in am.get_surface_count():
					var material: Material = mmi.material_override
					if material == null:
						material = am.surface_get_material(surface)
					out.append({"path": "%s#%d" % [path, surface], "material": material})
	for child: Node in node.get_children():
		_collect_surfaces(child, out)


## Материал несёт текстуру (срез 5).
func _material_has_texture(material: Material) -> bool:
	if material is BaseMaterial3D:
		var base := material as BaseMaterial3D
		for prop: String in TEXTURE_SLOTS:
			if base.get(prop) != null:
				return true
		return false
	if material is ShaderMaterial:
		var sm := material as ShaderMaterial
		if sm.shader == null:
			return false
		for u: Dictionary in sm.shader.get_shader_uniform_list():
			if sm.get_shader_parameter(u["name"]) is Texture2D:
				return true
	return false

## Все игровые .gdshader (каталоги + отдельные файлы).
func _shader_paths() -> Array[String]:
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
	return paths


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
	# Персонажи (герой BU) — внутри сцены мира: обычный обход их видит.
	_collect_materials(island, seen, out)
	_collect_materials(world, seen, out)
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
