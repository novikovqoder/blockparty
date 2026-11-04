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

@export_group("Расщелина: состояние «Висит» (раздел 9.1)")
## Сколько секунд упавший висит у края без помощи, с.
@export var hang_time: float = 10.0

## Период проверки активностей хостом (лестницы), с.
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

@export_group("Частицы шагов (переделка П9)")
## Порог «стопа на земле» в пространстве скелета героя BU, м: пересечение
## вниз = касание = шаг (замер по клипам loco_*: контакт 0.05–0.08).
@export var footfx_contact_y: float = 0.09
## Выше этой высоты стопа считается улетевшей в замах — детектор взводится.
@export var footfx_release_y: float = 0.14
## Бег, трава: травинок/обрывков листа на шаг (таблица владельца 2–4).
@export var footfx_grass_run: Vector2i = Vector2i(2, 4)
## Бег, грязь/сырая земля/лужа: капель или крошек на шаг (таблица 2–5).
@export var footfx_mud_run: Vector2i = Vector2i(2, 5)
## Бег, земля/тропа: крупинок на шаг (таблица 1–3).
@export var footfx_dirt_run: Vector2i = Vector2i(1, 3)
## Шагом (не бегом): максимум частиц на шаг — «почти ничего»; на земле
## и траве можно 0 (земля — 0).
@export var footfx_grass_walk: int = 1
@export var footfx_mud_walk: int = 1
@export var footfx_dirt_walk: int = 0
## Облачко пыли на шаге по земле (бег/приземление), спрайтов; альфа —
## footfx_alpha_dust, «едва видное».
@export var footfx_dust_count: int = 2
## Прыжок и приземление: порция «чуть больше обычной», множитель.
@export var footfx_burst_mult: float = 1.5
## Стороны спрайтов, м (требование: все частицы 0,5–3 см): травинка,
## крошка грязи, крупинка земли, капля воды, пылинка.
@export var footfx_size_blade: float = 0.03
@export var footfx_size_crumb: float = 0.015
@export var footfx_size_grain: float = 0.008
@export var footfx_size_drop: float = 0.01
@export var footfx_size_dust: float = 0.03
## Предел размера любой частицы, м (тест сверяет каждый квад).
@export var footfx_size_max: float = 0.03
## Жизнь частиц, с (требование 0,3–0,7): твёрдые / пылинка.
@export var footfx_life_solid: float = 0.55
@export var footfx_life_dust: float = 0.35
## Прозрачность (пределы 0,6 и 0,25): твёрдые / пылинка.
@export var footfx_alpha_solid: float = 0.55
@export var footfx_alpha_dust: float = 0.25
## Затемнение цвета поверхности для цвета частиц.
@export var footfx_color_darken: float = 0.45
## Скорость вылета из-под стопы, м/с (мин/макс): грязь при −9 м/с² даёт
## подлёт до ~10 см («летят невысоко и падают»).
@export var footfx_pop_speed: Vector2 = Vector2(0.35, 1.3)
## Гравитация твёрдых частиц, м/с² (травинки чуть легче — падают медленно).
@export var footfx_gravity_solid: float = 9.0
@export var footfx_gravity_blade: float = 6.0
## Чужие игроки дальше этого расстояния — эффект выключен, м.
@export var footfx_remote_range: float = 15.0
