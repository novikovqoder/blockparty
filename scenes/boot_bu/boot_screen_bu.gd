class_name BootScreenBU
extends Control
## Стартовый экран Born Unblessed: «Инициализация…» и окно «Steam не запущен»
## в стиле меню (тёмный собор, красный акцент, Cormorant + Manrope).
## Логику проверки Steam оставляет существующей сцене boot: она только вызывает
## show_status() / show_steam_missing() и слушает сигналы.

signal offline_requested
signal quit_requested

const ART_PATH: String = "res://assets/menu_bu/bu_bg.jpg"
## Доля ширины панорамы, где стоит рыцарь (центр кадра на старте).
const ART_FOCUS_X: float = 0.39

## Для предпросмотра сцены отдельно: сразу показать окно «Steam не запущен».
@export var demo_steam_missing: bool = false

var _t: float = 0.0
var _status: Label
var _panel: VBoxContainer
var _btn_offline: MenuButtonBU
var _btn_quit: MenuButtonBU
var _fade: ColorRect
var _art: TextureRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiStyleBU.get_theme()
	_build()
	show_status("BU_BOOT_INIT")
	if demo_steam_missing:
		show_steam_missing()


func _build() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = UiStyleBU.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_art = TextureRect.new()
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists(ART_PATH):
		var full: Texture2D = load(ART_PATH) as Texture2D
		# из панорамы берём кадр 16:9 вокруг рыцаря
		var w: float = float(full.get_width())
		var h: float = float(full.get_height())
		var cw: float = minf(w, h * 16.0 / 9.0)
		var at: AtlasTexture = AtlasTexture.new()
		at.atlas = full
		at.region = Rect2(clampf(w * ART_FOCUS_X - cw * 0.5, 0.0, w - cw), 0.0, cw, h)
		_art.texture = at
	_art.modulate = Color(0.42, 0.36, 0.36)
	add_child(_art)

	# виньетка
	var vig: TextureRect = TextureRect.new()
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(UiStyleBU.BG, 0.0))
	g.set_color(1, Color(UiStyleBU.BG, 0.95))
	var gt: GradientTexture2D = GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.45)
	gt.fill_to = Vector2(1.05, 0.45)
	gt.width = 256
	gt.height = 256
	vig.texture = gt
	add_child(vig)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col: VBoxContainer = VBoxContainer.new()
	col.custom_minimum_size = Vector2(760, 0)
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)

	var title: Label = Label.new()
	title.text = "BORN UNBLESSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UiStyleBU.display_spaced(700, 8))
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", UiStyleBU.TEXT_STRONG)
	col.add_child(title)

	var line: Control = Control.new()
	line.custom_minimum_size = Vector2(0, 26)
	line.draw.connect(func() -> void:
		var cx: float = line.size.x * 0.5
		var y: float = line.size.y * 0.5
		line.draw_line(Vector2(cx - 170, y), Vector2(cx - 14, y), UiStyleBU.BORDER, 1.0)
		line.draw_line(Vector2(cx + 14, y), Vector2(cx + 170, y), UiStyleBU.BORDER, 1.0)
		UiStyleBU.draw_diamond(line, Vector2(cx, y), 6.0, UiStyleBU.ACCENT))
	col.add_child(line)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_override("font", UiStyleBU.body(500))
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_color_override("font_color", UiStyleBU.TEXT_MUTED)
	col.add_child(_status)

	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 6)
	_panel.visible = false
	col.add_child(_panel)

	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	_panel.add_child(gap)

	var head: Label = Label.new()
	head.text = tr("BU_BOOT_STEAM_TITLE")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_override("font", UiStyleBU.display(700))
	head.add_theme_font_size_override("font_size", 40)
	head.add_theme_color_override("font_color", UiStyleBU.ACCENT_TEXT)
	_panel.add_child(head)

	var body: Label = Label.new()
	body.text = tr("BU_BOOT_STEAM_BODY")
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_override("font", UiStyleBU.body(500))
	body.add_theme_font_size_override("font_size", 19)
	body.add_theme_color_override("font_color", UiStyleBU.TEXT_SOFT)
	_panel.add_child(body)

	var gap2: Control = Control.new()
	gap2.custom_minimum_size = Vector2(0, 14)
	_panel.add_child(gap2)

	var btns: VBoxContainer = VBoxContainer.new()
	btns.add_theme_constant_override("separation", 2)
	var bc: CenterContainer = CenterContainer.new()
	bc.add_child(btns)
	_panel.add_child(bc)
	_btn_offline = MenuButtonBU.new(tr("BU_BOOT_OFFLINE"), 26)
	_btn_offline.custom_minimum_size = Vector2(440, 50)
	_btn_offline.pressed.connect(func() -> void: offline_requested.emit())
	btns.add_child(_btn_offline)
	_btn_quit = MenuButtonBU.new(tr("BU_BOOT_QUIT"), 26)
	_btn_quit.custom_minimum_size = Vector2(440, 50)
	_btn_quit.pressed.connect(func() -> void: quit_requested.emit())
	btns.add_child(_btn_quit)
	_btn_offline.focus_neighbor_bottom = _btn_offline.get_path_to(_btn_quit)
	_btn_quit.focus_neighbor_top = _btn_quit.get_path_to(_btn_offline)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)


## Строка состояния под названием (ключ перевода или готовый текст).
func show_status(key_or_text: String) -> void:
	_status.text = tr(key_or_text)


## Показать окно «Steam не запущен» с кнопками «Играть офлайн» и «Выход».
func show_steam_missing() -> void:
	_status.text = ""
	_panel.visible = true
	_btn_offline.grab_focus()


func is_steam_missing_shown() -> bool:
	return _panel.visible


func _process(delta: float) -> void:
	_t += delta
	_fade.color.a = clampf(1.0 - _t / 0.8, 0.0, 1.0)
	# лёгкое «дыхание» фона
	var s: float = 1.0 + 0.012 * sin(_t * 0.35)
	_art.pivot_offset = size * 0.5
	_art.scale = Vector2(s, s)


func _unhandled_input(event: InputEvent) -> void:
	if _panel.visible and event.is_action_pressed(&"ui_cancel"):
		quit_requested.emit()
		get_viewport().set_input_as_handled()
