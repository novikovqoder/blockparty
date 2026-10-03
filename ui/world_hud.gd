# HUD мира (раздел 15 SPEC): монеты (П2 — их уже можно собирать), название
# зоны при переходе (П2), панель «Висит» с таймером у края расщелины,
# уведомления «игрок вошёл/покинул мир» (П3). Мини-индикатор маяков, иконка
# микрофона и подсказки взаимодействия — П5–П6.
# Весь текст — через tr() и i18n/strings.csv (правило проекта).
class_name WorldHud
extends CanvasLayer

const PAL: Palette = preload("res://assets/palette.tres")

## Сколько секунд висит название зоны при переходе.
const ZONE_HINT_TIME: float = 3.0

var _panel: PanelContainer
var _label: Label
var _coins: Label
var _zone: Label
var _zone_left: float = 0.0
var _toast: Label
var _toast_left: float = 0.0


func _ready() -> void:
	layer = 10
	_build()
	EventBus.player_hang_started.connect(_on_hang_started)
	EventBus.player_hang_updated.connect(_on_hang_updated)
	EventBus.player_hang_ended.connect(_on_hang_ended)
	EventBus.player_respawned.connect(_on_hang_ended)
	EventBus.world_coins_changed.connect(_on_coins_changed)
	EventBus.peer_joined_world.connect(_on_peer_joined)
	EventBus.peer_left.connect(_on_peer_left)


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
	# Монеты: слева сверху (раздел 15 — минималистичный HUD).
	_coins = Label.new()
	_coins.position = Vector2(20, 14)
	_coins.add_theme_font_size_override("font_size", 20)
	_coins.add_theme_color_override("font_color", PAL.coin)
	_coins.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_coins.add_theme_constant_override("outline_size", 4)
	root.add_child(_coins)
	_on_coins_changed(Session.world_coins)
	# Название зоны: по центру сверху, показывается при переходе (П2).
	_zone = Label.new()
	_zone.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_zone.position = Vector2(540, 12)
	_zone.size = Vector2(200, 30)
	_zone.add_theme_font_size_override("font_size", 22)
	_zone.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	_zone.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_zone.add_theme_constant_override("outline_size", 4)
	_zone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone.hide()
	root.add_child(_zone)
	# «Игрок вошёл/покинул мир» (П3): под названием зоны, гаснет сам.
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(540, 46)
	_toast.size = Vector2(200, 26)
	_toast.add_theme_font_size_override("font_size", 17)
	_toast.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_toast.add_theme_constant_override("outline_size", 4)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.hide()
	root.add_child(_toast)


## Показать название зоны (ключ ZONE_<ИМЯ>); пустая зона прячет подсказку.
func show_zone(zone_name: String) -> void:
	if zone_name == "":
		_zone_left = 0.0
		_zone.hide()
		return
	_zone.text = tr("ZONE_%s" % zone_name.to_upper())
	_zone.show()
	_zone_left = ZONE_HINT_TIME


func _on_coins_changed(total: int) -> void:
	_coins.text = tr("HUD_COINS") % total


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
