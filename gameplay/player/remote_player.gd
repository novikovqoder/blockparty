# Чужой игрок на сцене (разделы 5, 10 SPEC): позиция и поворот —
# интерполяция буфера снапшотов (задержка 100 мс, экстраполяция до 150 мс,
# телепорт при расхождении больше 5 м), поворот модели — по кратчайшей дуге.
# Модель та же, что у локального игрока (визуал заменяем), ник — Label3D
# в радиусе 40 м (раздел 6). Коллайдер головы — как у своего: плоский бокс
# на макушке, слой LAYER_HEAD — на голову можно встать и подпрыгнуть выше
# (подсадка, раздел 5). Движение ремоута клиентом владельца, здесь только
# отображение. Эмоции/косметика — П5/П8.
class_name RemotePlayer
extends Node3D

const VISUAL: PackedScene = preload("res://gameplay/player/player_visual.tscn")
const B: Balance = preload("res://gameplay/balance.tres")

## Высота коллайдера головы над ступнями и метки ника, м (как player.tscn).
const HEAD_TOP_Y: float = 1.65
const NAME_LABEL_Y: float = 2.15

var peer_id: int = 0
var player_name: String = ""

var _model: Node3D
var _visual: PlayerVisual
var _buffer := SnapshotBuffer.new()
var _last_anim: int = -1


func setup(p_peer_id: int, p_name: String) -> void:
	peer_id = p_peer_id
	player_name = p_name


func _ready() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	_visual = VISUAL.instantiate() as PlayerVisual
	_model.add_child(_visual)
	# Палитра «Фонарщика» по peer id (раздел 16): без сети — хэш id у всех
	# одинаковый, у одного игрока всегда одна палитра.
	_visual.setup_palette(peer_id)

	# Ник над головой (раздел 6: в радиусе 40 м), к игроку лицом.
	var label := Label3D.new()
	label.name = "NameLabel"
	label.text = player_name
	label.position = Vector3(0.0, NAME_LABEL_Y, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.outline_size = 12
	label.visibility_range_end = 40.0
	add_child(label)

	# Голова — плоский бокс на макушке, слой голов (подсадка, раздел 5).
	var head := AnimatableBody3D.new()
	head.name = "HeadTop"
	head.collision_layer = 1 << (HeadStand.LAYER_HEAD - 1)
	head.collision_mask = 0
	head.position = Vector3(0.0, HEAD_TOP_Y, 0.0)
	head.set_meta("peer_id", peer_id)  # «с чьей головы прыгнул» — П5
	add_child(head)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.1, 0.6)
	shape.shape = box
	head.add_child(shape)


## Снапшот чужого игрока (переслал хост после AOI-фильтра).
func apply_snapshot(snap: Dictionary, recv_msec: int) -> void:
	_buffer.push(snap, recv_msec)


## Отрисовать интерполированное состояние на момент now_msec (обычно «сейчас
## минус задержка»). Отдельный метод — чтобы тесты звали его с точным временем.
func render(now_msec: int) -> void:
	if _buffer.is_empty():
		return
	var snap := _buffer.sample(now_msec - Protocol.INTERP_DELAY_MS)
	global_position = Vector3(float(snap["x"]), float(snap["y"]), float(snap["z"]))
	_model.rotation.y = float(snap["yaw"])
	var anim: int = int(snap["anim"])
	if anim != _last_anim:
		_last_anim = anim
		_visual.set_state(anim)


func _process(_delta: float) -> void:
	render(Time.get_ticks_msec())


## Последняя известная позиция (карта, проверки).
func last_position() -> Vector3:
	return global_position


## Визуал «Фонарщика»: сцене мира нужен set_glow_level (фонарик ярче,
## когда рядом другой игрок) — свечением решает мир, у всех одинаково.
func visual() -> PlayerVisual:
	return _visual
