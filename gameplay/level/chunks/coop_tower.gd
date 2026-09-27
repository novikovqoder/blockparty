# Кооперативная секция «башня» (разделы 5, 7.3): высокий уступ 176 px —
# даже прыжок с головы (около 194 px) берётся в притирку. Наверху — монеты;
# когда кто-то оказался наверху, хост опускает лестницу. Одиночке через
# ledge_fallback_time у стены появляется платформа.
class_name CoopTowerChunk
extends Chunk


static func def() -> ChunkDef:
	var d := ChunkDef.new()
	d.id = "coop_tower"
	d.type = ChunkDef.Type.COOP
	d.difficulty = 3
	d.width = 2560
	d.min_players_for_coop = 2
	d.checkpoint = Vector2(96, FLOOR_Y)
	d.coop_spawns = [
		{
			"kind": "ledge",
			"ladder_x": 1660.0,
			"top_y": 400.0,
			"fallback_x": 1520.0,
			"fallback_top_y": 488.0,
			"zone_from": 1250.0,
			"zone_to": 1600.0,
			"top_from": 1600.0,
			"top_to": 2560.0,
		},
	]
	var coins: Array[Vector2] = [
		Vector2(600, 520), Vector2(648, 520),
		Vector2(1750, 352), Vector2(1950, 352),     # наверху башни
		Vector2(2150, 352), Vector2(2350, 352),
	]
	d.coin_spawns = coins
	d.mob_spawns = [
		{"kind": "bird", "x": 2100.0, "y": 300.0, "params": {"span": 500.0, "period": 5.2, "dir": -1.0, "wave_amp": 30.0, "wave_period": 2.6}},
	]
	return d


func build() -> void:
	add_floor(0.0, 2560.0)
	# Башня высотой 176 px от x = 1600 до конца секции.
	add_block(2080.0, 400.0, 960.0, 176.0, PAL.ground)
	add_deco(2450.0, 400.0 - 60.0, Vector2(28, 120), PAL.platform)
