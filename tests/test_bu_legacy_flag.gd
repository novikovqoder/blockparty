extends GutTest
# П10 (уборка мира): флаг bu_legacy_hidden (в balance.tres true, узлы читают
# статикой Balance.legacy_hidden()) — жители, костёр и сидения у костра не
# создаются: узлы освобождаются в _ready, модель и коллизии не строятся.
# При выключенном флаге — создаются, как раньше. Тесты наследия гоняются
# при выключенном флаге (tests/helpers/bu_flag.gd), этот — проверяет сам флаг.


func test_flag_hides_townsfolk_campfire_seat() -> void:
	Balance.set_legacy_hidden(true)
	var folk: Townsfolk = Townsfolk.new()
	add_child(folk)
	var fire: Campfire = Campfire.new()
	add_child(fire)
	var seat: CampfireSeat = CampfireSeat.new()
	add_child(seat)
	await wait_frames(3)
	assert_false(is_instance_valid(folk), "житель удалён")
	assert_false(is_instance_valid(fire), "костёр удалён")
	assert_false(is_instance_valid(seat), "сидение удалено")
	assert_eq(get_tree().get_nodes_in_group(Townsfolk.TOWNSFOLK_GROUP).size(), 0,
		"группа жителей пуста")


func test_flag_off_keeps_legacy_world() -> void:
	Balance.set_legacy_hidden(false)
	var folk: Townsfolk = Townsfolk.new()
	add_child_autofree(folk)
	var fire: Campfire = Campfire.new()
	add_child_autofree(fire)
	await wait_frames(2)
	assert_true(is_instance_valid(folk) and folk.is_inside_tree(), "житель жив")
	assert_not_null(folk.get_node_or_null("Model"), "модель жителя построена")
	assert_true(is_instance_valid(fire) and fire.is_inside_tree(), "костёр жив")
	assert_not_null(fire.get_node_or_null("FirePit"), "очаг построен")
	Balance.set_legacy_hidden(true)
