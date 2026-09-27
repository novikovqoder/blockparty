# Средняя секция «грот» (раздел 5): шипы на полу, вертикальная движущаяся
# платформа поднимает на верхний ярус с монетами, зверёк внизу, в конце
# пропасть 128 px.
class_name MediumCavernChunk
extends Chunk


static func def() -> ChunkDef:
	var d := ChunkDef.new()
	d.id = "medium_cavern"
	d.type = ChunkDef.Type.MEDIUM
	d.difficulty = 2
	d.width = 2560
	d.checkpoint = Vector2(96, FLOOR_Y)
	d.hang_points = [2176.0]
	d.mob_spawns = [
		{"kind": "bird", "x": 600.0, "y": 380.0, "params": {"span": 360.0, "period": 4.6, "dir": 1.0, "wave_amp": 22.0, "wave_period": 2.0}},
		{"kind": "critter", "x": 1900.0, "y": 504.0, "params": {"span": 440.0, "period": 4.0}},
	]
	var coins: Array[Vector2] = [
		Vector2(560, 470),
		Vector2(1080, 352), Vector2(1300, 352), Vector2(1520, 352),  # верхний ярус
		Vector2(1700, 464), Vector2(1900, 464),
		Vector2(2210, 484), Vector2(2258, 452), Vector2(2306, 484),  # дуга над пропастью
	]
	d.coin_spawns = coins
	return d


func build() -> void:
	add_floor(0.0, 2176.0)
	add_floor(2304.0, 256.0)
	add_pit(2176.0, 2304.0)
	# Шипы на полу (перепрыгиваются с запасом).
	_add_spikes(560.0)
	_add_spikes(1000.0)
	_add_spikes(1450.0)
	# Верхний ярус со «сталактитами»-декором; вход на него — платформой.
	add_block(1300.0, 384.0, 760.0, 24.0)
	add_deco(1300.0, 300.0, Vector2(24, 60), PAL.platform)
	add_deco(1500.0, 290.0, Vector2(24, 80), PAL.platform)
	# Вертикальная движущаяся платформа: возит с пола (576) на ярус (384).
	# Стоит левее яруса, чтобы не задевать его коллизией.
	var lift := MovingPlatform.new()
	lift.position = Vector2(850.0, 480.0)
	lift.setup(Vector2(128, 24), {"axis": Vector2.UP, "amp": 96.0, "period": 5.0, "phase": 0.0})
	add_child(lift)


func _add_spikes(x: float) -> void:
	var spikes := Spikes.new(64.0)
	spikes.position = Vector2(x, FLOOR_Y)
	add_child(spikes)
