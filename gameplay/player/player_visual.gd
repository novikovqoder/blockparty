# «Фонарщик» — модель персонажа (раздел 16 SPEC, шаг 5 П4.5): мягкая
# капля-тело со сглаженным затенением (тело вращения, сглаженные нормали),
# материал «леденец» (глянец + subsurface scattering + rim, без прозрачности),
# лицо с большими овальными глазами и розовыми щёчками (рта нет), капюшон
# с ушками, накидка с узором из ромбов и фонарик-сердечко на груди.
# Модель собирается кодом из примитивов в _ready (правило проекта: без
# внешних моделей, визуал заменяем). Анимации процедурные: «дыхание» в покое,
# покачивание и пыль из-под ног при беге, сжатие перед прыжком, вытягивание
# в полёте, сплющивание при приземлении, пружинная накидка.
# Палитра — по хэшу id игрока (Steam id или peer id), шесть наборов;
# фонарик ярче, когда рядом другой игрок: мир вызывает set_glow_level()
# по уже синхронизированным позициям — без нового сетевого трафика.
# Визуал отделён от логики: player.gd/remote_player.gd знают только
# set_state()/play_one_shot(). Модель смотрит в +Z (как раньше «мармеладка»).
class_name PlayerVisual
extends Node3D

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")

## Палитр «Фонарщика» (раздел 16): Персик, Мята, Слива, Лимон, Голубика,
## Карамель.
const PALETTES: int = 6
## Скорость сглаживания параметров позы (доля в секунду): переходы без рывков.
const POSE_SMOOTH: float = 10.0
## Пружина сквоша: жёсткость и демпфирование (мультяшная упругость).
const SQUASH_STIFF: float = 110.0
const SQUASH_DAMP: float = 7.5
## Пружина накидки: жёсткость и демпфирование (покачивается с задержкой).
const CAPE_STIFF: float = 40.0
const CAPE_DAMP: float = 6.0
## Моргание: пауза между морганиями, с (случайная в диапазоне — персонаж
## не остров и не мобы, randf допустим), и длительность закрытых глаз, с.
const BLINK_EVERY := Vector2(3.0, 6.0)
const BLINK_TIME: float = 0.13
## Частота «дыхания» в покое, Гц.
const BREATH_HZ: float = 0.35
## Пыль из-под ног при беге: пауза между облачками, с, и параметры облачка.
const DUST_EVERY: float = 0.26
const DUST_COLOR := Color(0.87, 0.82, 0.74)
## Вертикальная полуось овального глаза (моргание сжимает её).
const EYE_SCALE_Y: float = 1.4
## Базовый наклон накидки назад от спины, рад (чтобы не тонула в теле).
const CAPE_BASE_TILT: float = 0.22

## Узлы модели (создаются в _ready): rig качается и «дышит», ножки шагают
## отдельно — у них свой пивот у земли.
var rig: Node3D
var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var face: Node3D
var cape_root: Node3D

var _body_material: StandardMaterial3D
var _hood_material: StandardMaterial3D
var _cape_materials: Array[StandardMaterial3D] = []
var _diamond_material: StandardMaterial3D
var _eye_l: MeshInstance3D
var _eye_r: MeshInstance3D
var _cape_segments: Array[Node3D] = []
var _bulb_material: StandardMaterial3D
var _light: OmniLight3D

## Базовое состояние (устойчивое: idle, walk, run, jump, fall, hang, sit…).
var _base_state: int = Protocol.AnimState.IDLE
## Разовая анимация поверх базовой (land, bonk, эмоция) и остаток времени.
var _one_shot: int = -1
var _one_shot_left: float = 0.0
## Индекс выбранной палитры и текущий уровень свечения фонарика.
var _palette_index: int = 0
var _glow_target: float = 0.0
var _glow_current: float = 0.0

## Текущие значения параметров позы (сглаживаются к целевым).
var _pose: Dictionary = {}
## Фаза цикла походки (рад) и таймеры моргания, пыли.
var _phase: float = 0.0
var _blink_timer: float = 2.0
var _blink_phase: float = -1.0  # < 0 — глаза открыты
var _dust_timer: float = 0.0
## Пружины: сквош (масштаб по росту) и накидка (угол за спиной, рад;
## положительный угол отклоняет накидку назад).
var _squash: float = 1.0
var _squash_vel: float = 0.0
var _cape_angle: float = 0.0
var _cape_vel: float = 0.0
## Импульс «тычка» (ударился): наклон корпуса вперёд, затухает.
var _bonk_impulse: float = 0.0


func _ready() -> void:
	_build_model()
	_pose = _pose_targets(Protocol.AnimState.IDLE)


func _process(delta: float) -> void:
	if _one_shot_left > 0.0:
		_one_shot_left -= delta
		if _one_shot_left <= 0.0:
			_one_shot = -1
	_smooth_pose(_pose_targets(_active_state()), delta)
	_animate(delta)
	_blink(delta)
	_lantern(delta)
	_dust(delta)


# --- Публичный интерфейс (вызывают player.gd / remote_player.gd / мир) ---

## Устойчивое состояние (движение, висит, сидит, за руку).
func set_state(state: int) -> void:
	if state == Protocol.AnimState.JUMP and _base_state != state:
		# Сжатие перед прыжком: корпус приседает, пружиной вытягивается в полёте.
		_squash = minf(_squash, 0.86)
		_cape_vel += 2.5
	_base_state = state
	_one_shot = -1
	_one_shot_left = 0.0


## Разовая анимация поверх базовой (приземление, тычок, эмоция); после
## duration секунд возвращается базовое состояние.
func play_one_shot(state: int, duration: float) -> void:
	_one_shot = state
	_one_shot_left = duration
	match state:
		Protocol.AnimState.LAND:
			# Сплющивание при приземлении — пружина вернёт упруго; накидка
			# хлопнула вперёд.
			_squash = 0.8
			_cape_vel -= 3.0
		Protocol.AnimState.BONK:
			_bonk_impulse = 0.55


## Палитра по id игрока (Steam id в Steam-режиме, peer id в ENet): одинаковый
## id — одинаковый набор цветов у всех участников, без передачи по сети.
func setup_palette(id: int) -> void:
	_palette_index = palette_index(id)
	_body_material.albedo_color = PAL.lantern_body[_palette_index]
	var limb: Color = PAL.lantern_body[_palette_index].darkened(0.1)
	for node: Node3D in [arm_l, arm_r, leg_l, leg_r]:
		var mesh := node.get_child(0) as MeshInstance3D
		if mesh != null:
			(mesh.material_override as StandardMaterial3D).albedo_color = limb
	_hood_material.albedo_color = PAL.lantern_hood[_palette_index]
	for material: StandardMaterial3D in _cape_materials:
		material.albedo_color = PAL.lantern_hood[_palette_index]
	var light_color: Color = PAL.lantern_light[_palette_index]
	_diamond_material.albedo_color = light_color
	_diamond_material.emission = light_color
	_bulb_material.albedo_color = light_color
	_bulb_material.emission = light_color
	_light.light_color = light_color


## Яркость фонарика 0..1: рядом другой игрок (мир считает по локальным
## позициям), «взяться за руки» и костёр — П5. Значение клампится;
## нарастание плавное (lantern_glow_ramp_sec).
func set_glow_level(level: float) -> void:
	_glow_target = clampf(level, 0.0, 1.0)


## Текущий целевой уровень свечения (0..1) — для тестов.
func glow_level() -> float:
	return _glow_target


## Индекс палитры по id: шесть достижимых наборов, одинаковый id — один набор.
static func palette_index(id: int) -> int:
	return absi(id) % PALETTES


## Материал тела — для тестов «леденца» (непрозрачный, глянец, SSS, rim).
func body_material() -> StandardMaterial3D:
	return _body_material


func _active_state() -> int:
	return _one_shot if _one_shot_left > 0.0 else _base_state


# --- Позы состояний (как качается модель — визуальные числа, константы
#     движения персонажа в balance не дублируются) ---

## Целевые параметры позы состояния: углы ног и ручек-пивотов, наклон
## корпуса, добавка высоты, сквош, угол накидки (плюс к базовому наклону),
## частота походки и амплитуды циклов (шаг, взмахи, покачивание, машущая
## ручка).
func _pose_targets(state: int) -> Dictionary:
	match state:
		Protocol.AnimState.IDLE:
			return _p({})
		Protocol.AnimState.WALK:
			return _p({
				"gait": 1.7, "leg_amp": 0.5, "arm_amp": 0.35,
				"bob": 0.028, "roll": 0.035, "cape": 0.24,
			})
		Protocol.AnimState.RUN:
			return _p({
				"gait": 2.4, "leg_amp": 0.78, "arm_amp": 0.55,
				"bob": 0.05, "roll": 0.055, "lean": 0.12, "cape": 0.55,
			})
		Protocol.AnimState.JUMP:
			return _p({
				"leg_l": -0.5, "leg_r": -0.35,
				"arm_l": Vector3(-0.5, 0.0, -0.6), "arm_r": Vector3(-0.5, 0.0, 0.6),
				"squash": 1.09, "cape": 0.8,
			})
		Protocol.AnimState.FALL:
			return _p({
				"leg_l": -0.25, "leg_r": -0.1,
				"arm_l": Vector3(2.6, 0.0, -0.2), "arm_r": Vector3(2.6, 0.0, 0.2),
				"squash": 1.05, "cape": 0.35,
			})
		Protocol.AnimState.LAND:
			return _p({
				"leg_l": -0.45, "leg_r": -0.45,
				"arm_l": Vector3(0.5, 0.0, -0.5), "arm_r": Vector3(0.5, 0.0, 0.5),
				"squash": 0.82, "cape": -0.3,
			})
		Protocol.AnimState.BONK:
			return _p({"squash": 0.94})
		Protocol.AnimState.HANG:
			return _p({
				"leg_l": -0.45, "leg_r": -0.3,
				"arm_l": Vector3(2.9, 0.0, -0.25), "arm_r": Vector3(2.9, 0.0, 0.25),
				"squash": 0.97, "cape": 0.2,
			})
		Protocol.AnimState.PULLED_UP:
			return _p({
				"arm_l": Vector3(2.9, 0.0, -0.2), "arm_r": Vector3(2.9, 0.0, 0.2),
				"lift": 0.22, "cape": 0.5,
			})
		Protocol.AnimState.HELP_PULL:
			return _p({
				"arm_r": Vector3(-1.2, 0.0, 0.1), "lean": 0.28, "cape": 0.3,
			})
		Protocol.AnimState.SIT:
			return _p({
				"leg_l": -1.3, "leg_r": -1.3,
				"arm_l": Vector3(0.0, 0.0, -0.6), "arm_r": Vector3(0.0, 0.0, 0.6),
				"squash": 0.88, "lift": -0.24,
			})
		Protocol.AnimState.HOLD_HAND:
			return _p({
				"arm_r": Vector3(0.15, 0.0, 0.8), "cape": 0.1,
			})
		Protocol.AnimState.WAVE, Protocol.AnimState.EMOTE_1:
			# «Привет!» — правая ручка над головой, машет.
			return _p({"arm_r": Vector3(0.0, 0.0, 2.5), "arm_wave": 0.4})
		Protocol.AnimState.EMOTE_2:
			# «Спасибо!» — поклон.
			return _p({"lean": 0.5, "cape": 0.25})
		Protocol.AnimState.EMOTE_3:
			# «Сюда!» — правая ручка вперёд, манит.
			return _p({"arm_r": Vector3(-1.3, 0.0, 0.2), "arm_wave": 0.25})
		Protocol.AnimState.EMOTE_4:
			# «Подожди!» — ручки в стороны, покачивание.
			return _p({
				"arm_l": Vector3(0.0, 0.0, -1.2), "arm_r": Vector3(0.0, 0.0, 1.2),
				"roll": 0.07,
			})
		Protocol.AnimState.EMOTE_5:
			# «Ха-ха» — подпрыгивает.
			return _p({"gait": 3.0, "bob": 0.05, "leg_amp": 0.2, "cape": 0.3})
		Protocol.AnimState.EMOTE_6:
			# «Помогите!» — обе ручки вверх, машет.
			return _p({
				"arm_l": Vector3(0.0, 0.0, -2.6), "arm_r": Vector3(0.0, 0.0, 2.6),
				"arm_wave": 0.3,
			})
		_:
			return _p({})


## Поза с нейтральными значениями по умолчанию (названное — переопределено).
func _p(override: Dictionary) -> Dictionary:
	var defaults := {
		"leg_l": 0.0, "leg_r": 0.0,
		"arm_l": Vector3.ZERO, "arm_r": Vector3.ZERO,
		"lean": 0.0, "lift": 0.0, "squash": 1.0, "cape": 0.0,
		"gait": 0.0, "leg_amp": 0.0, "arm_amp": 0.0,
		"bob": 0.0, "roll": 0.0, "arm_wave": 0.0,
	}
	defaults.merge(override, true)
	return defaults


## Экспоненциальное сглаживание всех параметров позы к целевым.
func _smooth_pose(target: Dictionary, delta: float) -> void:
	var k: float = 1.0 - exp(-POSE_SMOOTH * delta)
	for key: String in target:
		var to: Variant = target[key]
		var from: Variant = _pose.get(key, to)
		if to is Vector3:
			_pose[key] = (from as Vector3).lerp(to as Vector3, k)
		else:
			_pose[key] = lerpf(from as float, to as float, k)


## Процедурные анимации: походка, «дыхание», сквош-пружина, накидка.
func _animate(delta: float) -> void:
	var t: float = Session.world_time
	var gait: float = _pose["gait"]
	if gait > 0.01:
		_phase = fposmod(_phase + TAU * gait * delta, TAU)

	# Пружина сквоша к целевому (сжатие/вытягивание — мультяшная упругость).
	_squash_vel += (float(_pose["squash"]) - _squash) * SQUASH_STIFF * delta
	_squash_vel *= exp(-SQUASH_DAMP * delta)
	_squash += _squash_vel * delta
	# «Дыхание»: лёгкое увеличение корпуса, на бегу слабее.
	var breath: float = sin(t * TAU * BREATH_HZ) * (0.35 + 0.65 * (1.0 - minf(gait, 1.0)))
	var wide: float = 1.0 / sqrt(clampf(_squash, 0.3, 2.0))
	rig.scale = Vector3(
		wide * (1.0 + 0.012 * breath), _squash * (1.0 + 0.02 * breath),
		wide * (1.0 + 0.012 * breath))
	rig.position.y = float(_pose["lift"]) + float(_pose["bob"]) * absf(sin(_phase))
	# Наклон корпуса вперёд + «тычок» при ударе (экспоненциально затухает).
	_bonk_impulse = lerpf(_bonk_impulse, 0.0, 6.0 * delta)
	rig.rotation.x = float(_pose["lean"]) + _bonk_impulse
	rig.rotation.z = float(_pose["roll"]) * sin(2.0 * _phase)

	# Походка: ножки шагают, ручки машут в противофазе, правая — приветствие.
	leg_l.rotation.x = float(_pose["leg_l"]) + float(_pose["leg_amp"]) * sin(_phase)
	leg_r.rotation.x = float(_pose["leg_r"]) - float(_pose["leg_amp"]) * sin(_phase)
	var wave: float = float(_pose["arm_wave"]) * sin(t * TAU * 1.8)
	arm_l.rotation = Vector3(-float(_pose["arm_amp"]) * sin(_phase), 0.0, 0.0) \
		+ (_pose["arm_l"] as Vector3)
	arm_r.rotation = Vector3(float(_pose["arm_amp"]) * sin(_phase), 0.0, wave) \
		+ (_pose["arm_r"] as Vector3)

	# Накидка: пружина к целевому углу (покачивается с задержкой; при
	# прыжке подлетает, при приземлении хлопает), сегменты — волной.
	_cape_vel += (float(_pose["cape"]) - _cape_angle) * CAPE_STIFF * delta
	_cape_vel *= exp(-CAPE_DAMP * delta)
	_cape_angle += _cape_vel * delta
	var share: float = 1.0
	var calm: float = 1.0 - minf(gait, 1.0) * 0.5  # в покое колышется заметнее
	for i: int in _cape_segments.size():
		share *= 0.75
		_cape_segments[i].rotation.x = CAPE_BASE_TILT + _cape_angle * (1.0 - share) \
			+ (0.05 + 0.025 * sin(t * 2.1 + float(i))) * calm


## Моргание: пауза 3–6 с (случайная), глаза закрываются на мгновение.
func _blink(delta: float) -> void:
	if _blink_phase >= 0.0:
		_blink_phase += delta / BLINK_TIME
		if _blink_phase >= 1.0:
			_blink_phase = -1.0
			_blink_timer = randf_range(BLINK_EVERY.x, BLINK_EVERY.y)
	else:
		_blink_timer -= delta
		if _blink_timer <= 0.0:
			_blink_phase = 0.0
	var closed: float = 1.0
	if _blink_phase >= 0.0:
		closed = 1.0 - 0.92 * sin(PI * clampf(_blink_phase, 0.0, 1.0))
	_eye_l.scale.y = EYE_SCALE_Y * closed
	_eye_r.scale.y = EYE_SCALE_Y * closed


## Фонарик-сердечко: спокойное мерцание и плавное нарастание яркости,
## когда рядом другой игрок (set_glow_level от мира, раздел 16).
func _lantern(delta: float) -> void:
	_glow_current = move_toward(
		_glow_current, _glow_target, delta / maxf(B.lantern_glow_ramp_sec, 0.01))
	var t: float = Session.world_time
	var flicker: float = 0.06 * sin(t * 2.1) + 0.03 * sin(t * 3.4 + 1.3)
	_light.light_energy = (0.55 + flicker) * (1.0 + _glow_current * 1.3)
	_bulb_material.emission_energy_multiplier = \
		(1.3 + flicker * 2.0) * (1.0 + _glow_current * 1.6)


## Пыль из-под ног при беге (маленькие облачка; при приземлении облачко
## пускает player.gd — общий Fx).
func _dust(delta: float) -> void:
	if _active_state() != Protocol.AnimState.RUN:
		_dust_timer = 0.0
		return
	_dust_timer -= delta
	if _dust_timer <= 0.0:
		_dust_timer = DUST_EVERY
		Fx.puff(self, Vector3(0.0, 0.05, 0.12), DUST_COLOR, 3, 0.09, 0.75)


# --- Сборка модели (примитивы, «ноги» модели на нуле, лицо в +Z) ---

func _build_model() -> void:
	rig = _pivot("Rig", Vector3.ZERO)
	add_child(rig)

	# Капля-тело: тело вращения по профилю (чуть шире внизу, округлый верх),
	# сглаженные нормали — мягкая форма (раздел 16).
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _lathe(BODY_PROFILE, 20)
	_body_material = candy(PAL.lantern_body[0])
	body.material_override = _body_material
	rig.add_child(body)

	# Ножки-лапки и ручки-кругляшки: пивоты у тела, меш-сфера на отростке.
	for pair: Array in [["LegL", -1.0], ["LegR", 1.0]]:
		var leg := _pivot(pair[0], Vector3(0.115 * pair[1], 0.16, 0.02))
		add_child(leg)
		var paw := _ball(
			Vector3(0.0, -0.07, 0.03), 0.085, PAL.lantern_body[0].darkened(0.1))
		paw.scale = Vector3(1.0, 0.75, 1.25)
		leg.add_child(paw)
		if pair[0] == "LegL":
			leg_l = leg
		else:
			leg_r = leg
	for pair: Array in [["ArmL", -1.0], ["ArmR", 1.0]]:
		var arm := _pivot(pair[0], Vector3(0.26 * pair[1], 0.84, 0.02))
		rig.add_child(arm)
		var hand := _ball(
			Vector3(0.085 * pair[1], -0.055, 0.01), 0.075,
			PAL.lantern_body[0].darkened(0.1))
		arm.add_child(hand)
		if pair[0] == "ArmL":
			arm_l = arm
		else:
			arm_r = arm

	# Лицо: большие овальные тёмные глаза с бликом, розовые щёчки (рта нет).
	# Вынос по Z — наружу от профиля тела (на высоте щёк радиус тела ~0.28:
	# глубже щёчки тонут в капле и их не видно).
	face = _pivot("Face", Vector3.ZERO)
	rig.add_child(face)
	for side: float in [-1.0, 1.0]:
		var eye := _ball(Vector3(0.085 * side, 1.06, 0.215), 0.055, EYE_COLOR)
		eye.scale = Vector3(1.0, EYE_SCALE_Y, 0.55)
		face.add_child(eye)
		# Блик — маленькая белая сфера, «живой» взгляд.
		var glint := _ball(
			Vector3(0.105 * side, 1.09, 0.245), 0.016, Color.WHITE)
		face.add_child(glint)
		var cheek := _ball(Vector3(0.155 * side, 0.99, 0.23), 0.045, CHEEK_COLOR)
		cheek.scale = Vector3(1.0, 0.75, 0.5)
		face.add_child(cheek)
		if side < 0.0:
			_eye_l = eye
		else:
			_eye_r = eye

	# Капюшон: сглаженная чаша над головой (лицо открыто — край выше глаз),
	# ушки — короткие закруглённые капсулы, свисающие назад.
	_hood_material = candy(PAL.lantern_hood[0])
	var hood := _pivot("Hood", Vector3(0.0, 0.0, -0.03))
	rig.add_child(hood)
	var hood_mesh := MeshInstance3D.new()
	hood_mesh.name = "HoodMesh"
	hood_mesh.mesh = _lathe(HOOD_PROFILE, 20)
	hood_mesh.material_override = _hood_material
	hood.add_child(hood_mesh)
	for side: float in [-1.0, 1.0]:
		var ear := _pivot("Ear", Vector3(0.12 * side, 1.42, -0.2))
		ear.rotation.x = -2.2  # капсула уходит вниз-назад от макушки капюшона
		hood.add_child(ear)
		var ear_mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.05
		capsule.height = 0.22
		ear_mesh.mesh = capsule
		ear_mesh.material_override = _hood_material
		ear_mesh.position = Vector3(0.0, 0.08, 0.0)
		ear.add_child(ear_mesh)

	# Накидка до середины спины: цепочка сегментов-лент, каждый следующий
	# крепится к нижнему краю предыдущего; узор из ромбов по нижнему краю
	# цветом фонарика. Качается пружиной в _animate.
	cape_root = _pivot("Cape", Vector3(0.0, 1.06, -0.3))
	rig.add_child(cape_root)
	_diamond_material = _cape_material(PAL.lantern_light[0], true)
	var segment_parent: Node3D = cape_root
	for i: int in 3:
		var hang: float = 0.0 if i == 0 else -0.15
		var segment := _pivot("CapeSeg%d" % i, Vector3(0.0, hang, 0.0))
		segment_parent.add_child(segment)
		var mesh := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(lerpf(0.42, 0.52, float(i) / 2.0), 0.15)
		mesh.mesh = quad
		mesh.material_override = _cape_material(PAL.lantern_hood[0])
		mesh.position = Vector3(0.0, -0.075, 0.0)
		segment.add_child(mesh)
		if i == 2:
			for d: int in 5:
				var diamond := MeshInstance3D.new()
				var diamond_quad := QuadMesh.new()
				diamond_quad.size = Vector2(0.07, 0.07)
				diamond.mesh = diamond_quad
				diamond.material_override = _diamond_material
				diamond.position = Vector3(-0.16 + 0.08 * d, -0.1, 0.0)
				diamond.rotation.z = PI / 4.0
				segment.add_child(diamond)
		_cape_segments.append(segment)
		segment_parent = segment

	# Фонарик-сердечко: шнурок от шеи и светящийся шарик на груди,
	# маленький источник света (радиус — balance).
	var lantern := _pivot("Lantern", Vector3(0.0, 1.04, 0.22))
	rig.add_child(lantern)
	var cord := MeshInstance3D.new()
	var cord_mesh := CylinderMesh.new()
	cord_mesh.top_radius = 0.012
	cord_mesh.bottom_radius = 0.012
	cord_mesh.height = 0.16
	cord.mesh = cord_mesh
	var cord_material := StandardMaterial3D.new()
	cord_material.albedo_color = Color(0.22, 0.19, 0.24)
	cord_material.roughness = 0.8
	cord.material_override = cord_material
	cord.position = Vector3(0.0, -0.05, 0.03)
	cord.rotation.x = 0.35
	lantern.add_child(cord)
	var bulb := MeshInstance3D.new()
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.055
	bulb_mesh.height = 0.11
	bulb.mesh = bulb_mesh
	_bulb_material = StandardMaterial3D.new()
	_bulb_material.albedo_color = PAL.lantern_light[0]
	_bulb_material.emission_enabled = true
	_bulb_material.emission = PAL.lantern_light[0]
	_bulb_material.emission_energy_multiplier = 1.3
	bulb.material_override = _bulb_material
	bulb.position = Vector3(0.0, -0.13, 0.1)
	lantern.add_child(bulb)
	_light = OmniLight3D.new()
	_light.name = "LanternLight"
	_light.omni_range = B.lantern_light_radius
	_light.light_color = PAL.lantern_light[0]
	_light.light_energy = 0.55
	_light.shadow_enabled = false
	bulb.add_child(_light)


## Профиль капли-тела: точки (высота, радиус) снизу вверх — чуть шире
## внизу, округлый верх; рост с капюшоном около 1.5 м (коллизия — раздел 5).
const BODY_PROFILE: Array[Vector2] = [
	Vector2(0.16, 0.13), Vector2(0.22, 0.22), Vector2(0.32, 0.44),
	Vector2(0.345, 0.66), Vector2(0.33, 0.84), Vector2(0.27, 1.0),
	Vector2(0.2, 1.12), Vector2(0.12, 1.24), Vector2(0.05, 1.33),
	Vector2(0.015, 1.38),
]

## Профиль капюшона-чаши: край над глазами (лицо открыто), макушка выше тела.
const HOOD_PROFILE: Array[Vector2] = [
	Vector2(1.12, 0.335), Vector2(1.24, 0.345), Vector2(1.36, 0.3),
	Vector2(1.45, 0.2), Vector2(1.52, 0.06),
]

## Цвета лица: почти чёрные глаза (с белым бликом) и розовые щёчки.
const EYE_COLOR := Color(0.13, 0.11, 0.16)
const CHEEK_COLOR := Color(1.0, 0.62, 0.62)


# --- Примитивы модели ---

func _pivot(node_name: String, position: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = position
	return node


## Сфера с простым материалом (глаза, блики, щёчки, лапки, ручки).
func _ball(position: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.45
	mesh.material_override = material
	mesh.position = position
	return mesh


## Тело вращения по профилю (высота, радиус): вершины колец общие через
## индексы, generate_normals сглаживает стыки — мягкое затенение капли.
func _lathe(profile: Array[Vector2], segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point: Vector2 in profile:
		for s: int in segments:
			var angle: float = TAU * float(s) / float(segments)
			st.add_vertex(Vector3(
				point.y * sin(angle), point.x, point.y * cos(angle)))
	for i: int in profile.size() - 1:
		for s: int in segments:
			var next: int = (s + 1) % segments
			var a: int = i * segments + s
			var b: int = i * segments + next
			var c: int = (i + 1) * segments + next
			var d: int = (i + 1) * segments + s
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(a)
			st.add_index(c)
			st.add_index(d)
	st.generate_normals()
	return st.commit()


## Материал «леденец»: глянец roughness ~0.45 и subsurface scattering
## для мягкости — и всегда непрозрачный (тело «сочное», не желейное).
## Rim не используем: на compatibility-рендерере (скриншоты сервера, слабые
## GPU игроков) он заливает материал белым — стенд шага 5 П4.5.
static func candy(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.45
	material.subsurf_scatter_enabled = true
	material.subsurf_scatter_strength = 0.35
	return material


## Материал накидки: «леденец», двусторонний (лента тонкая); вариант
## diamond=true — узорные ромбы цвета фонарика, слегка светятся.
func _cape_material(color: Color, diamond: bool = false) -> StandardMaterial3D:
	var material := candy(color)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if diamond:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.4
	return material
