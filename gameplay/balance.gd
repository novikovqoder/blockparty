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

@export_group("Удар (раздел 5)")
## Зона взмаха перед персонажем, м.
@export var attack_box_size: Vector3 = Vector3(1.2, 1.0, 1.2)
## Зона активна, с.
@export var attack_active_time: float = 0.12
## Перезарядка, с.
@export var attack_cooldown: float = 0.35
## Длительность реакции «тычок» у получившего удар игрока, с.
@export var bonk_time: float = 0.4

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

@export_group("Взаимодействия (раздел 13)")
## Секунда рядом (до 8 м) и лимит за сессию.
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
