# Одноразовая генерация острова (раздел 6 SPEC): godot --headless --script
# tools/generate_island.gd --path . — собирает из детерминированных данных
# IslandGen три артефакта, которые коммитятся:
#   gameplay/world/block_library.tres — MeshLibrary из 13 блоков (BlockLibrary);
#   gameplay/world/island.tscn        — остров целиком: GridMap рельефа,
#     вода (море и озеро), расщелина с HangPoint, камни духа, костёр,
#     60 статичных монет, мобы (птицы, зверьки, светлячки), ограждения края;
#   assets/island_map.png             — вид сверху для карты (M).
# По сети мир не передаётся: сцена одинакова у всех. Повторный запуск даёт
# тот же результат (тест — на хеш блоков IslandGen.block_hash).
# Скрипты нод (мобы, монеты, вода) подключаются load()-ом во время работы,
# а не на этапе разбора: они ссылаются на автолоады (Session, EventBus),
# которые в режиме «--script» регистрируются позже загрузки этого файла.
extends SceneTree

const LIBRARY_PATH: String = "res://gameplay/world/block_library.tres"
const SCENE_PATH: String = "res://gameplay/world/island.tscn"
const MAP_PATH: String = "res://assets/island_map.png"

const WATER_SCRIPT: String = "res://gameplay/world/water_area.gd"
const HANG_SCRIPT: String = "res://gameplay/activities/hang_area.gd"
const STONE_SCRIPT: String = "res://gameplay/world/respawn_stone.gd"
const CAMPFIRE_SCRIPT: String = "res://gameplay/world/campfire.gd"
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
	var hash_value: int = IslandGen.block_hash(data)

	# MeshLibrary сохраняем до сцены: GridMap ссылается на файл на диске
	# (ext_resource), а не на объект в памяти (иначе он запечётся внутрь tscn).
	var library := BlockLibrary.build()
	var library_error: int = ResourceSaver.save(library, LIBRARY_PATH)
	if library_error != OK:
		push_error("Не удалось сохранить %s (код %d)" % [LIBRARY_PATH, library_error])
		return

	var root := _build_scene(data, load(LIBRARY_PATH) as MeshLibrary)
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
	print("Остров: %d клеток GridMap, хеш %d, монет %d, мобов %d, %.1f с" % [
		IslandGen.cells(data).size(),
		hash_value,
		(data["coins"] as Array).size(),
		(data["mobs"] as Array).size(),
		(Time.get_ticks_msec() - started) / 1000.0,
	])
	print("Готово: %s, %s, %s" % [SCENE_PATH, LIBRARY_PATH, MAP_PATH])


## Собрать дерево острова (без входа в SceneTree — _ready нод не выполняется,
## визуал мобов/монет/камней строится в игре, в сцену попадает статика).
@warning_ignore("unsafe_method_access")
func _build_scene(data: Dictionary, library: MeshLibrary) -> Island:
	var root := Island.new()
	root.name = "Island"
	root.zones = IslandGen.ZONES
	root.spawn_zones = data["spawn_zones"]
	root.world_bounds = data["bounds"]

	var grid := GridMap.new()
	grid.name = "GridMap"
	grid.cell_size = Vector3.ONE
	grid.cell_octant_size = 16  # SPEC 16: производительность
	grid.mesh_library = library
	root.add_child(grid)
	for entry: Dictionary in IslandGen.cells(data):
		grid.set_cell_item(entry["cell"], entry["block"])

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
	for point: Vector3 in hang["points"]:
		var marker := Marker3D.new()
		marker.position = point - crevasse.position
		crevasse.add_child(marker)
	root.add_child(crevasse)

	# Камни духа (точки возрождения) и костёр на площади.
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


## Вид сверху (карта по M): цвет верхней поверхности клетки, море и озеро —
## вода (клетки дна ниже нуля не рисуем), высоты — лёгкое высветление, чтобы
## холмы читались. Чистая функция данных — детерминирована.
func _render_map(data: Dictionary) -> void:
	var image := Image.create(IslandGen.HALF * 2, IslandGen.HALF * 2, false, Image.FORMAT_RGB8)
	var blocks: Dictionary = {}
	var top: Dictionary = {}
	for entry: Dictionary in IslandGen.cells(data):
		var cell: Vector3i = entry["cell"]
		blocks[cell] = entry["block"]
		var key := Vector2i(cell.x, cell.z)
		if not top.has(key) or cell.y > (top[key] as Vector3i).y:
			top[key] = cell
	image.fill(PAL.water)
	for key: Vector2i in top:
		var cell: Vector3i = top[key]
		if cell.y < 0:
			continue
		var color := BlockLibrary.block_color(blocks[cell])
		color = color.lerp(Color.WHITE, clampf(cell.y / 24.0, 0.0, 1.0) * 0.25)
		image.set_pixel(key.x + IslandGen.HALF, key.y + IslandGen.HALF, color)
	var save_error: int = image.save_png(MAP_PATH)
	if save_error != OK:
		push_error("Не удалось сохранить %s (код %d)" % [MAP_PATH, save_error])
