# Экран выбора персонажа (раздел 15 SPEC, кнопка «Персонаж» в меню):
# в центре 3D-модель выбранного персонажа в цвете игрока (цвет по хэшу id,
# как в мире) — покой и периодический взмах; модель крутится мышью
# (зажать и тянуть, с небольшой инерцией), колёсико — зум, без ввода
# 3 секунды медленно поворачивается сама. Стрелки ‹ › и ← → переключают
# персонажей; сбоку — панель трёх характеристик с плавным заполнением
# 0.3 с; внизу — имя, девиз, описание, «Любит». «Выбрать» сохраняет выбор
# в user:// (Save) и возвращается в меню, «Назад» — без сохранения.
# Панели не перекрывают модель при любом размере окна: 3D-зона — отдельный
# SubViewportContainer, сжимающийся вместе с окном.
extends Control

const B: Balance = preload("res://gameplay/balance.tres")
const MAIN_MENU: String = "res://scenes/main_menu.tscn"
## Чувствительность вращения, рад на пиксель драга.
const SPIN_SENS: float = 0.009
## Торможение инерции после отпускания, рад/с².
const SPIN_DECEL: float = 3.0
## Автоповорот: после стольких секунд покоя, рад/с.
const AUTO_TURN_DELAY: float = 3.0
const AUTO_TURN_SPEED: float = 0.35
## Зум колёсиком: база и пределы, м. База 3.5 со взглядом на 1.02 — иначе
## шляпа Луми (самая высокая модель) упирается в верх кадра без запаса.
const ZOOM_BASE: float = 3.5
const ZOOM_MIN: float = 2.3
const ZOOM_MAX: float = 4.4
const ZOOM_STEP: float = 0.3
const CAM_HEIGHT: float = 1.05
const CAM_LOOK_Y: float = 1.02

@onready var model: CharacterModel = $ViewArea/View/Model
@onready var camera: Camera3D = $ViewArea/View/Camera
@onready var bars: Array[StatBar] = [
	$StatsPanel/Margin/Rows/StrengthRow/Bar as StatBar,
	$StatsPanel/Margin/Rows/SpeedRow/Bar as StatBar,
	$StatsPanel/Margin/Rows/JumpRow/Bar as StatBar,
]
@onready var name_label: Label = $InfoPanel/Margin/Rows/Name
@onready var motto_label: Label = $InfoPanel/Margin/Rows/Motto
@onready var desc_label: Label = $InfoPanel/Margin/Rows/Desc
@onready var loves_label: Label = $InfoPanel/Margin/Rows/Loves

## id игрока — тот же, по которому мир красит модель (Steam id / peer id).
var _own_id: int = 0
var _index: int = 0
var _yaw: float = 0.0
var _spin: float = 0.0
var _zoom: float = ZOOM_BASE
var _idle: float = 0.0
var _dragging: bool = false
## До следующего взмаха, с.
var _wave_in: float = 4.0


func _ready() -> void:
	LocLabels.apply(self)
	_own_id = SteamService.steam_id if SteamService.steam_id != 0 \
		else Net.local_peer_id
	_index = Save.load_character()
	camera.look_at_from_position(
		camera.global_position, Vector3(0.0, CAM_LOOK_Y, 0.0))
	_apply()
	Log.info("Экран персонажа: показываю %d (выбор из save)" % _index, "Menu")
	if not Dev.shot_dir.is_empty():
		_screenshot_tour()


## Фототур экрана (шаги 7 и 10 П4.6, как тур мира в world_scene): кадр
## каждого из трёх персонажей — PNG в Dev.shot_dir, после чего игра
## закрывается. Только для проверок (запуск с --shot-dir=PATH).
func _screenshot_tour() -> void:
	DirAccess.make_dir_recursive_absolute(Dev.shot_dir)
	for i: int in CharacterModel.count():
		_index = i
		_apply()
		await get_tree().create_timer(0.9).timeout
		var path := Dev.shot_dir.path_join("select_character_%d.png" % i)
		get_viewport().get_texture().get_image().save_png(path)
		print("экран выбора: ", path)
	get_tree().quit()


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_left"):
		_switch(-1)
	if Input.is_action_just_pressed("ui_right"):
		_switch(1)
	_idle += delta
	# Инерция драга затухает; без ввода модель медленно поворачивается сама.
	_yaw += _spin * delta
	_spin = move_toward(_spin, 0.0, SPIN_DECEL * delta)
	if _idle > AUTO_TURN_DELAY:
		_yaw += AUTO_TURN_SPEED * delta
	model.rotation.y = _yaw
	_wave_in -= delta
	if _wave_in <= 0.0:
		model.play_one_shot(Protocol.AnimState.WAVE, B.wave_time)
		_wave_in = randf_range(6.0, 10.0)


## Переключить персонажа (dir = ±1) и обновить панели.
func _switch(dir: int) -> void:
	_index = wrapi(_index + dir, 0, CharacterModel.count())
	_idle = 0.0
	_spin = 0.0
	_apply()


## Перестроить модель под _index и заполнить панели характеристик и текстов.
func _apply() -> void:
	model.setup(_index)
	model.setup_palette(_own_id)
	model.rotation.y = _yaw
	var entry := CharacterData.get_character(_index)
	name_label.text = CharacterData.pick_text(entry["name"])
	motto_label.text = CharacterData.pick_text(entry["motto"])
	desc_label.text = CharacterData.pick_text(entry["description"])
	loves_label.text = tr("CHARACTER_LOVES") % CharacterData.pick_text(entry["loves"])
	var stats := CharacterData.stats(_index)
	bars[0].animate_to(stats["strength"] as int)
	bars[1].animate_to(stats["speed"] as int)
	bars[2].animate_to(stats["jump"] as int)
	_wave_in = randf_range(4.0, 7.0)


## Драг и колёсико по 3D-зоне (SpinArea поверх SubViewportContainer).
func _on_spin_area_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
			if _dragging:
				_spin = 0.0
			_idle = 0.0
		elif button.pressed and (button.button_index == MOUSE_BUTTON_WHEEL_UP
				or button.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_set_zoom(ZOOM_STEP if button.button_index == MOUSE_BUTTON_WHEEL_UP
				else -ZOOM_STEP)
			_idle = 0.0
	elif _dragging and event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var turn: float = -motion.relative.x * SPIN_SENS
		_yaw += turn
		# Скорость для инерции: пиксели за кадр ≈ движение за 1/60 с.
		_spin = lerpf(_spin, turn * 60.0, 0.4)
		_idle = 0.0


func _set_zoom(step: float) -> void:
	_zoom = clampf(_zoom + step, ZOOM_MIN, ZOOM_MAX)
	camera.position = Vector3(0.0, CAM_HEIGHT, _zoom)


func _on_prev_pressed() -> void:
	_switch(-1)


func _on_next_pressed() -> void:
	_switch(1)


func _on_choose_pressed() -> void:
	Save.save_character(_index)
	Log.info("Персонаж %d выбран и сохранён" % _index, "Menu")
	_back_to_menu()


func _on_back_pressed() -> void:
	_back_to_menu()


func _back_to_menu() -> void:
	get_tree().call_deferred("change_scene_to_file", MAIN_MENU)
