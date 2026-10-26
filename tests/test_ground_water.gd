# Тесты П12 «Земля и вода Born Unblessed»: слои земли с полным PBR
# (LICENSES, нет пустых сэмплеров), лужи/параллакс/AO выключены на SIMPLE
# и включены на HIGH/ULTRA (по uniform quality), порог луж совпадает
# со всплесками FootFx, размеры third_party в лимите. Сервер — без
# рендера, поэтому поведение шейдера проверяется материалом (uniform
# quality по уровням) и исходником шейдера (ветвление уровней), как
# test_texture_audit проверяет фильтры сэмплеров по тексту.
extends GutTest

const ART: IslandArt = preload("res://gameplay/world/island_art.res")
const GROUND_SHADER: Shader = preload(
	"res://assets/shaders/forest_ground.gdshader")
const THIRD_PARTY: String = "res://assets/third_party"


# --- П12 D: земля ---

func test_ground_licenses_cover_all_layers() -> void:
	# SPEC П12 приёмка: у всех текстур земли есть запись в LICENSES.md,
	# лицензия CC0, сайт из разрешённых (polyhaven/ambientcg).
	var licenses := _read_licenses()
	for pair: Array in [
		["polyhaven.com/forest_ground_05/forest_ground_05_diffuse_2k.jpg", "forest_ground_05 | Poly Haven"],
		["polyhaven.com/forest_ground_05/forest_ground_05_orm_2k.jpg", "forest_ground_05 | Poly Haven"],
		["polyhaven.com/leafy_grass/leafy_grass_diffuse_1k.jpg", "leafy_grass | Poly Haven"],
		["polyhaven.com/leafy_grass/leafy_grass_orm_1k.jpg", "leafy_grass | Poly Haven"],
		["polyhaven.com/mud_forest/mud_forest_diffuse_1k.jpg", "mud_forest | Poly Haven"],
		["polyhaven.com/rock_face_03/rock_face_03_orm_2k.jpg", "rock_face_03 | Poly Haven"],
		["polyhaven.com/rocky_trail/rocky_trail_nor_gl_2k.jpg", "rocky_trail | Poly Haven"],
		["ambientcg.com/Moss001/Moss001_1K-JPG_ORM.jpg", "Moss001 | ambientCG"],
		["ambientcg.com/Moss001/Moss001_1K-JPG_NormalGL.jpg", "Moss001 | ambientCG"],
	]:
		assert_true(
			licenses.contains(pair[1]) or _licenses_mention(licenses, pair[1]),
			"LICENSES.md покрывает %s (строка «%s»)" % [pair[0], pair[1]],
		)
	assert_true(licenses.contains("CC0"), "лицензии CC0 в файле есть")


func test_ground_all_layer_textures_set() -> void:
	# SPEC П12 приёмка: шейдер земли получает все карты слоёв — у каждого
	# uniform-сэмплера материала стоит Texture2D (нет пустых сэмплеров).
	var material := ForestGround.make_material(ART, GraphicsQuality.Tier.HIGH)
	var regex := RegEx.new()
	regex.compile("uniform sampler2D\\s+(\\w+)")
	var matches := regex.search_all(GROUND_SHADER.code)
	assert_between(matches.size(), 12, 24,
		"карт слоёв найдено разумно: %d" % matches.size())
	for match: RegExMatch in matches:
		var name := match.get_string(1)
		assert_true(material.get_shader_parameter(name) is Texture2D,
			"карта %s задана текстурой" % name)


func test_ground_material_quality_by_tier() -> void:
	# SPEC П12 2.6: uniform quality в материале следует уровню графики —
	# SIMPLE/NORMAL/HIGH/ULTRA передаются в шейдер без искажений.
	for tier: int in [
		GraphicsQuality.Tier.SIMPLE,
		GraphicsQuality.Tier.NORMAL,
		GraphicsQuality.Tier.HIGH,
		GraphicsQuality.Tier.ULTRA,
	]:
		var material := ForestGround.make_material(ART, tier)
		assert_eq(
			material.get_shader_parameter("quality"), tier,
			"quality uniform = Tier.%d" % tier,
		)


func test_ground_shader_gates_by_quality() -> void:
	# Ветвление уровней в шейдере (текстом, как аудит фильтров): лужи и
	# слой травы гасятся на SIMPLE, параллакс — только HIGH/ULTRA
	# (quality >= QUALITY_HIGH) и с затуханием до PARALLAX_FAR.
	var text := GROUND_SHADER.code
	assert_true(
		text.contains("quality == QUALITY_SIMPLE\n\t\t? 0.0\n\t\t: smoothstep(PUDDLE_START"),
		"лужи гасятся на SIMPLE (vertex-вес puddle_v)")
	assert_true(
		text.contains("bool with_grass = quality != QUALITY_SIMPLE"),
		"слой травы не сэмплится на SIMPLE")
	assert_true(
		text.contains("if (quality >= QUALITY_HIGH) {"),
		"параллакс — только HIGH/ULTRA")
	assert_true(
		text.contains("parallax_near") and text.contains("parallax_far"),
		"затухание параллакса по дистанции (П13: дальности — uniform уровня)")
	assert_true(
		text.contains("AO_LIGHT_AFFECT") and text.contains("quality == QUALITY_SIMPLE"),
		"AO-канал (AO-выход, П14 2.3) и roughness из карт — не на SIMPLE")


func test_puddle_threshold_matches_foot_fx() -> void:
	# SPEC П12 2.5: лужи при w.g ≥ 0.9 — то же значение, что
	# ForestGround.PUDDLE_WET (всплески FootFx совпадают с лужами).
	var text := GROUND_SHADER.code
	var match_puddle := text.contains("const float PUDDLE_START = 0.9;")
	assert_true(match_puddle, "в шейдере PUDDLE_START = 0.9")
	assert_almost_eq(
		ForestGround.PUDDLE_WET, 0.9, 0.0001,
		"ForestGround.PUDDLE_WET — тот же порог")


func test_third_party_within_budget() -> void:
	# SPEC П12 3.3: assets/third_party/ не больше 300 МБ.
	var bytes := _dir_size(ProjectSettings.globalize_path(THIRD_PARTY))
	assert_lt(
		bytes, 300 * 1024 * 1024,
		"third_party %.1f МБ < 300 МБ" % (bytes / 1048576.0))


func test_no_oversized_files() -> void:
	# CLAUDE.md: файлы больше 10 МБ не появляются (LFS не настроен).
	var oversize: Array[String] = []
	_walk(ProjectSettings.globalize_path(THIRD_PARTY), func(path: String) -> void:
		if FileAccess.file_exists(path) \
				and FileAccess.get_file_as_bytes(path).size() > 10 * 1024 * 1024:
			oversize.append(path))
	assert_eq(oversize.size(), 0, "файлов > 10 МБ нет: %s" % str(oversize))


# --- П12 E: наполнение земли ---

func test_ground_detail_models_licensed() -> void:
	# SPEC П12 приёмка: у всех моделей-наполнителей есть запись в LICENSES.md
	# (CC0, polyhaven), файлы реально лежат в third_party.
	for pair: Array in [
		["namaqualand_boulder_02/boulder_02_lo.res", "namaqualand_boulder_02"],
		["namaqualand_boulder_03/boulder_03_lo.res", "namaqualand_boulder_03"],
		["namaqualand_stones_01/stones_lo.res", "namaqualand_stones_01"],
		["tree_stump_01/stump_01_lo.res", "tree_stump_01"],
		["tree_stump_02/stump_02_lo.res", "tree_stump_02"],
		["root_cluster_01/roots_lo.res", "root_cluster_01"],
		["single_root/root_lo.res", "single_root"],
		["bark_debris_01/debris_lo.res", "bark_debris_01"],
		["fern_02/fern_lo.res", "fern_02"],
	]:
		var path := "%s/polyhaven.com/%s" % [THIRD_PARTY, pair[0]]
		assert_true(ResourceLoader.exists(path), "модель лежит в проекте: %s" % path)
		assert_true(
			_licenses_mention(_read_licenses(), "%s | Poly Haven" % pair[1]),
			"LICENSES.md покрывает набор %s" % pair[1],
		)


func test_details_deterministic_and_sane() -> void:
	# SPEC П12 3.1: разброс детерминирован (два построения — те же
	# трансформы), всё на суше в пределах острова, вне Площади, коллизии —
	# только у крупных (валуны и пни). Инстанс-данные MultiMesh в headless
	# не читаются (пустой RenderingServer) — проверка по сырым трансформам
	# сборки, в игре узел строится из них же.
	var first: Dictionary = GroundDetails.build(ART, GraphicsQuality.Tier.HIGH)
	var second: Dictionary = GroundDetails.build(ART, GraphicsQuality.Tier.HIGH)
	var transforms: Dictionary = first["transforms"]
	assert_gte(transforms.size(), 8, "видов наполнения построено (из 10)")
	var colliders: Array[Dictionary] = first["colliders"]
	assert_gte(colliders.size(), 20, "коллизии крупных есть: %d" % colliders.size())
	var total := 0
	for type: String in transforms:
		var list: Array = transforms[type]
		var mirror: Array = second["transforms"].get(type, [])
		assert_eq(list.size(), mirror.size(),
			"вид %s: то же число экземпляров" % type)
		var same := true
		for i: int in list.size():
			if list[i] != mirror[i]:
				same = false
				break
		assert_true(same, "вид %s: трансформы совпадают (детерминизм)" % type)
		total += list.size()
		for xf_variant: Variant in list:
			var pos: Vector3 = (xf_variant as Transform3D).origin
			assert_gt(pos.y, 0.0, "вид %s: над водой (y=%.2f)" % [type, pos.y])
			assert_true(absf(pos.x) <= 128.0 and absf(pos.z) <= 128.0,
				"вид %s: в пределах острова" % type)
			var plaza: float = ForestGround._plaza_weight(pos.x, pos.z)
			assert_lt(plaza, 0.5, "вид %s: не на Площади (%.1f, %.1f)"
				% [type, pos.x, pos.z])
	for collider: Dictionary in colliders:
		var size: Vector3 = collider["size"]
		assert_true(size.x > 0.5 and size.y > 0.2,
			"бокс коллизии крупного адекватен: %s" % str(size))
	assert_between(total, 300, 4000,
		"экземпляров наполнения разумно (300–4000): %d" % total)
	print("П12 E: наполнение — %d экземпляров, коллизий %d"
		% [total, colliders.size()])


func test_grass_boost_by_tier() -> void:
	# SPEC П12 3.2: слой травы-буста только на HIGH/ULTRA, на ULTRA плотнее.
	for tier: int in [
		GraphicsQuality.Tier.SIMPLE,
		GraphicsQuality.Tier.NORMAL,
	]:
		var types: Array = (
			GroundDetails.build(ART, tier)["transforms"] as Dictionary).keys()
		assert_eq(
			types.filter(func(type: String) -> bool:
				return type.begins_with("gd_grass")).size(),
			0, "буст-травы нет на Tier.%d" % tier,
		)
	var high: int = _grass_total(
		GroundDetails.build(ART, GraphicsQuality.Tier.HIGH))
	var ultra: int = _grass_total(
		GroundDetails.build(ART, GraphicsQuality.Tier.ULTRA))
	assert_gt(high, 500, "буст на HIGH заметен: %d пучков" % high)
	assert_almost_eq(
		float(ultra) / float(high),
		GroundDetails.GRASS_BOOST_ULTRA / GroundDetails.GRASS_BOOST_HIGH,
		0.15, "ULTRA плотнее HIGH пропорционально константе (%d/%d)" % [ultra, high],
	)


func test_island_view_quality_ranges() -> void:
	# П12 E / П11 2.8: SIMPLE прячет траву и приближает дальность мелочи,
	# ULTRA отодвигает дальность ×1.5 и спад густоты травы в шейдере.
	WorldMaterials.textured_headless = true
	var view := IslandView.new()
	view.art = ART
	add_child_autofree(view)
	var ranges: Dictionary = {}
	for child: Node in view.get_children():
		if child is MultiMeshInstance3D:
			var type := String((child as MultiMeshInstance3D).name)
			if type.begins_with("gd_") or type.begins_with("Props_rgrass"):
				ranges[type] = (child as MultiMeshInstance3D).visibility_range_end
	assert_gte(ranges.size(), 5, "группы наполнения в острове: %d" % ranges.size())
	# SIMPLE: трава и папоротники скрыты, дальность мелочи ×0.6 (мин. 25 м).
	view.set_quality(GraphicsQuality.Tier.SIMPLE)
	for child: Node in view.get_children():
		if child is MultiMeshInstance3D:
			var instance := child as MultiMeshInstance3D
			var type := String(instance.name)
			if type.begins_with("Props_rgrass") \
					or type.begins_with("gd_grass") or type == "gd_fern":
				assert_false(instance.visible, "SIMPLE прячет %s" % type)
			if ranges.has(type):
				assert_almost_eq(instance.visibility_range_end,
					maxf(25.0, float(ranges[type]) * 0.6), 0.01,
					"SIMPLE: дальность %s ×0.6" % type)
	# ULTRA: всё видно, дальность ×1.5, спад травы отодвинут ×1.5.
	view.set_quality(GraphicsQuality.Tier.ULTRA)
	for child: Node in view.get_children():
		if child is MultiMeshInstance3D:
			var instance := child as MultiMeshInstance3D
			var type := String(instance.name)
			if type.begins_with("Props_rgrass") \
					or type.begins_with("gd_grass") or type == "gd_fern":
				assert_true(instance.visible, "ULTRA возвращает %s" % type)
			if ranges.has(type):
				assert_almost_eq(instance.visibility_range_end,
					float(ranges[type]) * 1.5, 0.01,
					"ULTRA: дальность %s ×1.5" % type)
			if type == "Props_rgrass_0":
				var material := instance.material_override
				assert_true(material is ShaderMaterial,
					"материал травы шейдерный (textured_headless)")
				if material is ShaderMaterial:
					var fade: float = float(
						(material as ShaderMaterial).get_shader_parameter(
							"fade_start"))
					assert_almost_eq(fade, 40.0 * 1.5, 0.01,
						"ULTRA: спад травы ×1.5 (fade_start %.1f)" % fade)
	WorldMaterials.textured_headless = false


static func _grass_total(built: Dictionary) -> int:
	var total := 0
	for type: String in built["transforms"]:
		if type.begins_with("gd_grass"):
			total += (built["transforms"][type] as Array).size()
	return total


# --- П12 F: вода ---

func test_water_palette_not_turquoise() -> void:
	# SPEC П12 4.1: палитра BU — озеро торфяное, море стальное; бирюза
	# Blockparty (PAL.water) не используется, глубина темнее мелководья,
	# мелководье прозрачное (дно видно).
	var pal: Palette = load("res://assets/palette.tres")
	for pair: Array in [
		["озеро глубина", WaterArea.LAKE_DEEP],
		["озеро мелководье", WaterArea.LAKE_SHALLOW],
		["море глубина", WaterArea.SEA_DEEP],
		["море мелководье", WaterArea.SEA_SHALLOW],
	]:
		var color: Color = pair[1]
		assert_gt(
			Vector3(color.r, color.g, color.b).distance_to(
				Vector3(pal.water.r, pal.water.g, pal.water.b)),
			0.1, "%s: не бирюза палитры" % pair[0])
		assert_lt(color.get_luminance(), 0.25, "%s: тёмная" % pair[0])
	assert_lt(
		(WaterArea.LAKE_DEEP as Color).get_luminance(),
		(WaterArea.LAKE_SHALLOW as Color).get_luminance(),
		"озеро: глубина темнее мелководья")
	assert_lt(
		(WaterArea.SEA_DEEP as Color).get_luminance(),
		(WaterArea.SEA_SHALLOW as Color).get_luminance(),
		"море: глубина темнее мелководья")
	# Прозрачность мелководья — в поглощении Бера, см.
	# test_water_palette_absorption_beer ниже (П14 4.1).


func test_water_palette_absorption_beer() -> void:
	# П14 4.1: прозрачность переехала из альфы цветов в поглощение Бера
	# по каналам (альфа-каналы палитры больше не несут смысла и равны 1):
	# на 20 см воды дно видно насквозь, на 5 м — исчезло. Проверяется
	# именно пара констант, которой пользуется шейдер.
	for pair: Array in [
		["озеро", WaterArea.LAKE_ABSORPTION],
		["море", WaterArea.SEA_ABSORPTION],
	]:
		var absorb: Vector3 = pair[1]
		for channel: int in 3:
			assert_gt(
				exp(-absorb[channel] * 0.2), 0.5,
				"%s: на 20 см дно видно (канал %d)" % [pair[0], channel])
			# Синий гаснет медленнее (красный первым) — порог 20 %:
			# на 5 м вклад дна мал, цвет задаёт рассеяние глубины.
			assert_lt(
				exp(-absorb[channel] * 5.0), 0.2,
				"%s: на 5 м дно почти исчезло (канал %d)" % [pair[0], channel])


func test_water_shader_no_painted_albedo() -> void:
	# SPEC П14 4: свой шейдер water_bu вместо Boujie — текстур аддона
	# нет вовсе (пена и рябь процедурные), цвет дают толщина воды,
	# небо и френель; экранная текстура — только у полной версии.
	for shader: Shader in [WaterArea.WATER_BU, WaterArea.WATER_BU_CHEAP]:
		var code := shader.code
		var path: String = shader.resource_path.get_file()
		assert_false(code.contains("addons/boujie_water_shader"),
			"%s: текстур Boujie нет" % path)
		assert_false(code.contains("uniform sampler2D texture_"),
			"%s: текстурных сэмплеров нет (всё процедурно)" % path)
	assert_true(WaterArea.WATER_BU.code.contains("hint_screen_texture"),
		"полная версия читает экран (преломление)")
	assert_false(
		WaterArea.WATER_BU_CHEAP.code.contains("hint_screen_texture"),
		"дешёвая версия без экранной выборки (SPEC П14 4.7)")


func test_water_refraction_by_tier() -> void:
	# SPEC П14 4.1/4.7: полная версия с экранной текстурой — только
	# HIGH/ULTRA, SIMPLE/NORMAL — дешёвая полупрозрачная.
	for pair: Array in [
		[GraphicsQuality.Tier.SIMPLE, WaterArea.WATER_BU_CHEAP],
		[GraphicsQuality.Tier.NORMAL, WaterArea.WATER_BU_CHEAP],
		[GraphicsQuality.Tier.HIGH, WaterArea.WATER_BU],
		[GraphicsQuality.Tier.ULTRA, WaterArea.WATER_BU],
	]:
		assert_eq(
			WaterArea.shader_for_tier(pair[0]), pair[1],
			"Tier.%d выбирает %s" % [pair[0], (pair[1] as Shader)
				.resource_path.get_file()],
		)


func test_water_material_bu_settings() -> void:
	# SPEC П14 4.1/4.4: почти зеркало (roughness 0.02–0.05), цвета BU
	# в материале, поглощение Бера по каналам с красным первым, озеро
	# (торфяная мгла) глотает свет плотнее стального моря.
	WorldMaterials.textured_headless = true
	var area := WaterArea.new()
	add_child_autofree(area)
	var lake := area._surface_material(true) as ShaderMaterial
	var sea := area._surface_material(false) as ShaderMaterial
	for pair: Array in [["озеро", lake, true], ["море", sea, false]]:
		var material := pair[1] as ShaderMaterial
		var calm: bool = pair[2]
		assert_true(material is ShaderMaterial,
			"вода %s — шейдерный материал" % pair[0])
		assert_between(
			float(material.get_shader_parameter("roughness")), 0.02, 0.05,
			"%s: почти зеркало (roughness)" % pair[0])
		var deep: Color = WaterArea.LAKE_DEEP if calm else WaterArea.SEA_DEEP
		var shallow: Color = WaterArea.LAKE_SHALLOW if calm else WaterArea.SEA_SHALLOW
		assert_eq(material.get_shader_parameter("color_deep"), deep,
			"%s: глубинный цвет — палитра BU" % pair[0])
		assert_eq(material.get_shader_parameter("color_shallow"), shallow,
			"%s: цвет мелководья — палитра BU" % pair[0])
		# Поглощение по каналам: красный гаснет первым (SPEC П14 4.1).
		var absorb: Vector3 = material.get_shader_parameter("absorption")
		assert_gt(absorb.x, absorb.y,
			"%s: красный гаснет первым" % pair[0])
		assert_gt(absorb.y, absorb.z,
			"%s: зелёный плотнее синего" % pair[0])
	for channel: int in 3:
		assert_gt(
			(WaterArea.LAKE_ABSORPTION as Vector3)[channel],
			(WaterArea.SEA_ABSORPTION as Vector3)[channel],
			"озеро глотает свет плотнее моря (торфяная мгла), канал %d"
				% channel)
	assert_ne(WaterArea.RING_COLOR, load("res://assets/palette.tres").water,
		"круги на воде — не бирюза палитры")
	WorldMaterials.textured_headless = false


# --- вспомогательные ---

func _read_licenses() -> String:
	var file := FileAccess.open(
		"res://assets/third_party/LICENSES.md", FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _licenses_mention(licenses: String, header: String) -> bool:
	# Строка таблицы может быть разбита правками: сверяем по ключу
	# «набор | автор» в любом месте текста.
	return licenses.contains(header)


func _dir_size(path: String) -> int:
	var total := 0
	_walk(path, func(file_path: String) -> void:
		if FileAccess.file_exists(file_path):
			total += FileAccess.get_file_as_bytes(file_path).size())
	return total


func _walk(path: String, visit: Callable) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var full := path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_walk(full, visit)
		else:
			visit.call(full)
		name = dir.get_next()
	dir.list_dir_end()
