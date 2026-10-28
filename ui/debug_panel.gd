# Отладочная панель F3 (разделы 15, 18 SPEC): FPS, пинг, число пиров, режим
# сети, часы мира, время сессии, позиция игрока, зона, трафик
# снапшотов (КБ/с, бюджет раздела 10) и игроки в мире. Переключается
# клавишей F3 (физическая, раскладконезависимая).
#
# П13 (панель замера, раздел 3): технические строки дополнены кадром
# CPU/GPU-мс (viewport_set_measure_render_time), уровнем качества и
# «Разрешением 3D»; рядом блок галочек — выключают тяжёлые эффекты
# ПО ОДНОМУ на лету (не сохраняются, настройки меню не меняют;
# повторная галочка возвращает состояние уровня). Кнопка «Скопировать
# отчёт» кладёт в буфер видеокарту, разрешение, уровень, разрешение 3D,
# средние FPS и GPU-мс за 5 с и список выключенного. Эти тексты —
# продуктные, через tr(); старые технические метки не локализуются.
class_name DebugPanel
extends CanvasLayer

const UPDATE_INTERVAL: float = 0.25
## Окно усреднения отчёта, с (П13 3.4).
const REPORT_WINDOW_SEC: float = 5.0
## Галочки эффектов (П13 3.2; П14 5.2 — пять новых для замеров земли
## и воды; П15 7 — «Каустика» и «Круги на воде»; П16 9 — «Окклюзия»):
## порядок = порядок в панели.
const EFFECTS: Array[StringName] = [
	&"sdfgi", &"ssil", &"ssr", &"ssao", &"vfog", &"glow", &"aa",
	&"lamps", &"grass", &"detail", &"pom", &"clutter", &"refr", &"ripple",
	&"caustic", &"rings", &"occl",
]
## Ключи перевода подписей и заголовка блока.
const EFFECT_LABELS: Dictionary[StringName, String] = {
	&"sdfgi": "BU_DBG_SDFGI", &"ssil": "BU_DBG_SSIL", &"ssr": "BU_DBG_SSR",
	&"ssao": "BU_DBG_SSAO", &"vfog": "BU_DBG_VFOG", &"glow": "BU_DBG_GLOW",
	&"aa": "BU_DBG_AA", &"lamps": "BU_DBG_LAMPS", &"grass": "BU_DBG_GRASS",
	&"detail": "BU_DBG_DETAIL", &"pom": "BU_DBG_POM",
	&"clutter": "BU_DBG_CLUTTER", &"refr": "BU_DBG_REFRACTION",
	&"ripple": "BU_DBG_RIPPLE",
	&"caustic": "BU_DBG_CAUSTIC", &"rings": "BU_DBG_RINGS",
	&"occl": "BU_DBG_OCCLUSION",
}
## Названия уровней для строк панели и отчёта (индекс = Tier).
const TIER_LABELS: Array[String] = [
	"BU_OPT_LOW", "BU_OPT_MEDIUM", "BU_OPT_HIGH", "BU_OPT_ULTRA",
]
## Позиция блока эффектов: правее нижнего информационного блока,
## вмещается в минимальную канву 1280×720 (П14 5.2 — галочек стало 14,
## блок поднят, чтобы не вылезал за нижний край; П16 9 — 17 галочек
## и кнопка авто-замера, поднят ещё).
const EFFECTS_POS: Vector2 = Vector2(690, 232)
## Ползунки вкладки «Вода» (П15 8.1): id — ключ состояния, label — ключ
## перевода, диапазон и шаг — как hint_range шейдера, def — номинал из
## констант WaterArea («Сбросить» возвращает их), const — имя константы
## для текста «Скопировать значения». Номиналы юбки дна (П15-ДОП2, п. 1)
## — константы SeafloorSkirt.
const WATER_SLIDERS: Array[Dictionary] = [
	{"id": &"abs", "label": "BU_W_ABSORPTION",
		"min": 0.0, "max": 3.0, "step": 0.05,
		"def": WaterArea.ABSORPTION_MULT, "const": "ABSORPTION_MULT"},
	{"id": &"wave_height", "label": "BU_W_WAVE_HEIGHT",
		"min": 0.0, "max": 2.0, "step": 0.05,
		"def": WaterArea.WAVE_HEIGHT_MULT},
	{"id": &"wave_choppy", "label": "BU_W_WAVE_CHOPPY",
		"min": 0.0, "max": 2.0, "step": 0.05,
		"def": WaterArea.WAVE_CHOPPY_MULT},
	{"id": &"wave_speed", "label": "BU_W_WAVE_SPEED",
		"min": 0.0, "max": 2.0, "step": 0.05,
		"def": WaterArea.WAVE_SPEED_MULT},
	{"id": &"wave_freq", "label": "BU_W_WAVE_FREQ",
		"min": 0.2, "max": 2.0, "step": 0.05,
		"def": WaterArea.WAVE_FREQ_MULT},
	{"id": &"ripple_strength", "label": "BU_W_RIPPLE_STRENGTH",
		"min": 0.0, "max": 2.0, "step": 0.05,
		"def": WaterArea.RIPPLE_STRENGTH_MULT,
		"const": "RIPPLE_STRENGTH_MULT"},
	{"id": &"ripple_scale", "label": "BU_W_RIPPLE_SCALE",
		"min": 0.5, "max": 2.0, "step": 0.05,
		"def": WaterArea.RIPPLE_SCALE_MULT,
		"const": "RIPPLE_SCALE_MULT"},
	{"id": &"refraction", "label": "BU_W_REFRACTION",
		"min": 0.0, "max": 4.0, "step": 0.1,
		"def": WaterArea.REFRACTION_MULT, "const": "REFRACTION_MULT"},
	{"id": &"foam_amount", "label": "BU_W_FOAM_AMOUNT",
		"min": 0.0, "max": 2.0, "step": 0.05,
		"def": WaterArea.FOAM_MULT, "const": "FOAM_MULT"},
	{"id": &"foam_width", "label": "BU_W_FOAM_WIDTH",
		"min": 0.02, "max": 0.3, "step": 0.01,
		"def": WaterArea.FOAM_WIDTH, "const": "FOAM_WIDTH"},
	{"id": &"foam_edge", "label": "BU_W_FOAM_EDGE",
		"min": 0.0, "max": 1.0, "step": 0.05,
		"def": WaterArea.FOAM_EDGE, "const": "FOAM_EDGE"},
	{"id": &"foam_bubbles", "label": "BU_W_FOAM_BUBBLES",
		"min": 0.0, "max": 4.0, "step": 0.1,
		"def": WaterArea.FOAM_BUBBLES, "const": "FOAM_BUBBLES"},
	{"id": &"rough_near", "label": "BU_W_ROUGH_NEAR",
		"min": 0.0, "max": 1.0, "step": 0.01,
		"def": WaterArea.ROUGHNESS_NEAR, "const": "ROUGHNESS_NEAR"},
	{"id": &"rough_far", "label": "BU_W_ROUGH_FAR",
		"min": 0.0, "max": 1.0, "step": 0.01,
		"def": WaterArea.ROUGHNESS_FAR, "const": "ROUGHNESS_FAR"},
	{"id": &"caustic", "label": "BU_W_CAUSTIC",
		"min": 0.0, "max": 4.0, "step": 0.1,
		"def": WaterArea.CAUSTIC_BRIGHTNESS,
		"const": "CAUSTIC_BRIGHTNESS"},
	{"id": &"seafloor_shelf", "label": "BU_W_SEAFLOOR_SHELF",
		"min": 10.0, "max": 200.0, "step": 5.0,
		"def": SeafloorSkirt.SHELF_M, "const": "SHELF_M"},
	{"id": &"seafloor_deep", "label": "BU_W_SEAFLOOR_DEPTH",
		"min": 20.0, "max": 160.0, "step": 5.0,
		"def": SeafloorSkirt.FAR_DEPTH_M, "const": "FAR_DEPTH_M"},
]
## Цвета воды (П15 8.1): мелководье и глубина, озеро и море раздельно.
## Значения — активного пресета (П15-ДОП блок 5): «Туториал» (бирюзовый,
## по умолчанию) или «Born Unblessed» (тёмная палитра П12).
const WATER_COLORS: Array[Dictionary] = [
	{"id": &"lake_deep", "label": "BU_W_LAKE_DEEP"},
	{"id": &"lake_shallow", "label": "BU_W_LAKE_SHALLOW"},
	{"id": &"sea_deep", "label": "BU_W_SEA_DEEP"},
	{"id": &"sea_shallow", "label": "BU_W_SEA_SHALLOW"},
]
## Имена констант WaterArea по пресету: «Скопировать значения» печатает
## цвета и базы поглощения активного пресета его именами (TUT_* —
## «Туториал», LAKE_*/SEA_* — «Born Unblessed»).
const WATER_PRESET_CONSTS: Dictionary = {
	WaterArea.WATER_PRESET_TUTORIAL: {
		"lake_deep": "TUT_LAKE_DEEP", "lake_shallow": "TUT_LAKE_SHALLOW",
		"sea_deep": "TUT_SEA_DEEP", "sea_shallow": "TUT_SEA_SHALLOW",
		"lake_abs": "TUT_LAKE_ABSORPTION", "sea_abs": "TUT_SEA_ABSORPTION",
	},
	WaterArea.WATER_PRESET_BU: {
		"lake_deep": "LAKE_DEEP", "lake_shallow": "LAKE_SHALLOW",
		"sea_deep": "SEA_DEEP", "sea_shallow": "SEA_SHALLOW",
		"lake_abs": "LAKE_ABSORPTION", "sea_abs": "SEA_ABSORPTION",
	},
}
## Порядок кнопок пресетов во вкладке (первый — по умолчанию).
const WATER_PRESET_ORDER: Array[StringName] = [
	WaterArea.WATER_PRESET_TUTORIAL, WaterArea.WATER_PRESET_BU,
]
## Базы волн sea_octave (П15-ДОП): в «Скопировать значения» печатаются
## как константы WaterArea с уже применённым множителем ползунка — текст
## вставляется в water_area.gd, множители возвращаются к 1.0.
const WAVE_BASE_CONSTS: Array[Dictionary] = [
	{"const": "SEA_WAVE_HEIGHT", "base": WaterArea.SEA_WAVE_HEIGHT,
		"mult": &"wave_height"},
	{"const": "LAKE_WAVE_HEIGHT", "base": WaterArea.LAKE_WAVE_HEIGHT,
		"mult": &"wave_height"},
	{"const": "SEA_WAVE_CHOPPY", "base": WaterArea.SEA_WAVE_CHOPPY,
		"mult": &"wave_choppy"},
	{"const": "LAKE_WAVE_CHOPPY", "base": WaterArea.LAKE_WAVE_CHOPPY,
		"mult": &"wave_choppy"},
	{"const": "SEA_WAVE_SPEED", "base": WaterArea.SEA_WAVE_SPEED,
		"mult": &"wave_speed"},
	{"const": "LAKE_WAVE_SPEED", "base": WaterArea.LAKE_WAVE_SPEED,
		"mult": &"wave_speed"},
	{"const": "SEA_WAVE_FREQ", "base": WaterArea.SEA_WAVE_FREQ,
		"mult": &"wave_freq"},
	{"const": "LAKE_WAVE_FREQ", "base": WaterArea.LAKE_WAVE_FREQ,
		"mult": &"wave_freq"},
]

var _label: Label
var _effects: PanelContainer
var _boxes: Dictionary[StringName, CheckBox] = {}
# --- Вкладка «Вода» (П15 8) ---
var _sliders: Dictionary[StringName, HSlider] = {}
var _slider_values: Dictionary[StringName, Label] = {}
var _pickers: Dictionary[StringName, ColorPickerButton] = {}
var _water_values: Dictionary[StringName, float] = {}
var _water_colors: Dictionary[StringName, Color] = {}
## Активный пресет воды (П15-ДОП блок 5) и его кнопки-переключатели.
var _water_preset: StringName = WaterArea.water_preset()
var _preset_buttons: Dictionary[StringName, Button] = {}
## «Сбросить» переставляет ползунки программно — сигналы погашены,
## промежуточные состояния в материалы не идут.
var _water_applying: bool = false
var _visible_panel: bool = false
var _was_pressed: bool = false
var _accum: float = 0.0
var _player: Player = null
var _island: Island = null

var _env: Environment = null
var _view: IslandView = null
var _tier: int = GraphicsQuality.Tier.HIGH
var _vp_rid: RID
var _mouse_was_captured: bool = false
## Сэмплы (время с запуска, FPS, GPU-мс) — окно REPORT_WINDOW_SEC.
var _samples: Array[Vector3] = []

# --- Авто-замер эффектов (П16 п. 9) ---

## Кнопка «Авто-замер»: сначала базовый шаг (уровень целиком), затем по
## шагу на каждый активный эффект уровня — эффект выключен, GPU-мс
## меряется; в конце отсортированный по экономии отчёт идёт в буфер.
## Первые AUTO_WARMUP_SEC шага сэмплы не копятся: после переключения
## эффекта движок компилирует шейдеры — кадры нетипично долгие.
const AUTO_STEP_SEC: float = 4.0
const AUTO_WARMUP_SEC: float = 0.75

var _auto_button: Button
var _auto_running: bool = false
## Длительности шага/прогрева (параметры start_auto_measure — тесты
## прогоняют быстро, в панели — константы).
var _auto_step_sec: float = AUTO_STEP_SEC
var _auto_warmup_sec: float = AUTO_WARMUP_SEC
## Очередь эффектов уровня (включённых сейчас), −1 в _auto_index —
## базовый шаг «всё включено».
var _auto_queue: Array[StringName] = []
var _auto_index: int = -1
var _auto_time: float = 0.0
var _auto_samples: Array[float] = []
var _auto_base_ms: float = 0.0
## {id: StringName, ms: float} — GPU-мс шага «без эффекта».
var _auto_rows: Array[Dictionary] = []


## Показывать позицию этого игрока (вызывает сцена мира).
func watch_player(player: Player) -> void:
	_player = player


## Остров для имени зоны (раздел 15: в панели есть зона).
func watch_island(island: Island) -> void:
	_island = island


## Графика для панели замера (П13 3): окружение сцены, вид острова
## (трава-буст, параллакс) и активный уровень. Вызывается сцена мира
## при каждом применении качества — тогда все эффекты уровня включены,
## галочки сбрасываются в «включено».
func watch_graphics(env: Environment, view: IslandView, tier: int) -> void:
	_env = env
	_view = view
	_tier = clampi(tier, 0, TIER_LABELS.size() - 1)
	if is_inside_tree():
		# Замер кадра CPU/GPU (П13 3.1) включается один раз на viewport.
		_vp_rid = get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	for id: StringName in EFFECTS:
		if _boxes.has(id):
			_boxes[id].set_pressed_no_signal(true)


func _ready() -> void:
	layer = 20
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_label = Label.new()
	_label.position = Vector2(16, 640)
	_label.size = Vector2(640, 80)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 4)
	_label.visible = false
	root.add_child(_label)
	_build_effects(root)


## Блок галочек и кнопки отчёта (П13 3.2; П15 8 — вкладка «Вода» рядом):
## видим только вместе с панелью; корень канвы события мыши не ест —
## клики мимо панели идут в игру.
func _build_effects(root: Control) -> void:
	_effects = PanelContainer.new()
	_effects.position = EFFECTS_POS
	_effects.visible = false
	root.add_child(_effects)
	var tabs := TabContainer.new()
	tabs.add_theme_font_size_override("font_size", 13)
	_effects.add_child(tabs)
	var box := VBoxContainer.new()
	box.name = tr("BU_DBG_EFFECTS_TAB")
	box.add_theme_constant_override("separation", 2)
	tabs.add_child(box)
	var title := Label.new()
	title.text = tr("BU_DBG_EFFECTS")
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.85))
	box.add_child(title)
	for id: StringName in EFFECTS:
		var check := CheckBox.new()
		check.text = tr(EFFECT_LABELS[id])
		check.button_pressed = true
		check.add_theme_font_size_override("font_size", 13)
		check.toggled.connect(_on_effect_toggled.bind(id))
		box.add_child(check)
		_boxes[id] = check
	var copy := Button.new()
	copy.text = tr("BU_DBG_COPY")
	copy.add_theme_font_size_override("font_size", 13)
	copy.pressed.connect(_copy_report)
	box.add_child(copy)
	# П16 п. 9: кнопка авто-замера — гоняет эффекты по одному, в конце
	# кладёт отсортированный отчёт в буфер; во время прогона кнопка — отмена.
	_auto_button = Button.new()
	_auto_button.text = tr("BU_DBG_AUTOM")
	_auto_button.add_theme_font_size_override("font_size", 13)
	_auto_button.pressed.connect(_on_auto_button)
	box.add_child(_auto_button)
	_build_water_tab(tabs)


## Вкладка «Вода» (П15 8.1): цвета и ползунки, меняющие воду на лету;
## «Сбросить» (8.2) и «Скопировать значения» (8.3). Строк больше, чем
## галочек эффектов, — в ScrollContainer, чтобы влезть на минимальную
## канву. Ничего не сохраняется и в сеть не идёт (8.4).
func _build_water_tab(tabs: TabContainer) -> void:
	for def: Dictionary in WATER_SLIDERS:
		_water_values[def["id"]] = def["def"]
	var preset_colors: Dictionary = _water_preset_colors()
	for def: Dictionary in WATER_COLORS:
		_water_colors[def["id"]] = preset_colors[def["id"]]
	var scroll := ScrollContainer.new()
	scroll.name = tr("BU_DBG_WATER_TAB")
	scroll.custom_minimum_size = Vector2(0.0, 352.0)
	scroll.horizontal_scroll_mode = \
		ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	# Переключатель пресетов (П15-ДОП блок 5): «Туториал» (по умолчанию)
	# и «Born Unblessed»; выбор переставляет пикеры и зоны воды.
	var preset_row := HBoxContainer.new()
	box.add_child(preset_row)
	var preset_label := Label.new()
	preset_label.text = tr("BU_W_PRESET")
	preset_label.custom_minimum_size = Vector2(198.0, 0.0)
	preset_label.add_theme_font_size_override("font_size", 13)
	preset_row.add_child(preset_label)
	var group := ButtonGroup.new()
	for id: StringName in WATER_PRESET_ORDER:
		var button := Button.new()
		button.text = tr(WaterArea.WATER_PRESETS[id]["label"])
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = _water_preset == id
		button.toggled.connect(_on_water_preset_toggled.bind(id))
		preset_row.add_child(button)
		_preset_buttons[id] = button
	for def: Dictionary in WATER_COLORS:
		var row := HBoxContainer.new()
		box.add_child(row)
		var name_label := Label.new()
		name_label.text = tr(def["label"])
		name_label.custom_minimum_size = Vector2(198.0, 0.0)
		name_label.add_theme_font_size_override("font_size", 13)
		row.add_child(name_label)
		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(92.0, 22.0)
		picker.edit_alpha = false
		picker.color = _water_colors[def["id"]]
		picker.color_changed.connect(
			_on_water_color_changed.bind(def["id"]))
		row.add_child(picker)
		_pickers[def["id"]] = picker
	for def: Dictionary in WATER_SLIDERS:
		var row := HBoxContainer.new()
		box.add_child(row)
		var name_label := Label.new()
		name_label.text = tr(def["label"])
		name_label.custom_minimum_size = Vector2(198.0, 0.0)
		name_label.add_theme_font_size_override("font_size", 13)
		row.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = float(def["min"])
		slider.max_value = float(def["max"])
		slider.step = float(def["step"])
		slider.value = _water_values[def["id"]]
		slider.custom_minimum_size = Vector2(122.0, 20.0)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(
			_on_water_slider_changed.bind(def["id"]))
		row.add_child(slider)
		_sliders[def["id"]] = slider
		var value_label := Label.new()
		value_label.custom_minimum_size = Vector2(46.0, 0.0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_font_size_override("font_size", 13)
		value_label.text = "%.2f" % _water_values[def["id"]]
		row.add_child(value_label)
		_slider_values[def["id"]] = value_label
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var reset := Button.new()
	reset.text = tr("BU_W_RESET")
	reset.add_theme_font_size_override("font_size", 13)
	reset.pressed.connect(_reset_water)
	buttons.add_child(reset)
	var copy := Button.new()
	copy.text = tr("BU_W_COPY")
	copy.add_theme_font_size_override("font_size", 13)
	copy.pressed.connect(_copy_water_values)
	buttons.add_child(copy)


func _process(delta: float) -> void:
	var pressed: bool = Input.is_physical_key_pressed(KEY_F3)
	if pressed and not _was_pressed:
		_visible_panel = not _visible_panel
		_label.visible = _visible_panel
		_effects.visible = _visible_panel
		# Галочки нужно кликать — при открытой панели курсор освобождается
		# (камера на VISIBLE-мышь не реагирует), закрытие возвращает захват.
		if _visible_panel:
			_mouse_was_captured = (
				Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
			if _mouse_was_captured:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif _mouse_was_captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_mouse_was_captured = false
	_was_pressed = pressed
	# Авто-замер (П16 п. 9) тикает и при закрытой панели — прогон длинный.
	if _auto_running:
		_auto_tick(delta)
	if not _visible_panel:
		return
	_accum += delta
	if _accum >= UPDATE_INTERVAL:
		_accum = 0.0
		_refresh()


func _refresh() -> void:
	var ping: int = Net.ping_msec()
	var pos_text: String = "—"
	var zone_text: String = "—"
	if _player != null:
		var pos := _player.global_position
		pos_text = "(%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z]
		if _island != null:
			zone_text = _island.zone_name_at(pos)
			if zone_text == "":
				zone_text = "—"
	# Кадр CPU/GPU (П13 3.1): замеры включаются в watch_graphics; в headless
	# и до входа в мир остаются нулями.
	var gpu_ms: float = (
		RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
		if _vp_rid.is_valid() else 0.0)
	var cpu_ms: float = (
		RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid)
		if _vp_rid.is_valid() else 0.0)
	_samples.append(Vector3(
		Time.get_ticks_msec() / 1000.0,
		Engine.get_frames_per_second(),
		gpu_ms,
	))
	_drop_old_samples()
	_label.text = "\n".join([
		"FPS %d | ping %s | peers %d | mode %s" % [
			Engine.get_frames_per_second(),
			"—" if ping < 0 else "%d ms" % ping,
			Net.peer_count(),
			Net.mode,
		],
		"world_time %.1f s | session %.1f s" % [
			Session.world_time, Session.session_time,
		],
		"pos %s | zone %s" % [pos_text, zone_text],
		"net ↑%.1f ↓%.1f КБ/с | in world %d" % [
			float(Net.snapshot_out_bps) / 1024.0,
			float(Net.snapshot_in_bps) / 1024.0,
			Net.in_world_count(),
		],
		"gfx %s | 3D %s | CPU %.1f ms | GPU %.1f ms" % [
			tr(TIER_LABELS[_tier]), _res3d_text(), cpu_ms, gpu_ms,
		],
	])


## Хвост окна усреднения: сэмплы старше REPORT_WINDOW_SEC выбрасываются.
func _drop_old_samples() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	while not _samples.is_empty() and now - _samples[0].x > REPORT_WINDOW_SEC:
		_samples.remove_at(0)


## «Разрешение 3D» фактическое: процент масштаба и апскейл (П13 3.1).
func _res3d_text() -> String:
	if not is_inside_tree():
		return "—"
	var vp := get_viewport()
	var mode := "FSR" if vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR \
		else "bilinear"
	return "%d %% (%s)" % [int(roundf(vp.scaling_3d_scale * 100.0)), mode]


## Выключение/возврат одного эффекта (П13 3.2): снятая галочка гасит
## эффект, повторная — возвращает состояние активного уровня. Меню
## и cfg не затрагиваются.
func _on_effect_toggled(on: bool, id: StringName) -> void:
	if _env == null:
		return
	var value: bool = on and _tier_effect_on(id)
	match id:
		&"sdfgi":
			_env.sdfgi_enabled = value
		&"ssil":
			_env.ssil_enabled = value
		&"ssr":
			_env.ssr_enabled = value
		&"ssao":
			_env.ssao_enabled = value
		&"vfog":
			_env.volumetric_fog_enabled = value
		&"glow":
			_env.glow_enabled = value
		&"aa":
			var vp := get_viewport()
			vp.msaa_3d = (
				GraphicsQuality.AA_MSAA_ULTRA
				if value and _tier == GraphicsQuality.Tier.ULTRA
				else Viewport.MSAA_DISABLED)
			vp.screen_space_aa = (
				Viewport.SCREEN_SPACE_AA_SMAA if value
				else Viewport.SCREEN_SPACE_AA_DISABLED)
		&"lamps":
			for node: Node in get_tree().get_nodes_in_group(CabinHouse.GROUP):
				(node as CabinHouse).set_lamp_shadows(value)
		&"grass":
			if _view != null:
				_view.set_grass_boost_visible(value)
		&"detail":
			if _view != null:
				_view.set_detail_ring_visible(value)
		&"pom":
			if _view != null:
				_view.set_parallax(value)
		&"clutter":
			if _view != null:
				_view.set_clutter_visible(value)
		&"refr":
			for node: Node in get_tree().get_nodes_in_group("water_surface"):
				(node as WaterArea).set_refraction(value)
		&"ripple":
			for node: Node in get_tree().get_nodes_in_group("water_surface"):
				(node as WaterArea).set_ripple(value)
		&"caustic":
			for node: Node in get_tree().get_nodes_in_group("water_surface"):
				(node as WaterArea).set_caustic(value)
		&"rings":
			for node: Node in get_tree().get_nodes_in_group("water_surface"):
				(node as WaterArea).set_ripples(value)
		&"occl":
			# П16 п. 5/9: окклюзия включена проектом на всех уровнях —
			# галочка снимает её с viewport сцены (гетчера нет, вызов
			# проверен тестом), возврат включает обратно.
			if is_inside_tree():
				RenderingServer.viewport_set_use_occlusion_culling(
					get_viewport().get_viewport_rid(), value)


## Включён ли эффект на активном уровне: возврат галочки возвращает
## именно уровень, а не «всё включено».
func _tier_effect_on(id: StringName) -> bool:
	match id:
		&"sdfgi", &"ssil", &"ssr", &"ssao", &"vfog", &"glow", &"aa", &"lamps":
			return _tier >= GraphicsQuality.Tier.HIGH
		&"grass":
			return _tier != GraphicsQuality.Tier.SIMPLE
		&"detail":
			return _tier >= GraphicsQuality.Tier.HIGH
		&"pom":
			# POM — только HIGH/ULTRA (П14 3.2); на NORMAL/SIMPLE рельефной
			# выборки в шейдере нет, включать нечего.
			return _tier >= GraphicsQuality.Tier.HIGH
		&"clutter":
			return _tier >= GraphicsQuality.Tier.HIGH
		&"refr":
			return _tier >= GraphicsQuality.Tier.HIGH
		&"ripple":
			# Рябь есть на всех уровнях (1 слой на SIMPLE/NORMAL — П14 4.7).
			return true
		&"caustic", &"rings":
			# Каустика и круги (П15 5-7) — только полная версия шейдера
			# (HIGH/ULTRA); на SIMPLE/NORMAL эффектов попросту нет.
			return _tier >= GraphicsQuality.Tier.HIGH
		&"occl":
			# Окклюзия (П16 п. 5) включена проектом на всех уровнях.
			return true
	return true


## Отчёт для буфера (П13 3.4): видеокарта, разрешение, уровень,
## разрешение 3D, средние FPS и GPU-мс за окно, выключенные эффекты.
func build_report() -> String:
	var lines: Array[String] = []
	lines.append("GPU: %s" % RenderingServer.get_video_adapter_name())
	if DisplayServer.get_name() != "headless":
		var size := DisplayServer.window_get_size()
		lines.append("Resolution: %d x %d" % [size.x, size.y])
	lines.append("Quality: %s (%d)" % [tr(TIER_LABELS[_tier]), _tier])
	if is_inside_tree():
		lines.append("3D resolution: %s" % _res3d_text())
	var fps_sum: float = 0.0
	var gpu_sum: float = 0.0
	for sample: Vector3 in _samples:
		fps_sum += sample.y
		gpu_sum += sample.z
	if _samples.is_empty():
		lines.append("FPS avg %d s: — | GPU ms avg: —" % REPORT_WINDOW_SEC)
	else:
		lines.append("FPS avg %d s: %.1f | GPU ms avg: %.2f" % [
			REPORT_WINDOW_SEC,
			fps_sum / _samples.size(),
			gpu_sum / _samples.size(),
		])
	var off: Array[String] = []
	for id: StringName in EFFECTS:
		if _boxes.has(id) and not _boxes[id].button_pressed:
			off.append(tr(EFFECT_LABELS[id]))
	lines.append("Disabled: %s" % (", ".join(off) if not off.is_empty() else "—"))
	return "\n".join(lines)


func _copy_report() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.clipboard_set(build_report())


# --- Авто-замер эффектов (П16 п. 9) ---

## Кнопка: свободна — запуск, идёт прогон — отмена (эффекты вернуть,
## отчёт не копировать).
func _on_auto_button() -> void:
	if _auto_running:
		_auto_finish(true)
	else:
		start_auto_measure()


## Запуск прогона: базовый шаг «уровень целиком» и по шагу на каждый
## активный сейчас эффект (галочка стоит, эффект есть на уровне).
## Длительности — параметры для тестов, кнопка зовёт с константами.
func start_auto_measure(
	step_sec: float = AUTO_STEP_SEC, warmup_sec: float = AUTO_WARMUP_SEC
) -> void:
	if _env == null:
		return
	_auto_queue.clear()
	for id: StringName in EFFECTS:
		if _boxes.has(id) and _boxes[id].button_pressed \
				and _tier_effect_on(id):
			_auto_queue.append(id)
	_auto_step_sec = maxf(step_sec, 0.001)
	_auto_warmup_sec = clampf(warmup_sec, 0.0, _auto_step_sec * 0.5)
	_auto_index = -1
	_auto_rows.clear()
	_auto_base_ms = 0.0
	_auto_running = true
	_auto_begin_step()


## Начало шага: у эффектного шага эффект выключен (базовый — уровень
## целиком), сэмплы копятся после прогрева.
func _auto_begin_step() -> void:
	_auto_time = 0.0
	_auto_samples.clear()
	if _auto_index >= 0 and _auto_index < _auto_queue.size():
		_on_effect_toggled(false, _auto_queue[_auto_index])
	if _auto_button != null:
		_auto_button.text = tr("BU_DBG_AUTOM_RUN") % [
			_auto_index + 2, _auto_queue.size() + 1]


## Тик кадра: после прогрева копить GPU-мс, по концу окна — следующий шаг.
func _auto_tick(delta: float) -> void:
	_auto_time += delta
	if _auto_time >= _auto_warmup_sec and _vp_rid.is_valid():
		_auto_samples.append(
			RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid))
	if _auto_time >= _auto_warmup_sec + _auto_step_sec:
		_auto_end_step()


## Конец шага: среднее шага в базу/строку, эффект вернуть уровнем,
## следующий шаг или финиш.
func _auto_end_step() -> void:
	var avg: float = 0.0
	if not _auto_samples.is_empty():
		var sum: float = 0.0
		for ms: float in _auto_samples:
			sum += ms
		avg = sum / _auto_samples.size()
	if _auto_index < 0:
		_auto_base_ms = avg
	else:
		_on_effect_toggled(true, _auto_queue[_auto_index])
		_auto_rows.append({"id": _auto_queue[_auto_index], "ms": avg})
	_auto_index += 1
	if _auto_index >= _auto_queue.size():
		_auto_finish(false)
	else:
		_auto_begin_step()


## Финиш/отмена: вернуть выключенный эффект текущего шага (отмена),
## кнопку — в исходный текст; не отмена — отчёт в буфер.
func _auto_finish(cancelled: bool) -> void:
	if cancelled and _auto_index >= 0 and _auto_index < _auto_queue.size():
		_on_effect_toggled(true, _auto_queue[_auto_index])
	_auto_running = false
	if _auto_button != null:
		_auto_button.text = tr("BU_DBG_AUTOM")
	if not cancelled and DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(build_auto_report())


## Отчёт авто-замера: экономия каждого эффекта по убыванию — что
## выключать в первую очередь (экономия = база − GPU-мс без эффекта).
func build_auto_report() -> String:
	var lines: Array[String] = []
	lines.append("GPU: %s" % RenderingServer.get_video_adapter_name())
	lines.append("Quality: %s (%d)" % [tr(TIER_LABELS[_tier]), _tier])
	if is_inside_tree():
		lines.append("3D resolution: %s" % _res3d_text())
	lines.append("Auto measure: %.1f s per effect, base %.2f GPU ms" % [
		_auto_step_sec, _auto_base_ms])
	var rows := _auto_rows.duplicate()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["ms"]) < float(b["ms"]))
	for row: Dictionary in rows:
		lines.append("%s: -%.2f GPU ms (%.2f without)" % [
			tr(EFFECT_LABELS[row["id"]]),
			_auto_base_ms - float(row["ms"]),
			float(row["ms"]),
		])
	return "\n".join(lines)


# --- Вкладка «Вода» (П15 8) ---

func _on_water_slider_changed(value: float, id: StringName) -> void:
	_water_values[id] = value
	if _slider_values.has(id):
		_slider_values[id].text = "%.2f" % value
	_apply_water()


func _on_water_color_changed(color: Color, id: StringName) -> void:
	_water_colors[id] = color
	_apply_water()


## Цвета активного пресета (П15-ДОП блок 5).
func _water_preset_colors() -> Dictionary:
	return WaterArea.WATER_PRESETS[_water_preset]["colors"]


func _on_water_preset_toggled(pressed: bool, id: StringName) -> void:
	if pressed:
		_select_water_preset(id)


## Выбрать пресет воды: общий идентификатор в WaterArea, живые зоны
## обновляют базы, пикеры переставляются на цвета пресета молча,
## затем одна рассылка значений.
func _select_water_preset(id: StringName) -> void:
	_water_preset = id
	WaterArea.set_water_preset(id)
	for node: Node in get_tree().get_nodes_in_group("water_surface"):
		(node as WaterArea).apply_water_preset()
	_water_applying = true
	var colors: Dictionary = _water_preset_colors()
	for def: Dictionary in WATER_COLORS:
		var color_id: StringName = def["id"]
		_pickers[color_id].color = colors[color_id]
		_water_colors[color_id] = colors[color_id]
	_water_applying = false
	_apply_water()


## Разослать текущие значения всем зонам воды (группа water_surface):
## каждая зона берёт свои озеро/море значения (WaterArea.set_palette/
## set_wave_params решают по calm). Настройки игры и сеть не затрагиваются.
func _apply_water() -> void:
	if _water_applying:
		return
	for node: Node in get_tree().get_nodes_in_group("water_surface"):
		var area := node as WaterArea
		area.set_palette(_water_colors[&"lake_deep"],
			_water_colors[&"lake_shallow"],
			_water_colors[&"sea_deep"], _water_colors[&"sea_shallow"])
		area.set_absorption_mult(_water_values[&"abs"])
		area.set_wave_params(_water_values[&"wave_height"],
			_water_values[&"wave_choppy"],
			_water_values[&"wave_speed"], _water_values[&"wave_freq"])
		area.set_ripple_fx(_water_values[&"ripple_strength"],
			_water_values[&"ripple_scale"])
		area.set_refraction_amount(_water_values[&"refraction"])
		area.set_foam(_water_values[&"foam_amount"],
			_water_values[&"foam_width"])
		area.set_foam_edge(_water_values[&"foam_edge"],
			_water_values[&"foam_bubbles"])
		area.set_roughness(_water_values[&"rough_near"],
			_water_values[&"rough_far"])
		area.set_caustic_brightness(_water_values[&"caustic"])
	# Юбка морского дна (П15-ДОП2, п. 1): ползунки склона идут в вид
	# острова (пересборка меша), не в шейдер воды; на сервере вида нет.
	if _view != null:
		_view.set_seafloor_slope(_water_values[&"seafloor_shelf"],
			_water_values[&"seafloor_deep"])


## «Сбросить» (П15 8.2): номиналы из констант WaterArea и дефолтный
## пресет («Туториал»); ползунки и пикеры переставляются молча
## (сигналы погашены), затем одно применение.
func _reset_water() -> void:
	_water_applying = true
	for def: Dictionary in WATER_SLIDERS:
		var id: StringName = def["id"]
		_sliders[id].value = def["def"]
		_water_values[id] = def["def"]
		_slider_values[id].text = "%.2f" % float(def["def"])
	_water_applying = false
	# Пресет возвращается к дефолту: кнопки переставляются без сигнала,
	# применение — одним вызовом (внутри переставит и пикеры).
	for id: StringName in _preset_buttons:
		_preset_buttons[id].set_pressed_no_signal(
			id == WaterArea.WATER_PRESET_DEFAULT)
	_select_water_preset(WaterArea.WATER_PRESET_DEFAULT)


## Текст «Скопировать значения» (П15 8.3 / П15-ДОП блок 5): константы
## WaterArea с текущими числами — вставляется в
## gameplay/world/water_area.gd как есть. Цвета и базы поглощения
## печатаются именами активного пресета (TUT_* / LAKE_*-SEA_*), базы —
## с уже применённым множителем ползунка (множители после вставки
## возвращаются к 1.0 — записей WAVE_*_MULT в тексте нет).
func build_water_values_text() -> String:
	var lines: Array[String] = []
	var consts: Dictionary = WATER_PRESET_CONSTS[_water_preset]
	var preset: Dictionary = WaterArea.WATER_PRESETS[_water_preset]
	for def: Dictionary in WATER_COLORS:
		var c: Color = _water_colors[def["id"]]
		lines.append("const %s: Color = Color(%s, %s, %s, %s)" % [
			consts[def["id"]], _fmt_water_num(c.r), _fmt_water_num(c.g),
			_fmt_water_num(c.b), _fmt_water_num(c.a)])
	for def: Dictionary in WATER_SLIDERS:
		if def.get("const", "") == "":
			continue
		lines.append("const %s: float = %s" % [
			def["const"], _fmt_water_num(_water_values[def["id"]])])
	# Базы поглощения пресета — с множителем ползунка «Поглощение».
	var mult: float = _water_values[&"abs"]
	for zone: String in ["lake", "sea"]:
		var base: Vector3 = preset["absorption"][zone] * mult
		lines.append("const %s: Vector3 = Vector3(%s, %s, %s)" % [
			consts["%s_abs" % zone], _fmt_water_num(base.x),
			_fmt_water_num(base.y), _fmt_water_num(base.z)])
	for def: Dictionary in WAVE_BASE_CONSTS:
		lines.append("const %s: float = %s" % [def["const"],
			_fmt_water_num(float(def["base"])
				* _water_values[def["mult"]])])
	return "\n".join(lines)


func _copy_water_values() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.clipboard_set(build_water_values_text())


## Число без хвоста нулей, но с десятичной частью («0.016», «1.0»).
static func _fmt_water_num(value: float) -> String:
	var text := "%.4f" % value
	while text.ends_with("0"):
		text = text.trim_suffix("0")
	if text.ends_with("."):
		text += "0"
	return text
