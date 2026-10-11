# Меню Esc в мире (раздел 15 SPEC): «Продолжить», «Пригласить друга»
# (оверлей Steam, раздел 11 — в Steam-мире) и «Выйти из мира», курсор
# освобождается, мир не ставится на паузу. Полное меню («Встречи»,
# «Вернуться на площадь», настройки) — этап П8.
# Сцена мира переключает меню по action «pause»; при выходе из мира
# слушает только сигнал exit_requested.
class_name EscMenu
extends CanvasLayer

const PAL: Palette = preload("res://assets/palette.tres")

## Пользователь выбрал «Выйти из мира».
signal exit_requested()

var _root: Control


func _ready() -> void:
	layer = 15
	_build()
	_root.visible = false


## Открыть/закрыть меню; возвращает новое состояние видимости.
func toggle() -> bool:
	_root.visible = not _root.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _root.visible else Input.MOUSE_MODE_CAPTURED
	return _root.visible


func close() -> void:
	if _root.visible:
		toggle()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.35)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	UiLayout.center(panel, Vector2(300, 220))
	var style := StyleBoxFlat.new()
	style.bg_color = PAL.hud_panel
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)

	var title := Label.new()
	title.text = tr("ESC_TITLE")
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var resume := Button.new()
	resume.text = tr("ESC_RESUME")
	resume.custom_minimum_size = Vector2(240, 48)
	resume.add_theme_font_size_override("font_size", 22)
	resume.pressed.connect(close)
	box.add_child(resume)

	# Раздел 11: в Steam-мире — приглашение через оверлей Steam.
	if Net.mode == "steam" and SteamService.current_lobby_id != 0:
		var invite := Button.new()
		invite.text = tr("ESC_INVITE_FRIEND")
		invite.custom_minimum_size = Vector2(240, 48)
		invite.add_theme_font_size_override("font_size", 22)
		invite.pressed.connect(func() -> void: SteamService.open_invite_overlay())
		box.add_child(invite)

	var exit := Button.new()
	exit.text = tr("ESC_EXIT_WORLD")
	exit.custom_minimum_size = Vector2(240, 48)
	exit.add_theme_font_size_override("font_size", 22)
	exit.pressed.connect(func() -> void: exit_requested.emit())
	box.add_child(exit)
