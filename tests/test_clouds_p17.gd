extends GutTest
## П17 п.9 (решение владельца 03.11): кучевость без полос яркости —
## проектная копия SkyMaterial аддона Sky3D с неподвижным пространственным
## дизерингом старта марша (БЕЗ TIME — мерцание без TAA недопустимо) и
## шагами марша по уровню качества. Сам аддон не правится.

const COPY_PATH: String = "res://assets/shaders/sky_material_p17.gdshader"
const ADDON_SHADER: String = "res://addons/sky_3d/shaders/SkyMaterial.gdshader"
const ADDON_COMMON: String = "res://addons/sky_3d/shaders/Common.gdshaderinc"
## SHA256 нетронутых файлов аддона на момент П17 (трипваер: правка аддона
## обязана оставлять пустой diff — см. решение владельца).
const ADDON_SHADER_SHA: String = \
	"920791cb2cadf5e303474220ba3093b9bd3d76605fedc92eb5bef835c1b35ad9"
const ADDON_COMMON_SHA: String = \
	"6265f2967250679e1b350b6133046c4f9b5b54029aea728f3a4aeb21685853c7"

const WORLD: PackedScene = preload("res://scenes/world_scene.tscn")


func _copy_text() -> String:
	return FileAccess.get_file_as_string(COPY_PATH)


## Тело функции марша кучевости — между её сигнатурой и следующим
## объявлением верхнего уровня, без комментариев (документация правок
## упоминает TIME словами — проверяется код, а не комментарии).
func _march_body(text: String) -> String:
	var start := text.find("vec4 render_cumulus_clouds(")
	assert_gt(start, -1, "копия содержит render_cumulus_clouds")
	var end := text.find("\nvec3 render_sky(", start)
	var code := ""
	for line: String in text.substr(start, end - start).split("\n"):
		code += line.split("//")[0] + "\n"
	return code


func test_world_sky_uses_project_copy() -> void:
	# Небо мира ссылается на копию (аддон не правится); копия существует
	# и грузится как шейдер.
	assert_true(ResourceLoader.exists(COPY_PATH), "файл копии есть")
	var scene := WORLD.instantiate()
	var material := (scene.get_node("WorldEnvironment") as WorldEnvironment) \
		.environment.sky.sky_material as ShaderMaterial
	assert_eq(material.shader.resource_path, COPY_PATH,
		"сцена мира использует проектную копию шейдера неба")
	scene.free()


func test_march_dither_static_no_time() -> void:
	# Дизеринг старта марша: попиксельный шум по направлению луча есть,
	# зависимости от TIME в коде марша НЕТ (TAA отсутствует — узор по
	# кадрам мерцал бы); дебандинг купола оставлен.
	var text := _copy_text()
	assert_true(text.contains("use_debanding"),
		"дебандинг неба не снят (render_mode)")
	assert_true(text.contains("43758.5453"),
		"дизеринг марша — попиксельный шум (хэш направления луча)")
	assert_true(text.contains("float jitter"),
		"джиттер старта марша объявлен")
	var march := _march_body(text)
	assert_false(march.contains("TIME"),
		"марш кучевости не зависит от TIME (неподвижный дизеринг)")


func test_march_steps_uniform_and_tiers() -> void:
	# Шаги марша — uniform (по уровню качества), дефолт — базовые 10
	# аддона; уровни: SIMPLE < NORMAL < HIGH (=10) < ULTRA.
	var text := _copy_text()
	assert_true(text.contains("uniform int cumulus_steps = 10;"),
		"шаги марша — uniform с базовым дефолтом")
	assert_lt(GraphicsQuality.cloud_steps(GraphicsQuality.Tier.SIMPLE),
		GraphicsQuality.cloud_steps(GraphicsQuality.Tier.NORMAL),
		"SIMPLE шагов меньше NORMAL")
	assert_lt(GraphicsQuality.cloud_steps(GraphicsQuality.Tier.NORMAL),
		GraphicsQuality.cloud_steps(GraphicsQuality.Tier.HIGH),
		"NORMAL шагов меньше HIGH")
	assert_eq(GraphicsQuality.cloud_steps(GraphicsQuality.Tier.HIGH), 10,
		"HIGH — базовые 10 шагов аддона (бюджет ~1 мс)")
	assert_gt(GraphicsQuality.cloud_steps(GraphicsQuality.Tier.ULTRA),
		GraphicsQuality.cloud_steps(GraphicsQuality.Tier.HIGH),
		"ULTRA шагов больше HIGH")


func test_addon_not_modified() -> void:
	# Аддон не правится (пустой diff): шейдер и инклуд совпадают с
	# зафиксированными на момент П17 контрольными суммами.
	assert_eq(FileAccess.get_sha256(ADDON_SHADER), ADDON_SHADER_SHA,
		"SkyMaterial.gdshader аддона не изменён")
	assert_eq(FileAccess.get_sha256(ADDON_COMMON), ADDON_COMMON_SHA,
		"Common.gdshaderinc аддона не изменён")


func test_copy_includes_addon_common() -> void:
	# Копия подключает общий инклуд аддона абсолютным путём (свой
	# Common.gdshaderinc рядом не дублируется).
	var text := _copy_text()
	assert_true(text.contains(
		"#include \"res://addons/sky_3d/shaders/Common.gdshaderinc\""),
		"копия инклюдит Common из аддона")
	assert_true(ResourceLoader.exists(ADDON_COMMON),
		"инклуд аддона существует")
