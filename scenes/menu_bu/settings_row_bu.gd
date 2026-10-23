class_name SettingsRowBU
extends Control
## Одна строка настроек. Получает фокус целиком: ←/→ меняют значение,
## Enter переключает. Мышь: стрелки, ползунок, клик по переключателю.

signal row_focused(row: SettingsRowBU)

enum Kind { CHOICE, SLIDER, TOGGLE, KEY }

const HEIGHT: float = 60.0
const CONTROL_W: float = 390.0


## Кнопка-стрелка ‹ ›, рисуется линиями, чтобы не зависеть от шрифта.
class ArrowButton extends Button:
	var left: bool = true

	func _init(is_left: bool) -> void:
		left = is_left
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(44, 44)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var s: float = 7.0
		var dir: float = -1.0 if left else 1.0
		var col: Color = UiStyleBU.ACCENT_TEXT if is_hovered() else UiStyleBU.TEXT_MUTED
		var pts: PackedVector2Array = PackedVector2Array([
			c + Vector2(-dir * s * 0.6, -s), c + Vector2(dir * s * 0.6, 0.0), c + Vector2(-dir * s * 0.6, s),
		])
		draw_polyline(pts, col, 2.0, true)

var kind: Kind = Kind.CHOICE
var key: StringName = &""
var label_key: String = ""
var option_keys: Array[String] = []
var desc_key: String = ""
var desc_keys: Array[String] = []
var warn_key: String = ""
var key_label: String = ""

var _store: MenuSettingsBU
var _label: Label
var _value_label: Label
var _slider: HSlider
var _slider_value: Label
var _toggle_box: Control
var _on_label: Label
var _off_label: Label
var _hovered: bool = false


func setup(store: MenuSettingsBU, def: Dictionary) -> void:
	_store = store
	key = StringName(def.get("k", ""))
	label_key = String(def.get("label", ""))
	desc_key = String(def.get("desc", ""))
	warn_key = String(def.get("warn", ""))
	key_label = String(def.get("value", ""))
	var opts: Array = def.get("opts", [])
	for o: Variant in opts:
		option_keys.append(String(o))
	var descs: Array = def.get("descs", [])
	for d: Variant in descs:
		desc_keys.append(String(d))
	match String(def.get("t", "choice")):
		"slider":
			kind = Kind.SLIDER
		"toggle":
			kind = Kind.TOGGLE
		"key":
			kind = Kind.KEY
		_:
			kind = Kind.CHOICE


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus)
	focus_exited.connect(queue_redraw)

	var row: HBoxContainer = HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 44
	row.offset_right = -20
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	_label = Label.new()
	_label.text = label_key
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", UiStyleBU.body(500))
	_label.add_theme_font_size_override("font_size", 20)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_label)

	var ctrl: HBoxContainer = HBoxContainer.new()
	ctrl.custom_minimum_size = Vector2(CONTROL_W, 0)
	ctrl.alignment = BoxContainer.ALIGNMENT_END
	ctrl.add_theme_constant_override("separation", 12)
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ctrl)

	match kind:
		Kind.CHOICE:
			_build_choice(ctrl)
		Kind.SLIDER:
			_build_slider(ctrl)
		Kind.TOGGLE:
			_build_toggle(ctrl)
		Kind.KEY:
			_build_key(ctrl)
	refresh()


func _arrow(left: bool) -> Button:
	var b: ArrowButton = ArrowButton.new(left)
	b.pressed.connect(_on_arrow.bind(-1 if left else 1))
	return b


func _on_arrow(dir: int) -> void:
	grab_focus()
	step(dir)


func _build_choice(ctrl: HBoxContainer) -> void:
	ctrl.add_child(_arrow(true))
	_value_label = Label.new()
	_value_label.custom_minimum_size = Vector2(250, 0)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value_label.add_theme_font_override("font", UiStyleBU.body(600))
	_value_label.add_theme_font_size_override("font_size", 19)
	_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl.add_child(_value_label)
	ctrl.add_child(_arrow(false))


func _build_slider(ctrl: HBoxContainer) -> void:
	_slider = HSlider.new()
	_slider.min_value = 0
	_slider.max_value = 100
	_slider.step = 1
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.custom_minimum_size = Vector2(290, 32)
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_slider.value = _store.get_int(key)
	_slider.value_changed.connect(func(v: float) -> void:
		_store.set_value(key, int(v))
		refresh())
	_slider.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton:
			grab_focus())
	ctrl.add_child(_slider)
	_slider_value = Label.new()
	_slider_value.custom_minimum_size = Vector2(52, 0)
	_slider_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_slider_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_slider_value.add_theme_font_override("font", UiStyleBU.body(700))
	_slider_value.add_theme_font_size_override("font_size", 19)
	_slider_value.add_theme_color_override("font_color", UiStyleBU.ACCENT_TEXT)
	_slider_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl.add_child(_slider_value)


func _build_toggle(ctrl: HBoxContainer) -> void:
	_off_label = _small_label("BU_SET_OFF")
	ctrl.add_child(_off_label)
	_toggle_box = Control.new()
	_toggle_box.custom_minimum_size = Vector2(58, 28)
	_toggle_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_toggle_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toggle_box.draw.connect(_draw_toggle)
	ctrl.add_child(_toggle_box)
	_on_label = _small_label("BU_SET_ON")
	ctrl.add_child(_on_label)


func _build_key(ctrl: HBoxContainer) -> void:
	var b: Label = Label.new()
	b.text = key_label
	b.custom_minimum_size = Vector2(130, 42)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_override("font", UiStyleBU.body(700))
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", UiStyleBU.TEXT_STRONG)
	b.add_theme_stylebox_override("normal", UiStyleBU.flat_box(Color(0.93, 0.88, 0.85, 0.05), UiStyleBU.BORDER, 1))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl.add_child(b)


func _small_label(k: String) -> Label:
	var l: Label = Label.new()
	l.text = k
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiStyleBU.body(600))
	l.add_theme_font_size_override("font_size", 17)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _draw_toggle() -> void:
	var on: bool = _store.get_bool(key)
	var r: Rect2 = Rect2(Vector2.ZERO, _toggle_box.size)
	if on:
		_toggle_box.draw_rect(r, Color(UiStyleBU.ACCENT_DEEP, 0.5))
	_toggle_box.draw_rect(r, UiStyleBU.ACCENT if on else Color(0.93, 0.88, 0.85, 0.3), false, 1.0)
	var k: float = r.size.y - 10.0
	var x: float = r.size.x - k - 5.0 if on else 5.0
	_toggle_box.draw_rect(Rect2(Vector2(x, 5.0), Vector2(k, k)), UiStyleBU.TEXT_STRONG if on else Color("8a7570"))


## Описание для правой панели (у некоторых строк зависит от значения).
func description_key() -> String:
	if not desc_keys.is_empty():
		return desc_keys[clampi(_store.get_int(key), 0, desc_keys.size() - 1)]
	return desc_key


func step(dir: int) -> void:
	match kind:
		Kind.CHOICE:
			var n: int = option_keys.size()
			if n > 0:
				_store.set_value(key, posmod(_store.get_int(key) + dir, n))
		Kind.SLIDER:
			_store.set_value(key, clampi(_store.get_int(key) + dir * 5, 0, 100))
		Kind.TOGGLE:
			_store.set_value(key, not _store.get_bool(key))
		Kind.KEY:
			pass
	refresh()
	row_focused.emit(self)


func refresh() -> void:
	var active: bool = has_focus() or _hovered
	if _label:
		_label.add_theme_color_override("font_color", UiStyleBU.TEXT_STRONG if active else UiStyleBU.TEXT_SOFT)
	match kind:
		Kind.CHOICE:
			if _value_label and not option_keys.is_empty():
				_value_label.text = option_keys[clampi(_store.get_int(key), 0, option_keys.size() - 1)]
				_value_label.add_theme_color_override("font_color", UiStyleBU.ACCENT_TEXT if active else UiStyleBU.TEXT)
		Kind.SLIDER:
			if _slider:
				_slider.set_value_no_signal(_store.get_int(key))
				_slider_value.text = str(_store.get_int(key))
		Kind.TOGGLE:
			var on: bool = _store.get_bool(key)
			_on_label.add_theme_color_override("font_color", UiStyleBU.TEXT_STRONG if on else Color("7d6b66"))
			_off_label.add_theme_color_override("font_color", Color("7d6b66") if on else UiStyleBU.TEXT_STRONG)
			_toggle_box.queue_redraw()
	queue_redraw()


func _on_mouse_entered() -> void:
	_hovered = true
	grab_focus()


func _on_mouse_exited() -> void:
	_hovered = false
	refresh()


func _on_focus() -> void:
	refresh()
	row_focused.emit(self)


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		step(-1)
		accept_event()
	elif event.is_action_pressed("ui_right"):
		step(1)
		accept_event()
	elif event.is_action_pressed("ui_accept") and kind == Kind.TOGGLE:
		step(1)
		accept_event()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and kind == Kind.TOGGLE:
			step(1)
			accept_event()


func _draw() -> void:
	var active: bool = has_focus() or _hovered
	if active:
		var w: float = size.x
		var steps: int = 24
		for i: int in steps:
			var t0: float = float(i) / float(steps)
			var a: float = 0.38 * (1.0 - t0) * (1.0 - t0 * 0.3)
			draw_rect(Rect2(Vector2(w * t0, 0), Vector2(w / float(steps) + 1.0, size.y)), Color(UiStyleBU.ACCENT_DEEP, a))
		UiStyleBU.draw_diamond(self, Vector2(22.0, size.y * 0.5), 6.0, UiStyleBU.ACCENT)
