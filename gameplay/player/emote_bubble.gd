# Пузырь эмоции над головой (раздел 9.7 SPEC): фраза из колеса Q живёт
# emote_bubble_time и видна в emote_bubble_range. Компонент вешают на себя
# Player и RemotePlayer — оба слушают player_emoted и сравнивают peer_id,
# поэтому пузырь рисуется одинаково у всех клиентов. Вешается над ником.
class_name EmoteBubble
extends Node3D

const B: Balance = preload("res://gameplay/balance.tres")

## Чей это пузырь (peer_id хозяина узла).
var peer_id: int = 0

var _label: Label3D
var _left: float = 0.0


func _ready() -> void:
	_label = Label3D.new()
	_label.name = "EmoteBubble"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 44
	_label.outline_size = 10
	_label.modulate = Color(1.0, 0.96, 0.86)
	_label.visibility_range_end = B.emote_bubble_range
	_label.hide()
	add_child(_label)
	EventBus.player_emoted.connect(_on_player_emoted)


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	if _left <= 0.0:
		_label.hide()


## Хозяин узла показал эмоцию: фраза в пузыре (маркер рисует мир, не игрок).
func _on_player_emoted(peer: int, emote: int, _marker: Vector3) -> void:
	if peer != peer_id:
		return
	_label.text = tr(Protocol.EMOTE_KEYS[emote])
	_label.show()
	_left = B.emote_bubble_time
