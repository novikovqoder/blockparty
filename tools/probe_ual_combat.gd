# Проверка боевых клипов Universal Animation Library 1/2 на риге UBC
# (П5.8, SPEC раздел 16 «Этап П5.8», задел на будущий бой: замах, выстрел,
# каст, получение удара, уклонение). В игру НЕ подключается — отчёт в
# docs/STATUS.md. Проверяются три вещи:
#   1) клипы нужных категорий есть в наборах UAL Standard;
#   2) треки переносятся на кости UBC той же прямой запечкой, что и игровые
#      клипы (tools/make_ubc_anims.gd): доля разрешившихся треков, кости;
#   3) клип реально водит риг: на живой сцене ubc_male кости отходят
#      от rest-позы на значимый угол.
# Запуск: godot --headless -s tools/probe_ual_combat.gd --path .
# Исходники — импортируемые копии builds/ual_probe/UAL{1,2}.glb
# (архивы наборов — вне git, .downloads/ual/).
extends SceneTree

## Проверяемые клипы: категория → имена в наборах UAL (без суффикса «_Loop»).
const COMBAT_CLIPS: Array[String] = [
	# замах/удар оружием и рукой
	"Sword_Attack", "Sword_Regular_A", "Sword_Regular_B", "Sword_Heavy_Combo",
	"Punch_Jab", "Punch_Cross", "Melee_Hook",
	# выстрел
	"Pistol_Shoot", "Pistol_Aim_Neutral", "Pistol_Reload",
	# каст / направленный жест
	"Spell_Simple_Shoot", "Spell_Simple_Enter", "Spell_Simple_Idle",
	# получение удара
	"Hit_Head", "Hit_Knockback",
	# уклонение
	"Roll", "Shield_Dash", "Slide_Start",
]
## Категория по имени клипа (для отчёта).
const CATEGORY_OF: Dictionary = {
	"Sword_Attack": "замах", "Sword_Regular_A": "замах",
	"Sword_Regular_B": "замах", "Sword_Heavy_Combo": "замах",
	"Punch_Jab": "замах", "Punch_Cross": "замах", "Melee_Hook": "замах",
	"Pistol_Shoot": "выстрел", "Pistol_Aim_Neutral": "выстрел",
	"Pistol_Reload": "выстрел",
	"Spell_Simple_Shoot": "каст", "Spell_Simple_Enter": "каст",
	"Spell_Simple_Idle": "каст",
	"Hit_Head": "получение удара", "Hit_Knockback": "получение удара",
	"Roll": "уклонение", "Shield_Dash": "уклонение",
	"Slide_Start": "уклонение",
}
## Представители категорий для живой проверки позы (по одному).
const LIVE_SAMPLE: PackedStringArray = [
	"Sword_Attack", "Pistol_Shoot", "Spell_Simple_Shoot", "Hit_Head", "Roll",
]

const UAL_GLB: PackedStringArray = [
	"res://builds/ual_probe/UAL1.glb",
	"res://builds/ual_probe/UAL2.glb",
]
const UBC_SCENE: String = "res://assets/third_party/quaternius.com/" \
	+ "universal_base_characters/baked/ubc_male.res"
const SKELETON_PATH: String = "Armature/Skeleton3D"
## Отношение rest-высот таза UBC/UAL — как в игровой запечке.
const PELVIS_RATIO: float = 0.949 / 0.917
## Угол, выше которого кость считается двинувшейся, градусы.
const MOVE_DEG: float = 10.0

var _bones: PackedStringArray = []
var _lower_to_bone: Dictionary = {}


func _init() -> void:
	_read_rest()
	# 1–2: собрать клипы UAL и переложить треки на кости UBC.
	var remapped: Dictionary = {}  # имя → Animation
	var report: Array[String] = []
	for path: String in UAL_GLB:
		var scene := load(path) as PackedScene
		var root := scene.instantiate()
		var player := root.find_children(
			"*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var lib := player.get_animation_library("")
		for clip_name in lib.get_animation_list():
			var name := String(clip_name)
			if not COMBAT_CLIPS.has(name) or remapped.has(name):
				continue
			var stats := _remapped(name, lib.get_animation(clip_name))
			remapped[name] = stats["anim"]
			report.append("%-19s %-16s %5.2f с  треков %3d → UBC %3d  "
				% [name, CATEGORY_OF[name],
					(stats["anim"] as Animation).length,
					stats["total"], stats["kept"]])
		root.free()
	report.sort()
	print("=== Переложение на риг UBC ===")
	print("\n".join(report))
	# 3: живая проверка поз на сцене ubc_male.
	await _live_check(remapped)
	quit()


## Rest-кости UBC и регистронезависимая карта имён (как в make_ubc_anims).
func _read_rest() -> void:
	var scene := load(UBC_SCENE) as PackedScene
	var root := scene.instantiate()
	var sk := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for i: int in sk.get_bone_count():
		_bones.append(sk.get_bone_name(i))
		_lower_to_bone[sk.get_bone_name(i).to_lower()] = i
	root.free()


## Переложить клип UAL на риг UBC; возвращает {anim, total, kept} —
## total/kept: треков было/разрешилось в кости UBC.
func _remapped(out_name: String, anim: Animation) -> Dictionary:
	var out := Animation.new()
	out.resource_name = out_name
	out.length = anim.length
	var total := 0
	var kept := 0
	for i: int in anim.get_track_count():
		var path := anim.track_get_path(i)
		var bone_idx: int = _lower_to_bone.get(
			String(path.get_subname(path.get_subname_count() - 1)).to_lower(), -1)
		if bone_idx < 0:
			total += 1
			continue  # лист-кости пальцев и нериговые треки — на UBC не везти
		match anim.track_get_type(i):
			Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D:
				total += 1
				kept += 1
				var ti := out.add_track(anim.track_get_type(i))
				out.track_set_path(ti, NodePath("%s:%s"
					% [SKELETON_PATH, _bones[bone_idx]]))
				out.track_set_interpolation_type(ti,
					anim.track_get_interpolation_type(i))
				for k: int in anim.track_get_key_count(i):
					var value: Variant = anim.track_get_key_value(i, k)
					if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
						value = (value as Vector3) * PELVIS_RATIO
					out.track_insert_key(ti, anim.track_get_key_time(i, k), value)
			_:
				pass
	return {"anim": out, "total": total, "kept": kept}


## Живая проверка: игрок анимирует сцену ubc_male, на середине и 2/3 клипа
## меряем, сколько костей отошло от rest-позы и на какой угол.
func _live_check(remapped: Dictionary) -> void:
	var scene := load(UBC_SCENE) as PackedScene
	var root := scene.instantiate()
	self.root.add_child(root)
	await process_frame
	var sk := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player := AnimationPlayer.new()
	player.name = "CombatProbe"
	root.add_child(player)
	player.add_animation_library("probe", _as_library(remapped))
	print("=== Живая проверка поз (ubc_male) ===")
	var lines: Array[String] = []
	for clip_name: String in LIVE_SAMPLE:
		if not remapped.has(clip_name):
			lines.append("%-19s НЕТ В НАБОРАХ" % clip_name)
			continue
		var anim := remapped[clip_name] as Animation
		player.stop()
		sk.reset_bone_poses()
		player.play("probe/%s" % clip_name)
		var max_deg := 0.0
		var moved := 0
		for fraction: float in [0.5, 0.75]:
			player.seek(anim.length * fraction, true, true)
			await process_frame
			var delta := _pose_stats(sk)
			max_deg = maxf(max_deg, delta[0])
			moved = maxi(moved, delta[1])
		var verdict := "ок" if max_deg >= MOVE_DEG else "СЛАБО"
		lines.append("%-19s кости >%d°: %2d   макс %.0f°   %s"
			% [clip_name, MOVE_DEG, moved, max_deg, verdict])
	print("\n".join(lines))
	root.queue_free()


## Обёртка Dictionary → AnimationLibrary (словарь типизировать нельзя).
func _as_library(remapped: Dictionary) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	for clip_name: String in remapped:
		lib.add_animation(StringName(clip_name), remapped[clip_name])
	return lib


## Максимальный отход кости от rest-позы (градусы) и число костей >MOVE_DEG.
func _pose_stats(sk: Skeleton3D) -> Array:
	var max_deg := 0.0
	var moved := 0
	for i: int in sk.get_bone_count():
		var a := sk.get_bone_global_pose(i).basis.get_rotation_quaternion()
		var b := sk.get_bone_global_rest(i).basis.get_rotation_quaternion()
		var deg := rad_to_deg(a.angle_to(b))
		max_deg = maxf(max_deg, deg)
		if deg > MOVE_DEG:
			moved += 1
	return [max_deg, moved]
