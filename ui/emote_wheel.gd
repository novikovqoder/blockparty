# Радиальное меню эмоций (раздел 7.5 SPEC): открывается удержанием Q
# (emote_wheel), секторы выбираются мышью, отпускание Q подтверждает выбор.
# Быстрые клавиши 1–6 работают без колеса — их обрабатывает сцена забега.
# UI из примитивов, как весь HUD (общая тема — этап 7).
class_name EmoteWheel
extends CanvasLayer

signal emote_selected(emote_id: int)

const PAL: Palette = preload("res://assets/palette.tres")

const RADIUS: float = 150.0  # радиус кольца секторов, px
const DEAD_ZONE: float = 36.0  # ближе к центру — выбора нет (отмена)
const SECTORS: int = 6
const CENTER: Vector2 = Vector2(640, 360)  # центр экрана 1280×720

var _slots: Array[ColorRect] = []
var _labels: Array[Label] = []
var _root: Control
var _active: int = -1  # индекс подсвеченного сектора, -1 — курсор в центре


func _ready() -> void:
	layer = 11
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	for i: int in SECTORS:
		var angle: float = TAU * float(i) / float(SECTORS)
		var pos: Vector2 = CENTER + Vector2(0.0, -RADIUS).rotated(angle) - Vector2(52, 26)
		var slot := ColorRect.new()
		slot.color = Color(PAL.plate, 0.92)
		slot.position = pos
		slot.size = Vector2(104, 52)
		_root.add_child(slot)
		var label := Label.new()
		label.text = "%d  %s" % [i + 1, tr("EMOTE_%d" % (i + 1))]
		label.position = pos + Vector2(6, 14)
		label.size = Vector2(92, 24)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", PAL.hud_text)
		label.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.15))
		label.add_theme_constant_override("outline_size", 3)
		_root.add_child(label)
		_slots.append(slot)
		_labels.append(label)


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	_active = -1
	_highlight()


func close() -> int:
	# Закрыть меню; возвращает выбранную эмоцию 1..6 или 0 (отмена).
	_root.visible = false
	var picked: int = 0
	if _active >= 0:
		picked = _active + 1
	_active = -1
	return picked


func _process(_delta: float) -> void:
	if not _root.visible:
		return
	var to_mouse: Vector2 = _root.get_local_mouse_position() - CENTER
	_active = -1
	if to_mouse.length() >= DEAD_ZONE:
		# Угол от верхней точки, растёт по часовой стрелке.
		var angle: float = fposmod(atan2(to_mouse.y, to_mouse.x) + PI * 0.5, TAU)
		_active = int(round(angle / TAU * float(SECTORS))) % SECTORS
	_highlight()


func _highlight() -> void:
	for i: int in SECTORS:
		var on: bool = i == _active
		_slots[i].color = PAL.marker if on else Color(PAL.plate, 0.92)
		_labels[i].add_theme_font_size_override("font_size", 18 if on else 15)
