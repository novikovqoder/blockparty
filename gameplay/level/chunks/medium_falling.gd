# Средняя секция «падающие платформы» (разделы 5, 6): широкая пропасть,
# перебираться по трём падающим платформам (падают через 0.6 с после того,
# как на неё встал игрок, у всех одинаково — событие шлёт хост).
class_name MediumFallingChunk
extends Chunk


static func def() -> ChunkDef:
	var d := ChunkDef.new()
	d.id = "medium_falling"
	d.type = ChunkDef.Type.MEDIUM
	d.difficulty = 2
	d.width = 2560
	d.checkpoint = Vector2(96, FLOOR_Y)
	d.hang_points = [1024.0]
	d.platform_spawns = [
		{"cx": 1120.0, "top_y": 512.0, "width": 96.0},
		{"cx": 1264.0, "top_y": 496.0, "width": 96.0},
		{"cx": 1408.0, "top_y": 512.0, "width": 96.0},
	]
	d.mob_spawns = [
		{"kind": "bird", "x": 700.0, "y": 420.0, "params": {"span": 400.0, "period": 5.0, "dir": 1.0, "wave_amp": 26.0, "wave_period": 2.2}},
		{"kind": "critter", "x": 1900.0, "y": 504.0, "params": {"span": 400.0, "period": 4.4}},
	]
	var coins: Array[Vector2] = [
		Vector2(560, 470),
		Vector2(1120, 456), Vector2(1264, 440), Vector2(1408, 456),  # над платформами
		Vector2(1700, 464), Vector2(1900, 464), Vector2(2100, 464),  # со зверьком
	]
	d.coin_spawns = coins
	return d


func build() -> void:
	add_floor(0.0, 1024.0)
	add_floor(1472.0, 1088.0)
	add_pit(1024.0, 1472.0)
	_add_spikes(560.0)
	_add_spikes(2200.0)


func _add_spikes(x: float) -> void:
	var spikes := Spikes.new(64.0)
	spikes.position = Vector2(x, FLOOR_Y)
	add_child(spikes)
