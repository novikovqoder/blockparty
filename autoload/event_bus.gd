# Глобальные сигналы для связи сцен и сервисов: сцены не обращаются друг к
# другу напрямую (правило проекта). Сигналы добавляются по мере появления
# механик (снапшоты и мир — П3, кооп и эмоции — П5, «Встречи» — П7).
# Не делает: не содержит никакой логики, только сигналы.
extends Node

# --- Мир (разделы 6, 7, 13) ---

## Локальный игрок вошёл в мир (сцена мира загружена).
signal world_entered()
## Локальный игрок покинул мир; session_time — сколько секунд провёл.
signal world_left(session_time: float)
## Изменилось число монет за текущее пребывание в мире.
signal world_coins_changed(total: int)

# --- Локальный игрок (разделы 5, 9.1) ---

## Игрок упал в расщелину и повис у края; time_left — сколько секунд висит.
signal player_hang_started(time_left: float)
## Оставшееся время висения (каждый тик).
signal player_hang_updated(time_left: float)
## Висение закончилось (перенос к Камню духа; вытягивание другим — П5).
signal player_hang_ended()
## Игрок перенесён на точку возрождения (Камень духа).
signal player_respawned()

# --- Кооп-механики (раздел 9; подтверждает хост) ---

## Хост подтвердил вытягивание: helper вытащил target из расщелины (раздел 9.1).
signal player_pulled(helper_peer: int, target_peer: int)

## «За руку» (раздел 9.5): связь leader ↔ follower включилась или оборвалась
## (F любого из двоих, расстояние больше hand_break_distance, выход из мира).
signal hand_link(leader_peer: int, follower_peer: int, on: bool)

## Игрок предлагает локальному взять его за руку (раздел 9.5): подсказка
## «F — принять» живёт hand_invite_time; согласие и отказ — hand_link/таймер.
signal hand_invite(by_peer: int, by_name: String)

## Занятость мест у костра (раздел 9.6): seats — массив peer по индексам мест
## (0 — свободно). Один сигнал на все изменения: сел, встал, вышел из мира.
signal campfire_seats(seats: Array)

## Игрок показал эмоцию (раздел 9.7): peer — кто, emote — индекс из
## Protocol.Emote, marker — точка маркера «Сюда!» (куда смотрела камера
## отправителя; INF — эмоция без маркера).
signal player_emoted(peer: int, emote: int, marker: Vector3)

## Состояние ворот руин (раздел 9.2): open — открыты, plates — peer на каждой
## плите (0 — пусто), openers — кто открыл плитами (пусто при запасном пути),
## reward_peers — получившие награду сундука (раздел 8), непусто только
## в событии открытия. При закрытии — open=false, остальные списки пусты.
signal ruins_state(open: bool, plates: Array, openers: Array, reward_peers: Array)

## Состояние лестницы смотровой (раздел 9.3): index — номер смотровой,
## active — висит ли, expires_at — время скрытия по world_time (−1 — не висит).
signal ladder_state(index: int, active: bool, expires_at: float)

## Состояние маяков (раздел 7): lit — индексы горящих, lighters — зажёгшие
## последний (для очков и монет; пусто при восстановлении из world_state),
## starfall_started_at — старт идущего Звездопада (−1 — не идёт).
signal beacons_state(lit: Array, lighters: Array, starfall_started_at: float)

## Хост подтвердил подбор звезды Звездопада (раздел 7): index — какая,
## collector_peer — кому монета (0 — восстановление из world_state).
signal star_taken(index: int, collector_peer: int)

## Показать короткое сообщение поверх HUD: ключ i18n («Нужен второй
## игрок» — попытка зажечь маяк в одиночку, раздел 7).
signal toast_requested(key: String)

# --- Взаимодействие E (раздел 9; П5) ---

## Подсказка у интерактивного объекта: ключ i18n действия («E — сесть»);
## пустая строка — рядом ничего нет, панель скрыта.
signal interaction_hint(key: String)
## Прогресс удержания E (0..1); отрицательное значение — удержание не идёт.
signal interaction_progress(fraction: float)

# --- Монеты и мобы (раздел 8; подтверждает хост — раздел 10) ---

## Хост подтвердил подбор монеты: spawn_id — какая, collector_peer — кому
## монеты, respawn_at — время возрождения по world_time.
signal coin_collected(spawn_id: int, collector_peer: int, respawn_at: float)
## Хост подтвердил убийство моба: killers — кому награда (светлячка убивают
## двое), respawn_at — время возрождения по world_time (клиенты оживляют
## моба сами).
signal mob_killed(spawn_id: int, killers: Array, respawn_at: float)
## Хост разослал ослабление светлячка (раздел 8): peer ударил первым,
## until — конец окна уязвимости по world_time.
signal firefly_weakened(spawn_id: int, peer: int, until: float)
## Хост разослал факт подсадки (раздел 13): jumper прыгнул с головы base.
signal player_boosted(base_peer: int, jumper_peer: int)
## Задания жителей (П5.5): хост разослал состояние заданий —
## {quest_id: {stage, done_day, steps, peers}}; stage: 0 доступно,
## 1 идёт, 2 выполнено сегодня.
signal quest_state(state: Dictionary)
## Задание выполнено: peers — участники, coins — монета каждому
## (параллельные массивы; Тимьяну бонус индивидуален), extra — детали
## финала (например, сидящие у костра).
signal quest_reward(quest_id: String, peers: Array, coins: Array, extra: Dictionary)
## Локальный игрок нажал E у жителя — открыть диалог (QuestDialog).
signal quest_talk_requested(quest_id: String)
## Хост прислал полное состояние мира (вход в идущий мир, раздел 10):
## dead_mobs и taken_coins — массивы {spawn_id, respawn_at}.
signal world_state_applied(dead_mobs: Array, taken_coins: Array)

# --- Сеть (раздел 10) ---

## Снапшот чужого игрока (хост переслал после AOI-фильтра).
signal peer_snapshot(peer_id: int, snap: Dictionary, recv_msec: int)
## Игрок вошёл в мир — его персонаж появляется у всех (rpc_player_joined);
## character — номер персонажа из раздела 16, проверенный хостом.
signal peer_joined_world(peer_id: int, player_name: String, character: int)

## Изменился состав участников мира.
signal roster_changed(count: int)
## Участник покинул мир — его персонаж убирается со сцены.
signal peer_left(peer_id: int, player_name: String)
## Хост мира вышел: мир закрывается у всех с сообщением «Хозяин мира вышел».
signal host_lost(reason: String)

# --- Steam (раздел 11) ---

## Лобби-мир Steam подключён и транспорт поднят (хостом или клиентом) —
## можно загружать остров. Dev-режим ENet этим сигналом не пользуется:
## там мир поднимается на старте и входят кнопкой вручную.
signal steam_world_ready()
