# Кооперативная секция «уступ-ступенька» (разделы 5, 7.3): верхний ярус
# на высоте 160 px — обычным прыжком (около 96 px) не забраться.
# Этап 1 (одиночный забег): верёвочная лестница уже опущена — проход есть.
# TODO (этап 3): плиты и кооп-ворота, лестница опускается событием хоста,
# запасная платформа через 45 с у уступа.
class_name CoopLedgeChunk
extends Chunk


static func def() -> ChunkDef:
	var d := ChunkDef.new()
	d.id = "coop_ledge"
	d.type = ChunkDef.Type.COOP
	d.difficulty = 2
	d.width = 2560
	d.min_players_for_coop = 2
	d.checkpoint = Vector2(96, FLOOR_Y)
	var coins: Array[Vector2] = [
		Vector2(700, 520), Vector2(752, 520),                  # на подходе
		Vector2(1700, 368), Vector2(1900, 368),                # верхний ярус
		Vector2(2100, 368), Vector2(2300, 368),
	]
	d.coin_spawns = coins
	d.mob_spawns = [
		{"kind": "bird", "x": 2050.0, "y": 320.0, "params": {"span": 480.0, "period": 5.5, "dir": -1.0, "wave_amp": 30.0, "wave_period": 2.6}},
	]
	return d


func build() -> void:
	add_floor(0.0, 2560.0)
	# Уступ высотой 160 px от x = 1500 до конца секции.
	add_block(2030.0, 416.0, 1060.0, 160.0, PAL.ground)
	# «Верёвочная лестница» этапа 1: ступени со шагом 64 px (прыжок — 96 px).
	add_block(1290.0, 512.0, 80.0, 24.0, PAL.ladder)
	add_block(1395.0, 448.0, 80.0, 24.0, PAL.ladder)
	# Столбик-декор на верхнем ярусе.
	add_deco(2400.0, 416.0 - 70.0, Vector2(32, 140), PAL.platform)
