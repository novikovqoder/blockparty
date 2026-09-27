# Кооперативная секция «ворота» (разделы 5, 7.2): проход преграждают
# ворота, перед ними три нажимные плиты. Ворота открываются, когда на плитах
# стоит need разных игроков (need = min(min_players, игроков, 3)); если
# игрок один — достаточно одной плиты, а запасной таймер 45 с откроет ворота,
# даже если на плиту не встать.
class_name CoopGateChunk
extends Chunk


static func def() -> ChunkDef:
	var d := ChunkDef.new()
	d.id = "coop_gate"
	d.type = ChunkDef.Type.COOP
	d.difficulty = 2
	d.width = 2560
	d.min_players_for_coop = 2
	d.checkpoint = Vector2(96, FLOOR_Y)
	d.coop_spawns = [
		{
			"kind": "gate",
			"plates": [800.0, 1000.0, 1200.0],
			"gate_x": 1500.0,
			"min_players": 2,
			"zone_from": 1300.0,
			"zone_to": 1700.0,
		},
	]
	var coins: Array[Vector2] = [
		Vector2(500, 520), Vector2(548, 520),          # на подходе к плитам
		Vector2(1700, 520), Vector2(1900, 520), Vector2(2100, 520),
		Vector2(2300, 520),                            # за воротами
	]
	d.coin_spawns = coins
	d.mob_spawns = [
		{"kind": "bird", "x": 2000.0, "y": 400.0, "params": {"span": 420.0, "period": 5.0, "dir": -1.0, "wave_amp": 26.0, "wave_period": 2.2}},
	]
	return d


func build() -> void:
	add_floor(0.0, 2560.0)
	# Плиты строит LevelBuilder по плану (как и ворота) — чтобы id совпадали
	# у всех участников; здесь только декор-подсказки у плит.
	add_deco(800.0, FLOOR_Y - 88.0, Vector2(4, 96), PAL.plate)
	add_deco(1000.0, FLOOR_Y - 88.0, Vector2(4, 96), PAL.plate)
	add_deco(1200.0, FLOOR_Y - 88.0, Vector2(4, 96), PAL.plate)
