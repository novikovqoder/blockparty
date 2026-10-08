# Числа геймплея (разделы 5, 13 SPEC): движение персонажа, камера, подсадка
# на голову, удар, очки взаимодействий. Все числа геймплея живут здесь
# (правило проекта), сетевые — в net/protocol.gd. Единицы: метры и секунды.
# Заполняется по этапам: мир, мобы и монеты — П2, кооп-механики — П5.
class_name Balance
extends Resource

@export_group("Персонаж (раздел 5)")
## Бег, м/с.
@export var run_speed: float = 6.5
## Шаг (Shift), м/с.
@export var walk_speed: float = 2.5
## Ускорение на земле, м/с².
@export var acceleration: float = 40.0
## Торможение на земле, м/с².
@export var deceleration: float = 50.0
## Доля ускорения в воздухе.
@export var air_control: float = 0.6
## Скорость прыжка, м/с (высота ~1.4 м: на один блок да, на два — нет).
@export var jump_speed: float = 7.5
## Гравитация, м/с².
@export var gravity: float = 20.0
## Множитель гравитации при падении.
@export var fall_gravity_mult: float = 1.3
## Предел скорости падения, м/с.
@export var max_fall_speed: float = 30.0
## Coyote time, с.
@export var coyote_time: float = 0.1
## Буфер прыжка, с.
@export var jump_buffer_time: float = 0.1
## Отпускание прыжка режет вертикальную скорость до этой доли.
@export var jump_cut_factor: float = 0.5
## Автоподъём на ступеньку (полублоки), м.
@export var step_up_height: float = 0.55
## Поворот модели к направлению движения, рад/с.
@export var model_turn_speed: float = 12.0
## Капсула персонажа: радиус и высота, м.
@export var body_radius: float = 0.35
@export var body_height: float = 1.6

@export_group("Камера (раздел 5)")
## Длина SpringArm3D за спиной и пределы колесом мыши, м.
@export var camera_length: float = 6.0
@export var camera_length_min: float = 3.0
@export var camera_length_max: float = 10.0
## Наклон камеры, пределы в градусах (−60 … +35).
@export var camera_pitch_min_deg: float = -60.0
@export var camera_pitch_max_deg: float = 35.0
## Скорость мягкого следования за персонажем (экспоненциальное сглаживание).
@export var camera_follow_speed: float = 10.0

@export_group("Подсадка на голову (раздел 5)")
## Коллайдер головы на макушке: плоский бокс, отдельный физический слой.
@export var head_box_size: Vector3 = Vector3(0.6, 0.1, 0.6)
## Усиление прыжка с головы другого игрока (хватает на уступ в 3 блока).
@export var head_jump_boost: float = 1.3
## Допуск для условия «ступни выше верхней грани бокса», м (кадр контакта).
@export var head_stand_epsilon: float = 0.05

@export_group("Расщелина: состояние «Висит» (раздел 9.1)")
## Сколько секунд упавший висит у края без помощи, с.
@export var hang_time: float = 10.0

@export_group("Расщелина: вытягивание (раздел 9.1)")
## Радиус от точки HangPoint, в котором работает помощь, м.
@export var pull_radius: float = 1.5
## Удержание E для вытягивания, с (Сила помощника делит на множитель).
@export var pull_hold_time: float = 0.5
## Монет помощнику за вытягивание (раздел 8: «помощь из расщелины — 3»).
@export var pull_reward: int = 3

@export_group("Характеристики: Сила (разделы 16, 17)")
## Множители скорости кооп-действий для Силы 1–5 (индекс = значение − 1):
## вытягивание быстрее у сильных, но любой персонаж может всё.
@export var strength_multipliers: PackedFloat32Array = [0.6, 0.72, 0.85, 1.0, 1.2]
## Множитель усиления прыжка с головы для Силы 1–5: «чуть больше высоты
## подсадки» (раздел 17), чем сильнее прыгающий, тем выше подъём.
@export var strength_head_boost: PackedFloat32Array = [0.95, 0.975, 1.0, 1.03, 1.06]

@export_group("Ворота руин и сундук (разделы 8, 9.2)")
## Радиус нажимной плиты: игрок «стоит на плите» в нём по горизонтали, м.
@export var plate_radius: float = 0.9
## Окно высоты стоящего на плите (плита y ± это), м.
@export var plate_height_window: float = 1.2
## Запасной путь одиночки: сколько секунд любой игрок стоит у закрытых
## ворот, чтобы они открылись сами, с.
@export var gate_open_wait: float = 60.0
## Радиус зоны «у ворот» для запасного пути, м.
@export var gate_near_radius: float = 4.5
## Открытые ворота и сундук сбрасываются через это время, с (раздел 8: 10 мин).
@export var gate_reset_sec: float = 600.0
## Монет из сундука каждому игроку в радиусе chest_radius в момент открытия.
@export var chest_reward: int = 10
## Радиус награды сундука, м.
@export var chest_radius: float = 10.0
## Период проверки активностей хостом (плиты, зоны), с.
@export var activity_tick: float = 0.1

@export_group("Смотровые уступы (раздел 9.3)")
## Сколько висит верёвочная лестница после сброса, с.
@export var ladder_time: float = 60.0
## Проверка хоста «поднявшийся»: высота игрока над площадкой, м (допуск).
@export var ladder_top_window: float = 1.2
## Радиус от центра смотровой для «поднявшийся», м.
@export var ladder_top_radius: float = 3.5

@export_group("Маяки и Звездопад (раздел 7)")
## Окно между нажатиями E двух разных игроков, зажигающими маяк, с.
@export var beacon_pair_window: float = 3.0
## Запасной путь при малом онлайне: удержание E в одиночку, с.
@export var beacon_solo_hold: float = 8.0
## Монет каждому из зажёгших маяк (раздел 8: «зажигание маяка — 3»).
@export var beacon_reward: int = 3
## Проверка хоста «у маяка»: окно высоты игрока над узлом, м.
@export var beacon_use_window: float = 3.0
## Длительность Звездопада (все 5 маяков зажжены), с.
@export var starfall_duration: float = 120.0
## Новая звезда падает каждые столько секунд.
@export var star_interval: float = 1.5
## Падение звезды с высоты star_spawn_height до земли, с.
@export var star_fall_time: float = 6.0
## Звезда лежит на земле и исчезает через столько секунд после рождения
## (падение + лежание; хватать надо успеть).
@export var star_lifetime: float = 12.0
## Высота, с которой падают звёзды, м.
@export var star_spawn_height: float = 35.0
## Монет за звезду Звездопада (раздел 8).
@export var star_reward: int = 1
## Маяки гаснут через столько секунд после конца Звездопада, с (15 мин).
@export var beacon_reset_sec: float = 900.0

@export_group("Характеристики персонажа (раздел 16)")
## Множители бега/высоты прыжка для значений характеристик 1–5 (индекс =
## значение − 1): влияние мягкое, ±10% между крайними персонажами.
## Скорость прыжка умножается на корень множителя (высота ∝ v²).
@export var stat_multipliers: PackedFloat32Array = [0.90, 0.95, 1.00, 1.05, 1.10]

@export_group("Удар (раздел 5)")
## Зона взмаха перед персонажем, м.
@export var attack_box_size: Vector3 = Vector3(1.2, 1.0, 1.2)
## Зона активна, с.
@export var attack_active_time: float = 0.12
## Перезарядка, с.
@export var attack_cooldown: float = 0.35
## Длительность реакции «тычок» у получившего удар игрока, с.
@export var bonk_time: float = 0.4
## Длительность взмаха «Привет!» (клавиша 1; клип KayKit Waving ≈2.1 с), с.
@export var wave_time: float = 2.0

@export_group("Вода (раздел 6)")
## Скорость движения в воде — шаг (раздел 6), м/с.
@export var swim_speed: float = 2.5
## Насколько тело погружено при плавании на поверхности (0 — по щиколотку), м.
@export var swim_submerge: float = 0.7
## Жёсткость всплытия к поверхности (скорость = отклонение × жёсткость).
@export var swim_buoyancy: float = 5.0
## Предел вертикальной скорости в воде, м/с.
@export var swim_vertical_speed: float = 2.5

@export_group("Камера: мышь (раздел 5)")
## Базовая чувствительность мыши, рад на пиксель (умножается на настройку).
@export var mouse_base_sensitivity: float = 0.0032

@export_group("Мир: цикл дня и графика (разделы 6, 7, 15)")
## Длина суток, с (раздел 7: 20 минут).
@export var day_cycle_sec: float = 1200.0
## Доля суток, когда солнце над горизонтом (день 60% / ночь 40%).
@export var day_share: float = 0.6
## Максимальный угол солнца над горизонтом, рад.
@export var sun_max_elevation: float = deg_to_rad(62.0)
## Размах азимута солнца за день (± рад от юга).
@export var sun_azimuth_swing: float = deg_to_rad(55.0)
## Энергия солнца в полдень (П1: 0.3 — «без пересвета»).
@export var sun_energy_noon: float = 0.3
## Часы мира на входе в мир, с (раздел 7): солнечное утро, а не рассвет —
## на рассвете солнце у горизонта и земля под ногами едва различима
## («пропавшая земля», шаг 1 П4.5).
@export var day_start_sec: float = 180.0
## Дальность видимости камеры, м (обычная / «Простая графика», раздел 15).
@export var view_distance: float = 160.0
@export var view_distance_simple: float = 70.0
## Плотность тумана (раздел 7): обычная / «Простая графика» (плотнее — мир
## меньше кажется, слабее видно дальние холмы). 0.006 на рассвете превращала
## ближний рельеф в «молочную пелену» (шаг 1 П4.5): дымка теперь мягче,
## читается у горизонта, земля под ногами чистая.
@export var fog_density: float = 0.0025
@export var fog_density_simple: float = 0.008
## Дымка по высоте (раздел 16: «низины и расщелина в дымке»): базовая
## высота тумана, м, и плотность высотного тумана (0 — ровный туман).
@export var fog_height_m: float = 0.6
@export var fog_height_density: float = 0.05

@export_group("Сеть: авторитет хоста (разделы 8, 10)")
## Дистанция удара по мобу, которую проверяет хост, м (раздел 8).
@export var mob_hit_distance: float = 2.5
## Допуск к дистанции удара на пинг (снапшот убийцы устарел на RTT), м.
@export var mob_hit_slack: float = 1.5

@export_group("Мобы (раздел 8)")
## Возрождение убитого моба, с (светлячок — отдельно).
@export var mob_respawn_sec: float = 180.0
## Возрождение золотого светлячка, с.
@export var firefly_respawn_sec: float = 300.0
## Монет за птицу / зверька (по одному удару).
@export var bird_reward: int = 1
@export var critter_reward: int = 1
## Золотой светлячок «на двоих» (раздел 8): окно между ударами двух
## разных игроков, с.
@export var firefly_window: float = 3.0
## Монет каждому из двоих, убивших светлячка.
@export var firefly_reward: int = 8

@export_group("Монеты острова (раздел 8)")
## Статичных монет на острове (SPEC: ровно 60 — тест).
@export var static_coins: int = 60
## Возрождение собранной монеты, с.
@export var coin_respawn_sec: float = 300.0
## Монет за монету острова.
@export var coin_reward: int = 1

@export_group("Боты (раздел 18: бродят между POI и иногда прыгают)")
## Пауза бота на точке интереса перед следующей целью, с.
@export var bot_poi_pause: float = 2.0
## Скорость поворота камеры бота к цели, рад/с.
@export var bot_turn_speed: float = 3.0
## Шанс прыжка в секунду на ходу (0 — никогда).
@export var bot_jump_chance_per_sec: float = 0.25
## Радиус атаки мобов ботом, м (0 — не атакует).
@export var bot_attack_radius: float = 2.2
## Секунд без прогресса до прыжка/смены цели (застрял у склона/дерева).
@export var bot_stuck_time: float = 4.0
## Дойти до цели считается на этом расстоянии, м.
@export var bot_arrive_radius: float = 2.0
## Сколько секунд бот держит кнопку прыжка (полная высота).
@export var bot_jump_hold: float = 0.25

@export_group("Взаимодействия (раздел 13)")
## Радиус «секунды рядом», м (раздел 13: до 8 м).
@export var proximity_m: float = 8.0
## Секунда рядом и лимит за сессию.
@export var pts_proximity: float = 0.05
@export var pts_proximity_max: float = 20.0
## Секунда его голоса и лимит.
@export var pts_voice_heard: float = 0.3
@export var pts_voice_heard_max: float = 25.0
## Вытянул меня / я вытянул его (одно число на оба вида).
@export var pts_pull: float = 10.0
## Каждые 30 с за руку и лимит.
@export var pts_hand_held: float = 4.0
@export var pts_hand_held_max: float = 16.0
## Каждые 30 с у костра и лимит.
@export var pts_campfire: float = 3.0
@export var pts_campfire_max: float = 12.0
## Вместе зажгли маяк.
@export var pts_beacon_lit: float = 6.0
## Вместе открыли ворота руин.
@export var pts_gate_open: float = 6.0
## Подсадил меня / я подсадил его.
@export var pts_boost: float = 5.0
## Вместе поймали золотого светлячка.
@export var pts_firefly: float = 6.0
## Ответная эмоция в течение 5 с и лимит.
@export var pts_emote_reply: float = 2.0
@export var pts_emote_reply_max: float = 6.0
