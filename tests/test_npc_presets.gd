# Пресеты жителей (П5.8, часть E): Тимьян/Луми/Финн строятся той же системой
# внешности, что и игрок, — фирменный убор (панама с веточкой / шляпа
# с ракушкой / кепка с «ушками»), причёска и цвет волос своего оттенка.
# Жители стоят на местах заданий П5.5 (Townsfolk.character → setup), диалог
# показывает девиз (тексты — test_character_data).
extends GutTest

const MODEL: PackedScene = preload("res://gameplay/player/character_model.tscn")

## Пресет: убор + причёска + пол (индексы как characters.json:
## 0 Финн, 1 Луми, 2 Тимьян).
const EXPECTED: Array = [
	{"hat": Appearance.HAT_CAP, "hair": 4, "gender": Appearance.GENDER_MALE},
	{"hat": Appearance.HAT_BRIM, "hair": 0, "gender": Appearance.GENDER_FEMALE},
	{"hat": Appearance.HAT_PANAMA, "hair": 1, "gender": Appearance.GENDER_MALE},
]


const BU_LEGACY: Script = preload("res://tests/helpers/bu_flag.gd")


func before_all() -> void:
	BU_LEGACY.legacy_off()


func after_all() -> void:
	BU_LEGACY.legacy_restore()


func test_townsfolk_presets_have_signature_hats() -> void:
	for index: int in EXPECTED.size():
		var want: Dictionary = EXPECTED[index]
		var model := MODEL.instantiate() as CharacterModel
		add_child_autofree(model)
		model.setup(index)
		assert_eq(model.appearance.hat, want["hat"],
			"житель %d: фирменный убор" % index)
		assert_eq(model.appearance.hair, want["hair"],
			"житель %d: причёска" % index)
		assert_eq(model.appearance.gender, want["gender"],
			"житель %d: тело" % index)
		assert_true(model.appearance.validated().same(model.appearance),
			"житель %d: внешность проходит validated()" % index)
		# Убор реально есть в собранной модели и показан (LOD-близнец тоже).
		var hat := CharacterModel.hat_part(want["hat"], want["gender"])
		for suffix: String in ["", "_LOD"]:
			var found: Array = model.find_children(hat + suffix,
				"MeshInstance3D", true, false)
			assert_eq(found.size(), 1,
				"житель %d: узел %s%s в сцене" % [index, hat, suffix])
			assert_true((found[0] as MeshInstance3D).visible,
				"житель %d: %s%s виден" % [index, hat, suffix])


## Житель сидящего задания (Тимьян у костра) — модель та же, состояние SIT
## задаёт Townsfolk; здесь проверяем, что после set_state(SIT) убор остаётся
## на месте (скин Head не теряется при переключении клипа).
func test_sitting_townsfolk_keeps_hat() -> void:
	var model := MODEL.instantiate() as CharacterModel
	add_child_autofree(model)
	model.setup(2)  # Тимьян — панама
	model.set_state(Protocol.AnimState.SIT)
	await get_tree().process_frame
	var hat: MeshInstance3D = model.find_children(
		CharacterModel.hat_part(Appearance.HAT_PANAMA, Appearance.GENDER_MALE),
		"MeshInstance3D", true, false)[0]
	assert_true(hat.visible, "панама на сидящем Тимьяне")


## Уборы доступны и валидны через Appearance: индексы в диапазоне, validated()
## не выдавливает их обратно к «без убора» (раньше HATS было 2 — кламп мог
## бы превратить панаму в капюшон).
func test_new_hats_survive_validation() -> void:
	for hat: int in [Appearance.HAT_PANAMA, Appearance.HAT_BRIM,
			Appearance.HAT_CAP]:
		var ap := Appearance.default_for(Appearance.GENDER_FEMALE)
		ap.hat = hat
		assert_eq(ap.validated().hat, hat, "убор %d проходит validated()" % hat)
	assert_eq(Appearance.HATS, 5, "пять вариантов убора в редакторе")
