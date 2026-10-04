# «Мармеладка» — модель персонажа (разделы 5, 16 SPEC): округлое тело
# (CapsuleMesh, высота около 1.5 м), большие глаза с бликом, маленькие руки
# и ступни — капсулы; сглаженные, в отличие от огранённого мира, поэтому
# обычный StandardMaterial3D, а не lowpoly-шейдер. Модель собирается кодом
# из примитивов в _ready (правило проекта: без внешних моделей, визуал
# заменяем). Анимации — твины с упругостью: сжатие при приземлении,
# вытягивание в прыжке, покачивание при беге, взмахи руками при эмоциях.
# Визуал отделён от логики: player.gd только вызывает set_state()/
# play_one_shot() с кодом Protocol.AnimState.
# Косметика (раздел 15): цвет тела (8), головной убор (6), плащ (4, слегка
# колышется), след при беге (4 цвета). Гардероб и передача по сети — П8;
# сейчас каждый игрок носит выбранный локально вариант (по умолчанию —
# бесплатный первый).
class_name PlayerVisual
extends Node3D

const PAL: Palette = preload("res://assets/palette.tres")

## Длительность перехода в позу, с.
const POSE_TIME: float = 0.1
## Нейтральная высота корпуса, м (низ ступней на нуле модели).
const HIPS_Y: float = 0.55
## Приседание при приземлении, м.
const LAND_DIP: float = 0.1
## Подъём корпуса при вытягивании, м.
const PULL_LIFT: float = 0.3

## Косметика — головные уборы (раздел 15: кепка, корона, шапка, нимб,
## рожки, цветок; 0 — без убора).
const HATS: PackedStringArray = ["none", "cap", "crown", "beanie", "halo", "horns", "flower"]

## Узлы модели (создаются в _ready).
var hips: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D

var _body_mesh: MeshInstance3D
var _cape: Node3D
var _trail: GPUParticles3D
var _cape_material: StandardMaterial3D
var _trail_material: ParticleProcessMaterial

## Базовое состояние (устойчивое: idle, walk, run, jump, fall, hang, sit…).
var _base_state: int = Protocol.AnimState.IDLE
## Осталось секунд у разовой анимации (land, bonk, wave, emote…); 0 — нет.
var _one_shot_left: float = 0.0
## Насколько «бежит» [0, 1] — плащ и след при беге.
var _run_factor: float = 0.0
## Выбранная косметика (индексы палитры).
var _body_index: int = 0
var _cape_index: int = 0
var _trail_index: int = 0

var _tweens: Array[Tween] = []


func _ready() -> void:
	_build_model()


func _process(delta: float) -> void:
	if _one_shot_left > 0.0:
		_one_shot_left -= delta
		if _one_shot_left <= 0.0:
			_apply(_base_state)
	# Плащ колышется всегда, при беге — тянется назад (раздел 16).
	var running: float = 1.0 if _base_state == Protocol.AnimState.RUN else 0.0
	_run_factor = move_toward(_run_factor, running, delta * 4.0)
	if _cape != null:
		var t: float = Session.world_time
		_cape.rotation.x = 0.12 + 0.08 * sin(t * 2.3) + _run_factor * (0.55 + 0.1 * sin(t * 9.0))
	if _trail != null:
		_trail.emitting = _trail_index > 0 and _run_factor > 0.5


# --- Косметика (раздел 15; гардероб и передача по сети — П8) ---

## Надеть косметику: индексы цвета тела, убора (HATS), плаща и следа
## (0 — нет). Вызывается после появления модели; -1 оставляет текущее.
func set_cosmetics(body_index: int, hat_index: int, cape_index: int, trail_index: int) -> void:
	if body_index >= 0:
		_body_index = wrapf(body_index, 0, PAL.body_colors.size()) as int
	if cape_index >= 0:
		_cape_index = wrapf(cape_index, 0, PAL.cape_colors.size()) as int
	if trail_index >= 0:
		_trail_index = wrapf(trail_index, 0, PAL.cape_colors.size()) as int
	_paint_body()
	_ensure_hat(hat_index)
	_ensure_cape()


# --- Состояния ---

## Установить устойчивое состояние (движение, висит, сидит, за руку).
func set_state(state: int) -> void:
	_base_state = state
	_one_shot_left = 0.0
	_apply(state)


## Разовая анимация поверх базовой (приземление, тычок, эмоция); после
## duration секунд возвращается базовое состояние.
func play_one_shot(state: int, duration: float) -> void:
	_apply(state)
	_one_shot_left = duration


func _apply(state: int) -> void:
	_stop_tweens()
	match state:
		Protocol.AnimState.IDLE:
			_pose({})
			_swing(hips, "position:y", HIPS_Y, 0.012, 2.0)
		Protocol.AnimState.WALK:
			_pose({})
			_gait(0.4, 0.7, 0.25)
			_swing(hips, "rotation:z", 0.0, 0.03, 1.4)
		Protocol.AnimState.RUN:
			_pose({"hips": Vector3(-0.1, 0.0, 0.0)})
			_gait(0.85, 0.45, 0.6)
			_swing(hips, "rotation:z", 0.0, 0.05, 0.9)
			_swing(hips, "position:y", HIPS_Y, 0.03, 0.45)
		Protocol.AnimState.JUMP:
			_pose({
				"arm_l": Vector3(-0.8, 0.0, 0.0),
				"arm_r": Vector3(-0.65, 0.0, 0.0),
				"leg_l": Vector3(-0.4, 0.0, 0.0),
				"leg_r": Vector3(-0.25, 0.0, 0.0),
			}, -1.0, Vector3(0.94, 1.12, 0.94))
		Protocol.AnimState.FALL:
			_pose({
				"arm_l": Vector3(2.7, 0.0, 0.0),
				"arm_r": Vector3(2.7, 0.0, 0.0),
				"leg_l": Vector3(-0.3, 0.0, 0.0),
				"leg_r": Vector3(-0.15, 0.0, 0.0),
			}, -1.0, Vector3(0.96, 1.06, 0.96))
		Protocol.AnimState.LAND:
			_pose({})
			_squash(Vector3(1.14, 0.82, 1.14))
			_dip(-LAND_DIP, POSE_TIME)
		Protocol.AnimState.BONK:
			_pose({})
			_bonk()
		Protocol.AnimState.HANG:
			_pose({
				"arm_l": Vector3(3.0, 0.0, 0.0),
				"arm_r": Vector3(3.0, 0.0, 0.0),
				"leg_l": Vector3(-0.4, 0.0, 0.0),
				"leg_r": Vector3(-0.25, 0.0, 0.0),
			}, -1.0, Vector3(1.04, 0.96, 1.04))
			_swing(hips, "rotation:z", 0.0, 0.06, 2.0)
		Protocol.AnimState.PULLED_UP:
			_pose({
				"arm_l": Vector3(3.0, 0.0, 0.0),
				"arm_r": Vector3(3.0, 0.0, 0.0),
			})
			_dip(PULL_LIFT, 0.3)
		Protocol.AnimState.HELP_PULL:
			_pose({
				"arm_r": Vector3(-1.35, 0.0, 0.0),
				"hips": Vector3(-0.15, 0.0, 0.0),
			})
		Protocol.AnimState.SIT:
			_pose({
				"leg_l": Vector3(-1.35, 0.0, 0.0),
				"leg_r": Vector3(-1.35, 0.0, 0.0),
				"arm_l": Vector3(-0.5, 0.0, 0.0),
				"arm_r": Vector3(-0.5, 0.0, 0.0),
			}, HIPS_Y - 0.35, Vector3(1.08, 0.9, 1.08))
		Protocol.AnimState.HOLD_HAND:
			_pose({
				"arm_r": Vector3(0.0, 0.0, 0.7),
			})
		Protocol.AnimState.WAVE, Protocol.AnimState.EMOTE_1:
			# «Привет!» — правая рука над головой, машет.
			_pose({"arm_r": Vector3(0.0, 0.0, 2.7)})
			_swing(arm_r, "rotation:z", 2.7, 0.35, 0.55)
		Protocol.AnimState.EMOTE_2:
			# «Спасибо!» — поклон.
			_pose({})
			_bow()
		Protocol.AnimState.EMOTE_3:
			# «Сюда!» — рука вперёд, манит.
			_pose({"arm_r": Vector3(-1.2, 0.0, 0.0)})
			_swing(arm_r, "rotation:z", 0.0, 0.3, 0.5)
		Protocol.AnimState.EMOTE_4:
			# «Подожди!» — руки в стороны, лёгкое покачивание.
			_pose({
				"arm_l": Vector3(0.0, 0.0, -1.3),
				"arm_r": Vector3(0.0, 0.0, 1.3),
			})
			_swing(arm_l, "rotation:z", -1.3, 0.12, 1.2)
			_swing(arm_r, "rotation:z", 1.3, 0.12, 1.2)
		Protocol.AnimState.EMOTE_5:
			# «Ха-ха» — подпрыгивает, корпус запрокинут.
			_pose({"head": Vector3(-0.3, 0.0, 0.0)})
			_swing(hips, "position:y", HIPS_Y, 0.06, 0.5)
		Protocol.AnimState.EMOTE_6:
			# «Помогите!» — обе руки вверх, машет.
			_pose({
				"arm_l": Vector3(0.0, 0.0, -2.8),
				"arm_r": Vector3(0.0, 0.0, 2.8),
			})
			_swing(arm_l, "rotation:z", -2.8, 0.3, 0.6)
			_swing(arm_r, "rotation:z", 2.8, 0.3, 0.6)
		_:
			_pose({})


# --- Инструменты аниматора ---

func _stop_tweens() -> void:
	for tween: Tween in _tweens:
		tween.kill()
	_tweens.clear()


func _node_for(key: String) -> Node3D:
	match key:
		"hips": return hips
		"head": return head
		"arm_l": return arm_l
		"arm_r": return arm_r
		"leg_l": return leg_l
		"leg_r": return leg_r
	return hips


## Применить позу: плавные твины поворотов всех частей к целевым углам
## (не названные в pose части — к нейтрали) и масштаб корпуса squash
## (приземление сжимает, прыжок вытягивает — раздел 16). hips_y задаёт
## высоту корпуса (SIT); по умолчанию положение не трогается, чтобы не
## мешать качанию.
func _pose(pose: Dictionary, hips_y: float = -1.0, squash: Vector3 = Vector3.ONE) -> void:
	var parts: Array[String] = ["hips", "head", "arm_l", "arm_r", "leg_l", "leg_r"]
	var tween := create_tween()
	tween.set_parallel(true)
	for part: String in parts:
		tween.tween_property(_node_for(part), "rotation", pose.get(part, Vector3.ZERO), POSE_TIME)
	tween.tween_property(hips, "scale", squash, POSE_TIME)
	if hips_y >= 0.0:
		tween.tween_property(hips, "position:y", hips_y, POSE_TIME)
	_tweens.append(tween)


## Цикл качания вокруг базового значения base: base → base±amp → base,
## период period с. Плавно стартует из текущего значения.
func _swing(node: Node3D, property: String, base: float, amp: float, period: float) -> void:
	var tween := create_tween().set_loops(-1)
	tween.tween_property(node, property, base + amp, period * 0.25)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, property, base - amp, period * 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, property, base, period * 0.25)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tweens.append(tween)


## Походка: ноги и руки в противофазе (раздел 16 — твины поворотов конечностей).
func _gait(leg_amp: float, period: float, arm_amp: float) -> void:
	_swing(leg_l, "rotation:x", 0.0, leg_amp, period)
	_swing(leg_r, "rotation:x", 0.0, -leg_amp, period)
	_swing(arm_l, "rotation:x", 0.0, -arm_amp, period)
	_swing(arm_r, "rotation:x", 0.0, arm_amp, period)


## Упругий сквош корпуса (сжатие при приземлении) с возвратом к единице —
## «мультяшная» упругость раздела 16.
func _squash(scale_to: Vector3) -> void:
	var tween := create_tween()
	tween.tween_property(hips, "scale", scale_to, 0.06)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(hips, "scale", Vector3.ONE, 0.35)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_tweens.append(tween)


## Присед/подъём корпуса с возвратом (приземление, вытягивание).
func _dip(dip: float, hold: float) -> void:
	var tween := create_tween()
	tween.tween_property(hips, "position:y", HIPS_Y + dip, POSE_TIME)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(hold)
	tween.tween_property(hips, "position:y", HIPS_Y, 2.0 * POSE_TIME)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tweens.append(tween)


## «Тычок»: корпус мотнулся вперёд-назад.
func _bonk() -> void:
	var tween := create_tween()
	tween.tween_property(head, "rotation:x", 0.5, 0.07)
	tween.tween_property(head, "rotation:x", -0.3, 0.1)
	tween.tween_property(head, "rotation:x", 0.0, 0.15)
	_tweens.append(tween)


## Поклон («Спасибо!»).
func _bow() -> void:
	var tween := create_tween()
	tween.tween_property(hips, "rotation:x", -0.5, 0.25)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.35)
	tween.tween_property(hips, "rotation:x", 0.0, 0.3)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tweens.append(tween)


# --- Сборка модели (примитивы, «ноги» модели на нуле) ---

func _build_model() -> void:
	hips = _pivot("Hips", Vector3(0.0, HIPS_Y, 0.0))
	add_child(hips)

	# Корпус: одна сглаженная капсула высотой 1.5 м (раздел 16).
	_body_mesh = _smooth(CapsuleMesh.new(), Vector3(0.0, 0.28, 0.0))
	var body: CapsuleMesh = _body_mesh.mesh
	body.radius = 0.27
	body.height = 1.5
	hips.add_child(_body_mesh)

	# Голова — пивот глаз и убора на «лице» тела.
	head = _pivot("Head", Vector3(0.0, 0.73, 0.0))
	hips.add_child(head)
	for side: float in [-1.0, 1.0]:
		var eye_pivot := _pivot("Eye", Vector3(0.1 * side, 0.0, 0.235))
		head.add_child(eye_pivot)
		var eyeball := _smooth(SphereMesh.new(), Vector3.ZERO)
		(eyeball.mesh as SphereMesh).radius = 0.052
		(eyeball.mesh as SphereMesh).height = 0.104
		eye_pivot.add_child(eyeball)
		(eyeball.material_override as StandardMaterial3D).albedo_color = PAL.eye
		# Блик — маленькая белая сфера, «живой» взгляд.
		var glint := _smooth(SphereMesh.new(), Vector3(0.016 * side, 0.018, 0.042))
		(glint.mesh as SphereMesh).radius = 0.017
		(glint.mesh as SphereMesh).height = 0.034
		eye_pivot.add_child(glint)
		(glint.material_override as StandardMaterial3D).albedo_color = Color.WHITE

	# Руки — маленькие капсулы на пивотах у «плеч».
	for pair: Array in [["ArmL", -1.0], ["ArmR", 1.0]]:
		var arm := _pivot(pair[0], Vector3(0.33 * pair[1], 0.4, 0.0))
		hips.add_child(arm)
		var mesh := _smooth(CapsuleMesh.new(), Vector3(0.0, -0.13, 0.0))
		var capsule: CapsuleMesh = mesh.mesh
		capsule.radius = 0.055
		capsule.height = 0.34
		arm.add_child(mesh)
		if pair[0] == "ArmL":
			arm_l = arm
		else:
			arm_r = arm

	# Ступни — маленькие капсулы у земли (гейтом «шагают»).
	for pair: Array in [["LegL", -1.0], ["LegR", 1.0]]:
		var leg := _pivot(pair[0], Vector3(0.12 * pair[1], 0.3, 0.0))
		add_child(leg)
		var mesh := _smooth(CapsuleMesh.new(), Vector3(0.0, -0.16, 0.0))
		var capsule: CapsuleMesh = mesh.mesh
		capsule.radius = 0.065
		capsule.height = 0.28
		leg.add_child(mesh)
		if pair[0] == "LegL":
			leg_l = leg
		else:
			leg_r = leg

	_paint_body()
	_ensure_cape()
	_ensure_trail()


## Перекрасить тело и конечности под выбранный цвет (раздел 15: 8 цветов,
## конечности — чуть темнее, чтобы форма читалась).
func _paint_body() -> void:
	if _body_mesh == null:
		return
	var body_color: Color = PAL.body_colors[_body_index]
	var limb_color: Color = body_color.darkened(0.14)
	(_body_mesh.material_override as StandardMaterial3D).albedo_color = body_color
	for node: Node3D in [arm_l, arm_r, leg_l, leg_r]:
		if node != null and node.get_child_count() > 0:
			var mesh := node.get_child(0) as MeshInstance3D
			(mesh.material_override as StandardMaterial3D).albedo_color = limb_color


## Головной убор по индексу HATS (0 — снять). Процедурный, из примитивов.
func _ensure_hat(hat_index: int) -> void:
	if head == null:
		return
	for child in head.get_children():
		if child.name == "Hat":
			child.queue_free()
	if hat_index <= 0:
		return
	var hat_index_wrapped: int = wrapi(hat_index, 1, HATS.size()) as int
	var hat := _pivot("Hat", Vector3(0.0, 0.32, 0.0))
	head.add_child(hat)
	match HATS[hat_index_wrapped]:
		"cap":
			# Кепка: тулья + козырёк вперёд.
			var crown := _smooth(CylinderMesh.new(), Vector3(0, 0.05, 0))
			var crown_mesh: CylinderMesh = crown.mesh
			crown_mesh.top_radius = 0.17
			crown_mesh.bottom_radius = 0.2
			crown_mesh.height = 0.14
			hat.add_child(crown)
			(crown.material_override as StandardMaterial3D).albedo_color = PAL.cape_colors[0]
			var peak := _smooth(BoxMesh.new(), Vector3(0.0, 0.02, 0.17))
			(peak.mesh as BoxMesh).size = Vector3(0.24, 0.03, 0.2)
			hat.add_child(peak)
			(peak.material_override as StandardMaterial3D).albedo_color = PAL.cape_colors[0].darkened(0.2)
		"crown":
			# Корона: кольцо с зубцами.
			var ring := _smooth(CylinderMesh.new(), Vector3.ZERO)
			var ring_mesh: CylinderMesh = ring.mesh
			ring_mesh.top_radius = 0.18
			ring_mesh.bottom_radius = 0.2
			ring_mesh.height = 0.12
			hat.add_child(ring)
			(ring.material_override as StandardMaterial3D).albedo_color = PAL.coin
			for i: int in 4:
				var spike := _smooth(CylinderMesh.new(), Vector3(
					0.13 * cos(PI * 0.5 * i + PI / 4.0), 0.09,
					0.13 * sin(PI * 0.5 * i + PI / 4.0)))
				var spike_mesh: CylinderMesh = spike.mesh
				spike_mesh.top_radius = 0.0
				spike_mesh.bottom_radius = 0.045
				spike_mesh.height = 0.09
				hat.add_child(spike)
				(spike.material_override as StandardMaterial3D).albedo_color = PAL.coin
		"beanie":
			# Вязаная шапка: полусфера с помпоном.
			var dome := _smooth(SphereMesh.new(), Vector3(0, 0.02, 0))
			var dome_mesh: SphereMesh = dome.mesh
			dome_mesh.radius = 0.21
			dome_mesh.height = 0.42
			hat.add_child(dome)
			(dome.material_override as StandardMaterial3D).albedo_color = PAL.cape_colors[2]
			var pompom := _smooth(SphereMesh.new(), Vector3(0, 0.21, 0))
			var pompom_mesh: SphereMesh = pompom.mesh
			pompom_mesh.radius = 0.07
			pompom_mesh.height = 0.14
			hat.add_child(pompom)
			(pompom.material_override as StandardMaterial3D).albedo_color = Color.WHITE
		"halo":
			# Нимб: светящееся кольцо над головой.
			var halo := _smooth(TorusMesh.new(), Vector3(0, 0.1, 0))
			var halo_mesh: TorusMesh = halo.mesh
			halo_mesh.inner_radius = 0.16
			halo_mesh.outer_radius = 0.2
			hat.add_child(halo)
			var material := halo.material_override as StandardMaterial3D
			material.albedo_color = PAL.coin
			material.emission_enabled = true
			material.emission = PAL.coin
			material.emission_energy_multiplier = 1.6
		"horns":
			# Рожки: пара конусов по бокам макушки.
			for side: float in [-1.0, 1.0]:
				var horn := _smooth(CylinderMesh.new(), Vector3(0.14 * side, 0.06, 0.0))
				horn.rotation.z = -0.5 * side
				var horn_mesh: CylinderMesh = horn.mesh
				horn_mesh.top_radius = 0.0
				horn_mesh.bottom_radius = 0.05
				horn_mesh.height = 0.16
				hat.add_child(horn)
				(horn.material_override as StandardMaterial3D).albedo_color = PAL.ruin_dark
		"flower":
			# Цветок: сердцевина и пять лепестков.
			var petal_color: Color = PAL.flowers[3]
			for i: int in 5:
				var petal := _smooth(SphereMesh.new(), Vector3(
					0.08 * cos(TAU * i / 5.0), 0.02, 0.08 * sin(TAU * i / 5.0)))
				var petal_mesh: SphereMesh = petal.mesh
				petal_mesh.radius = 0.05
				petal_mesh.height = 0.1
				hat.add_child(petal)
				(petal.material_override as StandardMaterial3D).albedo_color = petal_color
			var core := _smooth(SphereMesh.new(), Vector3(0, 0.05, 0))
			var core_mesh: SphereMesh = core.mesh
			core_mesh.radius = 0.04
			core_mesh.height = 0.08
			hat.add_child(core)
			(core.material_override as StandardMaterial3D).albedo_color = PAL.coin


## Плащ (раздел 16: плоский меш с простым покачиванием); 0 — не надевать.
func _ensure_cape() -> void:
	if hips == null:
		return
	if _cape != null:
		if _cape_index == 0:
			_cape.visible = false
		else:
			_cape.visible = true
			_cape_material.albedo_color = PAL.cape_colors[_cape_index]
		return
	if _cape_index == 0:
		return
	_cape = _pivot("Cape", Vector3(0.0, 0.47, -0.24))
	hips.add_child(_cape)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.42, 0.55)
	mesh.mesh = plane
	_cape_material = StandardMaterial3D.new()
	_cape_material.albedo_color = PAL.cape_colors[_cape_index]
	_cape_material.roughness = 1.0
	_cape_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = _cape_material
	mesh.position = Vector3(0.0, -0.26, -0.02)
	_cape.add_child(mesh)


## След при беге (раздел 15: 4 варианта): лёгкие частицы у пяток,
## видно только когда персонаж бежит и вариант выбран.
func _ensure_trail() -> void:
	if _trail != null:
		return
	_trail = GPUParticles3D.new()
	_trail.name = "Trail"
	_trail.amount = 24
	_trail.lifetime = 0.6
	_trail.emitting = false
	_trail.position = Vector3(0.0, 0.05, -0.1)
	_trail.local_coords = false
	_trail.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	_trail_material = ParticleProcessMaterial.new()
	_trail_material.direction = Vector3(0, 1, 0)
	_trail_material.spread = 30.0
	_trail_material.initial_velocity_min = 0.3
	_trail_material.initial_velocity_max = 0.7
	_trail_material.gravity = Vector3(0, -1.5, 0)
	_trail_material.scale_min = 0.4
	_trail_material.scale_max = 0.8
	_trail.process_material = _trail_material
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if _trail_index > 0:
		material.albedo_color = Color(PAL.cape_colors[_trail_index], 0.7)
	quad.material = material
	_trail.draw_pass_1 = quad
	add_child(_trail)


# --- Примитивы модели ---

func _pivot(node_name: String, position: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = position
	return node


## Сглаженный примитив с материалом персонажа (roughness 1 — матовый
## «пластилин»; цвет задаёт вызывающий код).
func _smooth(prim: PrimitiveMesh, position: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = prim
	var material := StandardMaterial3D.new()
	material.roughness = 1.0
	mesh.material_override = material
	mesh.position = position
	return mesh
