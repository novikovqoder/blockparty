# Глобальные сигналы для связи сцен и сервисов: сцены не обращаются друг к другу
# напрямую (правило проекта). Сигналы добавляются по мере появления механик.
# Не делает: не содержит никакой логики, только сигналы.
extends Node

# --- Забег (этап 1) ---

## Пошёл отсчёт перед стартом (3-2-1-GO), длительность — balance.start_countdown_time.
signal run_countdown_started()
## Отсчёт дошёл до нуля, можно управлять персонажем.
signal run_go()
## Забег завершился: finished = дошёл ли этот игрок до финиша, time — время забега, с.
signal run_finished(finished: bool, time: float)

# --- Монеты и мобы (раздел 6; подтверждение даёт хост, этап 1 — локально) ---

## Игрок коснулся монеты и просит её забрать (решает «хост»).
signal coin_pickup_requested(spawn_id: int)
## «Хост» подтвердил подбор монеты — исполнить у себя.
signal coin_picked(spawn_id: int)
## Атака попала по мобу: запрос подтверждения «хосту» (раздел 6, поток попадания).
signal mob_hit_requested(spawn_id: int, run_time: float, from_position: Vector2)
## «Хост» подтвердил смерть моба; killer_id — слот атакующего (этап 2 — peer id).
signal mob_killed(spawn_id: int, killer_id: int)
## Изменилось число монет за забег.
signal run_coins_changed(total: int)

# --- Чекпоинты и пропасти (разделы 5, 7.1) ---

## Игрок пересёк чекпоинт секции index; position — точка возврата.
signal checkpoint_reached(index: int, position: Vector2)
## Игрок упал в пропасть и повис (до таймаута или «Сдаться»).
signal hang_started()
## Игрок вернулся на чекпоинт после «Висит».
signal hang_ended()

# --- Финиш (раздел 7.6) ---

## Игрок пересёк финишную черту.
signal player_finished(run_time: float)
