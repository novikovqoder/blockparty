# Скелетные анимации персонажей (П5.7, блок 5 → П5.8, часть C): клипы
# Quaternius Universal Animation Library 1/2 (CC0 — assets/third_party/
# LICENSES.md), запечённые tools/make_ubc_anims.gd в anims_ubc.res на риг
# Universal Base Characters (65 костей). Линейки Quaternius Universal
# делят риг с UBC, треки записаны путями «Armature/Skeleton3D:<кость>» —
# одна библиотека работает на ubc_male и ubc_female, при загрузке ничего
# не пересобирается (loop-режимы выставлены при запечке). Клипы без
# аналога в UAL Standard (взмах, «Помогите!», вис у кромки, «за руку»)
# сгенерированы процедурно поверх rest/запечённых баз — честная запись
# в docs/STATUS.md (раздел 16). Состояние Protocol.AnimState → клип: у
# эмоций колеса (раздел 5) жесты по смыслу — полный список клипов UAL
# и маппинг в docs/STATUS.md.
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
	Protocol.AnimState.RUN: &"Jog_Fwd",
	Protocol.AnimState.JUMP: &"Jump_Start",
	Protocol.AnimState.FALL: &"NinjaJump_Idle",
	Protocol.AnimState.LAND: &"Jump_Land",
	Protocol.AnimState.BONK: &"Hit_Chest",
	Protocol.AnimState.HANG: &"Hang_Pose",
	Protocol.AnimState.PULLED_UP: &"ClimbUp_1m",
	Protocol.AnimState.HELP_PULL: &"Interact",
	Protocol.AnimState.SIT: &"Sitting_Idle",
	Protocol.AnimState.HOLD_HAND: &"Walk_Hand",
	Protocol.AnimState.WAVE: &"Wave_Hand",
	# Эмоции колеса: «Привет!» — взмах одной рукой (замыкает EMOTE_ANIMS),
	# «Спасибо» — разговорный жест, «Вон там» — указание вдаль (Rail Call),
	# «Подожди» — качание головой, «Смешно» — танец, «Помогите!» — обе
	# руки вверх (процедурный Help_Call).
	Protocol.AnimState.EMOTE_1: &"Wave_Hand",
	Protocol.AnimState.EMOTE_2: &"Idle_Talking",
	Protocol.AnimState.EMOTE_3: &"Idle_Rail_Call",
	Protocol.AnimState.EMOTE_4: &"Idle_No",
	Protocol.AnimState.EMOTE_5: &"Dance",
	Protocol.AnimState.EMOTE_6: &"Help_Call",
}

## Циклические состояния (покой, перемещение, полёт, сидение, за руку);
## остальное — разовые, CharacterModel.play_one_shot возвращает состояние
## по таймеру. Соответствует LOOP_CLIPS запечки (loop_mode уже в .res).
const LOOP_STATES: Array[int] = [
	Protocol.AnimState.IDLE,
	Protocol.AnimState.WALK,
	Protocol.AnimState.RUN,
	Protocol.AnimState.FALL,
	Protocol.AnimState.HANG,
	Protocol.AnimState.SIT,
	Protocol.AnimState.HOLD_HAND,
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
