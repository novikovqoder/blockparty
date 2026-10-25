class_name SettingsPanelBU
extends Control
## Экран «Настройки». Строится кодом из SCHEMA, тексты — ключи i18n/strings_bu.csv.
## Q/E (или бамперы геймпада) — вкладки, Esc — назад, R — сбросить раздел.

signal back_requested

const LEFT: float = 144.0
const WIDTH: float = 900.0
## Вертикальная сетка под канву 720 px (stretch canvas_items): шапка,
## вкладки, прокручиваемые строки, описание и нижняя полоса подсказок.
const HEADER_Y: float = 56.0
const TABS_Y: float = 152.0
const TABS_H: float = 44.0
const ROWS_Y: float = 216.0
const ROWS_BOTTOM: float = 540.0
const DESC_Y: float = 548.0

const TABS: Array[StringName] = [&"gfx", &"audio", &"ctrl", &"game", &"lang"]

## Описание строк. t: choice | slider | toggle | key.
const SCHEMA: Dictionary[StringName, Array] = {
	&"gfx": [
		{"k": "mode", "t": "choice", "label": "BU_SET_MODE", "opts": ["BU_OPT_FULLSCREEN", "BU_OPT_BORDERLESS", "BU_OPT_WINDOWED"], "desc": "BU_DESC_MODE"},
		{"k": "res", "t": "choice", "label": "BU_SET_RES", "opts": ["1920 × 1080", "2560 × 1440", "3840 × 2160", "1600 × 900", "1280 × 720"], "desc": "BU_DESC_RES"},
		{"k": "quality", "t": "choice", "label": "BU_SET_QUALITY", "opts": ["BU_OPT_LOW", "BU_OPT_MEDIUM", "BU_OPT_HIGH", "BU_OPT_ULTRA"], "descs": ["BU_DESC_QUALITY_0", "BU_DESC_QUALITY_1", "BU_DESC_QUALITY_2", "BU_DESC_QUALITY_3"], "warn": "BU_WARN_QUALITY"},
		{"k": "res3d", "t": "choice", "label": "BU_SET_RES3D", "opts": ["100 %", "85 %", "75 %", "67 %"], "descs": ["BU_DESC_RES3D_0", "BU_DESC_RES3D_1", "BU_DESC_RES3D_2", "BU_DESC_RES3D_3"]},
		{"k": "vsync", "t": "toggle", "label": "BU_SET_VSYNC", "desc": "BU_DESC_VSYNC"},
		{"k": "fps", "t": "choice", "label": "BU_SET_FPS", "opts": ["30", "60", "120", "144", "BU_OPT_UNLIMITED"], "desc": "BU_DESC_FPS"},
		{"k": "bright", "t": "slider", "label": "BU_SET_BRIGHT", "desc": "BU_DESC_BRIGHT"},
		{"k": "grain", "t": "toggle", "label": "BU_SET_GRAIN", "desc": "BU_DESC_GRAIN"},
		{"k": "camshake", "t": "slider", "label": "BU_SET_CAMSHAKE", "desc": "BU_DESC_CAMSHAKE"},
	],
	&"audio": [
		{"k": "master", "t": "slider", "label": "BU_SET_MASTER", "desc": "BU_DESC_MASTER"},
		{"k": "music", "t": "slider", "label": "BU_SET_MUSIC", "desc": "BU_DESC_MUSIC"},
		{"k": "sfx", "t": "slider", "label": "BU_SET_SFX", "desc": "BU_DESC_SFX"},
		{"k": "amb", "t": "slider", "label": "BU_SET_AMB", "desc": "BU_DESC_AMB"},
		{"k": "voice", "t": "slider", "label": "BU_SET_VOICE", "desc": "BU_DESC_VOICE"},
		{"k": "bgsound", "t": "toggle", "label": "BU_SET_BGSOUND", "desc": "BU_DESC_BGSOUND"},
	],
	&"ctrl": [
		{"k": "k1", "t": "key", "label": "BU_SET_K_LIGHT", "value": "BU_KEY_LMB", "desc": "BU_DESC_K_LIGHT"},
		{"k": "k2", "t": "key", "label": "BU_SET_K_HEAVY", "value": "BU_KEY_RMB", "desc": "BU_DESC_K_HEAVY"},
		{"k": "k3", "t": "key", "label": "BU_SET_K_BLOCK", "value": "Q", "desc": "BU_DESC_K_BLOCK"},
		{"k": "k4", "t": "key", "label": "BU_SET_K_DODGE", "value": "BU_KEY_SPACE", "desc": "BU_DESC_K_DODGE"},
		{"k": "k5", "t": "key", "label": "BU_SET_K_FINISH", "value": "F", "desc": "BU_DESC_K_FINISH"},
		{"k": "k6", "t": "key", "label": "BU_SET_K_USE", "value": "E", "desc": "BU_DESC_K_USE"},
		{"k": "k7", "t": "key", "label": "BU_SET_K_ZOOM", "value": "BU_KEY_ZOOM", "desc": "BU_DESC_K_ZOOM"},
		{"k": "sens", "t": "slider", "label": "BU_SET_SENS", "desc": "BU_DESC_SENS"},
		{"k": "invert", "t": "toggle", "label": "BU_SET_INVERT", "desc": "BU_DESC_INVERT"},
	],
	&"game": [
		{"k": "diff", "t": "choice", "label": "BU_SET_DIFF", "opts": ["BU_OPT_PILGRIM", "BU_OPT_KNIGHT", "BU_OPT_DAMNED"], "descs": ["BU_DESC_DIFF_0", "BU_DESC_DIFF_1", "BU_DESC_DIFF_2"]},
		{"k": "gore", "t": "choice", "label": "BU_SET_GORE", "opts": ["BU_OPT_GORE_OFF", "BU_OPT_GORE_MID", "BU_OPT_GORE_FULL"], "descs": ["BU_DESC_GORE_0", "BU_DESC_GORE_1", "BU_DESC_GORE_2"], "warn": "BU_WARN_GORE"},
		{"k": "hints", "t": "toggle", "label": "BU_SET_HINTS", "desc": "BU_DESC_HINTS"},
		{"k": "subs", "t": "toggle", "label": "BU_SET_SUBS", "desc": "BU_DESC_SUBS"},
		{"k": "subsize", "t": "choice", "label": "BU_SET_SUBSIZE", "opts": ["BU_OPT_SMALL", "BU_OPT_MEDIUM_SIZE", "BU_OPT_LARGE"], "desc": "BU_DESC_SUBSIZE"},
		{"k": "hitshake", "t": "slider", "label": "BU_SET_HITSHAKE", "desc": "BU_DESC_HITSHAKE"},
	],
	&"lang": [
		{"k": "lang", "t": "choice", "label": "BU_SET_LANG", "opts": ["Русский", "English"], "desc": "BU_DESC_LANG"},
		{"k": "voicelang", "t": "choice", "label": "BU_SET_VOICELANG", "opts": ["English", "Русский"], "desc": "BU_DESC_VOICELANG"},
		{"k": "sublang", "t": "choice", "label": "BU_SET_SUBLANG", "opts": ["Русский", "English"], "desc": "BU_DESC_SUBLANG"},
	],
}

const TAB_LABELS: Dictionary[StringName, String] = {
	&"gfx": "BU_TAB_GFX", &"audio": "BU_TAB_AUDIO", &"ctrl": "BU_TAB_CTRL",
	&"game": "BU_TAB_GAME", &"lang": "BU_TAB_LANG",
}

var store: MenuSettingsBU
var current_tab: StringName = &"game"

var _tab_buttons: Dictionary[StringName, Button] = {}
var _rows_box: VBoxContainer
var _desc_title: Label
var _desc_text: Label
var _desc_warn: Label
var _dirty_label: Label
var _rows: Array[SettingsRowBU] = []


func setup(settings_store: MenuSettingsBU) -> void:
	store = settings_store


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	show_tab(current_tab)


func _build() -> void:
	# Мягкая подложка только под колонкой настроек: фон сцены остаётся чистым справа.
	var back_g: Gradient = Gradient.new()
	back_g.set_color(0, Color(0.035, 0.01, 0.014, 0.82))
	back_g.set_color(1, Color(0.035, 0.01, 0.014, 0.0))
	back_g.add_point(0.78, Color(0.035, 0.01, 0.014, 0.66))
	var back_tex: GradientTexture2D = GradientTexture2D.new()
	back_tex.gradient = back_g
	back_tex.fill_from = Vector2(0.0, 0.5)
	back_tex.fill_to = Vector2(1.0, 0.5)
	var backing: TextureRect = TextureRect.new()
	backing.texture = back_tex
	backing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backing.stretch_mode = TextureRect.STRETCH_SCALE
	backing.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	backing.offset_right = LEFT + WIDTH + 200.0
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backing)

	var header: VBoxContainer = VBoxContainer.new()
	header.position = Vector2(LEFT, HEADER_Y)
	header.add_theme_constant_override("separation", 2)
	add_child(header)
	var kicker: Label = _label("BORN UNBLESSED", UiStyleBU.display(700), 15, UiStyleBU.TEXT_FAINT)
	kicker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	header.add_child(kicker)
	header.add_child(_label("BU_SETTINGS_TITLE", UiStyleBU.display(700), 52, UiStyleBU.TEXT_STRONG))

	_dirty_label = _label("BU_SETTINGS_DIRTY", UiStyleBU.body(500), 13, UiStyleBU.TEXT_FAINT)
	_dirty_label.position = Vector2(LEFT + WIDTH - 360, 118)
	_dirty_label.custom_minimum_size = Vector2(360, 0)
	_dirty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dirty_label.visible = false
	add_child(_dirty_label)

	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.position = Vector2(LEFT, TABS_Y)
	tabs.custom_minimum_size = Vector2(WIDTH, TABS_H)
	tabs.add_theme_constant_override("separation", 36)
	add_child(tabs)
	for t: StringName in TABS:
		var b: Button = Button.new()
		b.text = TAB_LABELS[t]
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_override("font", UiStyleBU.display(700))
		b.add_theme_font_size_override("font_size", 21)
		b.pressed.connect(show_tab.bind(t))
		b.draw.connect(_draw_tab_line.bind(b, t))
		tabs.add_child(b)
		_tab_buttons[t] = b
	var line: ColorRect = ColorRect.new()
	line.color = UiStyleBU.HAIRLINE
	line.position = Vector2(LEFT, TABS_Y + TABS_H)
	line.size = Vector2(WIDTH, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)

	# Строки — в контейнере с обрезкой: длинные вкладки не наезжают на
	# описание и нижнюю полосу (полоса прокрутки — доработка после сдачи П9).
	var rows_scroll: ScrollContainer = ScrollContainer.new()
	rows_scroll.name = "RowsScroll"
	rows_scroll.position = Vector2(LEFT - 16, ROWS_Y)
	rows_scroll.size = Vector2(WIDTH + 16, ROWS_BOTTOM - ROWS_Y)
	rows_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows_scroll.follow_focus = true
	add_child(rows_scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.custom_minimum_size = Vector2(WIDTH, 0)
	_rows_box.add_theme_constant_override("separation", 2)
	rows_scroll.add_child(_rows_box)

	var desc: VBoxContainer = VBoxContainer.new()
	desc.name = "Desc"
	desc.position = Vector2(LEFT, DESC_Y)
	desc.custom_minimum_size = Vector2(WIDTH, 0)
	desc.add_theme_constant_override("separation", 4)
	add_child(desc)
	var topline: ColorRect = ColorRect.new()
	topline.color = UiStyleBU.ACCENT_LINE
	topline.custom_minimum_size = Vector2(64, 2)
	topline.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	desc.add_child(topline)
	_desc_title = _label("", UiStyleBU.display(700), 22, UiStyleBU.TEXT_STRONG)
	desc.add_child(_desc_title)
	_desc_text = _label("", UiStyleBU.body(400), 14, UiStyleBU.TEXT_SOFT)
	_desc_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_text.custom_minimum_size = Vector2(WIDTH, 0)
	desc.add_child(_desc_text)
	_desc_warn = _label("", UiStyleBU.body(600), 13, UiStyleBU.ACCENT_TEXT)
	_desc_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_warn.custom_minimum_size = Vector2(WIDTH, 0)
	desc.add_child(_desc_warn)

	var bar: HBoxContainer = HBoxContainer.new()
	bar.name = "BarHints"
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = LEFT
	bar.offset_right = -LEFT
	bar.offset_top = -62
	bar.offset_bottom = -16
	bar.add_theme_constant_override("separation", 24)
	add_child(bar)
	bar.add_child(_hint("Q / E", "BU_HINT_TABS"))
	bar.add_child(_hint("R", "BU_HINT_RESET"))
	bar.add_child(_hint("Esc", "BU_HINT_BACK"))
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var reset_b: Button = _bar_button("BU_SETTINGS_RESET", false)
	reset_b.pressed.connect(reset_tab)
	bar.add_child(reset_b)
	var back_b: Button = _bar_button("BU_BACK", false)
	back_b.pressed.connect(func() -> void: back_requested.emit())
	bar.add_child(back_b)
	var apply_b: Button = _bar_button("BU_SETTINGS_APPLY", true)
	apply_b.pressed.connect(apply)
	bar.add_child(apply_b)

	store.changed.connect(func(_k: StringName) -> void: _update_dirty())


func _label(text_key: String, font: Font, font_size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text_key
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _hint(key_text: String, label_key: String) -> HBoxContainer:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var k: Label = _label(key_text, UiStyleBU.body(600), 13, UiStyleBU.TEXT)
	k.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var sb: StyleBoxFlat = UiStyleBU.flat_box(Color(0, 0, 0, 0), UiStyleBU.BORDER, 1)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sb.set_corner_radius_all(4)
	k.add_theme_stylebox_override("normal", sb)
	k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(k)
	var t: Label = _label(label_key, UiStyleBU.body(500), 14, UiStyleBU.TEXT_MUTED)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(t)
	return h


func _bar_button(text_key: String, primary: bool) -> Button:
	var b: Button = Button.new()
	b.text = text_key
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 44)
	var sb: StyleBoxFlat
	if primary:
		sb = UiStyleBU.flat_box(UiStyleBU.ACCENT_DEEP, UiStyleBU.ACCENT, 1)
		b.add_theme_font_override("font", UiStyleBU.display(700))
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_color_override("font_color", Color("fff3ee"))
		b.add_theme_color_override("font_hover_color", Color.WHITE)
	elif text_key == "BU_BACK":
		sb = UiStyleBU.flat_box(Color(0, 0, 0, 0), UiStyleBU.BORDER, 1)
		b.add_theme_font_override("font", UiStyleBU.display(700))
		b.add_theme_font_size_override("font_size", 20)
	else:
		sb = UiStyleBU.flat_box()
		b.add_theme_font_override("font", UiStyleBU.body(600))
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_color", UiStyleBU.TEXT_MUTED)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	var hov: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
	if primary:
		hov.bg_color = UiStyleBU.ACCENT
	for st: String in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	for st: String in ["hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, hov)
	return b


func _draw_tab_line(b: Button, t: StringName) -> void:
	if t == current_tab:
		b.draw_rect(Rect2(Vector2(0, b.size.y - 2), Vector2(b.size.x, 2)), UiStyleBU.ACCENT_LINE)


func show_tab(t: StringName) -> void:
	current_tab = t
	for k: StringName in _tab_buttons.keys():
		var b: Button = _tab_buttons[k]
		var on: bool = k == t
		b.add_theme_color_override("font_color", UiStyleBU.TEXT_STRONG if on else UiStyleBU.TEXT_DIM)
		b.add_theme_color_override("font_hover_color", UiStyleBU.TEXT_STRONG if on else UiStyleBU.ACCENT_TEXT)
		b.queue_redraw()
	for r: SettingsRowBU in _rows:
		_rows_box.remove_child(r)
		r.free()
	_rows.clear()
	var defs: Array = SCHEMA[t]
	for d: Variant in defs:
		var row: SettingsRowBU = SettingsRowBU.new()
		row.setup(store, d as Dictionary)
		row.row_focused.connect(_on_row_focused)
		_rows_box.add_child(row)
		_rows.append(row)
	for i: int in _rows.size():
		var prev: SettingsRowBU = _rows[(i - 1 + _rows.size()) % _rows.size()]
		var next: SettingsRowBU = _rows[(i + 1) % _rows.size()]
		_rows[i].focus_neighbor_top = _rows[i].get_path_to(prev)
		_rows[i].focus_neighbor_bottom = _rows[i].get_path_to(next)
	if is_visible_in_tree() and not _rows.is_empty():
		_rows[0].grab_focus.call_deferred()
	if not _rows.is_empty():
		_on_row_focused(_rows[0])


func focus_first() -> void:
	if not _rows.is_empty():
		_rows[0].grab_focus()


func _on_row_focused(row: SettingsRowBU) -> void:
	_desc_title.text = row.label_key
	_desc_text.text = row.description_key()
	_desc_warn.text = row.warn_key
	_desc_warn.visible = row.warn_key != ""


func _update_dirty() -> void:
	_dirty_label.visible = store.dirty


func reset_tab() -> void:
	var keys: Array[StringName] = []
	for d: Variant in SCHEMA[current_tab]:
		keys.append(StringName((d as Dictionary).get("k", "")))
	store.reset_keys(keys)
	for r: SettingsRowBU in _rows:
		r.refresh()
	_update_dirty()


func apply() -> void:
	store.apply_runtime()
	store.save_to_disk()
	_update_dirty()


## Отмена несохранённого при выходе назад.
func discard() -> void:
	if store.dirty:
		store.load_from_disk()
		for r: SettingsRowBU in _rows:
			r.refresh()
	_update_dirty()


func cycle_tab(dir: int) -> void:
	var i: int = TABS.find(current_tab)
	show_tab(TABS[posmod(i + dir, TABS.size())])


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var ke: InputEventKey = event as InputEventKey
		match ke.physical_keycode:
			KEY_Q:
				cycle_tab(-1)
				get_viewport().set_input_as_handled()
			KEY_E:
				cycle_tab(1)
				get_viewport().set_input_as_handled()
			KEY_R:
				reset_tab()
				get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.is_pressed():
		var jb: InputEventJoypadButton = event as InputEventJoypadButton
		if jb.button_index == JOY_BUTTON_LEFT_SHOULDER:
			cycle_tab(-1)
			get_viewport().set_input_as_handled()
		elif jb.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			cycle_tab(1)
			get_viewport().set_input_as_handled()
