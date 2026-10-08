# Одноразовая генерация острова (раздел 6 SPEC): godot --headless --script
# tools/generate_island.gd --path . — собирает из детерминированных данных
# IslandGen два артефакта, которые коммитятся:
#   gameplay/world/island_art.res — запечённый визуал (IslandArt): карта
#     высот, меши чанков рельефа, MultiMesh предметов, боксы коллизий;
#   gameplay/world/island.tscn    — остров целиком: IslandView (визуал из
#     island_art.res), вода (море и озеро), расщелина с HangPoint, камни
#     духа, костёр, 60 статичных монет, мобы, ограждения края;
#   assets/island_map.png         — вид сверху для карты (M).
# По сети мир не передаётся: сцена одинакова у всех. Повторный запуск даёт
# тот же результат (тест — на хеш высот и предметов IslandGen.island_hash).
# Скрипты нод (мобы, монеты, вода) подключаются load()-ом во время работы,
# а не на этапе разбора: они ссылаются на автолоады (Session, EventBus),
# которые в режиме «--script» регистрируются позже загрузки этого файла.
extends SceneTree

const ART_PATH: String = "res://gameplay/world/island_art.res"
const SCENE_PATH: String = "res://gameplay/world/island.tscn"
const MAP_PATH: String = "res://assets/island_map.png"

const WATER_SCRIPT: String = "res://gameplay/world/water_area.gd"
const HANG_SCRIPT: String = "res://gameplay/activities/hang_area.gd"
const HANG_POINT_SCRIPT: String = "res://gameplay/activities/hang_point.gd"
const GATE_SCRIPT: String = "res://gameplay/activities/ruin_gate.gd"
const PLATE_SCRIPT: String = "res://gameplay/activities/ruin_plate.gd"
const CHEST_SCRIPT: String = "res://gameplay/activities/ruin_chest.gd"
const LADDER_SCRIPT: String = "res://gameplay/activities/lookout_ladder.gd"
const BEACON_SCRIPT: String = "res://gameplay/activities/beacon.gd"
const BOARD_SCRIPT: String = "res://gameplay/activities/beacon_board.gd"
const STONE_SCRIPT: String = "res://gameplay/world/respawn_stone.gd"
const CAMPFIRE_SCRIPT: String = "res://gameplay/world/campfire.gd"
const STARFALL_SCRIPT: String = "res://gameplay/world/starfall.gd"
const COIN_SCRIPT: String = "res://gameplay/world/coin_pickup.gd"
const BIRD_SCRIPT: String = "res://gameplay/mobs/bird.gd"
const CRITTER_SCRIPT: String = "res://gameplay/mobs/critter.gd"
const FIREFLY_SCRIPT: String = "res://gameplay/mobs/golden_firefly.gd"

const PAL: Palette = preload("res://assets/palette.tres")


func _init() -> void:
	# Первый кадр: автолоады (Session, EventBus) уже в дереве — скрипты мобов
	# и монет компилируются при load() с готовыми глобальными именами.
	await create_timer(0.01).timeout
	_generate()
	quit()


func _generate() -> void:
	var started := Time.get_ticks_msec()
	var data: Dictionary = IslandGen.generate()
	var hash_value: int = IslandGen.island_hash(data)

	# Визуал запекаем до сцены: IslandView ссылается на файл на диске
	# (ext_resource), а не на объект в памяти (иначе он запечётся внутрь tscn).
	var art := IslandArt.build(data)
	var art_error: int = ResourceSaver.save(art, ART_PATH)
	if art_error != OK:
		push_error("Не удалось сохранить %s (код %d)" % [ART_PATH, art_error])
		return

	var root := _build_scene(data, load(ART_PATH) as IslandArt)
	var packed := PackedScene.new()
	var pack_error: int = packed.pack(root)
	root.free()  # не тащить узлы к выходу процесса (чистый лог)
	if pack_error != OK:
		push_error("Не удалось упаковать сцену острова (код %d)" % pack_error)
		return
	var scene_error: int = ResourceSaver.save(packed, SCENE_PATH)
	if scene_error != OK:
		push_error("Не удалось сохранить %s (код %d)" % [SCENE_PATH, scene_error])
		return

	_render_map(data)
	print("Остров: предметов %d, монет %d, мобов %d, хеш %d, %.1f с" % [
		(data["props"] as Array).size(),
		(data["coins"] as Array).size(),
		(data["mobs"] as Array).size(),
		hash_value,
		(Time.get_ticks_msec() - started) / 1000.0,
	])
	print("Готово: %s, %s, %s" % [SCENE_PATH, ART_PATH, MAP_PATH])


## Собрать дерево острова (без входа в SceneTree — _ready нод не выполняется,
## визуал мобов/монет/камней строится в игре, в сцену попадает статика).
@warning_ignore("unsafe_method_access")
func _build_scene(data: Dictionary, art: IslandArt) -> Island:
	var root := Island.new()
	root.name = "Island"
	root.zones = IslandGen.ZONES
	root.spawn_zones = data["spawn_zones"]
	root.world_bounds = data["bounds"]

	var view := IslandView.new()
	view.name = "IslandView"
	view.art = art
	root.add_child(view)

	# Вода: море вокруг и озеро (surface_gap 0 — кромка вплотную к воде).
	for water_key: String in ["sea", "lake"]:
		var area: Dictionary = data["water"][water_key]
		var water: Area3D = load(WATER_SCRIPT).new()
		water.name = "SeaWater" if water_key == "sea" else "LakeWater"
		root.add_child(water)
		water.setup(area["center"], area["size"], area["level"], 0.0)

	# Расщелина: зона и светящиеся HangPoint на кромках.
	var hang: Dictionary = data["hang"]
	var crevasse: Area3D = load(HANG_SCRIPT).new()
	crevasse.name = "Crevasse"
	crevasse.position = hang["center"]
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = hang["size"]
	shape.shape = box
	crevasse.add_child(shape)
	for i: int in hang["points"].size():
		var hang_point: Node3D = load(HANG_POINT_SCRIPT).new()
		hang_point.name = "HangPoint%d" % (i + 1)
		hang_point.position = hang["points"][i] - crevasse.position
		crevasse.add_child(hang_point)
	root.add_child(crevasse)

	# Руины: ворота-решётка в проёме рамы, три плиты перед ними, сундук
	# внутри (состояниями управляет хост, раздел 9.2).
	var ruins: Dictionary = data["poi"]["ruins"]
	var gate: Node3D = load(GATE_SCRIPT).new()
	gate.name = "RuinGate"
	gate.position = ruins["gate_center"] + Vector3(0.0, 0.0, 0.5)
	root.add_child(gate)
	var chest: Node3D = load(CHEST_SCRIPT).new()
	chest.name = "RuinChest"
	chest.position = ruins["chest"]
	root.add_child(chest)
	var plates: Array = ruins["plates"]
	for i: int in plates.size():
		var plate: Node3D = load(PLATE_SCRIPT).new()
		plate.name = "Plate%d" % (i + 1)
		plate.position = plates[i]
		root.add_child(plate)

	# Камни духа (точки возрождения) и костёр на площади.
	# Перед ними — лестницы смотровых (раздел 9.3): узел в центре площадки,
	# порядок имён LookoutLadder1..4 — как LOOKOUTS у IslandGen.
	for i: int in (data["poi"]["lookouts"] as Array).size():
		var ladder: Node3D = load(LADDER_SCRIPT).new()
		ladder.name = "LookoutLadder%d" % (i + 1)
		ladder.position = (data["poi"]["lookouts"] as Array)[i]["center"]
		root.add_child(ladder)
	# Маяки мирового события (раздел 7): узлы у башен-предметов «beacon»,
	# порядок имён Beacon1..5 — как _beacons у IslandGen. Доска прогресса —
	# на площади, Звездопад — менеджер звёзд.
	for i: int in (data["beacons"] as Array).size():
		var beacon: Node3D = load(BEACON_SCRIPT).new()
		beacon.name = "Beacon%d" % (i + 1)
		beacon.position = (data["beacons"] as Array)[i]
		root.add_child(beacon)
	var board: Label3D = load(BOARD_SCRIPT).new()
	board.name = "BeaconBoard"
	board.position = (data["poi"]["campfire"] as Dictionary)["board"] \
		+ Vector3(0.0, 0.0, 0.05)
	root.add_child(board)
	var starfall: Node3D = load(STARFALL_SCRIPT).new()
	starfall.name = "Starfall"
	root.add_child(starfall)
	var stones: Array = data["stones"]
	for i: int in stones.size():
		var stone: Node3D = load(STONE_SCRIPT).new()
		stone.name = "RespawnStone%d" % (i + 1)
		stone.position = stones[i]
		root.add_child(stone)
	var campfire: Node3D = load(CAMPFIRE_SCRIPT).new()
	campfire.position = data["poi"]["campfire"]["center"]
	root.add_child(campfire)

	# Статичные монеты (ровно 60) и мобы — траектории в параметрах.
	var coins: Array = data["coins"]
	for i: int in coins.size():
		var coin: Area3D = load(COIN_SCRIPT).new()
		coin.name = "Coin%d" % (i + 1)
		coin.spawn_id = i + 1
		coin.position = coins[i]
		root.add_child(coin)
	for mob: Dictionary in data["mobs"]:
		root.add_child(_mob_node(mob))

	# Невидимые ограждения по краю мира.
	var bounds: float = root.world_bounds
	for i: int in 4:
		var side: float = -1.0 if i < 2 else 1.0
		var wall := StaticBody3D.new()
		wall.name = "Bounds%d" % (i + 1)
		var wall_shape := CollisionShape3D.new()
		var wall_box := BoxShape3D.new()
		wall_box.size = Vector3(2.0, 40.0, bounds * 2 + 4.0) if i < 2 \
			else Vector3(bounds * 2 + 4.0, 40.0, 2.0)
		wall_shape.shape = wall_box
		wall.add_child(wall_shape)
		wall.position = Vector3(side * (bounds + 1.0), 12.0, 0.0) if i < 2 \
			else Vector3(0.0, 12.0, side * (bounds + 1.0))
		root.add_child(wall)

	_set_owners(root)
	return root


@warning_ignore("unsafe_method_access")
func _mob_node(mob: Dictionary) -> Area3D:
	# Типизированные массивы из данных превращаем в обычные — так словарь
	# motion надёжно сериализуется в tscn и читается обратно.
	var motion: Dictionary = {}
	for key: String in mob:
		if key == "kind" or key == "spawn_id":
			continue
		if mob[key] is Array:
			var plain: Array = []
			for item: Variant in mob[key]:
				plain.append(item)
			motion[key] = plain
		else:
			motion[key] = mob[key]
	var script_path: String = ""
	match String(mob["kind"]):
		"bird":
			script_path = BIRD_SCRIPT
			motion["center"] = mob["center"]
		"critter":
			script_path = CRITTER_SCRIPT
		"firefly":
			script_path = FIREFLY_SCRIPT
		_:
			push_error("Неизвестный тип моба: %s" % mob["kind"])
	var node: Area3D = load(script_path).new()
	node.name = "Mob%d" % int(mob["spawn_id"])
	node.spawn_id = int(mob["spawn_id"])
	node.motion = motion
	match String(mob["kind"]):
		"bird", "firefly":
			node.position = mob["center"]
		"critter":
			node.position = (mob["points"] as Array)[0]
	return node


## Владелец-корень для упаковки: без owner узел не попадёт в PackedScene.
func _set_owners(root: Island) -> void:
	for child: Node in root.get_children():
		_own(root, child)


func _own(root: Island, node: Node) -> void:
	node.owner = root
	for child: Node in node.get_children():
		_own(root, child)


## Вид сверху (карта по M): цвет грани рельефа из TerrainBuilder.point_color
## (пиксель = квадрат сетки), всё ниже уровня воды — море/озеро. Высоты
## уже учтены в цвете (лёгкое высветление холмов). Чистая функция данных.
func _render_map(data: Dictionary) -> void:
	var heights: PackedFloat32Array = data["heights"]
	var tint: Dictionary = data["tint"]
	var image := Image.create(IslandGen.HALF * 2, IslandGen.HALF * 2, false, Image.FORMAT_RGB8)
	image.fill(PAL.water)
	for z: int in range(-IslandGen.HALF, IslandGen.HALF):
		for x: int in range(-IslandGen.HALF, IslandGen.HALF):
			var h: float = heights[(z + IslandGen.HALF) * IslandGen.POINTS + x + IslandGen.HALF]
			if h <= IslandGen.SEA_LEVEL:
				continue  # под водой — заливка морем/озером
			image.set_pixel(
				x + IslandGen.HALF, z + IslandGen.HALF,
				TerrainBuilder.point_color(heights, tint, x, z)
			)
	var save_error: int = image.save_png(MAP_PATH)
	if save_error != OK:
		push_error("Не удалось сохранить %s (код %d)" % [MAP_PATH, save_error])
