# Диагностика Skin-привязок (П5.8, возврат владельца): скелет анимируется
# (diag_anim_break.gd), но меши в T-позе — проверяем бинды скинов запечённых
# частей. Кожура: бинд без имени ссылается индексом кости на ПОРЯДОК костей
# скелета-источника; порядок костей запечённого скелета должен совпадать.
#   godot --headless --path . -s res://tools/diag_skin_binds.gd
extends SceneTree

const MESH_DIR: String = "res://assets/third_party/quaternius.com/" \
	+ "universal_base_characters/baked/meshes"
const SCENE: String = "res://assets/third_party/quaternius.com/" \
	+ "universal_base_characters/baked/ubc_male.res"
const PARTS: PackedStringArray = ["head_m", "legs_peasant_m",
	"arms_peasant_m", "top_peasant_m", "feet_peasant_m", "hair_long"]


func _init() -> void:
	await create_timer(0.01).timeout
	var scene := load(SCENE) as PackedScene
	var root := scene.instantiate()
	self.root.add_child(root)
	await process_frame
	var sk := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	print("скелет ubc_male: %d костей" % sk.get_bone_count())

	# Что говорит MeshInstance3D сцены: skin установлен? skeleton-путь?
	for part: String in PARTS:
		var mi := root.find_children(part, "MeshInstance3D", true,
			false)[0] as MeshInstance3D
		var skin := mi.skin
		var resolved := mi.get_node_or_null(mi.skeleton)
		if skin == null:
			print("%s: skin НЕ установлен!" % part)
			continue
		var named := 0
		var named_ok := 0
		var indexed_ok := 0
		for i: int in skin.get_bind_count():
			var name := skin.get_bind_name(i)
			if name != null and not String(name).is_empty():
				named += 1
				if sk.find_bone(String(name)) >= 0:
					named_ok += 1
			elif skin.get_bind_bone(i) >= 0 \
					and skin.get_bind_bone(i) < sk.get_bone_count():
				indexed_ok += 1
		print("%s: binds=%d именованных=%d(найдено %d) индексных валидных=%d skeleton=«%s»→%s" \
			% [part, skin.get_bind_count(), named, named_ok, indexed_ok,
			String(mi.skeleton),
			str(resolved.get_path()) if resolved != null else "<НЕТ УЗЛА>"])

	# Детально один бинд: куда смотрит индекс/имя.
	var skin := load(MESH_DIR + "/legs_peasant_m_skin.res") as Skin
	print("\nlegs_peasant_m_skin: binds=", skin.get_bind_count())
	for i: int in mini(skin.get_bind_count(), 10):
		var b := skin.get_bind_bone(i)
		var n := skin.get_bind_name(i)
		print("  bind %d: bone=%d name=%s → в ubc_male: %s" % [i, b,
			str(n),
			sk.get_bone_name(b) if b >= 0 and b < sk.get_bone_count()
			else "<вне диапазона>"])
	quit(0)
