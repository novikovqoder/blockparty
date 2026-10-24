# Скелетные анимации персонажей (П5.7, блок 5 → П5.8, часть C): клипы
# Quaternius Universal Animation Library 1/2 (CC0 — assets/third_party/
# LICENSES.md), запечённые tools/make_ubc_anims.gd в anims_ubc.res на риг
# Universal Base Characters (65 костей). Линейки Quaternius Universal
# делят риг с UBC, треки записаны путями «Armature/Skeleton3D:<кость>» —
# одна библиотека работает на ubc_male и ubc_female, при загрузке ничего
# не пересобирается (loop-режимы выставлены при запечке). Клипы без
# аналога в UAL Standard (взмах, «Помогите!», вис у кромки, «за руку»)
# сгенерированы процедурно поверх rest/запечённых баз — честная запись
# в docs/STATUS.md (раздел 16). Состояние Protocol.AnimState → клип —
# полный список клипов UAL и маппинг в docs/STATUS.md.
class_name CharacterAnims
extends RefCounted

## Запечённая библиотека клипов UAL на риге UBC (ресурс, не glb).
const LIB_PATH: String = "res://assets/third_party/quaternius.com/" \
	+ "universal_animation_library/anims_ubc.res"

## Имя библиотеки внутри AnimationPlayer моделей персонажей.
const LIB_NAME: StringName = &"ubc"

## Состояние аниматора (раздел 5) → клип UAL (после ретаргетинга).
const STATE_CLIPS: Dictionary = {
	Protocol.AnimState.IDLE: &"Idle",
	Protocol.AnimState.WALK: &"Walk",
	Protocol.AnimState.RUN: &"Sprint",
	Protocol.AnimState.JUMP: &"Jump_Start",
	Protocol.AnimState.FALL: &"NinjaJump_Idle",
	Protocol.AnimState.LAND: &"Jump_Land",
	Protocol.AnimState.BONK: &"Hit_Chest",
	Protocol.AnimState.HANG: &"Hang_Pose",
	Protocol.AnimState.SIT: &"Sitting_Idle",
	Protocol.AnimState.WAVE: &"Wave_Hand",
}

## Циклические состояния (покой, перемещение, полёт, сидение);
## остальное — разовые, CharacterModel.play_one_shot возвращает состояние
## по таймеру. Соответствует LOOP_CLIPS запечки (loop_mode уже в .res).
## Кооп-состояния Blockparty (PULLED_UP, HELP_PULL, HOLD_HAND) удалены
## с наследием (born-unblessed) — в enum остались мёртвыми.
const LOOP_STATES: Array[int] = [
	Protocol.AnimState.IDLE,
	Protocol.AnimState.WALK,
	Protocol.AnimState.RUN,
	Protocol.AnimState.FALL,
	Protocol.AnimState.HANG,
	Protocol.AnimState.SIT,
]

static var _library: AnimationLibrary = null


## Общая библиотека «ubc»: запечённый ресурс со всеми клипами и
## loop-режимами; загрузка один раз на процесс, playback клипы не мутирует.
static func library() -> AnimationLibrary:
	if _library == null:
		_library = load(LIB_PATH) as AnimationLibrary
		assert(_library != null, "нет %s" % LIB_PATH)
	return _library


## Клип состояния по номеру Protocol.AnimState.
static func clip_for_state(state: int) -> StringName:
	return STATE_CLIPS.get(state, &"")


## Циклическое ли состояние (клип зациклен).
static func is_loop(state: int) -> bool:
	return LOOP_STATES.has(state)


# --- Локомоция по фактической скорости (Д3: ноги успевают за телом) ---

## Естественная скорость локомоционных клипов, м/с — скорость обратного
## хода стопы в фазе опоры (замер tools/probe_clip_speed.gd). Темп клипа
## speed_scale = фактическая скорость / natural: стопы не скользят.
## Walk_Hand — «за руку», темп по более медленному из пары (player.gd).
const NATURAL_SPEED: Dictionary = {
	&"Walk": 0.95,
	&"Jog_Fwd": 2.96,
	&"Sprint": 4.36,
	&"Walk_Hand": 0.96,
}
## Пределы темпа: ниже — шаг замирает на месте, выше — мельтешение.
const SPEED_SCALE_MIN: float = 0.55
const SPEED_SCALE_MAX: float = 1.7
## Клипы бега/ходьбы по возрастанию natural (выбор по скорости).
const LOCO_CLIPS: Array[StringName] = [&"Walk", &"Jog_Fwd", &"Sprint"]


## Естественная скорость клипа, м/с (1.0 — «не знаем», темп не менять).
static func natural_speed(clip: StringName) -> float:
	return float(NATURAL_SPEED.get(clip, 1.0))


## Клип ходьбы/бега для фактической скорости: ближайшая опорная natural
## (границы — середины между соседями). Смена клипа плавная: у модели
## play() идёт с кросс-фейдом ANIM_BLEND, темп меняется непрерывно.
static func locomotion_clip(hspeed: float) -> StringName:
	var speeds: Array = LOCO_CLIPS.map(func(c: StringName) -> float:
		return natural_speed(c))
	for i: int in speeds.size() - 1:
		if hspeed < (speeds[i] + speeds[i + 1]) * 0.5:
			return LOCO_CLIPS[i]
	return LOCO_CLIPS[LOCO_CLIPS.size() - 1]


## Темп клипа для фактической скорости (1.0 — клип в «родном» темпе).
static func speed_scale(clip: StringName, hspeed: float) -> float:
	return clampf(hspeed / natural_speed(clip),
		SPEED_SCALE_MIN, SPEED_SCALE_MAX)

