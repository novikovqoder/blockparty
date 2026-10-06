# Скелетные анимации персонажей (раздел 16 SPEC, v2.3): клипы трёх glb-библиотек
# набора KayKit Character Animations (CC0, Kay Lousberg — assets/third_party/
# LICENSES.md) на риге Rig_Medium — том же, что у моделей Adventurers, поэтому
# ретаргетинг не нужен: пути треков «Rig_Medium/Skeleton3D:<кость>» совпадают
# с деревом инстанса персонажа (AnimationPlayer кладётся ребёнком корня glb,
# корневой узел плеера по умолчанию «..»). Библиотека собирается один раз на
# процесс и расшаривается всеми AnimationPlayer: playback клипы не мутирует,
# а loop-режимы выставляются в дубликатах, исходные glb не трогаются.
# Состояние Protocol.AnimState → клип: у состояний без своего клипа в наборе
# (взмах при ударе, вис, эмоции) стоит ближайший по смыслу клип — полный
# список найденных клипов и маппинг в docs/STATUS.md (раздел 16).
class_name CharacterAnims
extends RefCounted

## glb-библиотеки анимаций KayKit (общий риг Rig_Medium).
const LIB_PATHS: PackedStringArray = [
	"res://assets/third_party/kaykit/animations/Rig_Medium_General.glb",
	"res://assets/third_party/kaykit/animations/Rig_Medium_MovementBasic.glb",
	"res://assets/third_party/kaykit/animations/Rig_Medium_Simulation.glb",
]

## Имя библиотеки внутри AnimationPlayer моделей персонажей.
const LIB_NAME: StringName = &"kaykit"

## Состояние аниматора (раздел 5) → клип KayKit.
const STATE_CLIPS: Dictionary = {
	Protocol.AnimState.IDLE: &"Idle_A",
	Protocol.AnimState.WALK: &"Walking_A",
	Protocol.AnimState.RUN: &"Running_A",
	Protocol.AnimState.JUMP: &"Jump_Start",
	Protocol.AnimState.FALL: &"Jump_Idle",
	Protocol.AnimState.LAND: &"Jump_Land",
	Protocol.AnimState.BONK: &"Hit_A",
	Protocol.AnimState.HANG: &"Jump_Idle",
	Protocol.AnimState.PULLED_UP: &"Jump_Land",
	Protocol.AnimState.HELP_PULL: &"Interact",
	Protocol.AnimState.SIT: &"Sit_Chair_Idle",
	Protocol.AnimState.HOLD_HAND: &"Walking_B",
	Protocol.AnimState.WAVE: &"Waving",
	Protocol.AnimState.EMOTE_1: &"Cheering",
	Protocol.AnimState.EMOTE_2: &"Use_Item",
	Protocol.AnimState.EMOTE_3: &"Throw",
	Protocol.AnimState.EMOTE_4: &"PickUp",
	Protocol.AnimState.EMOTE_5: &"Cheering",
	Protocol.AnimState.EMOTE_6: &"Interact",
}

## Циклические состояния (покой, перемещение, полёт, сидение, за руку);
## остальное — разовые, CharacterModel.play_one_shot возвращает состояние
## по таймеру.
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


## Общая библиотека «kaykit»: все клипы трёх glb; у клипов циклических
## состояний проставлен LOOP_LINEAR (KayKit экспортирует всё как one-shot).
static func library() -> AnimationLibrary:
	if _library != null:
		return _library
	_library = AnimationLibrary.new()
	for path: String in LIB_PATHS:
		var scene := load(path) as PackedScene
		var root := scene.instantiate()
		var players := root.find_children("*", "AnimationPlayer", true, false)
		assert(not players.is_empty(), "в %s нет AnimationPlayer" % path)
		var source := (players[0] as AnimationPlayer).get_animation_library("")
		for anim_name: StringName in source.get_animation_list():
			# Дубликат: правки loop-режима не задевают общий ресурс glb.
			var anim := source.get_animation(anim_name).duplicate() as Animation
			_library.add_animation(anim_name, anim)
		root.free()
	var loop_clips: Array[StringName] = []
	for state: int in LOOP_STATES:
		var clip: StringName = STATE_CLIPS[state]
		if not loop_clips.has(clip):
			loop_clips.append(clip)
	for clip: StringName in loop_clips:
		(_library.get_animation(clip) as Animation).loop_mode = Animation.LOOP_LINEAR
	return _library


## Клип состояния по номеру Protocol.AnimState.
static func clip_for_state(state: int) -> StringName:
	return STATE_CLIPS.get(state, &"")


## Циклическое ли состояние (клип зациклен).
static func is_loop(state: int) -> bool:
	return LOOP_STATES.has(state)
