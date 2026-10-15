# Д3 (темп ног): естественная скорость локомоционных клипов — скорость,
# при которой стопы не скользят по земле. Клипы UAL in-place (только
# ротации костей): в фазе опоры стопа едет назад в системе модели с той
# скоростью, с которой персонаж едет вперёд по миру. Средняя |скорость|
# стоп в нижней части дуги (40% размаха) = natural speed клипа, м/с.
# Позы собираются вручную по цепочке rest-трансформов (headless, без
# AnimationPlayer): global_i = global_parent * (rest_i с ротацией из клипа).
# Значения переносим в CharacterAnims.NATURAL_SPEED; тест
# test_ubc_anims.gd::test_natural_speeds сверяет, что константы не
# разъехались с ресурсом после перепечки.
#   godot --headless --path . -s res://tools/probe_clip_speed.gd
extends SceneTree

const UBC_SCENE: String = "res://assets/third_party/quaternius.com/" \
	+ "universal_base_characters/baked/ubc_male.res"
const ANIMS: String = "res://assets/third_party/quaternius.com/" \
	+ "universal_animation_library/anims_ubc.res"
const CLIPS: PackedStringArray = ["Walk", "Jog_Fwd", "Sprint", "Walk_Hand"]
const HZ: int = 120
## Какая доля размаха дуги стопы снизу считается фазой опоры.
const CONTACT_SHARE: float = 0.4


func _init() -> void:
	var scene := load(UBC_SCENE) as PackedScene
	var root := scene.instantiate()
	var sk := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var lib := load(ANIMS) as AnimationLibrary
	for clip_name: String in CLIPS:
		var anim := lib.get_animation(clip_name) as Animation
		assert(anim != null, "нет клипа %s" % clip_name)
		# Треки кость → индекс трека.
		var tracks := {}
		for i: int in anim.get_track_count():
			var path := anim.track_get_path(i)
			tracks[str(path).get_slice(":", 1)] = i
		var foot_l := sk.find_bone("foot_l")
		var foot_r := sk.find_bone("foot_r")
		var frames: int = int(anim.length * HZ) + 1
		var pts_l := PackedVector3Array()
		var pts_r := PackedVector3Array()
		var chain := _chains(sk, [foot_l, foot_r])
		for f: int in frames:
			var t: float = minf(f / float(HZ), anim.length)
			var globals := _pose_globals(sk, anim, tracks, chain, t)
			pts_l.append((globals[foot_l] as Transform3D).origin)
			pts_r.append((globals[foot_r] as Transform3D).origin)
		var path_len := 0.0
		var contact_time := 0.0
		for arr: PackedVector3Array in [pts_l, pts_r]:
			var low := 1e9
			var swing := 0.0
			for p: Vector3 in arr:
				low = minf(low, p.y)
				swing = maxf(swing, p.y)
			swing -= low
			var contact_top: float = low + swing * CONTACT_SHARE
			for i: int in range(1, arr.size()):
				if arr[i].y > contact_top:
					continue  # перенос стопы — не считается
				path_len += (arr[i] - arr[i - 1]).length()
				contact_time += 1.0 / HZ
		var natural: float = path_len / contact_time if contact_time > 0.0 else 0.0
		print("%-10s длина %.2f с, опора %.2f с, natural %.2f м/с"
			% [clip_name, anim.length, contact_time, natural])
	root.free()
	quit()


## Все кости цепочек root→foot (с повторами — проще, чем уникализация).
func _chains(sk: Skeleton3D, feet: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for foot: int in feet:
		var i: int = foot
		while i != -1:
			out.append(i)
			i = sk.get_bone_parent(i)
	return out


## Глобальные позы костей цепочки в момент t: локальная ротация из клипа
## (линейная интерполяция соседних ключей), трансляция — rest.
func _pose_globals(sk: Skeleton3D, anim: Animation, tracks: Dictionary,
		chain: PackedInt32Array, t: float) -> Dictionary:
	var locals := {}
	for i: int in chain:
		var q := sk.get_bone_rest(i).basis.get_rotation_quaternion()
		if tracks.has(sk.get_bone_name(i)):
			q = _sample_rot(anim, tracks[sk.get_bone_name(i)], t)
		locals[i] = Transform3D(Basis(q), sk.get_bone_rest(i).origin)
	var globals := {}
	for i: int in range(chain.size() - 1, -1, -1):  # от root вниз
		var bone: int = chain[i]
		var parent: int = sk.get_bone_parent(bone)
		globals[bone] = (globals[parent] as Transform3D) * (locals[bone] as Transform3D) \
			if parent != -1 and globals.has(parent) else locals[bone]
	return globals


func _sample_rot(anim: Animation, track: int, t: float) -> Quaternion:
	var count: int = anim.track_get_key_count(track)
	if count <= 1:
		return anim.track_get_key_value(track, 0)
	for i: int in count:
		var key_t: float = anim.track_get_key_time(track, i)
		if key_t >= t:
			if i == 0:
				return anim.track_get_key_value(track, 0)
			var prev_t: float = anim.track_get_key_time(track, i - 1)
			var prev: Quaternion = anim.track_get_key_value(track, i - 1)
			var next: Quaternion = anim.track_get_key_value(track, i)
			if key_t - prev_t <= 0.0:
				return prev
			return prev.slerp(next, (t - prev_t) / (key_t - prev_t))
	return anim.track_get_key_value(track, count - 1)
