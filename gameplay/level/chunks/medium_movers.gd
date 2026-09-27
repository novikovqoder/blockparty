# Средняя секция «переправы» (разделы 5, 6): две пропасти шире прыжка —
# только на движущихся платформах (детерминированы от run_time); зверьки
# на промежуточных островах.
class_name MediumMoversChunk
extends Chunk


static func def() -> ChunkDef:
	var d := ChunkDef.new()
	d.id = "medium_movers"
	d.type = ChunkDef.Type.MEDIUM
	d.difficulty = 2
	d.width = 2560
	d.checkpoint = Vector2(96, FLOOR_Y)
	d.hang_points = [704.0, 1536.0]
	d.mob_spawns = [
		{"kind": "critter", "x": 1250.0, "y": 504.0, "params": {"span": 500.0, "period": 5.0}},
		{"kind": "bird", "x": 2200.0, "y": 420.0, "params": {"span": 440.0, "period": 5.2, "dir": -1.0, "wave_amp": 28.0, "wave_period": 2.4}},
	]
	var coins: Array[Vector2] = [
		Vector2(400, 470),
		Vector2(830, 440), Vector2(900, 440),          # над первой платформой
		Vector2(1100, 520), Vector2(1300, 520),        # на среднем острове
		Vector2(1660, 440), Vector2(1730, 440),        # над второй платформой
		Vector2(2100, 520), Vector2(2400, 520),
	]
	d.coin_spawns = coins
	return d


func build() -> void:
	add_floor(0.0, 704.0)
	add_floor(960.0, 576.0)
	add_floor(1792.0, 768.0)
	add_pit(704.0, 960.0)
	add_pit(1536.0, 1792.0)
	_add_spikes(1150.0)
	# Обе платформы горизонтальные, в противофазе: пока одна у левого края,
	# другая у правого.
	var first := MovingPlatform.new()
	first.position = Vector2(832.0, 540.0)
	first.setup(Vector2(128, 24), {"axis": Vector2.RIGHT, "amp": 64.0, "period": 4.2, "phase": 0.0})
	add_child(first)
	var second := MovingPlatform.new()
	second.position = Vector2(1664.0, 540.0)
	second.setup(Vector2(128, 24), {"axis": Vector2.RIGHT, "amp": 64.0, "period": 4.2, "phase": PI})
	add_child(second)


func _add_spikes(x: float) -> void:
	var spikes := Spikes.new(64.0)
	spikes.position = Vector2(x, FLOOR_Y)
	add_child(spikes)
