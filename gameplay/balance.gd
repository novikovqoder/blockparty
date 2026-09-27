# Все числовые параметры геймплея (правило проекта). Значения — стартовые
# из разделов 4–6 SPEC, финальная подстройка — на плейтестах.
# Экземпляр с данными: gameplay/balance.tres; доступ из кода —
# `const B: Balance = preload("res://gameplay/balance.tres")`.
# Не делает: не содержит сетевых констант (они в net/protocol.gd, этап 2).
class_name Balance
extends Resource

@export_group("Движение (раздел 4)")
## Максимальная скорость бега, px/с.
@export var run_speed: float = 260.0
## Ускорение на земле, px/с².
@export var accel_ground: float = 1800.0
## Торможение на земле, px/с².
@export var friction_ground: float = 2200.0
## Доля наземного ускорения/торможения, доступная в воздухе.
@export var air_control: float = 0.7
## Импульс скорости прыжка, px/с.
@export var jump_speed: float = 520.0
## Гравитация при движении вверх, px/с².
@export var gravity: float = 1400.0
## Множитель гравитации при падении.
@export var gravity_fall_multiplier: float = 1.4
## Максимальная скорость падения, px/с.
@export var max_fall_speed: float = 900.0
## Coyote time: сколько секунд после схода с края ещё можно прыгнуть.
@export var coyote_time: float = 0.10
## Буфер прыжка: нажатие раньше приземления срабатывает после него.
@export var jump_buffer_time: float = 0.10
## Доля вертикальной скорости при отпускании кнопки прыжка (переменная высота).
@export var jump_cut_factor: float = 0.45
## Хитбокс персонажа, px.
@export var hitbox_width: float = 28.0
@export var hitbox_height: float = 44.0
## Множитель скорости прыжка с головы другого игрока (механика «ступенька»).
@export var head_jump_bonus: float = 1.25

@export_group("Атака (раздел 4)")
## Хитбокс удара перед персонажем, px.
@export var attack_width: float = 40.0
@export var attack_height: float = 32.0
## Сколько секунд хитбокс удара активен.
@export var attack_active_time: float = 0.12
## Перезарядка между ударами, с.
@export var attack_cooldown: float = 0.35

@export_group("Урон и отталкивание (раздел 4, 6)")
## Длительность неуязвимости после шипов/кактуса, с.
@export var hit_invuln_time: float = 1.0
## Горизонтальное отталкивание от шипов и кактусов, px/с.
@export var hazard_knockback_x: float = 300.0
## Вертикальная составляющая отталкивания, px/с.
@export var hazard_knockback_y: float = 220.0
## Отталкивание от моба при касании, px/с (урона нет).
@export var mob_push_speed: float = 260.0
## Мигание персонажа после урона, с.
@export var hit_blink_time: float = 1.0

@export_group("Состояние «Висит» (раздел 5, 7.1)")
## Сколько секунд игрок висит у края пропасти без помощи, с.
@export var hang_time: float = 8.0
## Смещение висящего игрока от точки HangPoint, px (висит ниже края).
@export var hang_offset_y: float = 14.0

@export_group("Забег (разделы 5, 7.6)")
## Жёсткий лимит забега, с.
@export var run_time_limit: float = 600.0
## За сколько секунд до конца забега HUD показывает таймер, с.
@export var timer_visible_last: float = 120.0
## Отсчёт перед стартом (3-2-1-GO), с (раздел 8).
@export var start_countdown_time: float = 3.0
## Отсчёт после первого финиша, с: забег заканчивается, когда время истекло
## или финишировали все (раздел 7.6).
@export var finish_wait_time: float = 90.0

@export_group("Мобы и монеты (раздел 6)")
## Ударов до смерти: птица, зверёк, золотая цель.
@export var bird_hits_to_die: int = 1
@export var critter_hits_to_die: int = 1
@export var golden_hits_to_die: int = 2
## Монет за убийство птицы/зверька.
@export var mob_kill_coins: int = 1
## Монет каждому за золотую цель (этап 3).
@export var golden_kill_coins: int = 10
## Номинал подобранной монеты.
@export var coin_value: int = 1
## Монет за помощь из пропасти (этап 3).
@export var pull_up_coins: int = 3
## Монет каждому за кооп-ворота (этап 3).
@export var gate_coins: int = 2
## Монет за финиш.
@export var finish_coins: int = 5
## Радиус, в котором «хост» признаёт попадание атакующего по мобу, px (раздел 6).
@export var hit_accept_range: float = 96.0

@export_group("Камера (раздел 4)")
## Опережение камеры по направлению бега, px.
@export var camera_lead: float = 96.0
## Скорость сглаживания камеры.
@export var camera_smoothing: float = 8.0

@export_group("Бот (раздел 3, --bot)")
## Дальность взгляда вперёд: стена ближе — прыжок, px.
@export var bot_look_ahead: float = 48.0
## Глубина луча под ногами впереди: достаёт и до пола на 160 ниже (сброс
## с уступа кооп-секции), под настоящей пропастью пусто, px.
@export var bot_gap_depth: float = 220.0
## Смещение дальнего луча пропасти: если и тут пола нет — пропасть шире
## прыжка, бот ждёт движущуюся платформу (узкие пропасти 128 px этот луч
## перебрасывает), px.
@export var bot_gap_far_x: float = 170.0
## Высота луча-детектора платформы над центром персонажа (платформы выше
## центра тела), px.
@export var bot_platform_cast_y: float = -40.0
## Смещение лучей от центра персонажа, px.
@export var bot_cast_offset_x: float = 24.0
## Дальность атаки по мобу впереди, px.
@export var bot_attack_range: float = 64.0
## Сколько стоять на месте, чтобы прыгнуть от безысходности, с.
@export var bot_stuck_time: float = 0.6
## Сколько держать кнопку прыжка (полная высота), с.
@export var bot_jump_hold: float = 0.25
## Сдаться в «Висит» через это время (раньше таймаута 8 с), с.
@export var bot_hang_give_up: float = 1.0
