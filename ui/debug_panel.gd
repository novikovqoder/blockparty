# Отладочная панель F3 (разделы 15, 18 SPEC): FPS, пинг, число пиров, режим
# сети, часы мира, время сессии и монеты. Переключается клавишей F3
# (физическая, раскладконезависимая). Технические метки не локализуются —
# это dev-инструмент, не UI продукта.
# Не делает: трафик снапшотов и зону — появятся на этапах П2–П3.
class_name DebugPanel
extends CanvasLayer

const UPDATE_INTERVAL: float = 0.25

var _label: Label
var _visible_panel: bool = false
var _was_pressed: bool = false
var _accum: float = 0.0


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


func _process(delta: float) -> void:
	var pressed: bool = Input.is_physical_key_pressed(KEY_F3)
	if pressed and not _was_pressed:
		_visible_panel = not _visible_panel
		_label.visible = _visible_panel
	_was_pressed = pressed
	if not _visible_panel:
		return
	_accum += delta
	if _accum >= UPDATE_INTERVAL:
		_accum = 0.0
		_refresh()


func _refresh() -> void:
	var ping: int = Net.ping_msec()
	_label.text = "\n".join([
		"FPS %d | ping %s | peers %d | mode %s" % [
			Engine.get_frames_per_second(),
			"—" if ping < 0 else "%d ms" % ping,
			Net.peer_count(),
			Net.mode,
		],
		"world_time %.1f s | session %.1f s | coins %d" % [
			Session.world_time, Session.session_time, Session.world_coins,
		],
	])
