# Диагностика разрыва анимационного конвейера (П5.8, возврат владельца):
# анимации не работают нигде — T-поза и скольжение. Лог Windows ошибок
# резолва не содержит, значит нерезолв идёт молча: диагноз ставится прямым
# сравнением, не поиском по логу. Скрипт печатает:
#   1) default root_node у AnimationPlayer, созданного кодом (character_model);
#   2) дерево запечённой сцены UBC (куда указывают пути дорожек);
#   3) таблицу «клип → дорожка → кость найдена/нет» (узел + кость);
#   4) применяется ли анимация: позы ключевых костей в покое против Walk
#      через play() с ожиданием кадров — в текущем конвейере CharacterModel
#      и с явно выставленным root_node (изоляция причины).
#   godot --headless --path . -s res://tools/diag_anim_break.gd
extends SceneTree

const MODEL: PackedScene = preload("res://gameplay/player/character_model.tscn")
const WALK_BONES: PackedStringArray = ["thigh_l", "calf_l", "upperarm_l"]


func _init() -> void:
	await create_timer(0.01).timeout

	print("=== 1. root_node по умолчанию ===")
	var fresh := AnimationPlayer.new()
	print("AnimationPlayer.new().root_node = «%s»" % String(fresh.root_node))
	fresh.free()

	print("\n=== 2. Дерево запечённой сцены (модель после setup_appearance) ===")
	var model := MODEL.instantiate() as CharacterModel
	root.add_child(model)
	model.setup_appearance(Appearance.default_for(0))
	_dump_tree(model._root, 0)
	var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player: AnimationPlayer = model._player
	print("плеер: %s, root_node=«%s», resolves to: %s" % [
		str(player.get_path()), String(player.root_node),
		str(player.get_node_and_resource(player.root_node)[0].get_path()
			if player.get_node_or_null(player.root_node) != null else "<нет>")])
	print("скелет: %s, костей: %d" % [str(sk.get_path()), sk.get_bone_count()])
	print("кости: ", " ".join(_bone_list(sk)))

	print("\n=== 3. Резолв дорожек: клип → дорожка → кость ===")
	var lib := CharacterAnims.library()
	var unresolved := 0
	var total := 0
	for clip_name: StringName in lib.get_animation_list():
		var anim := lib.get_animation(clip_name) as Animation
		var lines: PackedStringArray = []
		for i: int in anim.get_track_count():
			total += 1
			var path := anim.track_get_path(i)
			var node := model._root.get_node_or_null(
				NodePath(str(path).get_slice(":", 0)))
			var bone := str(path).get_slice(":", 1)
			var found: int = sk.find_bone(bone)
			var verdict := "кость найдена" if node != null and found >= 0 \
				else "НЕТ УЗЛА" if node == null else "НЕТ КОСТИ"
			if node == null or found < 0:
				unresolved += 1
			lines.append("    %s → %s" % [str(path), verdict])
		print("  %s (%d дорожек)" % [clip_name, anim.get_track_count()])
		if clip_name == &"Walk":
			for line: String in lines:
				print(line)
	print("итог: %d дорожек из %d не находят узел/кость"
		% [unresolved, total])

	print("\n=== 4. Применение к скелету: покой против Walk ===")
	# Позы через ТЕКУЩИЙ конвейер (как в игре: set_state + кадры).
	_pose_report(model, sk, "покой (после сборки)")
	model.set_state(Protocol.AnimState.WALK)
	await process_frame
	await process_frame
	await process_frame
	_pose_report(model, sk, "Walk, 3 кадра, текущий конвейер")

	# Изоляция: тот же клип напрямую, root_node указывает на _root явно.
	player.root_node = player.get_path_to(model._root)
	player.stop()
	player.play("ubc/Walk")
	await process_frame
	await process_frame
	await process_frame
	_pose_report(model, sk, "Walk, 3 кадра, root_node явно на UbcRoot")

	# Изоляция 2: seek без ожидания кадров — применяет ли advance значения.
	player.stop()
	player.play("ubc/Walk")
	player.advance(0.3)
	_pose_report(sk, sk, "Walk, advance(0.3) без кадров")

	quit(0)


func _pose_report(model: Node, sk: Skeleton3D, label: String) -> void:
	var parts: PackedStringArray = []
	for bone: String in WALK_BONES:
		var idx := sk.find_bone(bone)
		if idx < 0:
			parts.append("%s=<нет>" % bone)
			continue
		var pose := sk.get_bone_pose(idx)
		parts.append("%s=(%.3f %.3f %.3f)%.0f°" % [bone, pose.origin.x,
			pose.origin.y, pose.origin.z,
			rad_to_deg(pose.basis.get_euler().length())])
	print("  %s: %s" % [label, " ".join(parts)])


func _bone_list(sk: Skeleton3D) -> PackedStringArray:
	var out: PackedStringArray = []
	for i: int in sk.get_bone_count():
		out.append(sk.get_bone_name(i))
	return out


func _dump_tree(node: Node, depth: int) -> void:
	if depth <= 2 or node is Skeleton3D or node.get_child_count() == 0:
		print("%s%s [%s]%s" % ["  ".repeat(depth), str(node.name),
			node.get_class(),
			" — %d детей" % node.get_child_count() if depth <= 1 else ""])
	if depth < 3:
		for child: Node in node.get_children():
			_dump_tree(child, depth + 1)
