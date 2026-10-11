# Колесо эмоций (раздел 9.7 SPEC, раздел 15): Q (удерживать) открывает
# шесть фраз по кругу, выбор — клавиши 1–6 (они же «быстрые эмоции» без
# открытия колеса). Перезарядка 1 с — подписи приглушены. «Сюда!» берёт
# точку перед камерой (луч до 30 м) и передаёт её маркером. Весь текст —
# tr() и i18n/strings.csv (правило проекта).
class_name EmoteWheel
extends CanvasLayer

const B: Balance = preload("res://gameplay/balance.tres")

## Радиус колеса от центра экрана, px.
const WHEEL_RADIUS: float = 170.0

var _player: Player = null
var _labels: Array[Label] = []
var _open: bool = false
var _left: float = 0.0


func setup(player: Player) -> void:
	_player = player


func _ready() -> void:
	layer = 11
	var root := Control.new()
	root.name = "Wheel"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	for i: int in Protocol.EMOTE_KEYS.size():
		var angle := -PI / 2.0 + TAU * i / float(Protocol.EMOTE_KEYS.size())
		var label := Label.new()
		label.text = "%d\n%s" % [i + 1, tr(Protocol.EMOTE_KEYS[i])]
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		label.add_theme_constant_override("outline_size", 5)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiLayout.center_offset(
			label, Vector2(120.0, 48.0),
			Vector2(cos(angle), sin(angle)) * WHEEL_RADIUS,
		)
		root.add_child(label)
		_labels.append(label)
	_show(false)


func _process(delta: float) -> void:
	if _left > 0.0:
		_left -= delta
		if _left <= 0.0:
			_set_dim(false)
	# Q (удерживать) открывает колесо (раздел 15); отпускание закрывает.
	if Input.is_action_just_pressed("emote_wheel"):
		_open = true
		_show(true)
	elif _open and not Input.is_action_pressed("emote_wheel"):
		_open = false
		_show(false)
	for i: int in Protocol.EMOTE_KEYS.size():
		if Input.is_action_just_pressed("emote_%d" % (i + 1)):
			_send(i)


## Отправить эмоцию (раздел 9.7): перезарядка 1 с, «Сюда!» — с точкой
## маркера перед камерой. Клавиша работает и при открытом колесе.
func _send(emote: int) -> void:
	if _left > 0.0:
		return
	if _player == null:
		return
	_left = B.emote_cooldown
	_set_dim(true)
	var marker := Vector3.INF
	if emote == Protocol.Emote.HERE:
		marker = _camera_marker()
	Net.request_emote(emote, marker)
	_open = false
	_show(false)


## Точка перед камерой (раздел 9.7: «куда смотрит камера, луч до 30 м»):
## пересечение с миром или конец луча.
func _camera_marker() -> Vector3:
	var cam := _player.camera as Node3D
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var to := from + dir * B.emote_marker_range
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		return hit["position"] as Vector3
	return to


func _show(visible_now: bool) -> void:
	for label: Label in _labels:
		label.visible = visible_now


## Перезарядка: подписи приглушены, пока эмоция недоступна.
func _set_dim(dim: bool) -> void:
	for label: Label in _labels:
		label.modulate = Color(0.6, 0.6, 0.6, 0.8) if dim else Color.WHITE
