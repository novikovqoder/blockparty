# Чужой игрок на сцене (разделы 5, 10 SPEC): позиция и поворот —
# интерполяция буфера снапшотов (задержка 100 мс, экстраполяция до 150 мс,
# телепорт при расхождении больше 5 м), поворот модели — по кратчайшей дуге.
# Модель та же, что у локального игрока (визуал заменяем), ник — Label3D
# в радиусе 40 м (раздел 6). Движение ремоута клиентом владельца, здесь
# только отображение. Косметика — П5/П8. Подсадка на голову и внешность
# из сети удалены с наследием Blockparty (born-unblessed).
class_name RemotePlayer
extends Node3D

## Высота метки ника над ступнями, м (рост героя BU — 1,8 м, П10).
const NAME_LABEL_Y: float = 2.35
## Группа узлов чужих игроков (жители ищут для реакции, П6).
const GROUP: StringName = &"remote_player"
## Сглаживание оценки скорости, 1/с (как LOCO_SMOOTH у модели).
const SPEED_SMOOTH: float = 10.0

var peer_id: int = 0
var player_name: String = ""

var _model: Node3D
var _visual: CharacterVisual
var _buffer := SnapshotBuffer.new()
var _last_anim: int = -1
## Флаги последнего снапшота (висит, сидит — раздел 10).
var _flags: int = 0
## Оценка скорости по дельтам интерполированной позиции (Д3: темп ног
## ремоута — по фактической скорости, как у локального игрока).
var _speed_est: float = 0.0
var _speed_pos: Vector3 = Vector3.ZERO
var _speed_msec: int = -1
## Частицы из-под ног (переделка П9): как у локального, порции по шагам.
var _foot_fx: FootFx = null
## Флаг «на полу» прошлого снапшота (порция при приземлении чужого).
var _was_on_floor: bool = true


func setup(p_peer_id: int, p_name: String) -> void:
	peer_id = p_peer_id
	player_name = p_name


func _ready() -> void:
	add_to_group(GROUP)
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	# Модель чужого игрока — тот же герой Born Unblessed (П10): модель одна
	# на всех; колёсико меча не слушает (меч — локальная механика П10).
	_visual = HeroModelBU.new()
	_visual.name = "Visual"
	_model.add_child(_visual)

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
	# Частицы из-под ног (переделка П9): ребёнок самого узла (origin
	# в ногах); порции по шагам включит setup_foot_fx (сцена мира передаст
	# арт острова), дальше порога дальности — эффект выключен.
	_foot_fx = FootFx.new()
	_foot_fx.name = "FootFx"
	add_child(_foot_fx)


## Снапшот чужого игрока (переслал хост после AOI-фильтра).
func apply_snapshot(snap: Dictionary, recv_msec: int) -> void:
	_flags = int(snap["flags"])
	_buffer.push(snap, recv_msec)


## Висит ли игрок у края расщелины сейчас (флаг снапшота, раздел 10).
func is_hanging() -> bool:
	return (_flags & Protocol.FLAG_HANGING) != 0


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
	var jumped_now: bool = anim == Protocol.AnimState.JUMP \
		and _last_anim != Protocol.AnimState.JUMP
	if anim != _last_anim:
		_last_anim = anim
		_visual.set_state(anim)
	_visual.set_locomotion_speed(_speed_est)
	# Частицы из-под ног (переделка П9): по оцененной скорости и флагу
	# «на полу»; смотрящий — локальный игрок (дальше footfx_remote_range
	# эффект чужого выключен). Приземление — переход флага «на полу»,
	# отрыв прыжка — состояние JUMP.
	if _foot_fx != null:
		var on_floor: bool = (_flags & Protocol.FLAG_ON_FLOOR) != 0
		if not _was_on_floor and on_floor:
			_foot_fx.land(_speed_est)
		if jumped_now:
			_foot_fx.jump(_speed_est)
		_foot_fx.update(_speed_est, on_floor, _viewer_pos())
		_was_on_floor = on_floor


## Подключить частицы шагов к острову (сцена мира передаёт запечённый
## арт — по нему берётся покрытие и цвет поверхности под стопой).
func setup_foot_fx(art: IslandArt) -> void:
	_foot_fx.setup(art)


## Позиция смотрящего: локальный игрок (для отсечки дальних чужих).
func _viewer_pos() -> Vector3:
	var local := get_tree().get_first_node_in_group(Player.GROUP) as Node3D
	return local.global_position if local != null else global_position


func _process(_delta: float) -> void:
	render(Time.get_ticks_msec())


## Последняя известная позиция (карта, проверки).
func last_position() -> Vector3:
	return global_position
