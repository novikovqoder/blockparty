# Средняя секция «шипы и платформы» (раздел 5: обычная средняя — шипы,
# движущиеся платформы, наземные зверьки). Пропасть 192 px шире дальности
# прыжка — перелетать только на движущейся платформе (раздел 6).
class_name MediumSpikesChunk
extends Chunk


static func def() -> ChunkDef:
	var d := ChunkDef.new()
	d.id = "medium_spikes"
	d.type = ChunkDef.Type.MEDIUM
	d.difficulty = 2
	d.width = 2560
	d.checkpoint = Vector2(96, FLOOR_Y)
	d.hang_points = [1600.0]
	d.mob_spawns = [
		# Птица над первым отрезком.
		{"kind": "bird", "x": 600.0, "y": 400.0, "params": {"span": 320.0, "period": 5.0, "dir": 1.0, "wave_amp": 24.0, "wave_period": 2.0}},
		# Зверёк бегает по подвешенной платформе 900..1300.
		{"kind": "critter", "x": 1100.0, "y": 504.0, "params": {"span": 360.0, "period": 4.0}},
	]
	var coins: Array[Vector2] = [
		Vector2(560, 470), Vector2(1240, 470),          # над шипами
		Vector2(950, 464), Vector2(1100, 464), Vector2(1250, 464),  # на платформе зверька
		Vector2(1600, 440), Vector2(1696, 396), Vector2(1792, 440), # дуга над пропастью
		Vector2(1900, 520), Vector2(1980, 520),
	]
	d.coin_spawns = coins
	return d


func build() -> void:
	add_floor(0.0, 1600.0)
	add_floor(1792.0, 768.0)
	add_pit(1600.0, 1792.0)
	# Шипы на полу: перепрыгиваются с запасом.
	_add_spikes(560.0)
	_add_spikes(1240.0)
	# Подвешенная платформа со зверьком (64 px над полом).
	add_block(1100.0, 512.0, 400.0, 24.0)
	# Движущаяся платформа возит через пропасть 1600..1792: амплитуда —
	# половина зазора между берегами, в крайних фазах платформа прижата
	# к берегам (не заезжает на них). Верх на 48 px выше пола: прыжок с
	# разбега запрыгивает на неё без точного тайминга.
	var platform := MovingPlatform.new()
	platform.position = Vector2(1696.0, 540.0)
	platform.setup(Vector2(128, 24), {"axis": Vector2.RIGHT, "amp": 32.0, "period": 4.6, "phase": 0.0})
	add_child(platform)


func _add_spikes(x: float) -> void:
	var spikes := Spikes.new(64.0)
	spikes.position = Vector2(x, FLOOR_Y)
	add_child(spikes)
