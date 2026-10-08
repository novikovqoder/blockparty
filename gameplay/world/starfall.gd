# Звездопад (раздел 7 SPEC): 2 минуты после зажжения всех 5 маяков по
# острову падают золотые звёзды. Менеджер — ребёнок island.tscn: слышит
# beacons_state (старт от хоста) и сам рисует живые звёзды — позиции
# детерминированы от (старт, индекс), поэтому у всех клиентов и хоста
# звёзды совпадают. Подбор подтверждает хост («кто первый»), звезда
# исчезает по star_taken. Возрождения нет — цикл даёт новые звёзды.
class_name Starfall
extends Node3D

const B: Balance = preload("res://gameplay/balance.tres")
const STAR_SCRIPT: String = "res://gameplay/world/star_pickup.gd"

## Старт текущего Звездопада по часам мира (−1 — не идёт).
var _started_at: float = -1.0
## Живые звёзды: index -> StarPickup.
var _stars: Dictionary = {}
## Карта высот острова (посадка звёзд на землю) — из IslandView.
var _heights: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	EventBus.beacons_state.connect(_on_beacons_state)
	var parent := get_parent()
	if parent != null:
		var view := parent.get_node_or_null("IslandView") as IslandView
		if view != null:
			_heights = view.art.heights


func _on_beacons_state(_lit: Array, _lighters: Array, starfall_started_at: float) -> void:
	_started_at = starfall_started_at
	if _started_at < 0.0 and not _stars.is_empty():
		_clear_stars()


func _process(_delta: float) -> void:
	if _started_at < 0.0:
		return
	var now := Session.world_time
	var elapsed := now - _started_at
	# Живые индексы: родились не позже конца Звездопада и не истлели.
	var first: int = maxi(0, int(floor((elapsed - B.star_lifetime) / B.star_interval)) + 1)
	var last: int = int(floor(minf(elapsed, B.starfall_duration) / B.star_interval))
	for index: int in range(first, last + 1):
		if not _stars.has(index):
			_spawn(index)
	# Протухшие (истлели по возрасту) — убрать; взятые хостом звёзды уже
	# freed и не возрождаются: пустая ячейка _stars держит индекс занятым.
	var stale: Array[int] = []
	for index: int in _stars:
		if index < first or index > last:
			stale.append(index)
	for index: int in stale:
		_free_star(_stars[index])
		_stars.erase(index)


## Индексы звёзд, живых в момент elapsed от старта (для тестов и отладки).
static func star_indices(elapsed: float, b: Balance) -> Array[int]:
	var first: int = maxi(0, int(floor((elapsed - b.star_lifetime) / b.star_interval)) + 1)
	var last: int = int(floor(minf(elapsed, b.starfall_duration) / b.star_interval))
	var indices: Array[int] = []
	for index: int in range(first, last + 1):
		indices.append(index)
	return indices


## Точка падения звезды (детерминирована от старта и индекса: RandomNumber
## Generator с явным seed, правило проекта — без randf()). Высоту земли
## подставляет менеджер по карте острова.
static func star_position(started_at: float, index: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(round(started_at * 100.0)) * 31 + index
	var reach: float = IslandGen.HALF * 0.75
	return Vector3(rng.randf_range(-reach, reach), 0.0, rng.randf_range(-reach, reach))


func _spawn(index: int) -> void:
	var star := load(STAR_SCRIPT).new() as StarPickup
	star.index = index
	star.position = star_position(_started_at, index)
	star.ground_y = ground_y(star.position)
	star.born_at = _started_at + float(index) * B.star_interval
	add_child(star)
	_stars[index] = star


## Высота рельефа в точке — ближайший узел карты высот (сетка 1 м).
func ground_y(pos: Vector3) -> float:
	if _heights.is_empty():
		return 0.0
	var x: int = clampi(int(round(pos.x)), -IslandGen.HALF, IslandGen.HALF)
	var z: int = clampi(int(round(pos.z)), -IslandGen.HALF, IslandGen.HALF)
	return _heights[(z + IslandGen.HALF) * IslandGen.POINTS + (x + IslandGen.HALF)]


func _clear_stars() -> void:
	for index: int in _stars:
		_free_star(_stars[index])
	_stars.clear()


## Освободить звезду, если она ещё жива (взятые хостом уже freed — каст
## freed-объекта в GDScript падает, поэтому проверка до приведения).
func _free_star(star: Variant) -> void:
	if is_instance_valid(star):
		(star as Node).queue_free()
