# Числа геймплея (разделы 5, 13 SPEC): движение персонажа, камера, подсадка
# на голову, удар, очки взаимодействий. Все числа геймплея живут здесь
# (правило проекта), сетевые — в net/protocol.gd. Единицы: метры и секунды.
# Заполняется по этапам: мир и мобы — П2, кооп-механики — П5.
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
## Автоподъём на ступеньку, м (доработка-2 П5.13, П2: ~0.3 м — ступени
## лестниц смотровых 0.3 м проходят с запасом, всё выше — только прыжком).
@export var step_up_height: float = 0.33
## Ходьба по склонам (доработка-2 П5.13, П2): максимальный уклон, при
## котором поверхность ещё пол, °. 54° — с запасом над худшими диагоналями
## холмов (~52°); кромки террас, стенки расщелины и отвесные скалы круче —
## остаются стенами, пешеходом не проходимы.
@export var walk_max_slope_deg: float = 54.0
## Привязка к поверхности: прилипание к полу при спуске и на гребнях, м
## (не даёт подпрыгивать на рёбрах рельефа).
@export var floor_snap_length: float = 0.3
## Предел компенсации скорости на склоне: во сколько раз можно усилить
## тягу вверх по склону, чтобы подъём не замедлялся (1/cos²θ; 3.0 покрывает
## все проходимые углы, у стен отсекает неверные нормали).
@export var slope_speed_comp_max: float = 3.0
## Предел вертикальной составляющей тяги в гору, м/с: бег по крутым
## проходимым склонам поднимает персонажа со скоростью v·tanθ (на 54° —
## почти 9 м/с, как прыжок); выше этого предела тяга срезается — подъём
## чуть медленнее полной скорости, но вертикаль не прыжковая.
@export var slope_climb_vy_max: float = 5.0
## Поворот модели к направлению движения, рад/с.
@export var model_turn_speed: float = 12.0
## Порог «почти стоит» для анимаций, м/с (Д2: покой — только при ≈0).
@export var anim_idle_speed: float = 0.3
## Выше этой скорости снапшот несёт состояние бега (клип внутри —
## Walk/Jog/Sprint — модель выбирает по фактической скорости, Д3), м/с.
@export var anim_walk_run_speed: float = 4.5
## Приземление после прыжка, с (Д2: короткое, сразу локомоция по скорости).
@export var land_time: float = 0.2
## Капсула персонажа: радиус и высота, м (герой BU — рост 1,8, П10).
@export var body_radius: float = 0.35
@export var body_height: float = 1.8

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
## Удержание E для вытягивания, с — базовое для всех (характеристики
## убраны, П5.8 часть D: игроки равны).
@export var pull_hold_time: float = 0.5

@export_group("За руку (раздел 9.5)")
## Радиус, в котором F берёт ближайшего игрока за руку, м.
@export var hand_link_radius: float = 2.0
## Сколько секунд у приглашённого действует подсказка «F — принять», с.
@export var hand_invite_time: float = 5.0
## Связь рвётся сама при большем расстоянии между парой, м.
@export var hand_break_distance: float = 4.0
## Ведомый держится на этом расстоянии позади-сбоку ведущего, м.
@export var hand_follow_distance: float = 1.0
## Жёсткость следования ведомого (скорость = отклонение × жёсткость).
@export var hand_follow_gain: float = 10.0
## Предел скорости следования ведомого, м/с.
@export var hand_follow_speed: float = 7.0
## Максимум людей в цепочке («C держит B, B держит A», раздел 9.5).
@export var hand_chain_max: int = 4

@export_group("Места у костра (раздел 9.6)")
## Проверка хоста «игрок у лавки»: расстояние по горизонтали до места, м.
@export var campfire_seat_radius: float = 3.0
## Окно высоты проверки «у лавки» (лавка на возвышении площади), м.
@export var campfire_use_window: float = 1.5
## На сколько ниже узла места (верх лавки) сидит origin игрока, м:
## Поза сидя (Sitting_Idle) считается от пола, лавки генератора — выше.
@export var campfire_seat_floor: float = 0.45
## Скольких сидящих огонь принимает за «компанию» (разгорается), раздел 9.6.
@export var campfire_company_size: int = 2

@export_group("Эмоции (раздел 9.7)")
## Пузырь фразы над головой, с.
@export var emote_bubble_time: float = 2.5
## Перезарядка между эмоциями, с.
@export var emote_cooldown: float = 1.0
## Маркер «Сюда!» и стрелка «Помогите!», с.
@export var emote_marker_time: float = 5.0
## «Сюда!» ставит маркер в точку, куда смотрит камера (луч до этой длины), м.
@export var emote_marker_range: float = 30.0
## Пузырь виден в этом радиусе, м («Помогите!» дальше — стрелка, раздел 9.1).
@export var emote_bubble_range: float = 40.0
@export var emote_help_range: float = 60.0

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
## Период проверки активностей хостом (плиты, зоны), с.
@export var activity_tick: float = 0.1

@export_group("Смотровые уступы (раздел 9.3)")
## Сколько висит верёвочная лестница после сброса, с.
@export var ladder_time: float = 60.0
## Проверка хоста «поднявшийся»: высота игрока над площадкой, м (допуск).
@export var ladder_top_window: float = 1.2
## Радиус от центра смотровой для «поднявшийся», м.
@export var ladder_top_radius: float = 3.5

@export_group("Удар (раздел 5)")
## Зона взмаха перед персонажем, м.
@export var attack_box_size: Vector3 = Vector3(1.2, 1.0, 1.2)
## Зона активна, с.
@export var attack_active_time: float = 0.12
## Перезарядка, с.
@export var attack_cooldown: float = 0.35
## Длительность реакции «тычок» у получившего удар игрока, с.
@export var bonk_time: float = 0.4
## Длительность взмаха «Привет!» (клавиша 1; клип Wave_Hand ≈2.5 с), с.
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
## Энергия луны в полночь (П5.9 блок 6: Sky3D): мягкая синеватая подсветка
## ночи, при которой читаются силуэты (раздел 7 «мягкая светлая ночь»).
@export var moon_energy_night: float = 0.22
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
## читается у горизонта, земля под ногами чистая. Доработка П5.9 под эталон
## («небольшой туман»): 0.0035 — лёгкая воздушная перспектива на дальних
## склонах при чистой земле под ногами; основная дымка Леса — сгусток зоны.
@export var fog_density: float = 0.0035
@export var fog_density_simple: float = 0.008
## Дымка по высоте (раздел 16: «низины и расщелина в дымке»): базовая
## высота тумана, м, и плотность высотного тумана (0 — ровный туман).
@export var fog_height_m: float = 0.6
@export var fog_height_density: float = 0.05

@export_group("Сеть: авторитет хоста (разделы 9, 10)")
## Допуск проверяемых хостом дистанций на пинг (снапшот игрока устарел
## на RTT): посадка у костра, руки, вытягивание. М (в доработке П5.13
## переименован из mob_hit_slack — мобы удалены).
@export var ping_slack: float = 1.5

@export_group("Боты (раздел 18: бродят между POI и иногда прыгают)")
## Пауза бота на точке интереса перед следующей целью, с.
@export var bot_poi_pause: float = 2.0
## Скорость поворота камеры бота к цели, рад/с.
@export var bot_turn_speed: float = 3.0
## Шанс прыжка в секунду на ходу (0 — никогда).
@export var bot_jump_chance_per_sec: float = 0.25
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
## Вместе открыли ворота руин.
@export var pts_gate_open: float = 6.0
## Подсадил меня / я подсадил его.
@export var pts_boost: float = 5.0
## Ответная эмоция в течение 5 с и лимит.
@export var pts_emote_reply: float = 2.0
@export var pts_emote_reply_max: float = 6.0

@export_group("Частицы бега (доработка П9)")
## Максимум частиц у ног при полном беге; шаг эмитит долю от этого
## (кривая RunParticles.intensity: покой — 0, бег — 1, шаг — ≈0.2).
@export var run_dust_amount: int = 26
## Жизнь комка, с.
@export var run_dust_lifetime: float = 0.45
## Сторона спрайта-комка, м (травинка — 0.7 от этого).
@export var run_dust_size: float = 0.08
## Скорость вылета из-под ног, м/с.
@export var run_dust_speed: float = 1.1
## Разброс вылета, °.
@export var run_dust_spread_deg: float = 40.0
