# Глобальные сигналы для связи сцен и сервисов: сцены не обращаются друг к другу
# напрямую (правило проекта). Сигналы добавляются по мере появления механик.
# Не делает: не содержит никакой логики, только сигналы.
extends Node

# --- Забег (разделы 5, 8) ---

## Пошёл отсчёт перед стартом (3-2-1-GO), длительность — balance.start_countdown_time.
signal run_countdown_started()
## Хост назначил время GO (rpc_go): можно показывать синхронный отсчёт.
signal run_go_scheduled()
## Отсчёт дошёл до нуля, можно управлять персонажем.
signal run_go()
## Забег завершился: finished = дошёл ли этот игрок до финиша, time — время забега, с.
signal run_finished(finished: bool, time: float)

# --- Сеть (раздел 8) ---

## Изменился состав участников (подключение/отключение/старт).
signal roster_changed(count: int)
## Участник вышел из забега — его персонаж убирается со сцены.
signal peer_left(peer_id: int)
## Связь с хостом потеряна (раздел 8: хост отключился).
signal host_lost(reason: String)

# --- Монеты и мобы (раздел 6; подтверждение даёт хост) ---

## Игрок коснулся монеты и просит её забрать (решает хост).
signal coin_pickup_requested(spawn_id: int)
## Хост подтвердил подбор монеты — победителю; исполнить у себя.
signal coin_picked(spawn_id: int, winner_peer: int)
## Атака попала по мобу: запрос подтверждения хосту (раздел 6, поток попадания).
signal mob_hit_requested(spawn_id: int, run_time: float, from_position: Vector2)
## Хост подтвердил смерть моба; killer_ids — участники, кому положена награда.
signal mob_killed(spawn_id: int, killer_ids: Array[int])
## Изменилось число монет за забег.
signal run_coins_changed(total: int)

# --- Чекпоинты и пропасти (разделы 5, 7.1) ---

## Игрок пересёк чекпоинт секции index; position — точка возврата.
signal checkpoint_reached(index: int, position: Vector2)
## Игрок упал в пропасть и повис (до таймаута или «Сдаться»).
signal hang_started()
## Игрок вышел из «Висит» (кнопка или таймаут 8 с) — хост подтвердит возврат.
signal hang_ended()
## Хост подтвердил возврат игрока на чекпоинт (rpc_respawn) — телепорт.
signal player_respawned(position: Vector2)

# --- Финиш (раздел 7.6) ---

## Игрок пересёк финишную черту.
signal player_finished(run_time: float)
