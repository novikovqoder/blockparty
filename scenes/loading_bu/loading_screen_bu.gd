class_name LoadingScreenBU
extends CanvasLayer
## Экран загрузки Born Unblessed: картина, название, строка состояния, тонкая полоса прогресса
## и сменяющиеся подсказки. Грузит сцену мира в фоне (ResourceLoader.load_threaded_request),
## подменяет текущую сцену и держится поверх, пока мир не будет готов, затем плавно уходит.
##
## Использование (например, из главного меню вместо change_scene_to_file):
##     LoadingScreenBU.open(get_tree(), "res://scenes/world_scene.tscn")
## Если у корня сцены мира есть сигнал `world_ready`, экран ждёт его (до ready_timeout секунд),
## иначе — несколько кадров после добавления сцены.

signal finished(scene: Node)
signal failed(path: String)

const ART_PATH: String = "res://assets/loading_bu/loading_bg.jpg"
const FALLBACK_ART_PATH: String = "res://assets/menu_bu/bu_bg.jpg"
const HINT_KEYS: Array[String] = ["BU_LOAD_HINT_1", "BU_LOAD_HINT_2", "BU_LOAD_HINT_3", "BU_LOAD_HINT_4",
	"BU_LOAD_HINT_5", "BU_LOAD_HINT_6"]

## Минимальное время показа экрана, с (чтобы не мигал при быстрой загрузке).
@export var min_time: float = 1.6
## Сколько ждать сигнала world_ready, с.
@export var ready_timeout: float = 30.0
## Затухание из чёрного в начале и уход экрана в конце, с.
@export var fade_in_time: float = 0.6
@export var fade_out_time: float = 0.8
## Смена подсказки, с.
@export var hint_period: float = 7.0

var scene_path: String = ""
var progress: float = 0.0

var _state: int = 0          # 0 загрузка ресурса, 1 ждём готовности мира, 2 уход, 3 ошибка, 4 подмена сцены
var _t: float = 0.0
var _state_t: float = 0.0
var _shown: float = 0.0
var _hint_i: int = 0
var _hint_base: int = 0
var _new_scene: Node = null
var _ready_flag: bool = false
var _frames_after: int = 0

var _root: Control
var _art: TextureRect
var _black: ColorRect
var _status: Label
var _dots: Control
var _bar_bg: ColorRect
var _bar: ColorRect
var _hint: Label
var _pct: Label

## Открытый сейчас экран загрузки (или null) — мир может менять строку состояния:
##     if LoadingScreenBU.current: LoadingScreenBU.current.set_status("BU_LOAD_CONNECT")
static var current: LoadingScreenBU = null


## Открыть экран загрузки и начать загрузку сцены. Возвращает созданный экран.
static func open(tree: SceneTree, path: String) -> LoadingScreenBU:
	var ls: LoadingScreenBU = LoadingScreenBU.new()
	ls.scene_path = path
	tree.root.add_child(ls)
	return ls


## Строка состояния (ключ перевода или текст) — для этапов, которые знает только мир
## (например «Подключение к миру» у клиента).
func set_status(key_or_text: String) -> void:
	if _status != null and _state != 3:
		_status.text = tr(key_or_text)


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		_fail("scene not found")
		return
	var err: Error = ResourceLoader.load_threaded_request(scene_path, "PackedScene", true)
	if err != OK:
		_fail("load_threaded_request %d" % err)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiStyleBU.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var bg: ColorRect = ColorRect.new()
	bg.color = UiStyleBU.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	_art = TextureRect.new()
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var tex: Texture2D = null
	if ResourceLoader.exists(ART_PATH):
		tex = load(ART_PATH) as Texture2D
	if tex == null and ResourceLoader.exists(FALLBACK_ART_PATH):
		tex = load(FALLBACK_ART_PATH) as Texture2D
		_art.modulate = Color(0.55, 0.5, 0.5)       # запасная картинка — приглушённая
	_art.texture = tex
	_root.add_child(_art)

	# затемнение снизу — под текст
	var shade: TextureRect = TextureRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(UiStyleBU.BG, 0.0))
	g.set_color(1, Color(UiStyleBU.BG, 0.92))
	g.add_point(0.55, Color(UiStyleBU.BG, 0.15))
	var gt: GradientTexture2D = GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 16
	gt.height = 256
	shade.texture = gt
	_root.add_child(shade)

	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 96
	box.offset_right = -96
	box.offset_top = -300
	box.offset_bottom = -72
	box.add_theme_constant_override("separation", 14)
	_root.add_child(box)

	var title: Label = Label.new()
	title.text = "BORN UNBLESSED"
	title.add_theme_font_override("font", UiStyleBU.display_spaced(700, 6))
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", UiStyleBU.TEXT_STRONG)
	box.add_child(title)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	_dots = Control.new()
	_dots.custom_minimum_size = Vector2(54, 26)
	_dots.draw.connect(_draw_dots)
	row.add_child(_dots)
	_status = Label.new()
	_status.text = tr("BU_LOAD_ASSETS")
	_status.add_theme_font_override("font", UiStyleBU.body(600))
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_color_override("font_color", UiStyleBU.TEXT_SOFT)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status)
	_pct = Label.new()
	_pct.text = "0 %"
	_pct.add_theme_font_override("font", UiStyleBU.body(600))
	_pct.add_theme_font_size_override("font_size", 18)
	_pct.add_theme_color_override("font_color", UiStyleBU.TEXT_DIM)
	row.add_child(_pct)

	var bar_holder: Control = Control.new()
	bar_holder.custom_minimum_size = Vector2(0, 2)
	box.add_child(bar_holder)
	_bar_bg = ColorRect.new()
	_bar_bg.color = UiStyleBU.HAIRLINE
	_bar_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_holder.add_child(_bar_bg)
	_bar = ColorRect.new()
	_bar.color = UiStyleBU.ACCENT_LINE
	_bar.anchor_bottom = 1.0
	bar_holder.add_child(_bar)

	_hint = Label.new()
	_hint_i = randi() % HINT_KEYS.size()
	_hint_base = _hint_i
	_hint.text = tr(HINT_KEYS[_hint_i])
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_override("font", UiStyleBU.display(600))
	_hint.add_theme_font_size_override("font_size", 24)
	_hint.add_theme_color_override("font_color", UiStyleBU.TEXT_MUTED)
	box.add_child(_hint)

	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 1)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_black)


func _draw_dots() -> void:
	# три ромба бегут по очереди
	for i: int in 3:
		var ph: float = fmod(_t * 1.6 - float(i) * 0.33, 1.0)
		var a: float = 0.25 + 0.75 * clampf(sin(ph * PI), 0.0, 1.0)
		var col: Color = UiStyleBU.ACCENT
		col.a = a
		UiStyleBU.draw_diamond(_dots, Vector2(9.0 + float(i) * 18.0, 13.0), 6.0, col)


func _process(delta: float) -> void:
	_t += delta
	_state_t += delta
	_shown += delta
	_dots.queue_redraw()
	# появление из чёрного (меню уходит в чёрный — переход без вспышки)
	if _state < 2:
		_black.color.a = clampf(1.0 - _shown / maxf(fade_in_time, 0.01), 0.0, 1.0)
	# подсказки
	if _shown > float(_hint_i - _hint_base + 1) * hint_period:
		_hint_i += 1
		_hint.text = tr(HINT_KEYS[_hint_i % HINT_KEYS.size()])
	match _state:
		0:
			var p: Array = []
			var st: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(scene_path, p)
			if p.size() > 0:
				progress = maxf(progress, float(p[0]) * 0.7)
			if st == ResourceLoader.THREAD_LOAD_LOADED and _shown >= fade_in_time:
				var ps: PackedScene = ResourceLoader.load_threaded_get(scene_path) as PackedScene
				if ps == null:
					_fail("not a PackedScene")
					return
				_state = 4                          # идёт подмена сцены
				_status.text = tr("BU_LOAD_BUILD")
				progress = 0.75
				_pct.text = "75 %"
				_bar.anchor_right = progress
				# кадр с обновлённой надписью успевает показаться до тяжёлого _ready мира
				await get_tree().process_frame
				await get_tree().process_frame
				_swap_scene(ps)
			elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_fail("thread load status %d" % st)
		1:
			_frames_after += 1
			progress = minf(0.98, progress + delta * 0.15)
			var ok: bool = _ready_flag or (_frames_after > 3 and not _new_scene.has_signal(&"world_ready"))
			if (ok or _state_t > ready_timeout) and _shown >= min_time:
				progress = 1.0
				_state = 2
				_state_t = 0.0
				_status.text = tr("BU_LOAD_DONE")
		2:
			var k: float = clampf(_state_t / maxf(fade_out_time, 0.01), 0.0, 1.0)
			_root.modulate.a = 1.0 - k
			if k >= 1.0:
				finished.emit(_new_scene)
				queue_free()
	_bar.anchor_right = progress
	_pct.text = "%d %%" % int(round(progress * 100.0))


func _swap_scene(ps: PackedScene) -> void:
	var tree: SceneTree = get_tree()
	var old: Node = tree.current_scene
	_new_scene = ps.instantiate()
	if _new_scene.has_signal(&"world_ready"):
		_new_scene.connect(&"world_ready", _on_world_ready, CONNECT_ONE_SHOT)
	if old != null:
		old.queue_free()
	tree.root.add_child(_new_scene)
	tree.current_scene = _new_scene
	tree.root.move_child(self, -1)          # экран остаётся поверх
	if _status.text == tr("BU_LOAD_BUILD"):
		_status.text = tr("BU_LOAD_HERO")
	_state = 1
	_state_t = 0.0
	_frames_after = 0


func _on_world_ready() -> void:
	_ready_flag = true


func _fail(why: String) -> void:
	push_warning("LoadingScreenBU: %s (%s)" % [why, scene_path])
	_state = 3
	_status.text = tr("BU_LOAD_FAILED")
	_status.add_theme_color_override("font_color", UiStyleBU.ACCENT_TEXT)
	_black.color.a = 0.0
	failed.emit(scene_path)
