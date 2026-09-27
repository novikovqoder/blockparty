# Вторая бонусная секция (разделы 5, 7.4): золотая цель в кольце монет,
# без опасностей. Цель умирает только от ударов двух разных игроков
# в пределах golden_hit_window — награда 10 монет каждому.
class_name BonusGoldenChunk
extends Chunk


static func def() -> ChunkDef:
	var d := ChunkDef.new()
	d.id = "bonus_golden"
	d.type = ChunkDef.Type.BONUS
	d.difficulty = 1
	d.width = 1920
	d.checkpoint = Vector2(96, FLOOR_Y)
	d.mob_spawns = [
		{"kind": "golden", "x": 960.0, "y": 340.0, "params": {"span_x": 360.0, "span_y": 90.0, "period_x": 2.8, "period_y": 3.9, "phase": 1.3}},
	]
	# Кольцо из 10 монет вокруг траектории цели — собирается, пока её бьёшь.
	var coins: Array[Vector2] = []
	for i: int in 10:
		var angle := TAU * float(i) / 10.0
		coins.append(Vector2(960.0 + 420.0 * cos(angle), 400.0 + 120.0 * sin(angle) - 60.0))
	d.coin_spawns = coins
	return d


func build() -> void:
	add_floor(0.0, 1920.0)
	# Низкие холмики по краям кольца.
	add_block(560.0, 540.0, 160.0, 36.0, PAL.ground)
	add_block(1360.0, 540.0, 160.0, 36.0, PAL.ground)
