extends SceneTree
## Нарезка локомоции героя Born Unblessed из запечённой библиотеки пака
## «Pro Sword and Shield» (assets/hero/hero_sword_anims.res, сделал
## tools/retarget_mixamo_bu.gd). Добавляет клипы с префиксом loco_:
##   loco_idle, loco_walk, loco_run, loco_turn — копии ss_idle/ss_walk/ss_run/ss_turn;
##   loco_jump_up/fly/land — три фазы прыжка из ss_jump_2 (взлёт/полёт/приземление).
## Во всех клипах у кости Hips из трека позиции убираются ключи X/Z:
## клипы пака записаны «с пробегом» (walk едет 1,5 м за цикл) — горизонтальное
## движение задаёт физика игрока, в клипе остаются только вертикальный бой
## и приседания. Циклы: idle/walk/run/fly — LOOP_LINEAR, остальные разовые.
## Запуск: godot --headless --path . -s res://tools/slice_locomotion_bu.gd
## Идемпотентно: существующие loco_* перед добавлением удаляются.

const ANIMS_PATH: String = "res://assets/hero/hero_sword_anims.res"
const HIPS_SUFFIX: String = "mixamorig_Hips"
## Фазы прыжка из ss_jump_2 (0,97 с, прыжок на месте): присед+толчок до
## отрыва, полёт с поджатыми ногами, касание и амортизация. Границы — на сетке
## ключей запечки (30 fps): 12/30 и 22/30, чтобы фазы резались по ключам.
const JUMP_SOURCE: String = "ss_jump_2"
const JUMP_UP: float = 12.0 / 30.0
const JUMP_FLY: float = 22.0 / 30.0
## Клипы-копии: имя на выходе → исходник.
const COPIES: Dictionary = {
	"loco_idle": "ss_idle",
	"loco_walk": "ss_walk",
	"loco_run": "ss_run",
	"loco_turn": "ss_turn",
}
const LOOPED: Array[String] = ["loco_idle", "loco_walk", "loco_run", "loco_jump_fly"]


func _initialize() -> void:
	var lib: AnimationLibrary = load(ANIMS_PATH) as AnimationLibrary
	if lib == null:
		push_error("нет библиотеки %s (сначала retarget_mixamo_bu.gd)" % ANIMS_PATH)
		quit(1)
		return
	for name: String in lib.get_animation_list():
		if name.begins_with("loco_"):
			lib.remove_animation(name)
	for out: String in COPIES:
		var src: String = COPIES[out]
		if not lib.has_animation(src):
			push_error("в библиотеке нет клипа %s" % src)
			quit(1)
			return
		var anim: Animation = _copy(lib.get_animation(src) as Animation, 0.0,
			(lib.get_animation(src) as Animation).length, out)
		lib.add_animation(out, anim)
		print("loco: %s <- %s" % [out, src])
	if not lib.has_animation(JUMP_SOURCE):
		push_error("в библиотеке нет клипа %s" % JUMP_SOURCE)
		quit(1)
		return
	var jump: Animation = lib.get_animation(JUMP_SOURCE) as Animation
	var phases: Dictionary = {
		"loco_jump_up": [0.0, JUMP_UP, false],
		# Полёт: Y таза выравнивается (дугу даёт физика прыжка, цикл не должен
		# качать тело), клип держит поджатые ноги.
		"loco_jump_fly": [JUMP_UP, JUMP_FLY, true],
		"loco_jump_land": [JUMP_FLY, jump.length, false],
	}
	for out: String in phases:
		var range: Array = phases[out]
		lib.add_animation(out, _copy(jump, range[0], range[1], out, range[2]))
		print("loco: %s <- %s [%.2f..%.2f]%s" % [out, JUMP_SOURCE, range[0],
			range[1], " Y-плоско" if range[2] else ""])
	for name: String in lib.get_animation_list():
		if name.begins_with("loco_"):
			var a: Animation = lib.get_animation(name)
			a.loop_mode = Animation.LOOP_LINEAR if LOOPED.has(name) else Animation.LOOP_NONE
	var err: Error = ResourceSaver.save(lib, ANIMS_PATH)
	var n_loco: int = 0
	for name: String in lib.get_animation_list():
		if name.begins_with("loco_"):
			n_loco += 1
	print("saved %s err=%s animations=%s loco=%s" % [ANIMS_PATH, err,
		lib.get_animation_list().size(), n_loco])
	quit(0 if err == OK else 1)


## Копия клипа между from и to: ключи переносятся со сдвигом времени −from,
## трек Hips-позиции теряет X/Z (flat_y — ещё и выравнивает Y по первому ключу).
func _copy(src: Animation, from: float, to: float, out_name: String,
		flat_y: bool = false) -> Animation:
	var anim: Animation = Animation.new()
	anim.length = maxf(to - from, 0.01)
	var hips_pos_track: int = -1
	for tr: int in src.get_track_count():
		var path: NodePath = src.track_get_path(tr)
		var type: Animation.TrackType = src.track_get_type(tr)
		if type < 0 or not src.track_is_enabled(tr):
			continue
		var dst: int = -1
		if type == Animation.TYPE_VALUE or type == Animation.TYPE_METHOD \
				or type == Animation.TYPE_BEZIER or type == Animation.TYPE_AUDIO \
				or type == Animation.TYPE_ANIMATION:
			continue  # скелетных клипов пака касается только 3D-типов
		dst = anim.add_track(type)
		anim.track_set_path(dst, path)
		anim.track_set_interpolation_type(dst, src.track_get_interpolation_type(tr))
		var n: int = src.track_get_key_count(tr)
		var flat_y_value: float = NAN
		for k: int in n:
			var t: float = src.track_get_key_time(tr, k)
			if t < from - 0.001 or t > to + 0.001:
				continue
			var value: Variant = src.track_get_key_value(tr, k)
			if type == Animation.TYPE_POSITION_3D \
					and String(path).ends_with(HIPS_SUFFIX):
				var p: Vector3 = value
				if flat_y and not is_nan(flat_y_value):
					p.y = flat_y_value
				value = Vector3(0.0, p.y, 0.0)
				if flat_y and is_nan(flat_y_value):
					flat_y_value = p.y
				hips_pos_track = dst
			var trans: float = src.track_get_key_transition(tr, k)
			anim.track_insert_key(dst, t - from, value, trans)
		if anim.track_get_key_count(dst) == 0:
			anim.remove_track(dst)
			if hips_pos_track == dst:
				hips_pos_track = -1
	if hips_pos_track < 0:
		push_warning("%s: трек позиции Hips не найден (клип без корня)" % out_name)
	# Гарантия «ступни на земле» у фаз полёта: копии уже без X/Z, менять Y не нужно.
	anim.resource_name = out_name
	return anim
