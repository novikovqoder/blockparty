# Запасная платформа уступа (раздел 7.3 SPEC): появляется через
# ledge_fallback_time после того, как игрок встал у закрытого уступа, —
# запасной путь для одиночки. Видна и осязаема только после события хоста.
class_name FallbackPlatform
extends StaticBody2D

const PAL: Palette = preload("res://assets/palette.tres")

## id кооп-объекта уступа.
var ledge_id: int = -1


func setup(p_id: int, width: float) -> void:
	ledge_id = p_id
	collision_layer = 0  # включится при появлении
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(width, 20.0)
	shape.shape = box
	add_child(shape)
	add_child(Prim.outlined_rect(Vector2(width, 20.0), PAL.platform, PAL.outline))
	visible = false


func _ready() -> void:
	EventBus.coop_object_opened.connect(_on_coop_opened)


func _on_coop_opened(opened_id: int, fallback: bool, _participants: Array[int]) -> void:
	if opened_id != ledge_id or not fallback or visible:
		return
	visible = true
	set_deferred("collision_layer", 1)
	modulate = Color.TRANSPARENT
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.4)
