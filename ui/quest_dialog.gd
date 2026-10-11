# Диалог жителя (П5.5): короткая плашка — имя, задание, 2 реплики и кнопки
# «Помогу» / «Потом». Деревьев диалогов нет: доступно — предложить задание,
# идёт — реплика с прогрессом, выполнено сегодня — благодарность. E/Enter —
# «Помогу», Esc — «Потом». Открывается сигналом quest_talk_requested
# (узел Townsfolk), состояние спрашивает у Net.quests.
class_name QuestDialog
extends CanvasLayer

const PAL: Palette = preload("res://assets/palette.tres")

## id → ключи строк: название, реплики предложения, хода и благодарности.
const TEXT_KEYS: Dictionary = {
	Protocol.QUEST_THYME: {
		"name": "QUEST_THYME_NAME", "offer": ["QUEST_THYME_L1", "QUEST_THYME_L2"],
		"active": "QUEST_THYME_ACTIVE", "done": "QUEST_THYME_DONE",
	},
	Protocol.QUEST_LUMI: {
		"name": "QUEST_LUMI_NAME", "offer": ["QUEST_LUMI_L1", "QUEST_LUMI_L2"],
		"active": "QUEST_LUMI_ACTIVE", "done": "QUEST_LUMI_DONE",
	},
	Protocol.QUEST_FINN: {
		"name": "QUEST_FINN_NAME", "offer": ["QUEST_FINN_L1", "QUEST_FINN_L2"],
		"active": "QUEST_FINN_ACTIVE", "done": "QUEST_FINN_DONE",
	},
}
## id → ключ строки счётчика шагов в реплике хода.
const TRACK_KEYS: Dictionary = {
	Protocol.QUEST_THYME: "QUEST_TRACK_MINT",
	Protocol.QUEST_LUMI: "QUEST_TRACK_BEACONS",
	Protocol.QUEST_FINN: "QUEST_TRACK_FLAGS",
}

var _root: Control
var _title: Label
var _quest_name: Label
var _line1: Label
var _line2: Label
var _help: Button
var _quest_id: String = ""


func _ready() -> void:
	layer = 16
	_build()
	_root.visible = false
	EventBus.quest_talk_requested.connect(open)
	EventBus.quest_state.connect(_on_quest_state)


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		if _help.visible:
			_take()
		else:
			close()
		get_viewport().set_input_as_handled()


## Открыть диалог жителя (E у Townsfolk или таблички-записки).
func open(quest_id: String) -> void:
	_quest_id = quest_id
	_fill()
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Состояние заданий сменилось, пока диалог открыт — обновить реплики.
func _on_quest_state(_state: Dictionary) -> void:
	if _root.visible:
		_fill()


## Разложить текст по стадии задания.
func _fill() -> void:
	var keys: Dictionary = TEXT_KEYS.get(_quest_id, {})
	if keys.is_empty():
		close()
		return
	var stage := Net.quests.stage(_quest_id)
	var quest: Variant = Net.quests.state().get(_quest_id)
	_title.text = _npc_name()
	_quest_name.text = tr(String(keys["name"]))
	_help.visible = stage == QuestAuthority.AVAILABLE
	_line2.visible = true
	match stage:
		QuestAuthority.AVAILABLE:
			var offer: Array = keys["offer"]
			_line1.text = tr(String(offer[0]))
			_line2.text = tr(String(offer[1]))
		QuestAuthority.ACTIVE:
			_line1.text = tr(String(keys["active"]))
			_line2.text = _progress_line(quest)
		_:
			_line1.text = tr(String(keys["done"]))
			_line2.visible = false


## «Мята: 3 / 5» — реплика хода с прогрессом.
func _progress_line(quest: Variant) -> String:
	if quest is not Dictionary:
		return ""
	var done := 0
	var total := 0
	for value: int in quest["steps"]:
		done += value
		total += 1
	return "%s: %d / %d" % [tr(String(TRACK_KEYS.get(_quest_id, ""))), done, total]


func _take() -> void:
	Net.request_quest_take(_quest_id)
	close()


## Имя жителя задания из characters.json по текущей локали.
func _npc_name() -> String:
	for spot: Dictionary in QuestLayout.npc_spots(null):
		if String(spot["quest_id"]) == _quest_id:
			return CharacterData.pick_text(
				CharacterData.get_character(int(spot["character"]))["name"]
			)
	return ""


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.25)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	UiLayout.center(panel, Vector2(420, 300))
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
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)

	_quest_name = Label.new()
	_quest_name.add_theme_font_size_override("font_size", 19)
	_quest_name.add_theme_color_override("font_color", PAL.coin)
	_quest_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_quest_name)

	_line1 = Label.new()
	_line1.add_theme_font_size_override("font_size", 20)
	_line1.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	_line1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line1.custom_minimum_size = Vector2(360, 0)
	box.add_child(_line1)

	_line2 = Label.new()
	_line2.add_theme_font_size_override("font_size", 20)
	_line2.add_theme_color_override("font_color", Color(0.85, 0.88, 0.94))
	_line2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line2.custom_minimum_size = Vector2(360, 0)
	box.add_child(_line2)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)

	_help = Button.new()
	_help.text = tr("QUEST_HELP")
	_help.custom_minimum_size = Vector2(180, 48)
	_help.add_theme_font_size_override("font_size", 22)
	_help.pressed.connect(_take)
	buttons.add_child(_help)

	var later := Button.new()
	later.text = tr("QUEST_LATER")
	later.custom_minimum_size = Vector2(180, 48)
	later.add_theme_font_size_override("font_size", 22)
	later.pressed.connect(close)
	buttons.add_child(later)
