# П5.13, блок 3: рельеф вне сектора Леса рисуют два узла Terrain3D
# (terrain3d_island.gd) — по одному региону 256 × 256 от локального нуля
# (единственный надёжный паттерн импорта v1.0.2). Проверяем: настройки
# узлов, соответствие высот карте генератора, дырки рендера (Лес, пустота
# за краем карты, стык-вершина world x = 0 без зазора и наложения),
# непрерывность высот на стыке East/West, маску и детерминизм
# гидравлической эрозии (лес не размывается).
extends GutTest

## Кэш данных генератора между тестами (generate() дорогой, ~10 с).
static var _heights_cache: PackedFloat32Array = PackedFloat32Array()


func _heights() -> PackedFloat32Array:
	if _heights_cache.is_empty():
		_heights_cache = IslandGen.generate()["heights"]
	return _heights_cache


## Собрать оба узла в автоочищаемом родителе.
func _spawn() -> Node3D:
	var root := Node3D.new()
	add_child_autofree(root)
	Terrain3DIsland.spawn(root, _heights())
	GutNoise.ignore_terrain3d_deprecation(self)
	return root


## Высота карты в мировой клетке (целые координаты −128..128).
func _map_h(heights: PackedFloat32Array, x: int, z: int) -> float:
	return heights[(z + IslandGen.HALF) * IslandGen.POINTS + x + IslandGen.HALF]


func test_nodes_settings() -> void:
	var root := _spawn()
	var east := root.get_node("Terrain3DEast") as Terrain3D
	var west := root.get_node("Terrain3DWest") as Terrain3D
	assert_not_null(east, "узел East собран")
	assert_not_null(west, "узел West собран")
	if east == null or west == null:
		return
	assert_eq(east.position, Vector3(-16.0, 0.0, -128.0), "смещение East")
	assert_eq(west.position, Vector3(-128.0, 0.0, -16.0), "смещение West")
	for terrain: Terrain3D in [east, west]:
		assert_eq(terrain.material.world_background, Terrain3DMaterial.NONE,
			"за регионами — пустота, не плоскость")
		assert_eq(terrain.collision.mode, Terrain3DCollision.DISABLED,
			"коллизия аддона выключена: физика на HeightMapShape3D")
		assert_true(terrain.material.shader_override_enabled,
			"шейдер рельефа подключён")


## Высоты Terrain3D совпадают с картой генератора в доменах обоих узлов
## (API данных — в локальных координатах узла: local = world − position).
func test_heights_match_map() -> void:
	var root := _spawn()
	var east := root.get_node("Terrain3DEast") as Terrain3D
	var west := root.get_node("Terrain3DWest") as Terrain3D
	var heights := _heights()
	# world x/z → (узел, локальная точка в центре текселя).
	var samples: Array = [
		[east, 60, 50], [east, 100, -60], [east, 0, 5],
		[west, -60, 50], [west, -100, 100], [west, -1, 1],
	]
	for sample: Array in samples:
		var terrain: Terrain3D = sample[0]
		var world := Vector2(int(sample[1]), int(sample[2]))
		var local := Vector3(
			world.x - terrain.position.x + 0.5, 0.0,
			world.y - terrain.position.z + 0.5)
		var got: float = terrain.data.get_height(local)
		assert_almost_eq(got, _map_h(heights, int(world.x), int(world.y)),
			0.05, "высота в world (%d, %d)" % [world.x, world.y])


## Дырки рендера: Лес и пустота за краем карты не рисуют, домены узлов
## рисуют, тексель world x = 0 на West жив (общая стык-вершина East/West).
func test_holes() -> void:
	var root := _spawn()
	var east := root.get_node("Terrain3DEast") as Terrain3D
	var west := root.get_node("Terrain3DWest") as Terrain3D
	var checks: Array = [
		# [узел, world x, world z, ожидание]
		[east, -1, 50, true],  # поле нормалей за кромкой Леса
		[east, 0, 0, false],  # домен East: от стыка вправо
		[east, 60, -60, false],  # юго-западная полоса карты (x ≥ 0) — East
		[east, 128, 0, true],  # пустота за краем карты
		[west, -60, 50, false],  # домен West
		[west, -60, -1, true],  # поле нормалей за кромкой Леса (z < 0)
		[west, 0, 5, false],  # стык-вершина world x = 0
		[west, 1, 5, true],  # правее стык-вершины гаснет дыркой
		[west, -60, 128, true],  # пустота за краем карты
	]
	for check: Array in checks:
		var terrain: Terrain3D = check[0]
		var local := Vector3(
			int(check[1]) - terrain.position.x + 0.5, 0.0,
			int(check[2]) - terrain.position.z + 0.5)
		assert_eq(terrain.data.get_control_hole(local), check[3],
			"дырка в world (%d, %d)" % [int(check[1]), int(check[2])])


## Стык узлов по линии world x = 0: высоты с обеих сторон совпадают —
## ни уступа, ни щели между East и West.
func test_seam_continuous() -> void:
	var root := _spawn()
	var east := root.get_node("Terrain3DEast") as Terrain3D
	var west := root.get_node("Terrain3DWest") as Terrain3D
	for z: int in [5, 40, 80, 120]:
		# world x = 0: East-тексель 16 и West-тексель 128 — одна вершина.
		var from_east: float = east.data.get_height(
			Vector3(16.5, 0.0, float(z) + 128.0 + 0.5))
		var from_west: float = west.data.get_height(
			Vector3(128.5, 0.0, float(z) + 16.0 + 0.5))
		assert_almost_eq(from_east, from_west, 0.02,
			"стык East/West на z = %d" % z)


## Маска эрозии: Лес, мелье кромки воды и террасы Площади/Руин/Озера
## не размываются, склоны Холмов — размываются.
func test_erodible_mask() -> void:
	assert_false(IslandGen._erodible(-60, -60, 10.0), "сектор Леса")
	assert_false(IslandGen._erodible(60, 100, IslandGen.SEA_H), "мель у кромки воды")
	assert_false(IslandGen._erodible(0, 4, 8.0), "терраса Площади")
	assert_false(IslandGen._erodible(58, -48, 8.0), "терраса Руин")
	assert_false(IslandGen._erodible(6, 82, 8.0), "котловина Озера")
	assert_true(IslandGen._erodible(60, 60, 10.0), "склон Холмов")


## Эрозия на синтетической карте: крутой конус в восточном квадранте
## размывается, такой же конус в секторе Леса не меняется ни на тексель,
## прогоны детерминированы (собственный RNG, seed от SEED_VALUE).
func test_erode_touches_only_masked_slopes() -> void:
	var base := PackedFloat32Array()
	base.resize(IslandGen.POINTS * IslandGen.POINTS)
	base.fill(2.0)
	for cone: Vector2i in [Vector2i(70, 70), Vector2i(-70, -70)]:
		for dz: int in range(-30, 31):
			for dx: int in range(-30, 31):
				var dist: float = Vector2(dx, dz).length()
				base[(cone.y + dz + IslandGen.HALF) * IslandGen.POINTS
					+ cone.x + dx + IslandGen.HALF] = maxf(2.0, 12.0 - dist * 0.4)
	var forest_before := _forest_cells(base)
	var first := base.duplicate()
	IslandGen._erode(first)
	var second := base.duplicate()
	IslandGen._erode(second)
	assert_eq(first, second, "эрозия детерминирована")
	assert_eq(_forest_cells(first), forest_before,
		"сектор Леса не тронут эрозией")
	var changed: int = 0
	for i: int in first.size():
		if absf(first[i] - base[i]) > 0.001:
			changed += 1
	assert_gt(changed, 200, "склон восточного конуса размыт (не холостой прогон)")


## Клетки сектора Леса (x < 0 ∧ z < 0) подряд — для сравнения «до/после».
func _forest_cells(heights: PackedFloat32Array) -> PackedFloat32Array:
	var cells := PackedFloat32Array()
	cells.resize(IslandGen.HALF * IslandGen.HALF)
	var out: int = 0
	for z: int in IslandGen.HALF:
		var row: int = z * IslandGen.POINTS
		for x: int in IslandGen.HALF:
			cells[out] = heights[row + x]
			out += 1
	return cells
