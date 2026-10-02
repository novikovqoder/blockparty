# HUD мира (раздел 15 SPEC): на этапе П1 — панель «Висит» с таймером у края
# расщелины. Монеты, маяки, иконка микрофона и подсказки взаимодействия —
# П2–П6, ников и пузырей над головами нет (это 3D-надписи, П3).
# Весь текст — через tr() и i18n/strings.csv (правило проекта).
class_name WorldHud
extends CanvasLayer

const PAL: Palette = preload("res://assets/palette.tres")

var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	layer = 10
	_build()
	EventBus.player_hang_started.connect(_on_hang_started)
	EventBus.player_hang_updated.connect(_on_hang_updated)
	EventBus.player_hang_ended.connect(_on_hang_ended)
	EventBus.player_respawned.connect(_on_hang_ended)


func _build() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PAL.hud_panel
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.position = Vector2(440, 560)
	_panel.size = Vector2(400, 60)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_label)
	_panel.hide()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.add_child(_panel)


func _on_hang_started(time_left: float) -> void:
	_refresh(time_left)
	_panel.show()


func _on_hang_updated(time_left: float) -> void:
	_refresh(time_left)


func _on_hang_ended() -> void:
	_panel.hide()


func _refresh(time_left: float) -> void:
	_label.text = tr("HUD_HANG") % time_left
