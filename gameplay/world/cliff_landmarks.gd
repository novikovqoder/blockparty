# Расширение карты, сборка 2 (SPEC 3.1): крыло Утёсов — скалы-ориентиры,
# сканированные CC0-модели Poly Haven, запечённые в .res с цветом текстуры
# в вершинах (tools/decimate_polyhaven.gd, как наполнение GroundDetails).
# Ставятся в рантайме IslandView._ready по печёным высотам: центр каждой
# скалы — подножие обрыва, найденное шагами от якоря на плато к морю до
# спуска ниже FOOT_H (детерминировано, island_art.res и хеш острова не
# меняются). Лицо стен смотрит в локальном −Z: yaw разворачивает его
# к морю — запад PI/2, север PI, юг 0. Тинт и упрощённая коллизия
# боксом по AABB (SPEC 3.1) — общие с GroundDetails.
# Сборка 4: тот же слой несёт пару прибрежных глыб восточного Берега
# (lm_shore_*) — подножие-плита у уреза воды, лицо на восток.
class_name CliffLandmarks
extends RefCounted

## Подножие: шаг от якоря к морю, пока высота не уйдёт ниже порога.
const STEP_M: float = 0.5
const MAX_STEPS: int = 80
## Пороги подножия, м: стены/контрфорсы встают у основания обрыва,
## плиты — у самого уреза воды.
const FOOT_WALL_H: float = 2.0
const FOOT_SLAB_H: float = 0.9
## Прохладный тинт сканов (тот же, что у наполнения, SPEC 3.7).
const TINT_COOL: Color = Color(0.93, 0.95, 1.03)
## Санитарный коридор высоты грунта под основанием: обрыв крыла зубчатый
## (перепад одной клетки до ~20 м), первая точка ниже порога может
## оказаться уже глубоко под водой — центр скалы не тонет глубже и
## не повисает выше (итоговый y = clamp + dy держится у воды).
const FOOT_G_MIN: float = -1.2
const FOOT_G_MAX: float = 2.0

## Скалы крыла: anchor — точка на плато/гребне, dir — к морю (шаги
## STEP_M дают подножие — центр скалы); yaw — лицо к морю; scale
## единый по осям; dy — сдвиг-origin от земли (у стен уходит вглубь,
## у плит основание ниже origin); range — дальность видимости, bright —
## вариация тона. Стык крыла с востока (перешеек) и террасы смотровых
## свободны от ориентиров.
const SITES: Array[Dictionary] = [
	{
		"name": "lm_cliff_west", "foot_h": FOOT_WALL_H,
		"mesh": preload("res://assets/third_party/polyhaven.com/coastal_cliff_01/coastal_cliff_01_lo.res"),
		"anchor": Vector2(-226.0, 30.0), "dir": Vector2(-1.0, 0.0),
		"yaw": PI / 2.0, "scale": 1.1, "dy": -2.0, "range": 340.0,
		"bright": 1.04,
	},
	{
		"name": "lm_cliff_north", "foot_h": FOOT_WALL_H,
		"mesh": preload("res://assets/third_party/polyhaven.com/coastal_cliff_02/coastal_cliff_02_lo.res"),
		"anchor": Vector2(-170.0, 90.0), "dir": Vector2(0.0, 1.0),
		"yaw": PI, "scale": 1.5, "dy": -2.5, "range": 300.0,
		"bright": 0.98,
	},
	{
		"name": "lm_cliff_south", "foot_h": FOOT_WALL_H,
		"mesh": preload("res://assets/third_party/polyhaven.com/coastal_cliff_02/coastal_cliff_02_lo.res"),
		"anchor": Vector2(-170.0, -30.0), "dir": Vector2(0.0, -1.0),
		"yaw": 0.0, "scale": 1.4, "dy": -2.5, "range": 300.0,
		"bright": 1.02,
	},
	{
		"name": "lm_buttress_nw", "foot_h": FOOT_WALL_H,
		"mesh": preload("res://assets/third_party/polyhaven.com/namaqualand_cliff_02/namaqualand_cliff_02_lo.res"),
		"anchor": Vector2(-222.0, 56.0), "dir": Vector2(-0.89, 0.45),
		"yaw": 2.04, "scale": 2.0, "dy": -1.5, "range": 280.0,
		"bright": 0.96,
	},
	{
		"name": "lm_buttress_sw", "foot_h": FOOT_WALL_H,
		"mesh": preload("res://assets/third_party/polyhaven.com/namaqualand_cliff_02/namaqualand_cliff_02_lo.res"),
		"anchor": Vector2(-222.0, 4.0), "dir": Vector2(-0.89, -0.45),
		"yaw": 1.10, "scale": 1.8, "dy": -1.5, "range": 280.0,
		"bright": 1.02,
	},
	{
		"name": "lm_slab_west", "foot_h": FOOT_SLAB_H,
		"mesh": preload("res://assets/third_party/polyhaven.com/coast_rocks_01/coast_rocks_01_lo.res"),
		"anchor": Vector2(-226.0, 12.0), "dir": Vector2(-1.0, 0.0),
		"yaw": PI / 2.0, "scale": 0.9, "dy": 0.4, "range": 300.0,
		"bright": 1.0,
	},
	{
		"name": "lm_slab_south", "foot_h": FOOT_SLAB_H,
		"mesh": preload("res://assets/third_party/polyhaven.com/coast_rocks_03/coast_rocks_03_lo.res"),
		"anchor": Vector2(-170.0, -28.0), "dir": Vector2(0.0, -1.0),
		"yaw": 0.0, "scale": 1.1, "dy": 0.3, "range": 260.0,
		"bright": 0.98,
	},
	{
		"name": "lm_slab_north", "foot_h": FOOT_SLAB_H,
		"mesh": preload("res://assets/third_party/polyhaven.com/coast_rocks_03/coast_rocks_03_lo.res"),
		"anchor": Vector2(-150.0, 88.0), "dir": Vector2(0.0, 1.0),
		"yaw": PI, "scale": 1.0, "dy": 0.3, "range": 260.0,
		"bright": 1.02,
	},
	# Расширение карты, сборка 4: восточный Берег — пара прибрежных глыб
	# у кромки воды (лицо на восток, к открытому морю); подножие — плита,
	# якорь на берегу, шаги к морю находят урез.
	{
		"name": "lm_shore_north", "foot_h": FOOT_SLAB_H,
		"mesh": preload("res://assets/third_party/polyhaven.com/coast_rocks_03/coast_rocks_03_lo.res"),
		"anchor": Vector2(226.0, 16.0), "dir": Vector2(1.0, 0.0),
		"yaw": -PI / 2.0, "scale": 0.45, "dy": 0.3, "range": 280.0,
		"bright": 1.0,
	},
	{
		"name": "lm_shore_south", "foot_h": FOOT_SLAB_H,
		"mesh": preload("res://assets/third_party/polyhaven.com/coast_rocks_01/coast_rocks_01_lo.res"),
		"anchor": Vector2(224.0, -52.0), "dir": Vector2(0.96, -0.28),
		"yaw": -PI / 2.0, "scale": 0.32, "dy": 0.3, "range": 280.0,
		"bright": 0.98,
	},
]


## Построить слой: по узлу MultiMeshInstance3D на скалу (трансформ
## считается от печёных высот — повторный вход в мир даёт то же), колайдеры
## боксов крупных — в формате art.colliders. Формат ответа — как у
## GroundDetails.build, IslandView подключает их одними циклами.
static func build(art: IslandArt) -> Dictionary:
	var instances: Array[MultiMeshInstance3D] = []
	var ranges: Dictionary = {}
	var colliders: Array[Dictionary] = []
	var transforms: Dictionary = {}
	for site: Dictionary in SITES:
		var foot := _foot_point(
			art, site["anchor"], site["dir"], float(site["foot_h"]))
		if foot == Vector2.INF:
			push_error("Скала %s: подножие не найдено" % site["name"])
			continue
		var scale: float = site["scale"]
		var pos := Vector3(
			foot.x,
			clampf(
				IslandGen.ground_height(art.heights, foot.x, foot.y),
				FOOT_G_MIN, FOOT_G_MAX) + float(site["dy"]),
			foot.y)
		var xf := Transform3D(
			Basis(Vector3.UP, float(site["yaw"])) * Basis().scaled(
				Vector3.ONE * scale), pos)
		var type := String(site["name"])
		instances.append(_to_instance(site, xf))
		ranges[type] = site["range"]
		transforms[type] = [xf]
		colliders.append(GroundDetails._collider(site["mesh"], xf))
	return {
		"instances": instances,
		"ranges": ranges,
		"colliders": colliders,
		"transforms": transforms,
	}


## Меш скалы по имени вида (null — имя неизвестно); окклюдеры и тесты
## смотрят трансформы через эту пару (как GroundDetails.kind_mesh).
static func site_mesh(type: StringName) -> Mesh:
	for site: Dictionary in SITES:
		if String(site["name"]) == String(type):
			return site["mesh"]
	return null


## Узел скалы: MultiMesh на один экземпляр — общий формат с наполнением,
## IslandView регистрирует его в таблицах дальностей (set_quality).
static func _to_instance(site: Dictionary, xf: Transform3D) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = site["mesh"]
	mm.instance_count = 1
	mm.set_instance_transform(0, xf)
	var bright: float = site["bright"]
	mm.set_instance_color(0, Color(
		TINT_COOL.r * bright, TINT_COOL.g * bright,
		TINT_COOL.b * bright, 1.0))
	var instance := MultiMeshInstance3D.new()
	instance.name = site["name"]
	instance.multimesh = mm
	instance.material_override = LowPolyMat.flat_or_vertex()
	instance.visibility_range_end = float(site["range"])
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return instance


## Подножие: шаги STEP_M от якоря в сторону моря до первого спуска ниже
## foot_h — сама эта точка (низ обрыва; зубчатость кромки гасит кламп
## FOOT_G_* в build). Vector2.INF — за MAX_STEPS подножие не встретилось
## (стену не ставить; тест ловит).
static func _foot_point(
	art: IslandArt, anchor: Vector2, dir: Vector2, foot_h: float,
) -> Vector2:
	var pos := anchor
	for i: int in MAX_STEPS:
		var next := pos + dir * STEP_M
		if IslandGen.ground_height(art.heights, next.x, next.y) < foot_h:
			return next
		pos = next
	return Vector2.INF
