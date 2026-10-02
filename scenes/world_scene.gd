# Сцена мира (раздел 6 SPEC): остров (генерация — этап П2), игроки, мобы и UI.
# Этап П1 — полная тестовая площадка 64 × 64 м со ступенями в 1 блок, стенкой
# в 2 блока (критерий: «на 1 — да, на 2 — нет»), уступом в 3 блока (подсадка),
# ямой с HangPoint (состояние «Висит»), плитой, водой и Камнем духа.
# Вся статика собирается кодом из примитивов (правило проекта); сцены и зоны
# живых объектов (плита, вода, яма, камень) — дочерние узлы.
# Не делает: снапшоты и вход в идущий мир по сети — этап П3.
extends Node3D

const MENU_SCENE: String = "res://scenes/main_menu.tscn"
const PLAYER_SCENE: PackedScene = preload("res://gameplay/player/player.tscn")
const PLATE_SCENE: PackedScene = preload("res://gameplay/activities/pressure_plate.tscn")
const PAL: Palette = preload("res://assets/palette.tres")

## Позиция появления игрока (на юге площадки).
const SPAWN: Vector3 = Vector3(0.0, 1.0, 24.0)

## Ракурсы фототура для --shot-dir=PATH (самопроверка визуала через xvfb-run):
## спавн с Камнём духа, лесенка и стенка-2, яма с HangPoint, пруд, портрет.
const SHOT_TOUR: Array[Dictionary] = [
	{"name": "spawn", "from": Vector3(6.0, 3.5, 30.0), "at": Vector3(0.0, 1.0, 21.0)},
	{"name": "steps", "from": Vector3(7.0, 4.0, 2.0), "at": Vector3(0.0, 1.0, -5.0)},
	{"name": "pit", "from": Vector3(14.0, 5.0, 22.0), "at": Vector3(14.0, -1.0, 11.0)},
	{"name": "pond", "from": Vector3(-26.0, 4.0, -12.0), "at": Vector3(-26.0, -0.5, -27.0)},
	{"name": "player", "from": Vector3(2.4, 1.7, 26.2), "at": Vector3(0.0, 1.1, 24.0)},
]

var _debug: DebugPanel
var _esc_menu: EscMenu
var _player: Player
var _leaving: bool = false
var _materials: Dictionary = {}


func _ready() -> void:
	$Sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	_build_ground()
	_build_steps()
	_build_two_block_wall()
	_build_cliff()
	_build_pit()
	_build_pond()
	_add(PLATE_SCENE.instantiate(), Vector3(8.0, 0.0, -12.0))
	var stone := RespawnStone.new()
	_add(stone, Vector3(0.0, 0.0, 20.0))
	_spawn_player()
	add_child(WorldHud.new())
	_esc_menu = EscMenu.new()
	add_child(_esc_menu)
	_esc_menu.exit_requested.connect(_exit_to_menu)
	_debug = DebugPanel.new()
	add_child(_debug)
	_debug.watch_player(_player)
	Session.enter_world()
	EventBus.host_lost.connect(_on_host_lost)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not Dev.shot_dir.is_empty():
		_screenshot_tour()


## Фототур: временная камера обходит точки SHOT_TOUR и сохраняет PNG в
## Dev.shot_dir (создаётся), после чего закрывает игру. Только для проверок.
func _screenshot_tour() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	DirAccess.make_dir_recursive_absolute(Dev.shot_dir)
	for shot: Dictionary in SHOT_TOUR:
		camera.global_position = shot["from"]
		camera.look_at(shot["at"])
		await get_tree().create_timer(0.3).timeout
		var image := get_viewport().get_texture().get_image()
		var path: String = Dev.shot_dir.path_join("p1_%s.png" % shot["name"])
		image.save_png(path)
		Log.info("Скриншот сохранён: " + path, "World")
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	# Esc — меню (освобождает курсор, раздел 5); мир не на паузе (раздел 15).
	if event.is_action_pressed("pause"):
		_esc_menu.toggle()


func _exit_to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Session.leave_world()
	get_tree().call_deferred("change_scene_to_file", MENU_SCENE)


func _on_host_lost(_reason: String) -> void:
	# Хост вышел: мир закрылся у всех; экран «Встречи» на его месте — П7.
	_exit_to_menu()


func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = SPAWN
	add_child(_player)


func _add(node: Node, position: Vector3) -> void:
	add_child(node)
	if node is Node3D:
		(node as Node3D).position = position


# --- Геометрия площадки ---

func _build_ground() -> void:
	# Пол из панелей вокруг двух вырезов: пруд x[-32,-20] z[-32,-22] и яма
	# x[10,18] z[6,16]; боковые грани соседних панелей образуют стенки.
	_ground_panel(Vector3(-26.0, -0.5, 5.0), Vector3(12, 1, 54))    # запад
	_ground_panel(Vector3(6.0, -0.5, -13.0), Vector3(52, 1, 38))    # север-центр
	_ground_panel(Vector3(-5.0, -0.5, 11.0), Vector3(30, 1, 10))    # запад ямы
	_ground_panel(Vector3(25.0, -0.5, 11.0), Vector3(14, 1, 10))    # восток ямы
	_ground_panel(Vector3(6.0, -0.5, 24.0), Vector3(52, 1, 16))     # юг
	# Дно ямы (глубина 4 м) и дно пруда.
	_box(Vector3(8, 1, 10), Vector3(14.0, -4.5, 11.0), PAL.stone)
	_box(Vector3(12, 0.6, 10), Vector3(-26.0, -1.5, -27.0), PAL.sand)
	# Невидимые ограждения по периметру, чтобы не упасть за край мира.
	_wall(Vector3(0.0, 0.0, -32.5), Vector3(65, 4, 1))
	_wall(Vector3(0.0, 0.0, 32.5), Vector3(65, 4, 1))
	_wall(Vector3(-32.5, 0.0, 0.0), Vector3(1, 4, 65))
	_wall(Vector3(32.5, 0.0, 0.0), Vector3(1, 4, 65))


func _ground_panel(center: Vector3, size: Vector3) -> void:
	_box(size, center, PAL.grass)


func _build_steps() -> void:
	# Лесенка со ступенями в 1 блок: с пола на первую ступень запрыгивается
	# (критерий этапа), вторая — ещё +1 блок.
	_box(Vector3(2, 1, 2), Vector3(0.0, 0.5, -8.0), PAL.grass)
	_box(Vector3(2, 2, 2), Vector3(0.0, 1.0, -6.0), PAL.dirt)
	_box(Vector3(4, 2, 4), Vector3(0.0, 1.0, -2.5), PAL.dirt)


func _build_two_block_wall() -> void:
	# Стенка высотой 2 блока: прыжком с земли не берётся (высота ~1.4 м).
	_box(Vector3(6, 2, 0.6), Vector3(-8.0, 1.0, 6.0), PAL.stone)


func _build_cliff() -> void:
	# Уступ в 3 блока: без подсадки на голову не забраться (П3+), со стороны
	# стенки-2 не допрыгнуть (18 м по горизонтали).
	_box(Vector3(6, 3, 6), Vector3(-26.0, 1.5, 8.0), PAL.stone)


func _build_pit() -> void:
	# Яма с CrevasseArea и точками HangPoint на кромке (раздел 9.1).
	var area := HangArea.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(7.6, 3.2, 9.6)
	shape.shape = box
	area.add_child(shape)
	for local_point: Vector3 in [
		Vector3(0.0, 2.25, -4.6),
		Vector3(0.0, 2.25, 4.6),
		Vector3(-3.6, 2.25, 0.0),
		Vector3(3.6, 2.25, 0.0),
	]:
		var marker := Marker3D.new()
		marker.position = local_point
		area.add_child(marker)
	_add(area, Vector3(14.0, -2.2, 11.0))


func _build_pond() -> void:
	# Пруд: входим с берега, плаваем на поверхности, выпрыгиваем обратно.
	var water := WaterArea.new()
	_add(water, Vector3(-26.0, 0.0, -27.0))
	water.setup(Vector2(-26.0, -27.0), Vector2(11.6, 9.6), -0.15)


## Статичный цветной бокс с коллизией (вся графика — из примитивов).
func _box(size: Vector3, center: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = _material(color)
	body.add_child(mesh)
	body.position = center
	add_child(body)


## Невидимая стена (коллизия без меша).
func _wall(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	add_child(body)


func _material(color: Color) -> StandardMaterial3D:
	if _materials.has(color):
		return _materials[color] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	_materials[color] = material
	return material
