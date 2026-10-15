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

const VISUAL: PackedScene = preload("res://gameplay/player/character_model.tscn")
const B: Balance = preload("res://gameplay/balance.tres")

## Высота коллайдера головы над ступнями и метки ника, м (как player.tscn).
const HEAD_TOP_Y: float = 1.65
const NAME_LABEL_Y: float = 2.15
## Группа узлов чужих игроков (HangPoint ищет висящих, П5).
const GROUP: StringName = &"remote_player"
## Сглаживание оценки скорости, 1/с (как LOCO_SMOOTH у модели).
const SPEED_SMOOTH: float = 10.0

var peer_id: int = 0
var player_name: String = ""
## Внешность байтами индексов редактора (П5.8, пришла с rpc_player_joined;
## хост уже проверил диапазоны, валидируем ещё раз на случай мусора).
var appearance: PackedByteArray = PackedByteArray()

var _model: Node3D
var _visual: CharacterModel
var _buffer := SnapshotBuffer.new()
var _last_anim: int = -1
## Флаги последнего снапшота (висит, сидит, за руку — раздел 10).
var _flags: int = 0
## Оценка скорости по дельтам интерполированной позиции (Д3: темп ног
## ремоута — по фактической скорости, как у локального игрока).
var _speed_est: float = 0.0
var _speed_pos: Vector3 = Vector3.ZERO
var _speed_msec: int = -1


func setup(p_peer_id: int, p_name: String, p_appearance: PackedByteArray = PackedByteArray()) -> void:
	peer_id = p_peer_id
	player_name = p_name
	appearance = p_appearance


func _ready() -> void:
	add_to_group(GROUP)
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	_visual = VISUAL.instantiate() as CharacterModel
	_model.add_child(_visual)
	# Внешность игрока — собранная им в редакторе (П5.8), пришла
	# с rpc_player_joined. Цвет верхней одежды — по хэшу id того же игрока.
	_visual.setup_appearance(Appearance.from_bytes(appearance).validated())
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
	# Пузырь эмоций над ником (раздел 9.7) и жест по событию хоста.
	var bubble := EmoteBubble.new()
	bubble.name = "EmoteBubble"
	bubble.position = Vector3(0.0, 2.6, 0.0)
	bubble.peer_id = peer_id
	add_child(bubble)
	EventBus.player_emoted.connect(_on_player_emoted)

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
	_flags = int(snap["flags"])
	_buffer.push(snap, recv_msec)


## Висит ли игрок у края расщелины сейчас (флаг снапшота, раздел 10).
func is_hanging() -> bool:
	return (_flags & Protocol.FLAG_HANGING) != 0


## Игрок показал эмоцию (раздел 9.7): жест; пузырь рисует EmoteBubble.
func _on_player_emoted(peer: int, emote: int, _marker: Vector3) -> void:
	if peer == peer_id:
		_visual.play_one_shot(Protocol.EMOTE_ANIMS[emote], B.emote_bubble_time)


## Поворот модели из последнего снапшота (следование «за руку», раздел 9.5).
func model_yaw() -> float:
	return _model.rotation.y


## Состояние аниматора из последнего снапшота (повтор прыжков ведущего):
## только отрыв прыжка — падение с уступа ведомый повторяет «сходом» с края.
func is_jumping() -> bool:
	return _last_anim == Protocol.AnimState.JUMP


## Отрисовать интерполированное состояние на момент now_msec (обычно «сейчас
## минус задержка»). Отдельный метод — чтобы тесты звали его с точным временем.
func render(now_msec: int) -> void:
	if _buffer.is_empty():
		return
	var snap := _buffer.sample(now_msec - Protocol.INTERP_DELAY_MS)
	var pos := Vector3(float(snap["x"]), float(snap["y"]), float(snap["z"]))
	# Скорость по дельтам позиции (Д3): телепорт буфера (>5 м за кадр,
	# remote_player.gd шапка) в оценку не попадает.
	if _speed_msec >= 0 and now_msec > _speed_msec:
		var dt := (now_msec - _speed_msec) / 1000.0
		if pos.distance_to(_speed_pos) < 5.0:
			_speed_est = lerpf(_speed_est,
				(Vector2(pos.x - _speed_pos.x, pos.z - _speed_pos.z)).length() / dt,
				minf(dt * SPEED_SMOOTH, 1.0))
		else:
			_speed_est = 0.0
	_speed_pos = pos
	_speed_msec = now_msec
	global_position = pos
	_model.rotation.y = float(snap["yaw"])
	var anim: int = int(snap["anim"])
	if anim != _last_anim:
		_last_anim = anim
		_visual.set_state(anim)
	_visual.set_locomotion_speed(_speed_est)


## Оцененная горизонтальная скорость, м/с (для темпа «за руку» у пары).
func speed_estimate() -> float:
	return _speed_est


func _process(_delta: float) -> void:
	render(Time.get_ticks_msec())


## Последняя известная позиция (карта, проверки).
func last_position() -> Vector3:
	return global_position
