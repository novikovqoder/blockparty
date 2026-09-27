# Лёгкая секция «стая птиц» (раздел 5): три птицы на разных высотах над
# одной пропастью — бить в прыжке или пробегать понизу.
class_name EasyBirdsChunk
extends Chunk


static func def() -> ChunkDef:
	var d := ChunkDef.new()
	d.id = "easy_birds"
	d.type = ChunkDef.Type.EASY
	d.difficulty = 1
	d.width = 1920
	d.checkpoint = Vector2(96, FLOOR_Y)
	d.hang_points = [896.0]
	d.mob_spawns = [
		{"kind": "bird", "x": 500.0, "y": 356.0, "params": {"span": 420.0, "period": 4.8, "dir": 1.0, "wave_amp": 26.0, "wave_period": 2.1}},
		{"kind": "bird", "x": 960.0, "y": 440.0, "params": {"span": 400.0, "period": 4.2, "dir": -1.0, "wave_amp": 30.0, "wave_period": 1.8}},
		{"kind": "bird", "x": 1400.0, "y": 340.0, "params": {"span": 520.0, "period": 5.4, "dir": 1.0, "wave_amp": 24.0, "wave_period": 2.3}},
	]
	var coins: Array[Vector2] = [
		Vector2(300, 520), Vector2(348, 520),
		Vector2(930, 484), Vector2(976, 452), Vector2(1022, 484),  # дуга над пропастью
		Vector2(1300, 480), Vector2(1500, 480),                    # под птицами
	]
	d.coin_spawns = coins
	return d


func build() -> void:
	add_floor(0.0, 896.0)
	add_floor(1024.0, 896.0)
	add_pit(896.0, 1024.0)
	_add_cactus(640.0)
	_add_cactus(1600.0)


func _add_cactus(x: float) -> void:
	var cactus := Cactus.new()
	cactus.position = Vector2(x, FLOOR_Y)
	add_child(cactus)
