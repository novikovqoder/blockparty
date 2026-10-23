class_name MenuButtonBU
extends Button
## Пункт главного меню: заглавные буквы, ромб слева у выбранного пункта.
## Мышь и клавиатура/геймпад работают одинаково: наведение = фокус.

const INDENT: float = 40.0

var _t: float = 0.0


func _init(label_key: String = "", font_size: int = 30) -> void:
	text = label_key
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(0, 54)
	add_theme_font_override("font", UiStyleBU.display(700))
	add_theme_font_size_override("font_size", font_size)
	add_theme_constant_override("outline_size", 0)
	var pad: StyleBoxEmpty = StyleBoxEmpty.new()
	pad.content_margin_left = INDENT
	for st: String in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
		add_theme_stylebox_override(st, pad)


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _on_mouse_entered() -> void:
	if not disabled:
		grab_focus()


func _process(delta: float) -> void:
	if has_focus():
		_t += delta
		queue_redraw()


func _draw() -> void:
	if not has_focus():
		return
	var a: float = 0.6 + 0.4 * (0.5 + 0.5 * sin(_t * TAU / 2.0))
	var col: Color = UiStyleBU.ACCENT
	col.a = a
	UiStyleBU.draw_diamond(self, Vector2(10.0, size.y * 0.5), 7.0, col)
