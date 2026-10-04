# Остров (раздел 6 SPEC): сцена gameplay/world/island.tscn собирается оффлайн
# tools/generate_island.gd из детерминированных данных IslandGen (рельеф
# и предметы — запечённый IslandArt в IslandView, вода, расщелина с HangPoint,
# камни духа, руины, пирс, костёр, монеты, мобы, ограждения) и коммитится.
# Этот скрипт — тонкая обвязка корня: точки появления по --dev-spawn
# и название зоны для F3/карты; вся геометрия уже в сцене, рантайм ничего
# не строит. Данные зон — @export (видны в tscn).
class_name Island
extends Node3D

## Зоны острова: {name: String, center: Vector2, radius: float} — для карты,
## названий мест и проверки «внутри зоны» (радиус круга).
@export var zones: Array[Dictionary] = []
## Точка появления по имени зоны (--dev-spawn, Session.spawn_zone).
@export var spawn_zones: Dictionary = {}
## Граница мира, м (невидимые ограждения по периметру).
@export var world_bounds: float = 127.5

## Позиция появления в зоне (неизвестная зона — Площадь).
func spawn_point(zone_name: String) -> Vector3:
	var point: Variant = spawn_zones.get(zone_name, spawn_zones.get("plaza"))
	if point is Vector3:
		return point
	return Vector3.ZERO


## Имя зоны, в которой стоит позиция (пусто — между зонами). Название для UI
## локализуется по ключу ZONE_<ИМЯ> (i18n/strings.csv).
func zone_name_at(pos: Vector3) -> String:
	var best: String = ""
	var best_distance: float = 1e9
	for zone: Dictionary in zones:
		var center: Vector2 = zone["center"]
		var distance: float = Vector2(pos.x, pos.z).distance_to(center)
		if distance <= float(zone["radius"]) and distance < best_distance:
			best = zone["name"]
			best_distance = distance
	return best
