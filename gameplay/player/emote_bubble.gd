# Пузырь эмоции над персонажем (разделы 4, 7.5 SPEC): фраза-эмоция на
# emote_show_time секунд. Дочерняя нода игрока (своего или удалённого);
# текст — ключи EMOTE_1..EMOTE_6 из strings.csv.
class_name EmoteBubble
extends Node2D

const PAL: Palette = preload("res://assets/palette.tres")
const B: Balance = preload("res://gameplay/balance.tres")

var _label: Label
var _left: float = 0.0


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(-64, -14)
	_label.size = Vector2(128, 24)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", PAL.hud_text)
	_label.add_theme_color_override("font_outline_color", Color.WHITE)
	_label.add_theme_constant_override("outline_size", 3)
	add_child(_label)
	visible = false


## Показать эмоцию (1–6); перезапускает таймер, если пузырь уже висит.
func show_emote(emote_id: int) -> void:
	_label.text = tr("EMOTE_%d" % clampi(emote_id, 1, 6))
	visible = true
	_left = B.emote_show_time
	modulate = Color.TRANSPARENT
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.1)


func _process(delta: float) -> void:
	if not visible:
		return
	_left -= delta
	if _left <= 0.0:
		visible = false
