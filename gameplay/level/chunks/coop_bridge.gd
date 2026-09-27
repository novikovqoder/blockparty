# Кооперативная секция «мост» (разделы 5, 7.2): пропасть, за ней ворота
# на 3 плит (need = min(3, игроков, 3)). Полной компании надо разойтись по
# всем трём плитам; двоим и одиночке хватает меньшего числа.
class_name CoopBridgeChunk
extends Chunk


static func def() -> ChunkDef:
	var d := ChunkDef.new()
	d.id = "coop_bridge"
	d.type = ChunkDef.Type.COOP
	d.difficulty = 2
	d.width = 2560
	d.min_players_for_coop = 3
	d.checkpoint = Vector2(96, FLOOR_Y)
	d.hang_points = [1152.0]
	d.coop_spawns = [
		{
			"kind": "gate",
			"plates": [1500.0, 1700.0, 1900.0],
			"gate_x": 2200.0,
			"min_players": 3,
			"zone_from": 2000.0,
			"zone_to": 2400.0,
		},
	]
	var coins: Array[Vector2] = [
		Vector2(500, 520),
		Vector2(1180, 484), Vector2(1228, 452), Vector2(1276, 484),  # дуга над пропастью
		Vector2(2350, 520),
	]
	d.coin_spawns = coins
	return d


func build() -> void:
	add_floor(0.0, 1152.0)
	add_floor(1280.0, 1280.0)
	add_pit(1152.0, 1280.0)
	add_deco(1500.0, FLOOR_Y - 88.0, Vector2(4, 96), PAL.plate)
	add_deco(1700.0, FLOOR_Y - 88.0, Vector2(4, 96), PAL.plate)
	add_deco(1900.0, FLOOR_Y - 88.0, Vector2(4, 96), PAL.plate)
