# Чужой игрок на сцене (разделы 4, 7, 8 SPEC): позиция — интерполяция буфера
# снапшотов (задержка 100 мс, экстраполяция до 150 мс, телепорт дальше 256 px),
# ник над головой, отдельный кинематический коллайдер головы — односторонняя
# платформа, на неё можно встать и подпрыгнуть выше («ступенька», раздел 4);
# здесь же пузырь эмоций и подъём при вытягивании (раздел 7).
# Не делает: иконку микрофона (этап 5), косметику (этап 7).
class_name RemotePlayer
extends Node2D

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")
const VISUAL: PackedScene = preload("res://gameplay/player/player_visual.tscn")

var peer_id: int = 0
var player_name: String = ""

var _visual: PlayerVisual
var _name_label: Label
var _head: AnimatableBody2D
var _bubble: EmoteBubble
var _buffer := SnapshotBuffer.new()
var _last_anim: int = -1
var _last_facing: int = 0
var _remote_hanging: bool = false


func setup(p_peer_id: int, p_name: String) -> void:
	peer_id = p_peer_id
	player_name = p_name


func _ready() -> void:
	_visual = VISUAL.instantiate() as PlayerVisual
	add_child(_visual)
	_visual.tint(_peer_color(peer_id))

	_name_label = Label.new()
	_name_label.text = player_name
	_name_label.position = Vector2(-60, -52)
	_name_label.size = Vector2(120, 20)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", PAL.hud_text)
	_name_label.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.15))
	_name_label.add_theme_constant_override("outline_size", 4)
	add_child(_name_label)

	# Голова — односторонняя платформа (раздел 4: коллизия игроков между собой).
	_head = AnimatableBody2D.new()
	_head.sync_to_physics = true
	_head.collision_layer = 1
	_head.collision_mask = 0
	_head.position = Vector2(0, -B.hitbox_height * 0.5 - 4)
	# Метка для «ступеньки»: локальный игрок узнаёт, с чьей головы прыгнул.
	_head.set_meta("peer_id", peer_id)
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(B.hitbox_width, 8)
	shape.shape = box
	shape.one_way_collision = true
	shape.one_way_collision_margin = 4.0
	_head.add_child(shape)
	add_child(_head)


## Принять снапшот от хоста (Net._deliver_snapshot).
func apply_snapshot(snap: Dictionary, recv_msec: int) -> void:
	_buffer.push(snap, recv_msec)


## Телепорт без сглаживания (respawn, расхождение больше 256 px).
func teleport(position: Vector2) -> void:
	_buffer.clear()
	global_position = position
	_last_anim = -1


## Последняя известная позиция — для проверок хоста (раздел 6).
func last_position() -> Vector2:
	return global_position


## Состояние «Висит» приходит надёжным RPC (у снапшота флаг может потеряться).
func set_remote_hanging(hanging: bool) -> void:
	_remote_hanging = hanging


## Хост подтвердил вытягивание (раздел 7.1): снимаем вис и даём подскок —
## точную позицию принесёт ближайший снапшот самого игрока.
func rescued() -> void:
	_remote_hanging = false
	global_position += Vector2(0.0, -60.0)
	_visual.play_jump()


## Пузырь эмоции над головой (раздел 7.5).
func show_emote(emote_id: int) -> void:
	if _bubble == null:
		_bubble = EmoteBubble.new()
		add_child(_bubble)
	_bubble.position = Vector2(0.0, -B.hitbox_height * 0.5 - 22.0)
	_bubble.show_emote(emote_id)


func _physics_process(_delta: float) -> void:
	if _buffer.is_empty():
		return
	var render: Dictionary = _buffer.sample(Time.get_ticks_msec() - Protocol.INTERP_DELAY_MS)
	global_position = Vector2(render["x"], render["y"])
	_apply_visual(render)


func _apply_visual(render: Dictionary) -> void:
	var flags: int = int(render["flags"])
	var facing: int = 1 if (flags & Protocol.FLAG_FACING_RIGHT) != 0 else -1
	if facing != _last_facing:
		_last_facing = facing
		_visual.set_facing(facing)
	_visual.set_run_blend(clampf(float(render["vx"]) / B.run_speed, -1.0, 1.0))

	var anim: int = int(render["anim"])
	if _remote_hanging:
		anim = Protocol.AnimState.HANG
	if anim != _last_anim:
		_last_anim = anim
		match anim:
			Protocol.AnimState.HANG:
				_visual.play_hang()
			Protocol.AnimState.ATTACK:
				_visual.set_attack_side(facing)
				_visual.play_attack()
			Protocol.AnimState.JUMP, Protocol.AnimState.FALL:
				_visual.play_jump()
			Protocol.AnimState.RUN, Protocol.AnimState.IDLE:
				_visual.play_idle()


## Свой оттенок игрока: различать персонажей в толпе (плейсхолдер до косметики).
static func _peer_color(peer_id: int) -> Color:
	return Color.from_hsv(fmod(float(peer_id % 9) * 0.11 + 0.05, 1.0), 0.45, 0.92)
