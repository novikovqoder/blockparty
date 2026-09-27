# Лёгкая секция «холмы» (раздел 5): невысокие блоки-ступеньки 64 px с
# кактусами, одна пропасть 160 px. Птица над холмами.
class_name EasyHillsChunk
extends Chunk


static func def() -> ChunkDef:
	var d := ChunkDef.new()
	d.id = "easy_hills"
	d.type = ChunkDef.Type.EASY
	d.difficulty = 1
	d.width = 1920
	d.checkpoint = Vector2(96, FLOOR_Y)
	d.hang_points = [1600.0]
	d.mob_spawns = [
		{"kind": "bird", "x": 800.0, "y": 400.0, "params": {"span": 560.0, "period": 6.0, "dir": 1.0, "wave_amp": 30.0, "wave_period": 2.5}},
	]
	var coins: Array[Vector2] = [
		Vector2(360, 468), Vector2(560, 468),          # на первом холме
		Vector2(760, 404), Vector2(960, 404),          # на втором
		Vector2(1640, 484), Vector2(1688, 452), Vector2(1736, 484),  # дуга над пропастью
	]
	d.coin_spawns = coins
	return d


func build() -> void:
	add_floor(0.0, 1600.0)
	add_floor(1728.0, 192.0)
	add_pit(1600.0, 1728.0)
	# Холмы-ступеньки 64 px: заходятся прыжком без разбега.
	add_block(460.0, 512.0, 360.0, 64.0, PAL.ground)
	add_block(860.0, 448.0, 360.0, 128.0, PAL.ground)
	_add_cactus(200.0)
	_add_cactus(1160.0)


func _add_cactus(x: float) -> void:
	var cactus := Cactus.new()
	cactus.position = Vector2(x, FLOOR_Y)
	add_child(cactus)
