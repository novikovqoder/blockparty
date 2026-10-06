# Рендер-стенд персонажей (замена персонажей, шаги 2+): три модели KayKit
# с уборами и контуром на нейтральном тёмном фоне — по три ракурса
# (фронт/бок/зад) и общий ряд. Для осмотра картинки самим агентом
# (SPEC 18: «Самопроверка картинки»), шаг 10 расширяет список цветами
# и сценами в игре.
# Запуск (сервер без экрана, только opengl3 — Forward+/llvmpipe сегфолтит):
#   xvfb-run -a godot --path . --resolution 1280x720 \
#     --rendering-driver opengl3 -s res://tools/shot_characters.gd -- \
#     --out=builds/screenshots/chars
extends SceneTree

const MODEL_SCENE: PackedScene = preload("res://gameplay/player/character_model.tscn")
const NAMES: PackedStringArray = ["knight", "mage", "ranger"]
## Ракурс: имя → позиция камеры относительно персонажа.
const VIEWS: Dictionary = {
	"front": Vector3(0.0, 1.05, 3.4),
	"side": Vector3(3.4, 1.05, 0.0),
	"back": Vector3(0.0, 1.05, -3.4),
}
## Анимационные кадры: имя → [состояние Protocol.AnimState, пауза до
## снимка в середине клипа, с].
const ANIM_SHOTS: Array = [
	["idle", Protocol.AnimState.IDLE, 0.6],
	["walk", Protocol.AnimState.WALK, 0.55],
	["run", Protocol.AnimState.RUN, 0.4],
	["jump", Protocol.AnimState.JUMP, 0.25],
	["fall", Protocol.AnimState.FALL, 0.5],
	["land", Protocol.AnimState.LAND, 0.2],
	["wave", Protocol.AnimState.WAVE, 1.0],
	["sit", Protocol.AnimState.SIT, 1.6],
]
const OUT_PREFIX: String = "--out="


func _init() -> void:
	var out_dir := "builds/screenshots/chars"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(OUT_PREFIX):
			out_dir = arg.substr(OUT_PREFIX.length())
	DirAccess.make_dir_recursive_absolute(out_dir)

	var world := Node3D.new()
	world.name = "CharStand"
	root.add_child(world)
	_setup_stage(world)

	var models: Array[CharacterModel] = []
	for i: int in NAMES.size():
		var model := MODEL_SCENE.instantiate() as CharacterModel
		world.add_child(model)
		model.setup(i)
		models.append(model)

	# Ряд из троих — общий план.
	for i: int in models.size():
		models[i].position = Vector3((i - 1) * 2.0, 0.0, 0.0)
	var camera := Camera3D.new()
	camera.fov = 40.0
	world.add_child(camera)
	camera.current = true
	await _warmup()
	camera.global_position = Vector3(0.0, 1.1, 5.6)
	camera.look_at(Vector3(0.0, 0.95, 0.0))
	await _snap(out_dir.path_join("chars_row.png"))

	# Каждый крупно с трёх сторон: снимаемый в origin, остальные спрятаны.
	for i: int in models.size():
		var model := models[i]
		for j: int in models.size():
			models[j].visible = j == i
		model.position = Vector3.ZERO
		for view: String in VIEWS:
			camera.global_position = VIEWS[view]
			camera.look_at(Vector3(0.0, 0.95, 0.0))
			await _snap(out_dir.path_join(
				"char_%s_%s.png" % [NAMES[i], view]
			))
		models[i].visible = false

	# Все 6 цветов игрока рядом для каждого персонажа (шаги 3 и 10):
	# id 0…5 покрывают все варианты palette_index.
	for i: int in NAMES.size():
		var row: Array[CharacterModel] = []
		for id: int in 6:
			var colored := MODEL_SCENE.instantiate() as CharacterModel
			world.add_child(colored)
			colored.setup(i)
			colored.setup_palette(id)
			colored.position = Vector3((id - 2.5) * 1.7, 0.0, 0.0)
			row.append(colored)
		await _warmup()
		camera.global_position = Vector3(0.0, 1.15, 8.4)
		camera.look_at(Vector3(0.0, 0.95, 0.0))
		await _snap(out_dir.path_join("char_%s_colors.png" % NAMES[i]))
		for colored in row:
			colored.queue_free()

	# Анимации KayKit (шаг 4): knight — все состояния из ТЗ (покой, ходьба,
	# бег, прыжок взлёт/полёт/приземление, помахать, сесть), mage/ranger —
	# ходьба и взмах (клипы на всех трёх ригах). Кадр в середине клипа.
	for i: int in models.size():
		var model := models[i]
		for j: int in models.size():
			models[j].visible = j == i
		model.position = Vector3.ZERO
		camera.global_position = VIEWS["front"]
		camera.look_at(Vector3(0.0, 0.95, 0.0))
		for shot: Array in ANIM_SHOTS:
			if i != 0 and not ["walk", "wave"].has(shot[0]):
				continue  # полный набор — только для knight
			model.set_state(shot[1])
			await create_timer(shot[2]).timeout
			await _snap(out_dir.path_join(
				"char_%s_anim_%s.png" % [NAMES[i], shot[0]]
			))
		model.visible = false
	quit(0)


func _setup_stage(world: Node3D) -> void:
	# Нейтральный тёмный фон и ровный серый пол: видно и светлую модель,
	# и чёрный контур, без отвлекающих зон.
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.17, 0.17, 0.20)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	environment.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = environment
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -30.0, 0.0)
	sun.light_energy = 1.1
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24.0, 24.0)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.30, 0.30, 0.33)
	material.roughness = 1.0
	ground.material_override = material
	world.add_child(ground)


func _warmup() -> void:
	# Несколько кадров на компиляцию шейдеров и первый скиннинг.
	for i: int in 8:
		await process_frame


func _snap(path: String) -> void:
	await create_timer(0.25).timeout
	root.get_texture().get_image().save_png(path)
	print("стенд: ", path)
