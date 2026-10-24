# Частицы из-под ног (переделка П9 по замечанию владельца: «как в топовых
# играх — эффект еле заметный, его скорее чувствуешь, чем видишь»).
# НЕ непрерывный поток: одна короткая порция в момент шага. Шаг = касание
# стопой земли — по кости стопы рига героя BU (mixamorig_Left/RightFoot):
# пересечение высоты стопы вниз через порог контакта, перевзвод на замахе
# (амплитуды замерены по клипам loco_*: контакт 0,05–0,08 м в пространстве
# скелета, замах до 0,26 м шагом и 0,70 м бегом — пороги в балансе).
# Порция зависит от покрытия ПОД СТОПОЙ (ForestGround.surface_kind) и
# скорости: сухой камень — ничего, шагом — не больше одной, бегом —
# по таблице владельца; прыжок и приземление — порция чуть больше.
# Цвет частиц — цвет поверхности в точке, затемнённый (surface_color).
# Эмиттеры — пул переиспользуемых one-shot GPUParticles3D (4×5 твёрдых
# + 2×2 пылинки = ровно 24 частицы на игрока одновременно), ноды на каждый
# шаг не создаются. Чужие игроки дальше footfx_remote_range — эффект
# выключен. В headless частицы не тикают, но создаются безопасно — логика
# от рендера не зависит.
class_name FootFx
extends Node3D

const B: Balance = preload("res://gameplay/balance.tres")
## Спрайты (CC0-нарезки assets/vfx/particles, tools/make_vfx_textures.gd):
## травинка-лист, крошка земли, мягкое пятно (капля и пылинка).
const BLADE_TEX: Texture2D = preload("res://assets/vfx/particles/leaf.png")
const CRUMB_TEX: Texture2D = preload("res://assets/vfx/particles/dirt.png")
const SOFT_TEX: Texture2D = preload("res://assets/vfx/particles/soft.png")

## Пул: столько порций живёт одновременно; шаг бега каждые ~0,2 с при
## жизни 0,55 с — четырём эмиттерам хватает, порции не перебивают друг
## друга. 4×5 + 2×2 = 24 частицы на игрока (предел владельца).
const POOL_SOLID: int = 4
const POOL_SOLID_AMOUNT: int = 5
const POOL_DUST: int = 2
const POOL_DUST_AMOUNT: int = 2
## После прыжка/приземления детектор шагов глушится (клип ленда сам
## опускает стопы ниже порога — двойная порция не нужна), с.
const SUPPRESS_SEC: float = 0.35
## Защита от дребезга: минимум между сработками разных стоп, мс.
const MIN_STEP_GAP_MSEC: int = 100
## Кости стоп рига героя BU (порядок — Left, Right).
const FOOT_BONES: PackedStringArray = [
	"mixamorig_LeftFoot", "mixamorig_RightFoot"]
## Пропорция листа-травинки (нарезка 40×64).
const BLADE_ASPECT: float = 40.0 / 64.0

var _art: IslandArt = null
var _skeleton: Skeleton3D = null
var _grab_failed: bool = false
var _feet := PackedInt32Array()
var _armed := PackedByteArray()
var _foot_y := PackedFloat32Array()
var _solid: Array[GPUParticles3D] = []
var _solid_proc: Array[ParticleProcessMaterial] = []
var _dust: Array[GPUParticles3D] = []
var _dust_proc: Array[ParticleProcessMaterial] = []
var _blade_quad: QuadMesh = null
var _crumb_quad: QuadMesh = null
var _grain_quad: QuadMesh = null
var _drop_quad: QuadMesh = null
var _dust_quad: QuadMesh = null
var _solid_i: int = 0
var _dust_i: int = 0
var _suppress_until_msec: int = 0
var _last_step_msec: int = 0
## Счётчики для тестов: детектированные шаги, порции, частиц последней.
var stats_steps: int = 0
var stats_bursts: int = 0
var stats_last_count: int = 0


## Построить пул эмиттеров. art — запечённые данные острова (покрытие и
## цвет под стопой); без него системы нет — до setup ничего не создаётся.
func setup(art: IslandArt) -> void:
	if _solid.size() > 0:
		return
	_art = art
	_blade_quad = _quad(BLADE_TEX, Vector2(
		B.footfx_size_blade * BLADE_ASPECT, B.footfx_size_blade))
	_crumb_quad = _quad(CRUMB_TEX, Vector2(
		B.footfx_size_crumb, B.footfx_size_crumb))
	_grain_quad = _quad(CRUMB_TEX, Vector2(
		B.footfx_size_grain, B.footfx_size_grain))
	_drop_quad = _quad(SOFT_TEX, Vector2(
		B.footfx_size_drop, B.footfx_size_drop))
	_dust_quad = _quad(SOFT_TEX, Vector2(
		B.footfx_size_dust, B.footfx_size_dust))
	for i: int in POOL_SOLID:
		var fx := GPUParticles3D.new()
		fx.name = "StepDebris%d" % i
		fx.amount = POOL_SOLID_AMOUNT
		fx.lifetime = B.footfx_life_solid
		fx.one_shot = true
		fx.explosiveness = 1.0
		fx.local_coords = false
		fx.visibility_aabb = AABB(
			Vector3(-0.5, -0.2, -0.5), Vector3(1.0, 0.8, 1.0))
		fx.emitting = false
		var proc := ParticleProcessMaterial.new()
		# Порция вылетает вверх и чуть назад (модель смотрит лицом в +Z),
		# падает под гравитацией — баллистика крупинки из-под стопы.
		proc.direction = Vector3(0.0, 0.85, -0.3)
		proc.spread = 40.0
		proc.initial_velocity_min = B.footfx_pop_speed.x
		proc.initial_velocity_max = B.footfx_pop_speed.y
		proc.gravity = Vector3(0.0, -B.footfx_gravity_solid, 0.0)
		proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		proc.emission_box_extents = Vector3(0.03, 0.008, 0.04)
		proc.scale_min = 0.7
		proc.scale_max = 1.0
		# Дефолт — альфа из баланса: и в неиспользованном эмиттере пула
		# пределы владельца соблюдены до первой порции.
		proc.color = Color(1.0, 1.0, 1.0, B.footfx_alpha_solid)
		fx.process_material = proc
		fx.draw_pass_1 = _crumb_quad
		add_child(fx)
		_solid.append(fx)
		_solid_proc.append(proc)
	for i: int in POOL_DUST:
		var fx := GPUParticles3D.new()
		fx.name = "StepDust%d" % i
		fx.amount = POOL_DUST_AMOUNT
		fx.lifetime = B.footfx_life_dust
		fx.one_shot = true
		fx.explosiveness = 1.0
		fx.local_coords = false
		fx.visibility_aabb = AABB(
			Vector3(-0.5, -0.1, -0.5), Vector3(1.0, 0.6, 1.0))
		fx.emitting = false
		var proc := ParticleProcessMaterial.new()
		# Пылинка почти не летит: чуть вверх, висит и тает (масштаб по
		# кривой: быстро проявилась, к концу сошла на нет).
		proc.direction = Vector3.UP
		proc.spread = 60.0
		proc.initial_velocity_min = 0.1
		proc.initial_velocity_max = 0.35
		proc.gravity = Vector3(0.0, 0.05, 0.0)
		proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		proc.emission_box_extents = Vector3(0.05, 0.01, 0.06)
		proc.color = Color(1.0, 1.0, 1.0, B.footfx_alpha_dust)
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 0.35))
		curve.add_point(Vector2(0.3, 1.0))
		curve.add_point(Vector2(1.0, 0.15))
		var curve_tex := CurveTexture.new()
		curve_tex.curve = curve
		proc.scale_curve = curve_tex
		proc.scale_min = 0.8
		proc.scale_max = 1.0
		fx.process_material = proc
		fx.draw_pass_1 = _dust_quad
		add_child(fx)
		_dust.append(fx)
		_dust_proc.append(proc)


## Каждый тик от владельца: горизонтальная скорость, «на земле» (в воде
## и воздухе шагов нет) и позиция смотрящего (у чужих дальше порога
## эффект выключен). Здесь же детект шага по костям стоп. now_msec —
## время тика (тесты гоняют клипы быстрее реального времени и подставляют
## симулированное; в игре — реальное по умолчанию).
func update(
	hspeed: float, on_floor: bool, viewer: Vector3, now_msec: int = -1,
) -> void:
	if _art == null:
		return
	var root := get_parent() as Node3D
	if root == null:
		return
	var now := Time.get_ticks_msec() if now_msec < 0 else now_msec
	var near: bool = viewer.distance_squared_to(root.global_position) \
		<= B.footfx_remote_range * B.footfx_remote_range
	if _skeleton == null and not _grab_failed:
		_grab_skeleton(root)
	if _skeleton == null:
		return
	var detect: bool = near and on_floor and hspeed > B.anim_idle_speed \
		and now >= _suppress_until_msec
	for i: int in _feet.size():
		var y := _bone_chain(_feet[i]).origin.y
		if detect and _armed[i] == 1 \
				and y < B.footfx_contact_y \
				and _foot_y[i] >= B.footfx_contact_y \
				and now - _last_step_msec >= MIN_STEP_GAP_MSEC:
			_armed[i] = 0
			_last_step_msec = now
			stats_steps += 1
			_fire(_foot_world_pos(root, i), hspeed, 1.0, false)
		if _armed[i] == 0 and y > B.footfx_release_y:
			_armed[i] = 1
		_foot_y[i] = y


## Толчок прыжка: одна порция чуть больше обычной; детектор шагов глушим —
## клипы прыжка сами опускают стопы ниже порога контакта.
func jump(hspeed: float) -> void:
	_bigger_burst(hspeed)


## Приземление (бывший Fx.puff): та же порция у ног, той же системой.
func land(hspeed: float) -> void:
	_bigger_burst(hspeed)


func _bigger_burst(hspeed: float) -> void:
	if _art == null:
		return
	_suppress_until_msec = Time.get_ticks_msec() \
		+ int(SUPPRESS_SEC * 1000.0)
	var root := get_parent() as Node3D
	if root == null:
		return
	_fire(root.global_position + Vector3(0.0, 0.02, 0.0),
		hspeed, B.footfx_burst_mult, true)


## Одна порция в точке касания: покрытие и цвет под стопой, размер порции
## по таблице (бег/шаг, покрытие), прыжок/приземление — множитель.
## force_run — прыжок/приземление считают от беговой порции («чуть больше
## обычной» — обычная это бег), но сухой камень остаётся нулём.
func _fire(pos: Vector3, hspeed: float, mult: float, force_run: bool) -> void:
	var kind := ForestGround.surface_kind(_art, pos)
	if kind == ForestGround.Surface.STONE:
		stats_last_count = 0
		return
	var running: bool = force_run or hspeed >= B.anim_walk_run_speed
	var count: int = _portion(kind, running)
	if mult != 1.0:
		count = clampi(roundi(count * mult), 1, POOL_SOLID_AMOUNT)
	var color := ForestGround.surface_color(
		_art, kind, pos, B.footfx_color_darken)
	if count > 0:
		_spawn_solid(pos, kind, count, color)
	# Облачко пыли — только по земле/тропе (и в прыжке/приземлении с неё):
	# едва видное, альфа footfx_alpha_dust.
	var dust: int = B.footfx_dust_count \
		if kind == ForestGround.Surface.DIRT and (running or mult > 1.0) \
		else 0
	if dust > 0:
		_spawn_dust(pos, color)
	if count > 0 or dust > 0:
		stats_bursts += 1
	stats_last_count = count


## Таблица владельца: бег — трава 2–4, грязь/лужа 2–5, земля 1–3;
## шагом — не больше одной, на земле и траве можно 0.
func _portion(kind: int, running: bool) -> int:
	match kind:
		ForestGround.Surface.GRASS:
			return randi_range(B.footfx_grass_run.x, B.footfx_grass_run.y) \
				if running else mini(B.footfx_grass_walk, 1)
		ForestGround.Surface.MUD, ForestGround.Surface.PUDDLE:
			return randi_range(B.footfx_mud_run.x, B.footfx_mud_run.y) \
				if running else mini(B.footfx_mud_walk, 1)
		_:
			return randi_range(B.footfx_dirt_run.x, B.footfx_dirt_run.y) \
				if running else B.footfx_dirt_walk


func _spawn_solid(pos: Vector3, kind: int, count: int, color: Color) -> void:
	var i := _solid_i % _solid.size()
	_solid_i += 1
	var fx := _solid[i]
	var proc := _solid_proc[i]
	match kind:
		ForestGround.Surface.GRASS:
			# Травинка легче: падает медленнее.
			fx.draw_pass_1 = _blade_quad
			proc.gravity = Vector3(0.0, -B.footfx_gravity_blade, 0.0)
		ForestGround.Surface.MUD:
			fx.draw_pass_1 = _crumb_quad
			proc.gravity = Vector3(0.0, -B.footfx_gravity_solid, 0.0)
		ForestGround.Surface.PUDDLE:
			# Всплеск: капли воды (мягкое пятно, чуть светлее грязи).
			fx.draw_pass_1 = _drop_quad
			proc.gravity = Vector3(0.0, -B.footfx_gravity_solid, 0.0)
		_:
			fx.draw_pass_1 = _grain_quad
			proc.gravity = Vector3(0.0, -B.footfx_gravity_solid, 0.0)
	proc.color = Color(color, B.footfx_alpha_solid)
	fx.amount_ratio = clampf(
		float(count) / float(POOL_SOLID_AMOUNT), 0.0, 1.0)
	fx.global_position = pos
	fx.restart()


func _spawn_dust(pos: Vector3, color: Color) -> void:
	var i := _dust_i % _dust.size()
	_dust_i += 1
	var fx := _dust[i]
	# Пыль чуть светлее поверхности.
	_dust_proc[i].color = Color(
		color.lerp(Color.WHITE, 0.25), B.footfx_alpha_dust)
	fx.amount_ratio = 1.0
	fx.global_position = pos
	fx.restart()


## Найти скелет и кости стоп под владельцем (лениво, один раз); риг один
## на всех (герой BU), имена костей — константа FOOT_BONES.
func _grab_skeleton(root: Node3D) -> void:
	var found := root.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		_grab_failed = true
		return
	_skeleton = found[0] as Skeleton3D
	for bone_name: String in FOOT_BONES:
		var idx := _skeleton.find_bone(bone_name)
		if idx >= 0:
			_feet.append(idx)
	if _feet.is_empty():
		# Риг не героя BU (нет mixamo-имён): детекта шагов нет, порции
		# прыжка/приземления работают и без него.
		_skeleton = null
		_grab_failed = true
		return
	_armed.resize(_feet.size())
	_foot_y.resize(_feet.size())
	for i: int in _feet.size():
		_armed[i] = 1
		_foot_y[i] = 0.0


## Трансформация кости в пространстве скелета — накопление цепочки поз от
## кости к корню (get_bone_pose обновляется сразу, без ожидания тика
## скелета — работает и в headless-тестах). 16 уровней хватает с запасом
## (стопа — шестая от корня).
func _bone_chain(bone: int) -> Transform3D:
	var acc := Transform3D()
	var b := bone
	for i: int in 16:
		if b < 0:
			break
		acc = _skeleton.get_bone_pose(b) * acc
		b = _skeleton.get_bone_parent(b)
	return acc


## Мировая позиция стопы (XZ — куда встала, Y — земля под игроком:
## origin владельца в ногах, капсула поднята внутри сцены).
func _foot_world_pos(root: Node3D, i: int) -> Vector3:
	var world: Vector3 = _skeleton.global_transform \
		* _bone_chain(_feet[i]).origin
	return Vector3(world.x, root.global_position.y + 0.02, world.z)


## Квад-спрайт: текстура CC0-нарезки, биллборд, без освещения, без
## свечения; смешивание обычное (MIX) — никакого аддитива; цвет и альфа
## приходят вершинным цветом из порции (vertex_color_use_as_albedo).
func _quad(tex: Texture2D, side: Vector2) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = side
	quad.material = _tex_mat(tex)
	return quad


func _tex_mat(tex: Texture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
