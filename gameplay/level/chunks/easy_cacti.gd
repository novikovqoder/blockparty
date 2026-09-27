# Лёгкая секция «пропасти и кактусы» (раздел 5: обычная лёгкая — пропасти,
# кактусы, птицы). Две пропасти по 128 px — перепрыгиваются обычным прыжком.
class_name EasyCactiChunk
extends Chunk


static func def() -> ChunkDef:
	var d := ChunkDef.new()
	d.id = "easy_cacti"
	d.type = ChunkDef.Type.EASY
	d.difficulty = 1
	d.width = 1920
	d.checkpoint = Vector2(96, FLOOR_Y)
	d.hang_points = [640.0, 1280.0]
	d.mob_spawns = [
		{"kind": "bird", "x": 900.0, "y": 420.0, "params": {"span": 480.0, "period": 5.0, "dir": 1.0, "wave_amp": 26.0, "wave_period": 2.2}},
		{"kind": "bird", "x": 1560.0, "y": 380.0, "params": {"span": 560.0, "period": 6.5, "dir": -1.0, "wave_amp": 32.0, "wave_period": 2.8}},
	]
	# Монеты дугами над пропастями и на подходе.
	var coins: Array[Vector2] = [
		Vector2(300, 520), Vector2(348, 520),
		Vector2(660, 484), Vector2(704, 452), Vector2(748, 484),
		Vector2(1300, 484), Vector2(1344, 452), Vector2(1388, 484),
	]
	d.coin_spawns = coins
	return d


func build() -> void:
	# Пол тремя сегментами, между ними — пропасти 128 px.
	add_floor(0.0, 640.0)
	add_floor(768.0, 512.0)
	add_floor(1408.0, 512.0)
	add_pit(640.0, 768.0)
	add_pit(1280.0, 1408.0)
	# Кактусы на половых сегментах (перепрыгиваются).
	_add_cactus(420.0)
	_add_cactus(1000.0)
	_add_cactus(1680.0)


func _add_cactus(x: float) -> void:
	var cactus := Cactus.new()
	cactus.position = Vector2(x, FLOOR_Y)
	add_child(cactus)
