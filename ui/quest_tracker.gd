# Трекер заданий жителей (П5.5, раздел 15): справа сверху до трёх строк
# активных заданий — «Мята: 3/5», по одной на задание (порядок —
# Protocol.QUEST_IDS). Слушает quest_state от хоста: у всех игроков один
# прогресс. Названия — через tr() (QUEST_TRACK_* в strings.csv).
class_name QuestTracker
extends CanvasLayer

const PAL: Palette = preload("res://assets/palette.tres")

## Строк в трекере: по числу заданий (ТЗ: до 3).
const LINES: int = 3
## Шрифт строки и отступ от края окна, px.
const FONT_SIZE: int = 18
const MARGIN: float = 16.0
const LINE_HEIGHT: float = 26.0
## Ширина блока под строку (выравнивание вправо), px.
const LINE_WIDTH: float = 230.0

var _labels: Array[Label] = []


func _ready() -> void:
	layer = 11
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	for i: int in LINES:
		var label := Label.new()
		UiLayout.top_right(
			label, Vector2(LINE_WIDTH, LINE_HEIGHT),
			MARGIN, MARGIN + float(i) * LINE_HEIGHT,
		)
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.add_theme_color_override("font_color", PAL.coin)
		label.add_theme_color_override("font_color_outline", Color(0, 0, 0))
		label.add_theme_constant_override("outline_size", 4)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.hide()
		root.add_child(label)
		_labels.append(label)
	EventBus.quest_state.connect(_on_quest_state)


## Состояние заданий от хоста: строки идущих заданий с прогрессом шагов.
func _on_quest_state(state: Dictionary) -> void:
	var lines: Array[String] = []
	for id: String in Protocol.QUEST_IDS:
		var quest: Variant = state.get(id)
		if quest is not Dictionary:
			continue
		if int(quest["stage"]) != QuestAuthority.ACTIVE:
			continue
		var steps: Array = quest["steps"]
		var done := 0
		for value: int in steps:
			done += value
		var track: Dictionary = Protocol.QUEST_TRACK[id]
		lines.append("%s: %d/%d" % [tr(String(track["key"])), done, steps.size()])
	for i: int in LINES:
		if i < lines.size():
			_labels[i].text = lines[i]
			_labels[i].show()
		else:
			_labels[i].hide()
