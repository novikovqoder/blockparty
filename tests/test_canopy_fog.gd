# Тесты П17 п.4 «Туман крон»: у крон собственное смешение с туманом —
# тон темнее и зеленее цвета дневного тумана палитры, начало раньше
# Environment-тумана (плотность баланса при этом НЕ меняется). П18
# Сборка 1 п.2 убрала импостор-шейдер — формула осталась одна, у крон.
extends GutTest

const B: Balance = preload("res://gameplay/balance.tres")
const VPAL: VisualPalette = preload("res://assets/visual_palette.tres")
const CANOPY: Shader = preload("res://assets/shaders/canopy.gdshader")

const ENV_DENSITY: float = 0.0035


func test_tint_darker_and_greener_than_day_fog() -> void:
	# Тон тумана крон против day_fog палитры: ярче быть не может (темнее),
	# доля зелёного против суммы красного и синего — заметно выше.
	var tint := _const_vec3(CANOPY.code, "FOG_TINT")
	assert_false(is_nan(tint.x), "FOG_TINT найден в canopy-шейдере")
	if is_nan(tint.x):
		return
	var day := VPAL.day_fog
	assert_lt(_luminance(tint), _luminance(Vector3(day.r, day.g, day.b)),
		"туман крон темнее дневного тумана палитры")
	assert_gte(_green_share(tint) - _green_share(
			Vector3(day.r, day.g, day.b)), 0.03,
		"туман крон зеленее дневного тумана палитры")


func test_fog_starts_sooner_environment_untouched() -> void:
	# Плотность шейдера выше баланса (кроны затягивает раньше), но сама
	# плотность Environment-тумана не тронута — тон, не сила общего тумана.
	var density := _const_float(CANOPY.code, "FOG_DENSITY")
	assert_false(is_nan(density), "FOG_DENSITY найден в canopy-шейдере")
	if is_nan(density):
		return
	assert_between(density, B.fog_density * 1.05, B.fog_density * 1.5,
		"туман крон начинается раньше Environment (×1.05…×1.5)")
	assert_almost_eq(B.fog_density, ENV_DENSITY, 0.0000001,
		"плотность Environment-тумана не изменилась (0.0035)")


func test_fog_written_from_user_fog_function() -> void:
	# FOG пишется из пользовательской fog() (процессорной функции тумана
	# в Godot нет, docs 4.7 spatial) — формула одна у крон, импосторного
	# шейдера больше нет (П18 Сборка 1 п.2).
	assert_true(CANOPY.code.contains("FOG = fog("),
		"крона пишет FOG из fog()")
	assert_false(ClassDB.class_exists("TreeImpostors"),
		"класс импосторов удалён")
	var shader_path := "res://assets/shaders/impostor.gdshader"
	assert_false(FileAccess.file_exists(shader_path),
		"impostor.gdshader удалён")


func test_shader_code_parses() -> void:
	# Разбор кода свежим Shader'ом (GPU-компиляции в headless нет, при
	# синтаксической ошибке список uniform'ов пуст — приём приёмки воды
	# П15-ДОП блок 7): fog() — пользовательская функция с аргументами,
	# запись в FOG — обе новинки должны разбираться движком.
	for shader: Shader in [CANOPY]:
		var fresh := Shader.new()
		fresh.code = shader.code
		var uniforms: Array = fresh.get_shader_uniform_list()
		assert_gt(uniforms.size(), 5,
			"%s разбирается (uniform'ов > 5)" % shader.resource_path.get_file())


## Значение «const vec3 <имя> = vec3(…)» из кода шейдера (NAN, если нет).
func _const_vec3(code: String, const_name: String) -> Vector3:
	var regex := RegEx.new()
	regex.compile("const vec3 %s = vec3\\(([\\d.,\\s]+)\\)" % const_name)
	var found := regex.search(code)
	if found == null:
		return Vector3(NAN, NAN, NAN)
	var parts := found.get_string(1).split(",")
	return Vector3(parts[0].to_float(), parts[1].to_float(),
		parts[2].to_float())


## Значение «const float <имя> = …» из кода шейдера (NAN, если нет).
func _const_float(code: String, const_name: String) -> float:
	var regex := RegEx.new()
	regex.compile("const float %s = ([\\d.]+)" % const_name)
	var found := regex.search(code)
	return NAN if found == null else found.get_string(1).to_float()


func _luminance(color: Vector3) -> float:
	return 0.299 * color.x + 0.587 * color.y + 0.114 * color.z


func _green_share(color: Vector3) -> float:
	return color.y / maxf(color.x + color.z, 0.0001)
