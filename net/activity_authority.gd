# Авторитет хоста для активностей и социальных механик (разделы 7, 9, 10 SPEC):
# маяки и цикл Звездопада, ворота руин и сундук, лестницы смотровых, места
# у костра, связи «за руку», вытягивание из расщелины. Чистая логика без
# узлов — обязательные тесты раздела 18 («маяки, плиты, таймеры, места
# у костра, связь за руку»). Позиции и флаги игроков хост передаёт
# параметрами (из снапшотов), мировые константы — из данных острова.
# Состояние фиксируется словарём state() для world_state и rpc_activity.
class_name ActivityAuthority
extends RefCounted


## Проверка вытягивания из расщелины (раздел 9.1): helper удержал E у точки,
## где висит target. Хост видит флаг «висит» и позиции из снапшотов;
## дистанция допускает пинг (как mob_hit_slack у удара).
func try_pull(
	target: int,
	helper: int,
	world_time: float,
	target_hanging: bool,
	distance: float,
	b: Balance,
) -> Dictionary:
	if not target_hanging or helper == target:
		return {}
	if distance > b.pull_radius + b.mob_hit_slack:
		return {}
	return {"helper": helper, "target": target, "at": world_time}
