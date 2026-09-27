# Финишная площадка (раздел 5, 7.6): фиксированная секция, безопасная зона
# без препятствий; финишировавшие ждут остальных (в одиночном забеге — финиш).
class_name FinishAreaChunk
extends Chunk


static func def() -> ChunkDef:
	var d := ChunkDef.new()
	d.id = "finish_area"
	d.type = ChunkDef.Type.FINISH
	d.width = 1152
	d.checkpoint = Vector2(96, FLOOR_Y)
	d.finish_x = 300.0
	return d


func build() -> void:
	add_floor(0.0, 1152.0)
	# Праздничные «флажки» — простые декоративные блоки.
	add_deco(620.0, FLOOR_Y - 150.0, Vector2(20, 300), PAL.finish)
	add_deco(1080.0, FLOOR_Y - 150.0, Vector2(20, 300), PAL.finish)
