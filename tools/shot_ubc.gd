# Рендер-стенд собранных персонажей UBC+MCO (П5.8, часть B): набор
# комбинаций внешности на нейтральном тёмном фоне — общий ряд, каждый
# крупно с трёх сторон, все 6 цветов игрока. Для самопроверки картинки
# агентом (SPEC 18): тело под одеждой скрыто, просветы, тон кожи/волос,
# перекраска радужки, цвет игрока на верхней одежде.
# Запуск сценой (autoload'ы нужны GraphicsQuality), сервер без экрана:
#   xvfb-run -a godot --path . --resolution 1280x720 \
#     --rendering-driver opengl3 res://tools/shot_ubc.tscn -- \
#     --out=builds/screenshots/ubc
extends Node3D

const MODEL_SCENE: PackedScene = preload("res://gameplay/player/character_model.tscn")

## Снимаемые комбинации: [имя файла, пол, причёска, верх, низ, обувь,
## убор, тон кожи, тон волос, цвет глаз] — индексы списков Appearance.
const COMBOS: Array = [
	["male_peasant", 0, 4, 0, 0, 0, 0, 1, 2, 3],
	["female_peasant", 1, 0, 0, 0, 0, 0, 5, 8, 0],
	["male_ranger_hood", 0, 1, 1, 1, 1, 1, 0, 1, 4],
	["female_ranger_hood", 1, 3, 1, 1, 1, 1, 6, 4, 2],
	["male_beard", 0, 5, 0, 0, 0, 0, 3, 6, 1],
	["female_buns", 1, 1, 1, 0, 1, 0, 2, 9, 5],
]
## Ракурс: имя → позиция камеры относительно персонажа.
const VIEWS: Dictionary = {
	"front": Vector3(0.0, 1.05, 3.4),
	"side": Vector3(3.4, 1.05, 0.0),
	"back": Vector3(0.0, 1.05, -3.4),
}
const OUT_PREFIX: String = "--out="


func _ready() -> void:
	var out_dir := "builds/screenshots/ubc"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(OUT_PREFIX):
			out_dir = arg.substr(OUT_PREFIX.length())
	DirAccess.make_dir_recursive_absolute(out_dir)

	var world := Node3D.new()
	world.name = "UbcStand"
	get_tree().root.add_child(world)
	_setup_stage(world)

	var models: Array[CharacterModel] = []
	for combo: Array in COMBOS:
		var ap := Appearance.new()
		ap.gender = combo[1]
		ap.hair = combo[2]
		ap.top = combo[3]
		ap.legs = combo[4]
		ap.feet = combo[5]
		ap.hat = combo[6]
		ap.skin = combo[7]
		ap.hair_color = combo[8]
		ap.eye_color = combo[9]
		var model := MODEL_SCENE.instantiate() as CharacterModel
		world.add_child(model)
		model.setup_appearance(ap)
		models.append(model)

	# Общий ряд из всех комбинаций.
	for i: int in models.size():
		models[i].position = Vector3((i - float(models.size() - 1) / 2.0) * 2.0, 0.0, 0.0)
	var camera := Camera3D.new()
	camera.fov = 40.0
	world.add_child(camera)
	camera.current = true
	await _warmup()
	# Диагностика стенда: что вообще видно из origin камеры.
	var visible_meshes := 0
	for node in world.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.visible and mi.mesh != null:
			visible_meshes += 1
	print("стенд: видимых мешей %d, камера %s, модели %d" % [
		visible_meshes, camera.global_position, models.size()])
	camera.global_position = Vector3(0.0, 1.1, 7.2)
	camera.look_at(Vector3(0.0, 0.95, 0.0))
	await _snap(out_dir.path_join("ubc_row.png"))

	# Каждый крупно с трёх сторон: снимаемый в origin, остальные спрятаны.
	for i: int in models.size():
		for j: int in models.size():
			models[j].visible = j == i
		models[i].position = Vector3.ZERO
		for view: String in VIEWS:
			camera.global_position = VIEWS[view]
			camera.look_at(Vector3(0.0, 0.95, 0.0))
			await _snap(out_dir.path_join(
				"ubc_%s_%s.png" % [COMBOS[i][0], view]))

	# Все 6 цветов игрока (id 0…5 покрывает palette_index полностью)
	# на мужском и женском peasant.
	for gender: int in Appearance.GENDERS:
		var row: Array[CharacterModel] = []
		for id: int in CharacterModel.PALETTES:
			var colored := MODEL_SCENE.instantiate() as CharacterModel
			world.add_child(colored)
			var ap := Appearance.default_for(gender)
			ap.skin = 4
			ap.hair_color = 3
			colored.setup_appearance(ap)
			colored.setup_palette(id)
			colored.position = Vector3((id - 2.5) * 1.7, 0.0, 0.0)
			row.append(colored)
		await _warmup()
		camera.global_position = Vector3(0.0, 1.15, 8.4)
		camera.look_at(Vector3(0.0, 0.95, 0.0))
		await _snap(out_dir.path_join("ubc_g%d_colors.png" % gender))
		for colored in row:
			colored.queue_free()
	get_tree().quit(0)


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
		await get_tree().process_frame


func _snap(path: String) -> void:
	await get_tree().create_timer(0.25).timeout
	get_viewport().get_texture().get_image().save_png(path)
	print("стенд: ", path)
