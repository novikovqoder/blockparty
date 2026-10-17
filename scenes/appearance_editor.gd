# Редактор внешности (П5.8, часть B2): слева модель в полный рост — мышь
# вращает с инерцией, колёсико — зум, 3 с без ввода модель медленно
# поворачивается сама; студийная схема света в tscn (ключевой Sun с мягкой
# тенью на подиум, холодные контровые Rim/RimSide отделяют силуэт, тёплая
# Omni подсвечивает лицо, тоника Filmic как в мире). Справа панель: тело
# (пол), причёска (список по полу), цвета волос/кожи/глаз, верх, низ,
# обувь, головной убор («без» — только убор: персонаж всегда одет) и
# «Случайно». «Выбрать» сохраняет внешность в user:// (Save) и возвращается
# в меню, «Назад» — без сохранения.
class_name AppearanceEditor
extends Control

const MAIN_MENU: String = "res://scenes/main_menu.tscn"
const PAL: Palette = preload("res://assets/palette.tres")
## tr-ключи названий — параллельно спискам Appearance.
const HAIR_KEYS: PackedStringArray = [
	"APPEARANCE_HAIR_LONG", "APPEARANCE_HAIR_BUNS", "APPEARANCE_HAIR_BUZZED",
	"APPEARANCE_HAIR_BUZZED_FEMALE", "APPEARANCE_HAIR_PARTED",
	"APPEARANCE_HAIR_BEARD",
]
const OUTFIT_KEYS: PackedStringArray = [
	"APPEARANCE_OUTFIT_PEASANT", "APPEARANCE_OUTFIT_RANGER",
]
const HAT_KEYS: PackedStringArray = [
	"APPEARANCE_HAT_NONE", "APPEARANCE_HAT_HOOD", "APPEARANCE_HAT_PANAMA",
	"APPEARANCE_HAT_BRIM", "APPEARANCE_HAT_CAP",
]
## Чувствительность вращения, рад на пиксель драга.
const SPIN_SENS: float = 0.009
## Торможение инерции после отпускания, рад/с².
const SPIN_DECEL: float = 3.0
## Автоповорот: после стольких секунд покоя, рад/с.
const AUTO_TURN_DELAY: float = 3.0
const AUTO_TURN_SPEED: float = 0.35
## Зум колёсиком: база и пределы, м. Охват кадра по вертикали ≈ [-0.23, 2.09]:
## снизу подиум с запасом, сверху макушка 1.65 с высокой причёской; fov 33,
## взгляд на 0.95 — рост в кадре целиком.
const ZOOM_BASE: float = 3.9
const ZOOM_MIN: float = 2.6
const ZOOM_MAX: float = 4.8
const ZOOM_STEP: float = 0.3
const CAM_HEIGHT: float = 1.18
const CAM_LOOK_Y: float = 0.95
## Фототур редактора (--shot-dir, проверки SPEC 18): шесть собранных
## персонажей — Appearance.SHOWCASE (общий список с групповыми кадрами
## мира SHOT_CREW: на снимках «в редакторе» и «в мире» одни герои).
## Первые трое — как жители острова (кепка/шляпа/панама), дальше капюшон
## и «без убора».

@onready var model: CharacterModel = $ViewArea/View/Model
@onready var camera: Camera3D = $ViewArea/View/Camera
@onready var sections: VBoxContainer = $Panel/Margin/Box/Scroll/Sections

## Текущая внешность (всегда валидная комбинация).
var ap: Appearance = null

var _yaw: float = 0.0
var _spin: float = 0.0
var _zoom: float = ZOOM_BASE
var _idle: float = 0.0
var _dragging: bool = false
## До следующего взмаха, с (клипы появятся в части C, вызов безвреден).
var _wave_in: float = 5.0
## Подписи значений переключателей «‹ значение ›» (slot → Label).
var _value_labels: Dictionary = {}
## Цветовые кнопки (slot → массивы кнопок и цветов палитры).
var _swatch_buttons: Dictionary = {}
var _swatch_colors: Dictionary = {}
## Кнопки пола.
var _gender_buttons: Array[Button] = []


func _ready() -> void:
	LocLabels.apply(self)
	_style_panel()
	_build_panel()
	ap = Save.load_appearance()
	camera.look_at_from_position(
		camera.global_position, Vector3(0.0, CAM_LOOK_Y, 0.0))
	$ViewArea/View/Rim.look_at(Vector3(0.0, 0.95, 0.0))
	$ViewArea/View/RimSide.look_at(Vector3(0.0, 0.9, 0.0))
	_apply()
	Log.info("Редактор внешности открыт (внешность из save)", "Menu")
	if not Dev.shot_dir.is_empty():
		_screenshot_tour()


func _process(delta: float) -> void:
	_idle += delta
	# Инерция драга затухает; без ввода модель медленно поворачивается сама.
	_yaw += _spin * delta
	_spin = move_toward(_spin, 0.0, SPIN_DECEL * delta)
	if _idle > AUTO_TURN_DELAY:
		_yaw += AUTO_TURN_SPEED * delta
	model.rotation.y = _yaw
	_wave_in -= delta
	if _wave_in <= 0.0:
		model.play_one_shot(Protocol.AnimState.WAVE, 2.0)
		_wave_in = randf_range(6.0, 10.0)


# --- Панель настроек (строится кодом из списков Appearance) ---

## Стиль панели — как у esc_menu: тёмная плашка с углами.
func _style_panel() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = PAL.hud_panel
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	($Panel as PanelContainer).add_theme_stylebox_override("panel", style)


## Секция с заголовком; контент добавляет вызывающий.
func _add_section(title_key: String) -> VBoxContainer:
	var title := Label.new()
	title.text = tr(title_key)
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.6))
	sections.add_child(title)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	sections.add_child(box)
	return box


## Переключатель «‹ значение ›»: возвращает строку, подпись обновляет
## _refresh. on_step получает ±1.
func _add_cycle(parent: Container, slot: String, on_step: Callable) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var value := Label.new()
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 18)
	for dir: int in [-1, 1]:
		var arrow := Button.new()
		arrow.text = "‹" if dir < 0 else "›"
		arrow.add_theme_font_size_override("font_size", 26)
		arrow.custom_minimum_size = Vector2(42, 42)
		arrow.pressed.connect(on_step.bind(dir))
		# Стрелка в конец строки для dir=+1: добавляем после подписи.
		if dir < 0:
			row.add_child(arrow)
			row.add_child(value)
		else:
			row.add_child(arrow)
	parent.add_child(row)
	_value_labels[slot] = value
	return value


## Ряд цветовых кнопок (палитра внешности): отметка выбранной — рамкой.
func _add_swatches(parent: Container, slot: String,
		colors: PackedColorArray) -> void:
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)
	var buttons: Array[Button] = []
	for index: int in colors.size():
		var color: Color = colors[index]
		var button := Button.new()
		button.custom_minimum_size = Vector2(30, 30)
		button.focus_mode = Control.FOCUS_NONE
		_paint_swatch(button, color, false)
		button.pressed.connect(_pick_color.bind(slot, index))
		grid.add_child(button)
		buttons.append(button)
	_swatch_buttons[slot] = buttons
	_swatch_colors[slot] = colors


func _paint_swatch(button: Button, color: Color, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	var radius := 15
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_width_top = 3 if selected else 1
	style.border_width_bottom = 3 if selected else 1
	style.border_width_left = 3 if selected else 1
	style.border_width_right = 3 if selected else 1
	style.border_color = Color(1.0, 0.95, 0.7) if selected \
		else Color(0.0, 0.0, 0.0, 0.55)
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.15)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _build_panel() -> void:
	# Тело: мужское/женское, взаимоисключающие кнопки.
	var body := _add_section("APPEARANCE_BODY")
	var body_row := HBoxContainer.new()
	body_row.add_theme_constant_override("separation", 10)
	body.add_child(body_row)
	var group := ButtonGroup.new()
	for gender: int in Appearance.GENDERS:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(0, 44)
		button.add_theme_font_size_override("font_size", 18)
		button.text = tr("APPEARANCE_BODY_MALE" if gender == Appearance.GENDER_MALE
			else "APPEARANCE_BODY_FEMALE")
		button.pressed.connect(_set_gender.bind(gender))
		body_row.add_child(button)
		_gender_buttons.append(button)
	# Причёска и одежда — переключатели, палитры — кнопки-кружки.
	_add_cycle(_add_section("APPEARANCE_HAIR"), "hair", _step_hair)
	_add_swatches(_add_section("APPEARANCE_HAIR_COLOR"), "hair_color",
		Appearance.HAIR_COLORS)
	_add_swatches(_add_section("APPEARANCE_SKIN"), "skin",
		Appearance.SKIN_COLORS)
	_add_swatches(_add_section("APPEARANCE_EYES"), "eye_color",
		Appearance.EYE_COLORS)
	_add_cycle(_add_section("APPEARANCE_TOP"), "top",
		_step_index.bind("top", Appearance.OUTFITS.size()))
	_add_cycle(_add_section("APPEARANCE_LEGS"), "legs",
		_step_index.bind("legs", Appearance.OUTFITS.size()))
	_add_cycle(_add_section("APPEARANCE_FEET"), "feet",
		_step_index.bind("feet", Appearance.OUTFITS.size()))
	_add_cycle(_add_section("APPEARANCE_HAT"), "hat",
		_step_index.bind("hat", Appearance.HATS))


# --- Изменения ---

func _set_gender(gender: int) -> void:
	ap.gender = gender
	ap = ap.validated()  # причёска заменяется допустимой для пола
	_apply()


func _step_hair(dir: int) -> void:
	var variants := Appearance.hair_variants(ap.gender)
	var current: int = variants.find(ap.hair)
	ap.hair = variants[wrapi(current + dir, 0, variants.size())]
	_apply()


func _step_index(field: String, count: int, dir: int) -> void:
	ap.set(field, wrapi(int(ap.get(field)) + dir, 0, count))
	_apply()


func _pick_color(slot: String, index: int) -> void:
	ap.set(slot, index)
	_apply()


## Перестроить модель и обновить подписи/отметки панели.
func _apply() -> void:
	model.setup_appearance(ap)
	model.rotation.y = _yaw
	_refresh()


func _refresh() -> void:
	for gender: int in _gender_buttons.size():
		_gender_buttons[gender].set_pressed_no_signal(gender == ap.gender)
	(_value_labels["hair"] as Label).text = tr(HAIR_KEYS[ap.hair])
	(_value_labels["top"] as Label).text = tr(OUTFIT_KEYS[ap.top])
	(_value_labels["legs"] as Label).text = tr(OUTFIT_KEYS[ap.legs])
	(_value_labels["feet"] as Label).text = tr(OUTFIT_KEYS[ap.feet])
	(_value_labels["hat"] as Label).text = tr(HAT_KEYS[ap.hat])
	for slot: String in _swatch_buttons:
		var buttons: Array = _swatch_buttons[slot]
		var colors: PackedColorArray = _swatch_colors[slot]
		var picked: int = int(ap.get(slot))
		for index: int in buttons.size():
			_paint_swatch(buttons[index] as Button, colors[index],
				index == picked)


# --- Вращение и зум ---

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


# --- Кнопки ---

func _on_random_pressed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	ap = Appearance.random(rng)
	_apply()


func _on_choose_pressed() -> void:
	Save.save_appearance(ap)
	Log.info("Внешность выбрана и сохранена", "Menu")
	_back_to_menu()


func _on_back_pressed() -> void:
	_back_to_menu()


func _back_to_menu() -> void:
	get_tree().call_deferred("change_scene_to_file", MAIN_MENU)


# --- Фототур (--shot-dir) ---

## Кадр каждого из TOUR персонажей — PNG в Dev.shot_dir, затем игра
## закрывается. Только для проверок (запуск с --shot-dir=PATH).
func _screenshot_tour() -> void:
	DirAccess.make_dir_recursive_absolute(Dev.shot_dir)
	for index: int in Appearance.SHOWCASE.size():
		ap = Appearance.from_bytes(Appearance.SHOWCASE[index])
		_apply()
		Log.info("Тур редактора %d: пол %d, hair %d, hat %d, skin %d"
			% [index, ap.gender, ap.hair, ap.hat, ap.skin], "Menu")
		await get_tree().create_timer(0.9).timeout
		var path := Dev.shot_dir.path_join("editor_character_%d.png" % index)
		get_viewport().get_texture().get_image().save_png(path)
		print("редактор внешности: ", path)
	get_tree().quit()
