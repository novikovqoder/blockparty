# Карта острова (разделы 6, 15 SPEC): вид сверху — текстура island_map.png,
# отрендеренная при генерации острова; маркер своего персонажа двигается по
# карте, стрелка показывает направление взгляда. Подписи зон — через tr()
# (ZONE_<ИМЯ> в strings.csv). Не делает: друзей Steam (П4) и маяки (П5) —
# отметки появятся с этими этапами.
class_name IslandMap
extends CanvasLayer

const TEXTURE: Texture2D = preload("res://assets/island_map.png")

## Остров 256 × 256 м: x и z ∈ [−128, 128] (IslandGen.HALF).
const HALF_WORLD: float = 128.0
## Размер карты на экране, px (текстура 256 × 256 растянута ×2).
const DISPLAY_SIZE: float = 512.0
## Сторона маркера игрока, px.
const MARKER_SIZE: float = 12.0

var _island: Island = null
var _player: Player = null
var _frame: Control = null
var _marker: ColorRect = null
var _zone_layer: Control = null
var _shown: bool = false
var _was_pressed: bool = false


## Что показывать на карте (вызывает сцена мира после загрузки острова).
func track(island: Island, player: Player) -> void:
	_island = island
	_player = player
	if _zone_layer != null:
		_build_zone_labels()


func _ready() -> void:
	layer = 15
	_frame = Control.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.08, 0.12, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(dim)

	var map_holder := Control.new()
	map_holder.size = Vector2(DISPLAY_SIZE, DISPLAY_SIZE)
	map_holder.position = (Vector2(1280, 720) - Vector2(DISPLAY_SIZE, DISPLAY_SIZE)) * 0.5
	map_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(map_holder)

	var image := TextureRect.new()
	image.texture = TEXTURE
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.set_anchors_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_holder.add_child(image)

	_zone_layer = Control.new()
	_zone_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_zone_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_holder.add_child(_zone_layer)

	_marker = ColorRect.new()
	_marker.color = Color(0.98, 0.35, 0.35)
	_marker.size = Vector2(MARKER_SIZE, MARKER_SIZE)
	_marker.pivot_offset = Vector2(MARKER_SIZE, MARKER_SIZE) * 0.5
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_holder.add_child(_marker)

	_frame.visible = false
	if _island != null:
		_build_zone_labels()


func _process(_delta: float) -> void:
	var pressed: bool = Input.is_action_pressed("map")
	if pressed and not _was_pressed:
		_shown = not _shown
		_frame.visible = _shown
	_was_pressed = pressed
	if not _shown or _player == null:
		return
	_marker.position = _world_to_map(_player.global_position)
	# Взгляд на карте: модель смотрит (sin yaw, cos yaw) в мире — на карте
	# это (x, z); стрелка-квадрат по умолчанию «смотрит» вверх (−y).
	var yaw: float = _player.model_yaw()
	_marker.rotation = atan2(sin(yaw), -cos(yaw))


## Координата мира → точка на карте (px).
func _world_to_map(pos: Vector3) -> Vector2:
	return Vector2(
		(pos.x + HALF_WORLD) / (HALF_WORLD * 2.0),
		(pos.z + HALF_WORLD) / (HALF_WORLD * 2.0),
	) * DISPLAY_SIZE - _marker.pivot_offset


## Подписи зон из данных острова (локализация ZONE_<ИМЯ>).
func _build_zone_labels() -> void:
	for child: Node in _zone_layer.get_children():
		child.queue_free()
	if _island == null:
		return
	for zone: Dictionary in _island.zones:
		var label := Label.new()
		label.text = tr("ZONE_%s" % String(zone["name"]).to_upper())
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(0.13, 0.21, 0.34))
		label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.85))
		label.add_theme_constant_override("outline_size", 5)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var center: Vector2 = zone["center"]
		label.position = _world_to_map(Vector3(center.x, 0.0, center.y)) - _marker.pivot_offset
		label.size = Vector2(90, 20)
		label.position -= Vector2(45, 10)
		_zone_layer.add_child(label)
