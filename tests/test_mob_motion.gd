# Тесты траекторий мобов (раздел 8, этап П2): движение — чистые функции от
# world_time, обязательный тест раздела 18 («траектории мобов от времени»).
# Проверяются замкнутость, ограниченность и непрерывность — всё, что нужно
# для детерминизма в сети без синхронизации позиций (П3).
extends GutTest

const EPS: float = 0.01

const BIRD: Dictionary = {
	"center": Vector3(10.0, 5.0, -20.0),
	"radius": 6.0,
	"height": 3.0,
	"period": 30.0,
	"phase": 0.7,
	"direction": 1,
}

const CRITTER: Dictionary = {
	"points": [
		Vector3(0.0, 2.0, 0.0),
		Vector3(6.0, 3.0, 0.0),
		Vector3(6.0, 3.0, 8.0),
		Vector3(0.0, 2.0, 8.0),
	],
	"speed": 2.0,
}

const FIREFLY: Dictionary = {
	"center": Vector3(-50.0, 4.0, -50.0),
	"drift": 2.0,
	"period": 4.0,
	"phase": 0.3,
}


func test_bird_circle_is_closed() -> void:
	var at_start := MobMotion.bird_position(BIRD, 123.4)
	var at_period := MobMotion.bird_position(BIRD, 123.4 + BIRD["period"])
	assert_almost_eq(at_start.distance_to(at_period), 0.0, EPS, "период — полный круг")


func test_bird_keeps_radius_and_height() -> void:
	for t: float in [0.0, 3.3, 100.0, 777.7]:
		var position := MobMotion.bird_position(BIRD, t)
		var flat: float = Vector2(position.x - 10.0, position.z + 20.0).length()
		assert_almost_eq(flat, BIRD["radius"], EPS, "расстояние от центра = радиус")
		assert_almost_eq(position.y - 5.0, BIRD["height"], EPS, "высота над центром")


func test_bird_yaw_is_tangent() -> void:
	# Курс перпендикулярен радиусу: птица летит по кругу, не боком.
	var yaw: float = MobMotion.bird_yaw(BIRD, 10.0)
	var radial := (MobMotion.bird_position(BIRD, 10.0) - BIRD["center"]) \
		* Vector3(1.0, 0.0, 1.0)
	var heading := Vector3(sin(yaw), 0.0, cos(yaw))
	assert_almost_eq(absf(radial.normalized().dot(heading)), 0.0, 0.01, "курс ⊥ радиусу")


func test_critter_route_is_closed_and_starts_home() -> void:
	var home: Vector3 = MobMotion.critter_position(CRITTER, 0.0)
	assert_almost_eq(home.distance_to(CRITTER["points"][0]), 0.0, EPS, "старт — первая точка")
	# Период = длина маршрута / скорость; после него зверёк снова дома.
	var total: float = 0.0
	for i: int in CRITTER["points"].size():
		var a: Vector3 = CRITTER["points"][i]
		var b: Vector3 = CRITTER["points"][(i + 1) % CRITTER["points"].size()]
		total += a.distance_to(b)
	var after_loop := MobMotion.critter_position(CRITTER, total / CRITTER["speed"])
	assert_almost_eq(after_loop.distance_to(home), 0.0, EPS, "маршрут замкнут")


func test_critter_stays_on_route() -> void:
	# Позиция всегда на отрезках маршрута (интерполяция высоты — та же
	# плоскость, что и точки), шаг не больше скорости.
	var previous := MobMotion.critter_position(CRITTER, 0.0)
	for i: int in range(1, 200):
		var t: float = i * 0.1
		var position := MobMotion.critter_position(CRITTER, t)
		assert_lte(
			position.distance_to(previous), CRITTER["speed"] * 0.1 + EPS,
			"непрерывность (t=%.1f)" % t,
		)
		assert_between(position.x, 0.0, 6.0, "в границах маршрута по x")
		assert_between(position.z, 0.0, 8.0, "в границах маршрута по z")
		previous = position


func test_firefly_drifts_near_center() -> void:
	for t: float in [0.0, 1.7, 40.0, 365.0]:
		var position := MobMotion.firefly_position(FIREFLY, t)
		var offset := position - FIREFLY["center"]
		assert_lte(offset.length(), FIREFLY["drift"] + 0.5, "дрейф ограничен")
		assert_lte(absf(offset.y), 0.45, "вертикаль — лёгкое покачивание")


func test_firefly_glow_in_range() -> void:
	for t: float in [0.0, 0.9, 12.3]:
		var glow: float = MobMotion.firefly_glow(FIREFLY, t)
		assert_between(glow, 0.1, 1.0, "яркость вспышки в [0.1, 1.0]")
