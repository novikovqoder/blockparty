class_name MainMenuBU
extends Node2D
## Главное меню Born Unblessed.
## Сцена — слои картинки собора, камера переезжает к своему «кадру» для каждого
## раздела: Настройки — вправо к цепям, Авторы — влево в тёмный угол,
## Главы — к полу, Продолжить/Новая игра — наезд на рыцаря и затухание.
## Все координаты ниже — в ПИКСЕЛЯХ ИСХОДНОЙ КАРТИНКИ ФОНА (bg_texture).
## Если фон заменить на широкую панораму, достаточно поправить эти числа.

## Игрок выбрал «Продолжить», «Новую игру» или главу. mode: &"continue", &"new", &"chapter_N".
signal start_requested(mode: StringName)
signal quit_requested

enum Section { MAIN, SETTINGS, CREDITS, CHAPTERS, STARTING }

@export_group("Картинки")
@export var bg_texture: Texture2D
@export var knight_texture: Texture2D
@export var chains_texture: Texture2D
@export var rubble_texture: Texture2D
## Где лежит верхний левый угол каждого вырезанного слоя на фоне (пиксели фона).
## Фон — панорама 5974×1882: слева угол со скелетами, по центру исходный кадр
## (начинается с x = 1496), справа клетка и пролом в крыше.
@export var knight_origin: Vector2 = Vector2(3568, 505)
@export var chains_origin: Vector2 = Vector2(2784, 0)
@export var rubble_origin: Vector2 = Vector2(1496, 1455)

@export_group("Кадры камеры")
## x, y — центр кадра в пикселях фона; z — приближение (1 = фон по высоте экрана).
@export var shots: Dictionary[StringName, Vector3] = {
	&"intro": Vector3(3796, 900, 1.24),
	&"main": Vector3(3196, 941, 1.08),
	&"settings": Vector3(4700, 800, 1.35),
	&"credits": Vector3(1250, 1120, 1.35),
	&"chapters": Vector3(3146, 1300, 1.3),
	&"knight": Vector3(3936, 760, 2.7),
}
## Глубина слоёв: <1 дальше (двигается медленнее камеры), >1 ближе.
@export var depth_bg: float = 0.95
@export var depth_knight: float = 1.0
@export var depth_chains: float = 1.06
@export var depth_rubble: float = 1.1

@export_group("Свечение")
@export var blade_rect: Rect2 = Rect2(3811, 880, 100, 820)
@export var blade_reflection_rect: Rect2 = Rect2(3716, 1630, 290, 100)
@export var window_rects: Array[Rect2] = [
	Rect2(4056, 260, 460, 900), Rect2(3356, 470, 160, 640), Rect2(4186, 250, 270, 270),
	Rect2(780, 120, 260, 820), Rect2(5320, 820, 300, 420),
]
@export var glow_color: Color = Color(1.0, 0.24, 0.22)

@export_group("Игра")
## Сцена, которая откроется после затухания. Пусто — только сигнал start_requested.
@export_file("*.tscn") var next_scene_path: String = ""
## Есть ли сохранение (показывать «Продолжить»). Обвязка игры включает
## по флагу сессии: «начал игру → вышел в меню» (Session.played).
@export var has_save: bool = false
## Подпись под «Продолжить»: ключ перевода или готовый текст.
@export var continue_subtitle: String = "BU_CONTINUE_SUB"
@export var music_stream: AudioStream
@export var thunder_stream: AudioStream
@export var lightning_interval: Vector2 = Vector2(9.0, 16.0)

var settings_store: MenuSettingsBU = MenuSettingsBU.new()
var section: Section = Section.MAIN

var _scale: float = 1.0
var _camera: MenuCameraBU
var _layers: Array[Node2D] = []
var _depths: Array[float] = []
var _ref_center: Vector2 = Vector2.ZERO
var _blade_glows: Array[Sprite2D] = []
var _window_glows: Array[Sprite2D] = []
var _chains_sprite: Sprite2D
var _t: float = 0.0

var _ui: Control
var _main_panel: Control
var _settings_panel: SettingsPanelBU
var _credits_panel: Control
var _chapters_panel: Control
var _main_hints: Control
var _shade_left: TextureRect
var _shade_right: TextureRect
var _flash: TextureRect
var _fade: ColorRect
var _rain: CPUParticles2D
var _music: AudioStreamPlayer
var _thunder: AudioStreamPlayer
var _lightning_timer: Timer
var _first_button: Button
var _panel_tween: Tween


func _ready() -> void:
	settings_store.load_from_disk()
	settings_store.apply_runtime()
	var bg_h: float = float(bg_texture.get_height()) if bg_texture else 1080.0
	_scale = MenuCameraBU.WORLD_HEIGHT / bg_h
	_build_stage()
	_build_fx()
	_build_ui()
	_build_audio()
	settings_store.changed.connect(_on_setting_changed)
	_camera.shake_factor = settings_store.camera_shake_factor()
	_ref_center = _w(_shot_pos(&"main"))
	_camera.snap_to(_shot(&"intro"))
	_camera.go_to(_shot(&"main"), 3.4, Tween.TRANS_SINE, Tween.EASE_OUT)
	_fade.color.a = 1.0
	create_tween().tween_property(_fade, "color:a", 0.0, 1.8)
	_show_only(_main_panel, 1.1)
	_set_shades(1.0, 0.0, 1.2)
	_first_button.grab_focus.call_deferred()


# --- координаты -------------------------------------------------------------

func _w(src: Vector2) -> Vector2:
	return src * _scale


func _shot_pos(name: StringName) -> Vector2:
	var s: Vector3 = shots.get(name, Vector3(0, 0, 1))
	return Vector2(s.x, s.y)


## Кадр в координатах мира.
func _shot(name: StringName) -> Vector3:
	var s: Vector3 = shots.get(name, Vector3(0, 0, 1))
	return Vector3(s.x * _scale, s.y * _scale, s.z)


# --- сцена ------------------------------------------------------------------

func _layer(depth: float, z: int) -> Node2D:
	var n: Node2D = Node2D.new()
	n.z_index = z
	add_child(n)
	_layers.append(n)
	_depths.append(depth)
	return n


func _sprite(parent: Node2D, tex: Texture2D, origin_src: Vector2) -> Sprite2D:
	var s: Sprite2D = Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.position = _w(origin_src)
	s.scale = Vector2.ONE * _scale
	parent.add_child(s)
	return s


func _glow(parent: Node2D, rect_src: Rect2, color: Color) -> Sprite2D:
	var s: Sprite2D = Sprite2D.new()
	s.texture = UiStyleBU.radial_texture(128)
	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = mat
	s.modulate = color
	var r: Rect2 = Rect2(_w(rect_src.position), rect_src.size * _scale)
	s.position = r.get_center()
	s.scale = r.size / 128.0
	parent.add_child(s)
	return s


func _build_stage() -> void:
	var bg_layer: Node2D = _layer(depth_bg, 0)
	if bg_texture:
		_sprite(bg_layer, bg_texture, Vector2.ZERO)
	for r: Rect2 in window_rects:
		_window_glows.append(_glow(bg_layer, r, Color(glow_color, 0.35)))

	var world_w: float = (float(bg_texture.get_width()) if bg_texture else 1920.0) * _scale
	var fog_back: Node2D = _layer(0.97, 1)
	for i: int in ceili(world_w / 2000.0):
		_fog(fog_back, Rect2(-150 + i * 1900, 560, 2300, 420), 0.5, Vector2(0.010, 0.002))
	var embers_back: Node2D = _layer(0.98, 2)
	embers_back.add_child(_embers(70, Vector2(0.025, 0.07), 0.75))

	var knight_layer: Node2D = _layer(depth_knight, 3)
	if knight_texture:
		_sprite(knight_layer, knight_texture, knight_origin)
	_blade_glows.append(_glow(knight_layer, blade_rect, Color(glow_color, 0.55)))
	_blade_glows.append(_glow(knight_layer, blade_reflection_rect, Color(glow_color, 0.4)))

	var chains_layer: Node2D = _layer(depth_chains, 4)
	if chains_texture:
		_chains_sprite = _sprite(chains_layer, chains_texture, chains_origin)
	var rubble_layer: Node2D = _layer(depth_rubble, 5)
	if rubble_texture:
		var rb: Sprite2D = _sprite(rubble_layer, rubble_texture, rubble_origin)
		# Чуть шире кадра, чтобы при параллаксе не открывались края.
		var w: float = float(rubble_texture.get_width()) * _scale
		rb.scale.x *= 1.06
		rb.position.x -= w * 0.03
	var fog_front: Node2D = _layer(1.08, 6)
	for i: int in ceili(world_w / 2000.0):
		_fog(fog_front, Rect2(-200 + i * 1950, 760, 2400, 360), 0.38, Vector2(-0.014, 0.001))
	var embers_front: Node2D = _layer(1.15, 7)
	embers_front.add_child(_embers(10, Vector2(0.12, 0.22), 0.55))

	_camera = MenuCameraBU.new()
	_camera.world_width = (float(bg_texture.get_width()) if bg_texture else 1920.0) * _scale
	add_child(_camera)
	_camera.make_current()


func _fog(parent: Node2D, rect_world: Rect2, density: float, speed: Vector2) -> void:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var tex: NoiseTexture2D = NoiseTexture2D.new()
	tex.width = 512
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://scenes/menu_bu/fog_bu.gdshader") as Shader
	mat.set_shader_parameter("noise_tex", tex)
	mat.set_shader_parameter("density", density)
	mat.set_shader_parameter("speed", speed)
	mat.set_shader_parameter("tint", Color(0.78, 0.13, 0.17))
	var s: Sprite2D = Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.material = mat
	s.position = rect_world.position
	s.scale = rect_world.size / Vector2(512, 256)
	parent.add_child(s)


func _embers(amount: int, scale_range: Vector2, alpha: float) -> CPUParticles2D:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.texture = UiStyleBU.radial_texture(64)
	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	# Угольки по всей ширине панорамы.
	var world_w: float = (float(bg_texture.get_width()) if bg_texture else 1920.0) * _scale
	p.emission_rect_extents = Vector2(world_w * 0.5, 330)
	p.position = Vector2(world_w * 0.5, 760)
	p.amount = int(float(amount) * maxf(world_w / 1920.0, 1.0))
	p.direction = Vector2(0, -1)
	p.spread = 40.0
	p.gravity = Vector2(0, -7)
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 34.0
	p.tangential_accel_min = -9.0
	p.tangential_accel_max = 9.0
	p.damping_min = 0.5
	p.damping_max = 2.0
	p.scale_amount_min = scale_range.x
	p.scale_amount_max = scale_range.y
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(1.0, 0.55, 0.32, 0.0))
	ramp.set_color(1, Color(1.0, 0.3, 0.15, 0.0))
	ramp.add_point(0.15, Color(1.0, 0.78, 0.55, alpha))
	ramp.add_point(0.55, Color(1.0, 0.42, 0.22, alpha * 0.45))
	ramp.add_point(0.75, Color(1.0, 0.5, 0.3, alpha * 0.9))
	p.color_ramp = ramp
	return p


func _build_fx() -> void:
	var fx: CanvasLayer = CanvasLayer.new()
	fx.layer = 1
	add_child(fx)
	_rain = CPUParticles2D.new()
	_rain.amount = 240
	_rain.lifetime = 0.9
	_rain.preprocess = 1.0
	var streak_g: Gradient = Gradient.new()
	streak_g.set_color(0, Color(1, 1, 1, 0))
	streak_g.set_color(1, Color(1, 1, 1, 1))
	var streak: GradientTexture2D = GradientTexture2D.new()
	streak.gradient = streak_g
	streak.width = 2
	streak.height = 44
	streak.fill_from = Vector2(0.5, 0.0)
	streak.fill_to = Vector2(0.5, 1.0)
	_rain.texture = streak
	_rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_rain.direction = Vector2(-0.07, 1.0)
	_rain.spread = 2.0
	_rain.gravity = Vector2.ZERO
	_rain.initial_velocity_min = 1300.0
	_rain.initial_velocity_max = 1700.0
	_rain.particle_flag_align_y = true
	_rain.scale_amount_min = 0.5
	_rain.scale_amount_max = 1.0
	_rain.color = Color(1.0, 0.8, 0.76, 0.16)
	fx.add_child(_rain)

	var vignette_g: Gradient = Gradient.new()
	vignette_g.set_color(0, Color(0, 0, 0, 0))
	vignette_g.set_color(1, Color(0, 0, 0, 0.85))
	vignette_g.add_point(0.55, Color(0, 0, 0, 0))
	var vignette_tex: GradientTexture2D = GradientTexture2D.new()
	vignette_tex.gradient = vignette_g
	vignette_tex.fill = GradientTexture2D.FILL_RADIAL
	vignette_tex.fill_from = Vector2(0.5, 0.5)
	vignette_tex.fill_to = Vector2(1.05, 0.5)
	var vignette: TextureRect = _full_rect_texture(vignette_tex)
	fx.add_child(vignette)

	var shade_g: Gradient = Gradient.new()
	shade_g.set_color(0, Color(0.03, 0.008, 0.012, 0.86))
	shade_g.set_color(1, Color(0.03, 0.008, 0.012, 0.0))
	shade_g.add_point(0.38, Color(0.03, 0.008, 0.012, 0.5))
	var shade_tex: GradientTexture2D = GradientTexture2D.new()
	shade_tex.gradient = shade_g
	shade_tex.fill_from = Vector2(0.0, 0.5)
	shade_tex.fill_to = Vector2(0.62, 0.5)
	_shade_left = _full_rect_texture(shade_tex)
	_shade_left.modulate.a = 0.0
	fx.add_child(_shade_left)
	_shade_right = _full_rect_texture(shade_tex)
	_shade_right.flip_h = true
	_shade_right.modulate.a = 0.0
	fx.add_child(_shade_right)

	var flash_g: Gradient = Gradient.new()
	flash_g.set_color(0, Color(1.0, 0.89, 0.84, 1.0))
	flash_g.set_color(1, Color(1.0, 0.45, 0.4, 0.0))
	flash_g.add_point(0.55, Color(1.0, 0.5, 0.42, 0.25))
	var flash_tex: GradientTexture2D = GradientTexture2D.new()
	flash_tex.gradient = flash_g
	flash_tex.fill = GradientTexture2D.FILL_RADIAL
	flash_tex.fill_from = Vector2(0.68, 0.0)
	flash_tex.fill_to = Vector2(1.25, 0.6)
	_flash = _full_rect_texture(flash_tex)
	var add_mat: CanvasItemMaterial = CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flash.material = add_mat
	_flash.modulate.a = 0.0
	fx.add_child(_flash)

	_lightning_timer = Timer.new()
	_lightning_timer.one_shot = true
	_lightning_timer.timeout.connect(_lightning)
	add_child(_lightning_timer)
	_lightning_timer.start(randf_range(lightning_interval.x, lightning_interval.y))

	var fade_layer: CanvasLayer = CanvasLayer.new()
	fade_layer.layer = 20
	add_child(fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade)
	get_viewport().size_changed.connect(_layout_rain)
	_layout_rain()


func _full_rect_texture(tex: Texture2D) -> TextureRect:
	var r: TextureRect = TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _layout_rain() -> void:
	var vp: Vector2 = get_viewport_rect().size
	_rain.position = Vector2(vp.x * 0.5 + 60.0, -60.0)
	_rain.emission_rect_extents = Vector2(vp.x * 0.6, 10)


func _build_audio() -> void:
	_music = AudioStreamPlayer.new()
	_music.stream = music_stream
	_music.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	add_child(_music)
	if music_stream:
		_music.play()
	_thunder = AudioStreamPlayer.new()
	_thunder.stream = thunder_stream
	_thunder.bus = "Ambient" if AudioServer.get_bus_index("Ambient") >= 0 else "Master"
	add_child(_thunder)


# --- интерфейс --------------------------------------------------------------

func _build_ui() -> void:
	var ui_layer: CanvasLayer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	_ui = Control.new()
	_ui.theme = UiStyleBU.get_theme()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(_ui)

	_main_panel = _build_main_panel()
	_ui.add_child(_main_panel)

	_settings_panel = SettingsPanelBU.new()
	_settings_panel.setup(settings_store)
	_settings_panel.back_requested.connect(_back_to_main)
	_settings_panel.visible = false
	_ui.add_child(_settings_panel)

	_credits_panel = _build_credits_panel()
	_credits_panel.visible = false
	_ui.add_child(_credits_panel)

	_chapters_panel = _build_chapters_panel()
	_chapters_panel.visible = false
	_ui.add_child(_chapters_panel)


func _label(text_key: String, font: Font, font_size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text_key
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _accent_line(width: float, flip: bool = false) -> TextureRect:
	var g: Gradient = Gradient.new()
	g.set_color(0, UiStyleBU.ACCENT_LINE)
	g.set_color(1, Color(UiStyleBU.ACCENT_LINE, 0.0))
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 2
	var r: TextureRect = TextureRect.new()
	r.texture = tex
	r.flip_h = flip
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.custom_minimum_size = Vector2(width, 2)
	r.size_flags_horizontal = Control.SIZE_SHRINK_END if flip else Control.SIZE_SHRINK_BEGIN
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _hint_row(pairs: Array[PackedStringArray]) -> HBoxContainer:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	for p: PackedStringArray in pairs:
		var item: HBoxContainer = HBoxContainer.new()
		item.add_theme_constant_override("separation", 10)
		var k: Label = _label(p[0], UiStyleBU.body(600), 15, UiStyleBU.TEXT)
		k.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var sb: StyleBoxFlat = UiStyleBU.flat_box(Color(0, 0, 0, 0), UiStyleBU.BORDER, 1)
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		sb.set_corner_radius_all(4)
		k.add_theme_stylebox_override("normal", sb)
		item.add_child(k)
		var t: Label = _label(p[1], UiStyleBU.body(500), 16, UiStyleBU.TEXT_MUTED)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(t)
		h.add_child(item)
	return h


func _build_main_panel() -> Control:
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 144
	col.offset_right = 144 + 760
	# Канва меню при stretch canvas_items всегда 1280×720 (keep_height):
	# внизу резервируем полосу подсказок, чтобы пункты не наезжали на неё.
	col.offset_bottom = -132
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	root.add_child(col)

	var born: Label = _label("BORN", UiStyleBU.display_spaced(700, 22), 44, UiStyleBU.TEXT_MUTED)
	born.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(born)
	var unblessed: Label = _label("UNBLESSED", UiStyleBU.display_spaced(700, 6), 92, UiStyleBU.TEXT_STRONG)
	unblessed.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	unblessed.add_theme_constant_override("line_spacing", -16)
	col.add_child(unblessed)
	var gap1: Control = Control.new()
	gap1.custom_minimum_size = Vector2(0, 10)
	col.add_child(gap1)
	col.add_child(_accent_line(260))
	var gap2: Control = Control.new()
	gap2.custom_minimum_size = Vector2(0, 34)
	col.add_child(gap2)

	var items: Array[Array] = [
		[&"continue", "BU_MENU_CONTINUE", 40],
		[&"new", "BU_MENU_NEW", 32],
		[&"chapters", "BU_MENU_CHAPTERS", 32],
		[&"settings", "BU_MENU_SETTINGS", 32],
		[&"credits", "BU_MENU_CREDITS", 32],
		[&"exit", "BU_MENU_EXIT", 32],
	]
	var buttons: Array[Button] = []
	for it: Array in items:
		var id: StringName = it[0]
		if id == &"continue" and not has_save:
			continue
		var b: MenuButtonBU = MenuButtonBU.new(String(it[1]), int(it[2]))
		b.name = "Btn_" + String(id)
		if id == &"exit":
			b.add_theme_color_override("font_color", UiStyleBU.TEXT_DIM)
		if id == &"continue":
			b.add_theme_color_override("font_color", UiStyleBU.ACCENT_TEXT)
		b.pressed.connect(_on_menu_item.bind(id))
		col.add_child(b)
		buttons.append(b)
		if id == &"continue":
			var sub: Label = _label(continue_subtitle, UiStyleBU.body(500), 15, UiStyleBU.TEXT_MUTED)
			var m: MarginContainer = MarginContainer.new()
			m.add_theme_constant_override("margin_left", int(MenuButtonBU.INDENT))
			m.add_theme_constant_override("margin_bottom", 6)
			m.add_child(sub)
			m.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(m)
	for i: int in buttons.size():
		buttons[i].focus_neighbor_top = buttons[i].get_path_to(buttons[(i - 1 + buttons.size()) % buttons.size()])
		buttons[i].focus_neighbor_bottom = buttons[i].get_path_to(buttons[(i + 1) % buttons.size()])
	_first_button = buttons[0]

	_main_hints = _hint_row([PackedStringArray(["Enter", "BU_HINT_SELECT"]), PackedStringArray(["Esc", "BU_HINT_BACK"])])
	_main_hints.name = "BarHints"
	_main_hints.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_main_hints.offset_left = 144
	_main_hints.offset_top = -92
	_main_hints.offset_bottom = -60
	root.add_child(_main_hints)

	var version: Label = _label("BU_VERSION", UiStyleBU.body(500), 15, UiStyleBU.TEXT_FAINT)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -400
	version.offset_right = -80
	version.offset_top = -86
	version.offset_bottom = -60
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(version)
	return root


func _build_credits_panel() -> Control:
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: VBoxContainer = VBoxContainer.new()
	col.name = "CreditsCol"
	col.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	col.offset_left = -144 - 700
	col.offset_right = -144
	# Полоса «Esc — назад» внизу не перекрывается записями.
	col.offset_bottom = -120
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	root.add_child(col)
	var title: Label = _label("BU_CREDITS_TITLE", UiStyleBU.display_spaced(700, 6), 48, UiStyleBU.TEXT_STRONG)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(title)
	col.add_child(_accent_line(180, true))
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, 16)
	col.add_child(gap)
	var entries: Array[PackedStringArray] = [
		PackedStringArray(["BU_CR_IDEA", "BU_CR_IDEA_NAMES"]),
		PackedStringArray(["BU_CR_CODE", "BU_CR_CODE_NAMES"]),
		PackedStringArray(["BU_CR_ART", "BU_CR_ART_NAMES"]),
		PackedStringArray(["BU_CR_MUSIC", "BU_CR_MUSIC_NAMES"]),
		PackedStringArray(["BU_CR_FONTS", "BU_CR_FONTS_NAMES"]),
		PackedStringArray(["BU_CR_ENGINE", "BU_CR_ENGINE_NAMES"]),
		PackedStringArray(["BU_CR_THANKS", "BU_CR_THANKS_NAMES"]),
	]
	for e: PackedStringArray in entries:
		var role: Label = _label(e[0], UiStyleBU.body(600), 13, UiStyleBU.TEXT_FAINT)
		role.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		col.add_child(role)
		var names: Label = _label(e[1], UiStyleBU.display(600), 22, UiStyleBU.TEXT)
		names.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		names.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(names)
		var g: Control = Control.new()
		g.custom_minimum_size = Vector2(0, 8)
		col.add_child(g)
	var bar: HBoxContainer = _hint_row([PackedStringArray(["Esc", "BU_HINT_BACK"])])
	bar.name = "BarHints"
	var back: MenuButtonBU = MenuButtonBU.new("BU_BACK", 28)
	back.name = "Btn_credits_back"
	back.pressed.connect(_back_to_main)
	bar.add_child(back)
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	bar.offset_left = -600
	bar.offset_right = -144
	bar.offset_top = -110
	bar.offset_bottom = -50
	root.add_child(bar)
	root.set_meta(&"focus", back)
	return root


func _build_chapters_panel() -> Control:
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head: VBoxContainer = VBoxContainer.new()
	head.name = "ChaptersHead"
	head.position = Vector2(144, 56)
	root.add_child(head)
	head.add_child(_label("BU_CHAPTERS_TITLE", UiStyleBU.display_spaced(700, 6), 48, UiStyleBU.TEXT_STRONG))
	head.add_child(_label("BU_CHAPTERS_SUB", UiStyleBU.body(500), 15, UiStyleBU.TEXT_MUTED))

	var row: HBoxContainer = HBoxContainer.new()
	row.name = "ChaptersRow"
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_left = 144
	row.offset_right = -144
	row.offset_top = -470
	row.offset_bottom = -150
	row.add_theme_constant_override("separation", 22)
	root.add_child(row)
	# Статусы: 0 — пройдена, 1 — текущая, 2 — закрыта. Заглушка до системы сохранений.
	var chapters: Array[Array] = [
		["I", "BU_CH_1", 0], ["II", "BU_CH_2", 1], ["III", "BU_CH_LOCKED", 2],
		["IV", "BU_CH_LOCKED", 2], ["V", "BU_CH_LOCKED", 2],
	]
	var buttons: Array[Button] = []
	for i: int in chapters.size():
		var c: Array = chapters[i]
		var status: int = int(c[2])
		var card: Button = Button.new()
		card.name = "Chapter_%d" % (i + 1)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.focus_mode = Control.FOCUS_ALL if status < 2 else Control.FOCUS_NONE
		card.disabled = status == 2
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if status < 2 else Control.CURSOR_ARROW
		var base: StyleBoxFlat = UiStyleBU.flat_box(UiStyleBU.PANEL, UiStyleBU.ACCENT if status == 1 else UiStyleBU.HAIRLINE, 1)
		var hot: StyleBoxFlat = UiStyleBU.flat_box(Color(0.25, 0.03, 0.05, 0.85), UiStyleBU.ACCENT, 2)
		for st: String in ["normal", "disabled"]:
			card.add_theme_stylebox_override(st, base)
		for st: String in ["hover", "focus", "pressed", "hover_pressed"]:
			card.add_theme_stylebox_override(st, hot)
		card.modulate.a = 0.6 if status == 2 else 1.0
		card.pressed.connect(_on_chapter.bind(i + 1))
		card.mouse_entered.connect(card.grab_focus)
		var v: VBoxContainer = VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 24
		v.offset_right = -20
		v.offset_top = 16
		v.offset_bottom = -16
		v.add_theme_constant_override("separation", 8)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(v)
		var num: Label = _label(String(c[0]), UiStyleBU.display(700), 56, UiStyleBU.ACCENT_TEXT if status == 1 else Color("8f7570"))
		num.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		v.add_child(num)
		var t: Label = _label(String(c[1]), UiStyleBU.display(600), 24, UiStyleBU.TEXT_STRONG)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(t)
		var sp: Control = Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(sp)
		var st_key: String = ["BU_CH_DONE", "BU_CH_CURRENT", "BU_CH_AHEAD"][status]
		v.add_child(_label(st_key, UiStyleBU.body(600), 14, UiStyleBU.ACCENT_TEXT if status == 1 else UiStyleBU.TEXT_MUTED))
		row.add_child(card)
		if status < 2:
			buttons.append(card)
	var bar: HBoxContainer = _hint_row([PackedStringArray(["Enter", "BU_HINT_PLAY"]), PackedStringArray(["Esc", "BU_HINT_BACK"])])
	var back: MenuButtonBU = MenuButtonBU.new("BU_BACK", 28)
	back.name = "Btn_chapters_back"
	back.pressed.connect(_back_to_main)
	bar.add_child(back)
	bar.name = "BarHints"
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bar.offset_left = 144
	bar.offset_top = -110
	bar.offset_bottom = -50
	root.add_child(bar)
	root.set_meta(&"focus", buttons[buttons.size() - 1] if not buttons.is_empty() else back)
	return root


# --- навигация --------------------------------------------------------------

func _on_menu_item(id: StringName) -> void:
	if section == Section.STARTING:
		return
	match id:
		&"continue":
			_start(&"continue")
		&"new":
			_start(&"new")
		&"chapters":
			open_section(Section.CHAPTERS)
		&"settings":
			open_section(Section.SETTINGS)
		&"credits":
			open_section(Section.CREDITS)
		&"exit":
			_quit()


func _on_chapter(n: int) -> void:
	_start(StringName("chapter_%d" % n))


func open_section(s: Section) -> void:
	if section == Section.STARTING:
		return
	section = s
	match s:
		Section.MAIN:
			_camera.go_to(_shot(&"main"), 1.7)
			_show_only(_main_panel, 0.55)
			_set_shades(1.0, 0.0, 0.8)
			_first_button.grab_focus.call_deferred()
		Section.SETTINGS:
			_camera.go_to(_shot(&"settings"), 1.8)
			_show_only(_settings_panel, 0.6)
			_set_shades(1.0, 0.0, 0.8)
			_settings_panel.focus_first.call_deferred()
		Section.CREDITS:
			_camera.go_to(_shot(&"credits"), 2.0)
			_show_only(_credits_panel, 0.75)
			_set_shades(0.0, 1.0, 0.9)
			(_credits_panel.get_meta(&"focus") as Control).grab_focus.call_deferred()
		Section.CHAPTERS:
			_camera.go_to(_shot(&"chapters"), 1.8)
			_show_only(_chapters_panel, 0.6)
			_set_shades(0.7, 0.0, 0.8)
			(_chapters_panel.get_meta(&"focus") as Control).grab_focus.call_deferred()
		_:
			pass


func _back_to_main() -> void:
	if section == Section.SETTINGS:
		_settings_panel.discard()
	open_section(Section.MAIN)


## Плавно скрыть все панели и показать одну с задержкой (пока камера едет).
func _show_only(panel: Control, delay: float) -> void:
	if _panel_tween:
		_panel_tween.kill()
	_panel_tween = create_tween()
	_panel_tween.set_parallel(true)
	for p: Control in [_main_panel, _settings_panel, _credits_panel, _chapters_panel]:
		if p != panel and p.visible:
			_panel_tween.tween_property(p, "modulate:a", 0.0, 0.25)
			_panel_tween.tween_callback(p.hide).set_delay(0.25)
	if panel:
		if not panel.visible:
			panel.modulate.a = 0.0
		_panel_tween.tween_callback(panel.show).set_delay(delay)
		_panel_tween.tween_property(panel, "modulate:a", 1.0, 0.45).set_delay(delay)


func _set_shades(left: float, right: float, duration: float) -> void:
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(_shade_left, "modulate:a", left, duration)
	tw.tween_property(_shade_right, "modulate:a", right, duration)


func _start(mode: StringName) -> void:
	section = Section.STARTING
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_show_only(null, 0.0)
	_set_shades(0.0, 0.0, 0.6)
	_camera.go_to(_shot(&"knight"), 2.8, Tween.TRANS_CUBIC, Tween.EASE_IN)
	var tw: Tween = create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(_fade, "color:a", 1.0, 1.6)
	if _music.playing:
		create_tween().tween_property(_music, "volume_db", -40.0, 2.8)
	tw.tween_callback(_finish_start.bind(mode))


func _finish_start(mode: StringName) -> void:
	start_requested.emit(mode)
	if next_scene_path != "":
		get_tree().change_scene_to_file(next_scene_path)


func _quit() -> void:
	section = Section.STARTING
	quit_requested.emit()
	var tw: Tween = create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.6)
	tw.tween_callback(get_tree().quit)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if section in [Section.SETTINGS, Section.CREDITS, Section.CHAPTERS]:
			_back_to_main()
			get_viewport().set_input_as_handled()


func _on_setting_changed(key: StringName) -> void:
	if key == &"camshake":
		_camera.shake_factor = settings_store.camera_shake_factor()


# --- жизнь сцены -------------------------------------------------------------

func _lightning() -> void:
	var tw: Tween = create_tween()
	tw.tween_property(_flash, "modulate:a", 0.32, 0.05)
	tw.tween_property(_flash, "modulate:a", 0.05, 0.08)
	tw.tween_property(_flash, "modulate:a", 0.22, 0.07)
	tw.tween_property(_flash, "modulate:a", 0.0, 0.4)
	_camera.add_impulse(5.0)
	if _thunder.stream:
		get_tree().create_timer(0.35).timeout.connect(_thunder.play)
	_lightning_timer.start(randf_range(lightning_interval.x, lightning_interval.y))


func _process(delta: float) -> void:
	_t += delta
	# Свой параллакс: слой смещается на (центр камеры − опорный кадр) × (1 − глубина).
	var c: Vector2 = _camera.get_screen_center_position() - _ref_center
	for i: int in _layers.size():
		_layers[i].position = c * (1.0 - _depths[i])
	var pulse: float = 0.5 + 0.5 * sin(_t * TAU / 2.4)
	for g: Sprite2D in _blade_glows:
		g.modulate.a = 0.3 + 0.35 * pulse
	if _chains_sprite:
		_chains_sprite.rotation = deg_to_rad(0.35) * sin(_t * TAU / 7.0)
	var slow: float = 0.5 + 0.5 * sin(_t * TAU / 5.0)
	for i: int in _window_glows.size():
		_window_glows[i].modulate.a = 0.16 + 0.2 * (slow if i % 2 == 0 else 1.0 - slow)


## Для тестов.
func current_shot_name() -> StringName:
	match section:
		Section.SETTINGS:
			return &"settings"
		Section.CREDITS:
			return &"credits"
		Section.CHAPTERS:
			return &"chapters"
		Section.STARTING:
			return &"knight"
		_:
			return &"main"
