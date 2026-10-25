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
## Галочки эффектов (П13 3.2): порядок = порядок в панели.
const EFFECTS: Array[StringName] = [
	&"sdfgi", &"ssil", &"ssr", &"ssao", &"vfog", &"glow", &"aa",
	&"lamps", &"grass", &"parallax", &"water",
]
## Ключи перевода подписей и заголовка блока.
const EFFECT_LABELS: Dictionary[StringName, String] = {
	&"sdfgi": "BU_DBG_SDFGI", &"ssil": "BU_DBG_SSIL", &"ssr": "BU_DBG_SSR",
	&"ssao": "BU_DBG_SSAO", &"vfog": "BU_DBG_VFOG", &"glow": "BU_DBG_GLOW",
	&"aa": "BU_DBG_AA", &"lamps": "BU_DBG_LAMPS", &"grass": "BU_DBG_GRASS",
	&"parallax": "BU_DBG_PARALLAX", &"water": "BU_DBG_WATER",
}
## Названия уровней для строк панели и отчёта (индекс = Tier).
const TIER_LABELS: Array[String] = [
	"BU_OPT_LOW", "BU_OPT_MEDIUM", "BU_OPT_HIGH", "BU_OPT_ULTRA",
]
## Позиция блока эффектов: правее нижнего информационного блока,
## вмещается в минимальную канву 1280×720.
const EFFECTS_POS: Vector2 = Vector2(690, 360)

var _label: Label
var _effects: PanelContainer
var _boxes: Dictionary[StringName, CheckBox] = {}
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


## Блок галочек и кнопки отчёта (П13 3.2): видим только вместе с панелью;
## корень канвы события мыши не ест — клики мимо панели идут в игру.
func _build_effects(root: Control) -> void:
	_effects = PanelContainer.new()
	_effects.position = EFFECTS_POS
	_effects.visible = false
	root.add_child(_effects)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_effects.add_child(box)
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
		&"parallax":
			if _view != null:
				_view.set_parallax(value)
		&"water":
			for node: Node in get_tree().get_nodes_in_group("water_surface"):
				(node as WaterArea).set_refraction(value)


## Включён ли эффект на активном уровне: возврат галочки возвращает
## именно уровень, а не «всё включено».
func _tier_effect_on(id: StringName) -> bool:
	match id:
		&"sdfgi", &"ssil", &"ssr", &"ssao", &"vfog", &"glow", &"aa", &"lamps":
			return _tier >= GraphicsQuality.Tier.HIGH
		&"grass":
			return _tier != GraphicsQuality.Tier.SIMPLE
		&"parallax":
			return true
		&"water":
			return _tier >= GraphicsQuality.Tier.HIGH
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
