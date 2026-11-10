extends SceneTree
## Локомоция героя БЕЗ оружия (ветка bu-claude): из библиотеки, которую сделал
## tools/retarget_mixamo_bu.gd по FBX из assets_src/mixamo_base/, собирает
## assets/hero/hero_base_anims.res с клипами:
##   base_idle, base_walk, base_run, base_turn, base_jump_up/fly/land.
## Исходный клип для каждого ищется по списку кандидатов (имена Mixamo после
## retarget_mixamo_bu.anim_name: «unarmed walk forward.fbx» → unarmed_walk_forward).
## Как и в slice_locomotion_bu.gd: у кости Hips из трека позиции убираются X/Z
## (горизонтальное движение задаёт физика игрока), а естественная скорость
## клипа (м/с по пробегу таза за цикл) пишется в мету natural_speed — по ней
## HeroModelBU подбирает темп, чтобы стопы не скользили.
## Фазы прыжка режутся по кривой высоты таза: низ приседа перед толчком →
## верх → низ после касания.
## Запуск: godot --headless --path . -s res://tools/build_base_anims_bu.gd -- <сырой .res> [выход .res]
## (без выхода — assets/hero/hero_base_anims.res рыцаря; робот района —
## assets/robot_pa/robot_base_anims.res).

const OUT_PATH: String = "res://assets/hero/hero_base_anims.res"
const HIPS_SUFFIX: String = "mixamorig_Hips"
const CANDIDATES: Dictionary = {
	"base_idle": ["unarmed_idle", "idle", "breathing_idle", "unarmed_idle_01", "happy_idle"],
	"base_walk": ["unarmed_walk_forward", "walking", "walk", "male_walk"],
	"base_run": ["unarmed_run_forward", "running", "run", "standard_run", "male_run"],
	"base_turn": ["unarmed_turn_left_90", "left_turn", "turn_left", "left_turn_90"],
	"base_jump": ["unarmed_jump", "jump", "standing_jump"],
}
const LOOPED: Array[String] = ["base_idle", "base_walk", "base_run", "base_jump_fly"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("нужно: <сырая библиотека .res из retarget_mixamo_bu.gd>")
		quit(1)
		return
	var raw: AnimationLibrary = load(args[0]) as AnimationLibrary
	if raw == null:
		push_error("не загрузилась библиотека %s" % args[0])
		quit(1)
		return
	var out_path: String = args[1] if args.size() > 1 else OUT_PATH
	print("в сырой библиотеке: ", ", ".join(raw.get_animation_list()))
	var out := AnimationLibrary.new()
	for clip: String in CANDIDATES:
		var src_name := _find(raw, CANDIDATES[clip])
		if src_name.is_empty():
			push_warning("нет исходника для %s (кандидаты %s)" % [clip, CANDIDATES[clip]])
			continue
		var src: Animation = raw.get_animation(src_name)
		if clip == "base_jump":
			_add_jump(out, src, src_name)
			continue
		var speed := _hips_speed(src)
		var anim := _copy(src, 0.0, src.length, clip)
		anim.set_meta("natural_speed", speed)
		anim.set_meta("source", src_name)
		out.add_animation(clip, anim)
		print("base: %s <- %s  (%.2f с, пробег %.2f м/с)" % [clip, src_name, src.length, speed])
	for name: String in out.get_animation_list():
		var a: Animation = out.get_animation(name)
		a.loop_mode = Animation.LOOP_LINEAR if LOOPED.has(name) else Animation.LOOP_NONE
	var err := ResourceSaver.save(out, out_path)
	print("saved %s err=%s clips=%s" % [out_path, err, out.get_animation_list().size()])
	quit(0 if err == OK and out.has_animation("base_walk") and out.has_animation("base_run") \
		and out.has_animation("base_idle") else 1)


static func _find(lib: AnimationLibrary, names: Array) -> String:
	for n: String in names:
		if lib.has_animation(n):
			return n
	# мягкий поиск: первое имя, содержащее кандидата
	for n: String in names:
		for have: String in lib.get_animation_list():
			if String(have).contains(n):
				return have
	return ""


static func _hips_track(src: Animation) -> int:
	for tr: int in src.get_track_count():
		if src.track_get_type(tr) == Animation.TYPE_POSITION_3D \
				and String(src.track_get_path(tr)).ends_with(HIPS_SUFFIX):
			return tr
	return -1


## Средняя горизонтальная скорость таза за клип, м/с.
static func _hips_speed(src: Animation) -> float:
	var tr := _hips_track(src)
	if tr < 0 or src.track_get_key_count(tr) < 2:
		return 0.0
	var a: Vector3 = src.track_get_key_value(tr, 0)
	var b: Vector3 = src.track_get_key_value(tr, src.track_get_key_count(tr) - 1)
	var t := src.track_get_key_time(tr, src.track_get_key_count(tr) - 1) - src.track_get_key_time(tr, 0)
	return Vector2(b.x - a.x, b.z - a.z).length() / maxf(t, 0.01)


## Прыжок на три фазы по высоте таза.
func _add_jump(out: AnimationLibrary, src: Animation, src_name: String) -> void:
	var tr := _hips_track(src)
	var n := src.track_get_key_count(tr) if tr >= 0 else 0
	var up := src.length * 0.35
	var land := src.length * 0.7
	if n > 4:
		var top_i := 0
		for k: int in n:
			if (src.track_get_key_value(tr, k) as Vector3).y > (src.track_get_key_value(tr, top_i) as Vector3).y:
				top_i = k
		var low_before := 0
		for k: int in top_i:
			if (src.track_get_key_value(tr, k) as Vector3).y < (src.track_get_key_value(tr, low_before) as Vector3).y:
				low_before = k
		var low_after := top_i
		for k: int in range(top_i, n):
			if (src.track_get_key_value(tr, k) as Vector3).y < (src.track_get_key_value(tr, low_after) as Vector3).y:
				low_after = k
		up = src.track_get_key_time(tr, low_before) + 0.08
		land = maxf(src.track_get_key_time(tr, low_after) - 0.12, up + 0.1)
	var phases := {"base_jump_up": [0.0, up, false], "base_jump_fly": [up, land, true],
		"base_jump_land": [land, src.length, false]}
	for name: String in phases:
		var r: Array = phases[name]
		var a := _copy(src, r[0], r[1], name, r[2])
		a.set_meta("source", src_name)
		out.add_animation(name, a)
		print("base: %s <- %s [%.2f..%.2f]" % [name, src_name, r[0], r[1]])


## Копия клипа между from и to; у трека позиции Hips убираются X/Z
## (flat_y — ещё и Y по первому ключу). Как в slice_locomotion_bu.gd.
static func _copy(src: Animation, from: float, to: float, out_name: String,
		flat_y: bool = false) -> Animation:
	var anim := Animation.new()
	anim.length = maxf(to - from, 0.01)
	for tr: int in src.get_track_count():
		var type: Animation.TrackType = src.track_get_type(tr)
		if not src.track_is_enabled(tr):
			continue
		if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D \
				and type != Animation.TYPE_SCALE_3D:
			continue
		var path: NodePath = src.track_get_path(tr)
		var dst := anim.add_track(type)
		anim.track_set_path(dst, path)
		anim.track_set_interpolation_type(dst, src.track_get_interpolation_type(tr))
		var is_hips := type == Animation.TYPE_POSITION_3D and String(path).ends_with(HIPS_SUFFIX)
		var flat_val := NAN
		for k: int in src.track_get_key_count(tr):
			var t := src.track_get_key_time(tr, k)
			if t < from - 0.001 or t > to + 0.001:
				continue
			var value: Variant = src.track_get_key_value(tr, k)
			if is_hips:
				var p: Vector3 = value
				if flat_y:
					if is_nan(flat_val):
						flat_val = p.y
					p.y = flat_val
				value = Vector3(0.0, p.y, 0.0)
			anim.track_insert_key(dst, t - from, value, src.track_get_key_transition(tr, k))
		if anim.track_get_key_count(dst) == 0:
			anim.remove_track(dst)
	anim.resource_name = out_name
	return anim
