# Бонусная секция (раздел 5): много монет, без опасностей — передышка.
# TODO (этап 3): золотая цель, убиваемая ударами двух разных игроков.
class_name BonusCoinsChunk
extends Chunk


static func def() -> ChunkDef:
	var d := ChunkDef.new()
	d.id = "bonus_coins"
	d.type = ChunkDef.Type.BONUS
	d.difficulty = 1
	d.width = 1920
	d.checkpoint = Vector2(96, FLOOR_Y)
	# Волна из 12 монет синусоидой — собирается на бегу.
	var coins: Array[Vector2] = []
	for i: int in 12:
		var x := 260.0 + 130.0 * i
		var y := 500.0 - 64.0 * sin(TAU * float(i) / 11.0)
		coins.append(Vector2(x, y))
	d.coin_spawns = coins
	return d


func build() -> void:
	add_floor(0.0, 1920.0)
	# Пара низких холмиков, чтобы волна монет читалась.
	add_block(760.0, 540.0, 160.0, 36.0, PAL.ground)
	add_block(1420.0, 540.0, 160.0, 36.0, PAL.ground)
