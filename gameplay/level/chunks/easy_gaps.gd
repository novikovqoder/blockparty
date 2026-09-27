# Лёгкая секция «три пропасти» (раздел 5: обычная лёгкая — пропасти,
# кактусы, птицы). Три пропасти по 128 px — перепрыгиваются обычным прыжком.
class_name EasyGapsChunk
extends Chunk


static func def() -> ChunkDef:
	var d := ChunkDef.new()
	d.id = "easy_gaps"
	d.type = ChunkDef.Type.EASY
	d.difficulty = 1
	d.width = 1920
	d.checkpoint = Vector2(96, FLOOR_Y)
	d.hang_points = [384.0, 832.0, 1280.0]
	d.mob_spawns = [
		{"kind": "bird", "x": 700.0, "y": 420.0, "params": {"span": 400.0, "period": 4.5, "dir": -1.0, "wave_amp": 24.0, "wave_period": 2.0}},
		{"kind": "bird", "x": 1550.0, "y": 400.0, "params": {"span": 480.0, "period": 6.0, "dir": 1.0, "wave_amp": 28.0, "wave_period": 2.4}},
	]
	var coins: Array[Vector2] = [
		Vector2(250, 520),
		Vector2(420, 484), Vector2(464, 452), Vector2(508, 484),   # дуга над 1-й пропастью
		Vector2(870, 484), Vector2(914, 452), Vector2(958, 484),   # дуга над 2-й
		Vector2(1320, 484), Vector2(1364, 452), Vector2(1408, 484),  # над 3-й
		Vector2(1650, 520),
	]
	d.coin_spawns = coins
	return d


func build() -> void:
	add_floor(0.0, 384.0)
	add_floor(512.0, 320.0)
	add_floor(960.0, 320.0)
	add_floor(1408.0, 512.0)
	add_pit(384.0, 512.0)
	add_pit(832.0, 960.0)
	add_pit(1280.0, 1408.0)
	_add_cactus(200.0)
	_add_cactus(700.0)
	_add_cactus(1600.0)


func _add_cactus(x: float) -> void:
	var cactus := Cactus.new()
	cactus.position = Vector2(x, FLOOR_Y)
	add_child(cactus)
