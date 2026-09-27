# Стартовая площадка (раздел 5): фиксированная секция, все появляются здесь,
# дальше — отсчёт и забег. Без опасностей и спавнов.
class_name StartAreaChunk
extends Chunk


static func def() -> ChunkDef:
	var d := ChunkDef.new()
	d.id = "start_area"
	d.type = ChunkDef.Type.START
	d.width = 1152
	d.checkpoint = Vector2(192, FLOOR_Y)
	return d


func build() -> void:
	add_floor(0.0, 1152.0)
	# Декоративная арка входа.
	add_deco(80.0, FLOOR_Y - 90.0, Vector2(24, 180), PAL.platform)
	add_deco(320.0, FLOOR_Y - 90.0, Vector2(24, 180), PAL.platform)
	add_deco(200.0, FLOOR_Y - 176.0, Vector2(264, 24), PAL.checkpoint)
