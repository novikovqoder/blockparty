# HUD мира (раздел 15 SPEC): название зоны при переходе (П2), панель «Висит»
# с таймером у края расщелины, уведомления «игрок вошёл/покинул мир» (П3).
# Иконка микрофона и подсказки взаимодействия — П5–П6.
# Весь текст — через tr() и i18n/strings.csv (правило проекта).
class_name WorldHud
extends CanvasLayer

const PAL: Palette = preload("res://assets/palette.tres")

## Сколько секунд висит название зоны при переходе.
const ZONE_HINT_TIME: float = 3.0

var _panel: PanelContainer
var _label: Label
var _zone: Label
var _zone_left: float = 0.0
var _toast: Label
var _toast_left: float = 0.0
var _hint: Label
var _hint_hold: ProgressBar


func _ready() -> void:
	layer = 10
	_build()
	EventBus.player_hang_started.connect(_on_hang_started)
	EventBus.player_hang_updated.connect(_on_hang_updated)
	EventBus.player_hang_ended.connect(_on_hang_ended)
	EventBus.player_respawned.connect(_on_hang_ended)
	EventBus.peer_joined_world.connect(_on_peer_joined)
	EventBus.peer_left.connect(_on_peer_left)
	EventBus.interaction_hint.connect(_on_interaction_hint)
	EventBus.interaction_progress.connect(_on_interaction_progress)
	EventBus.toast_requested.connect(_on_toast_requested)


func _process(delta: float) -> void:
	if _zone_left > 0.0:
		_zone_left -= delta
		if _zone_left <= 0.0:
			_zone.hide()
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast.hide()


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
	UiLayout.center_bottom(_panel, Vector2(400, 60), 100.0)
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
	# Название зоны: по центру сверху, показывается при переходе (П2).
	_zone = Label.new()
	UiLayout.center_top(_zone, Vector2(200, 30), 12.0)
	_zone.add_theme_font_size_override("font_size", 22)
	_zone.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	_zone.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_zone.add_theme_constant_override("outline_size", 4)
	_zone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone.hide()
	root.add_child(_zone)
	# «Игрок вошёл/покинул мир» (П3): под названием зоны, гаснет сам.
	_toast = Label.new()
	UiLayout.center_top(_toast, Vector2(200, 26), 46.0)
	_toast.add_theme_font_size_override("font_size", 17)
	_toast.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_toast.add_theme_constant_override("outline_size", 4)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.hide()
	root.add_child(_toast)
	# Подсказка взаимодействия «E — …» (раздел 15) с прогрессом удержания.
	_hint = Label.new()
	UiLayout.center_bottom(_hint, Vector2(400, 28), 92.0)
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.hide()
	root.add_child(_hint)
	_hint_hold = ProgressBar.new()
	UiLayout.center_bottom(_hint_hold, Vector2(200, 8), 80.0)
	_hint_hold.min_value = 0.0
	_hint_hold.max_value = 1.0
	_hint_hold.show_percentage = false
	_hint_hold.modulate = PAL.gold
	_hint_hold.hide()
	root.add_child(_hint_hold)


## Подсказка у интерактивного объекта: ключ действия или пусто (скрыть).
## У объектов с удержанием добавляем «(удерживать)» — ключ знает hold только
## игрок, поэтому формат выбираем по факту прогресса.
func _on_interaction_hint(key: String) -> void:
	if key.is_empty():
		_hint.hide()
		return
	_hint.text = "%s — %s" % [tr("HUD_HINT_KEY"), tr(key)]
	_hint.show()


func _on_interaction_progress(fraction: float) -> void:
	if fraction < 0.0:
		_hint_hold.hide()
		return
	_hint_hold.value = fraction
	_hint_hold.show()


## Короткое сообщение от механик («Нужен второй игрок», раздел 7) —
## ключ i18n, как у подсказок.
func _on_toast_requested(key: String) -> void:
	_show_toast(tr(key))


## Показать название зоны (ключ ZONE_<ИМЯ>); пустая зона прячет подсказку.
func show_zone(zone_name: String) -> void:
	if zone_name == "":
		_zone_left = 0.0
		_zone.hide()
		return
	_zone.text = tr("ZONE_%s" % zone_name.to_upper())
	_zone.show()
	_zone_left = ZONE_HINT_TIME


func _on_hang_started(time_left: float) -> void:
	_refresh(time_left)
	_panel.show()


func _on_hang_updated(time_left: float) -> void:
	_refresh(time_left)


func _on_hang_ended() -> void:
	_panel.hide()


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.show()
	_toast_left = ZONE_HINT_TIME


func _on_peer_joined(_peer_id: int, player_name: String) -> void:
	_show_toast(tr("HUD_PLAYER_JOIN") % player_name)


func _on_peer_left(_peer_id: int, player_name: String) -> void:
	_show_toast(tr("HUD_PLAYER_LEAVE") % player_name)


func _refresh(time_left: float) -> void:
	_label.text = tr("HUD_HANG") % time_left
