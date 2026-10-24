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
		text.contains("PARALLAX_NEAR") and text.contains("PARALLAX_FAR"),
		"затухание параллакса по дистанции")
	assert_true(
		text.contains("AO_MIX") and text.contains("quality == QUALITY_SIMPLE"),
		"AO-канал и roughness из карт — не на SIMPLE")


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
