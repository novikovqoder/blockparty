# Тесты редактора внешности (П5.8, часть B2): экран открывается с внешностью
# из user://, панель меняет индексы (пол фильтрует причёски, палитры,
# комплекты, убор с «без»), «Случайно» даёт валидную комбинацию, драг
# вращает модель с инерцией, зум клампится, пресеты фототура валидны.
extends GutTest

const EDITOR: PackedScene = preload("res://scenes/appearance_editor.tscn")
const EPS: float = 0.001


func _make() -> AppearanceEditor:
	var editor := EDITOR.instantiate() as AppearanceEditor
	add_child_autofree(editor)
	return editor


func test_opens_with_saved_appearance() -> void:
	var editor := _make()
	assert_not_null(editor.ap, "внешность загружена из user://")
	assert_not_null(editor.model.appearance, "модель построена")
	assert_eq(editor.model.appearance.gender, editor.ap.gender,
		"пол модели совпадает с панелью")


func test_gender_switch_filters_hair() -> void:
	var editor := _make()
	editor.ap.hair = 5  # борода — только мужское тело
	editor._set_gender(Appearance.GENDER_FEMALE)
	assert_eq(editor.ap.gender, Appearance.GENDER_FEMALE, "пол переключился")
	var female_hairs: Array = []
	female_hairs.append_array(
		Appearance.hair_variants(Appearance.GENDER_FEMALE))
	assert_has(female_hairs, editor.ap.hair, "причёска допустима для пола")
	assert_ne(editor.ap.hair, 5, "борода не осталась на женском теле")
	assert_true(editor._gender_buttons[1].button_pressed,
		"кнопка женского тела отмечена")


func test_hair_cycle_wraps_by_gender_list() -> void:
	var editor := _make()
	editor._set_gender(Appearance.GENDER_FEMALE)
	var variants := Appearance.hair_variants(Appearance.GENDER_FEMALE)
	editor.ap.hair = variants[0]
	editor._step_hair(-1)  # назад от первого → последний
	assert_eq(editor.ap.hair, variants[variants.size() - 1],
		"цикл причёсок завернулся через край")
	editor._step_hair(1)
	assert_eq(editor.ap.hair, variants[0], "шаг вперёд вернул первый")


func test_outfit_and_hat_cycle_update_labels() -> void:
	var editor := _make()
	var top: int = editor.ap.top
	editor._step_index("top", Appearance.OUTFITS.size(), 1)
	assert_eq(editor.ap.top, wrapi(top + 1, 0, Appearance.OUTFITS.size()),
		"верх переключился")
	editor._step_index("hat", Appearance.HATS, 1)
	assert_eq(editor.ap.hat, Appearance.HAT_HOOD, "убор переключился на капюшон")
	assert_eq((editor._value_labels["hat"] as Label).text,
		tr("APPEARANCE_HAT_HOOD"), "подпись убора обновилась")


func test_color_pick_marks_selected_swatch() -> void:
	var editor := _make()
	var last: int = Appearance.SKIN_COLORS.size() - 1
	editor._pick_color("skin", last)
	assert_eq(editor.ap.skin, last, "индекс кожи выбран")
	var buttons: Array = editor._swatch_buttons["skin"]
	var style := (buttons[last] as Button) \
		.get_theme_stylebox("normal") as StyleBoxFlat
	assert_eq(style.border_width_top, 3, "выбранный кружок отмечен рамкой")
	var unselected := (buttons[0] as Button) \
		.get_theme_stylebox("normal") as StyleBoxFlat
	assert_eq(unselected.border_width_top, 1, "остальные без отметки")


func test_random_stays_valid() -> void:
	var editor := _make()
	editor._on_random_pressed()
	var variants := Appearance.hair_variants(editor.ap.gender)
	assert_has(variants, editor.ap.hair, "причёска допустима для выпавшего пола")
	assert_between(editor.ap.skin, 0, Appearance.SKIN_COLORS.size() - 1,
		"кожа в диапазоне")
	assert_not_null(editor.model.appearance, "модель перестроена")


func test_drag_spins_with_inertia_and_zoom_clamps() -> void:
	var editor := _make()
	var yaw_before: float = editor.model.rotation.y
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	editor._on_spin_area_gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(-40.0, 0.0)
	editor._on_spin_area_gui_input(motion)
	editor._process(1.0 / 60.0)  # поворот применяется в кадре
	assert_gt(absf(editor.model.rotation.y - yaw_before), 0.1,
		"драг повернул модель")
	assert_gt(absf(editor._spin), 0.0, "инерция накоплена")
	editor._set_zoom(10.0)
	assert_almost_eq(editor.camera.position.z, AppearanceEditor.ZOOM_MAX,
		EPS, "зум клампится сверху")


## Пресеты фототура (--shot-dir, материалы этапа): каждый валиден как есть —
## validated() ничего не меняет, на снимках именно заданные комбинации.
func test_tour_presets_are_valid() -> void:
	assert_gte(Appearance.SHOWCASE.size(), 4,
		"фототур покрывает несколько персонажей")
	for entry: PackedByteArray in Appearance.SHOWCASE:
		var ap := Appearance.from_bytes(entry)
		assert_true(ap.same(ap.validated()),
			"пресет фототура валиден без правок")
