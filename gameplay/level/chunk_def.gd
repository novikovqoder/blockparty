# Метаданные и данные спавнов секции уровня (раздел 5 SPEC). ChunkDef — чистые
# данные для планировщика забега (LevelPlanner) и теста детерминизма;
# статичную геометрию (пол, блоки, ямы) строит скрипт секции (chunk.gd).
# Согласование def и геометрии — в одном файле секции, рядом.
class_name ChunkDef
extends RefCounted

enum Type { START, EASY, MEDIUM, COOP, BONUS, FINISH }

var id: String = ""
var type: int = Type.EASY
## Сложность 1–3, только для сортировки и отладки.
var difficulty: int = 1
## Ширина секции, px; кратна 64, от 1920 до 3840 у игровых секций.
var width: int = 1920
## Сколько игроков нужно для кооп-механики секции (раздел 7.2).
var min_players_for_coop: int = 1
## Локальная точка чекпоинта в начале секции (возврат после «Висит»).
var checkpoint: Vector2 = Vector2(96, 576)
## Локальные спавны мобов: {kind: String, x: float, y: float, params: Dictionary}.
var mob_spawns: Array[Dictionary] = []
## Локальные позиции монет.
var coin_spawns: Array[Vector2] = []
## Локальные x-координаты краёв пропастей (y — уровень пола 576).
var hang_points: Array[float] = []
## Кооп-объекты секции (разделы 7.2, 7.3), локальные координаты:
## ворота {kind:"gate", plates:Array[float], gate_x:float, min_players:int,
##         zone_from:float, zone_to:float};
## уступ {kind:"ledge", ladder_x:float, top_y:float, fallback_x:float,
##        fallback_top_y:float, zone_from:float, zone_to:float,
##        top_from:float, top_to:float}.
var coop_spawns: Array[Dictionary] = []
## Падающие платформы (раздел 6), локальные координаты: {cx, top_y, width}.
var platform_spawns: Array[Dictionary] = []
## x финишной черты (только для секции FINISH, -1 — нет).
var finish_x: float = -1.0


func is_coop() -> bool:
	return type == Type.COOP
