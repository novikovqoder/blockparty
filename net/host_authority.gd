# Авторитет хоста для мобов и монет (разделы 8, 10 SPEC): хост решает
# «убит», «подобран» и «возродился», клиенты только показывают результат.
# Состояние — словари spawn_id -> respawn_at (по часам мира): возрождение
# вычисляется на каждом клиенте сравнением с world_time, поэтому достаточно
# разослать время возрождения один раз в событии смерти — позднее
# подключившиеся получают его из world_state.
# Чистая логика без узлов — обязательные тесты раздела 18 «расписание
# возрождений». Позиции мобов/убийц передают параметрами (Net берёт их из
# траекторий MobMotion и снапшотов).
class_name HostAuthority
extends RefCounted

## spawn_id -> время возрождения по world_time, с.
var dead_mobs: Dictionary = {}
## spawn_id -> время возрождения подобранной монеты по world_time, с.
var taken_coins: Dictionary = {}
## killer_peer -> world_time последнего принятого удара (перезарядка):
## хост не видит взмахов клиента и ограничивает частоту запросов сам.
var _last_hits: Dictionary = {}


## Общая проверка удара по мобу (раздел 8): моб жив, перезарядка убийцы
## прошла, дистанция в норме (с допуском на пинг). Прошедший удар
## записывается в перезарядку. Используют одиночные мобы (try_kill_mob)
## и светлячок «на двоих» (П5, раздел 8).
func hit_allowed(
	spawn_id: int,
	killer_peer: int,
	world_time: float,
	mob_pos: Vector3,
	killer_pos: Vector3,
	b: Balance,
) -> bool:
	if dead_mobs.has(spawn_id):
		return false
	if world_time - float(_last_hits.get(killer_peer, -1.0e9)) < b.attack_cooldown:
		return false
	if mob_pos.distance_to(killer_pos) > b.mob_hit_distance + b.mob_hit_slack:
		return false
	_last_hits[killer_peer] = world_time
	return true


## Записать смерть моба без проверок удара (светлячок умирает парой
## ударов — ActivityAuthority, а расписание возрождения ведёт хост).
func mark_mob_dead(spawn_id: int, respawn_at: float) -> void:
	dead_mobs[spawn_id] = respawn_at


## Попытка убийства моба (раздел 8: хост проверяет дистанцию до 2.5 м
## с допуском на пинг, перезарядку и что моб жив). Возвращает словарь
## события {spawn_id, respawn_at} или пустой словарь, если отказано.
## mob_pos — расчётная позиция моба на client_world_time (траектории
## детерминированы), killer_pos — последняя позиция убийцы из снапшотов,
## respawn_sec — время возрождения этого типа моба (светлячок дольше).
func try_kill_mob(
	spawn_id: int,
	killer_peer: int,
	world_time: float,
	mob_pos: Vector3,
	killer_pos: Vector3,
	respawn_sec: float,
	b: Balance,
) -> Dictionary:
	if not hit_allowed(spawn_id, killer_peer, world_time, mob_pos, killer_pos, b):
		return {}
	var respawn_at: float = world_time + respawn_sec
	dead_mobs[spawn_id] = respawn_at
	return {"spawn_id": spawn_id, "respawn_at": respawn_at}


## Попытка подобрать монету: побеждает первый запрос (раздел 10), монеты
## статичны и касание подтверждает физика самого клиента.
func try_take_coin(
	spawn_id: int,
	collector_peer: int,
	world_time: float,
	respawn_sec: float,
) -> Dictionary:
	if taken_coins.has(spawn_id):
		return {}
	var respawn_at: float = world_time + respawn_sec
	taken_coins[spawn_id] = respawn_at
	return {"spawn_id": spawn_id, "respawn_at": respawn_at}


## Убрать возродившихся из состояния: world_state остаётся компактным
## (клиенты сами показывают моба, когда world_time перевалила respawn_at).
func prune(world_time: float) -> void:
	for spawn_id: int in dead_mobs.keys():
		if world_time >= float(dead_mobs[spawn_id]):
			dead_mobs.erase(spawn_id)
	for spawn_id: int in taken_coins.keys():
		if world_time >= float(taken_coins[spawn_id]):
			taken_coins.erase(spawn_id)


## Мёртвые мобы для WorldState.pack (раздел 10).
func dead_mob_entries() -> Array:
	var out: Array = []
	for spawn_id: int in dead_mobs:
		out.append({"spawn_id": spawn_id, "respawn_at": dead_mobs[spawn_id]})
	return out


## Подобранные монеты для WorldState.pack (раздел 10).
func taken_coin_entries() -> Array:
	var out: Array = []
	for spawn_id: int in taken_coins:
		out.append({"spawn_id": spawn_id, "respawn_at": taken_coins[spawn_id]})
	return out


## Жив ли моб по состоянию хоста.
func is_mob_alive(spawn_id: int, world_time: float) -> bool:
	return not dead_mobs.has(spawn_id) or world_time >= float(dead_mobs[spawn_id])


## Новый мир — ничего не убито и не собрано.
func clear() -> void:
	dead_mobs.clear()
	taken_coins.clear()
	_last_hits.clear()
