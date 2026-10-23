# Частицы бега (доработка П9, по замечанию владельца о «квадратиках»):
# комья земли, травинки и каменная крошка вылетают немного из-под ног.
# Покрытие — ForestGround.surface_kind по точке под игроком (земля/трава/
# камень — те же веса, что красят землю), интенсивность — по скорости:
# шаг почти не пылит, бег заметен. Нода — ребёнок Model (модель повёрнута
# по движению, частицы сносит назад), сами частицы в мировых координатах —
# шлейф остаётся на земле и не едет за игроком. Спрайты — CC0-нарезки
# assets/vfx/particles (tools/make_vfx_textures.gd): нетекстурных
# («квадратных») частиц в проекте не остаётся. В headless не тикает,
# но создаётся безопасно — логика от частиц не зависит.
class_name RunParticles
extends Node3D

const B: Balance = preload("res://gameplay/balance.tres")
const DIRT_TEX: Texture2D = preload("res://assets/vfx/particles/dirt.png")
const GRASS_TEX: Texture2D = preload("res://assets/vfx/particles/grass.png")
const STONE_TEX: Texture2D = preload("res://assets/vfx/particles/stone.png")

## Как часто перекладывать спрайты по покрытию, с (точность «пятна под
## ногами» не нужна, а шум моха и уклоны считать каждый кадр незачем).
const SURFACE_INTERVAL_MSEC: int = 250

var _fx: GPUParticles3D = null
var _art: IslandArt = null
var _surface: int = -2  # −2 — пассы ещё не выложены; −1 — «нет покрытия».
var _surface_next_msec: int = 0
var _dirt_quad: QuadMesh
var _grass_quad: QuadMesh
var _stone_quad: QuadMesh


## Доля полной эмиссии по горизонтальной скорости: до порога анимаций —
## ноль, к бегу (B.run_speed) растёт до единицы; степенная кривая держит
## шаг почти без пыли («шаг — почти нет, бег — заметнее»). Чистая функция —
## юнит-тест проверяет монотонность и значения на шаге/беге.
static func intensity(hspeed: float, b: Balance) -> float:
	var t := (hspeed - b.anim_idle_speed) / (b.run_speed - b.anim_idle_speed)
	return pow(clampf(t, 0.0, 1.0), 1.6)


## Построить эмиттер. art — запечённые данные острова (уклоны и высоты
## для покрытия); без него системы нет — до setup частицы не создаются.
func setup(art: IslandArt) -> void:
	if _fx != null:
		return
	_art = art
	_dirt_quad = _quad(DIRT_TEX, 1.0)
	_grass_quad = _quad(GRASS_TEX, 0.7)
	_stone_quad = _quad(STONE_TEX, 1.0)
	_fx = GPUParticles3D.new()
	_fx.name = "RunDust"
	_fx.amount = B.run_dust_amount
	_fx.lifetime = B.run_dust_lifetime
	_fx.local_coords = false
	# Частицы в мировых координатах уезжают из локального бокса эмиттера
	# (шлейф позади бегуна до ~3 м) — без запаса AABB они пропадают.
	_fx.visibility_aabb = AABB(
		Vector3(-4.0, -0.5, -4.0), Vector3(8.0, 3.0, 8.0))
	var process := ParticleProcessMaterial.new()
	# Комья вылетают назад-вверх из-под пят: модель смотрит лицом в +Z.
	process.direction = Vector3(0.0, 0.55, -1.0)
	process.spread = B.run_dust_spread_deg
	process.initial_velocity_min = B.run_dust_speed * 0.4
	process.initial_velocity_max = B.run_dust_speed
	# Тяжёлые комки: гравитация сильнее тянет, чем пыль (−2 у Fx.puff).
	process.gravity = Vector3(0.0, -9.0, 0.0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.12, 0.03, 0.12)
	process.scale_min = 0.6
	process.scale_max = 1.3
	_fx.process_material = process
	_fx.draw_passes = 1
	_fx.draw_pass_1 = _dirt_quad
	_fx.emitting = false
	add_child(_fx)


## Каждый кадр от владельца: горизонтальная скорость и «стоит на земле»
## (в воде и воздухе частиц нет). Покрытие перекладывается по таймеру.
func update(hspeed: float, on_floor: bool) -> void:
	if _fx == null:
		return
	_fx.emitting = on_floor and hspeed > B.anim_idle_speed
	_fx.amount_ratio = intensity(hspeed, B)
	var now := Time.get_ticks_msec()
	if now >= _surface_next_msec:
		_surface_next_msec = now + SURFACE_INTERVAL_MSEC
		_refresh_surface()


func is_emitting() -> bool:
	return _fx != null and _fx.emitting


func ratio() -> float:
	return _fx.amount_ratio if _fx != null else 0.0


func surface() -> int:
	return _surface


## Текущее покрытие под ногами → набор пассов: камень — крошка, трава —
## комья + травинки (каждая частица берёт случайный пасс), земля — комья.
func _refresh_surface() -> void:
	if _art == null:
		return
	var kind := ForestGround.surface_kind(_art, global_position)
	if kind == _surface:
		return
	_surface = kind
	match kind:
		ForestGround.Surface.STONE:
			_fx.draw_passes = 1
			_fx.draw_pass_1 = _stone_quad
		ForestGround.Surface.GRASS:
			_fx.draw_passes = 2
			_fx.draw_pass_1 = _dirt_quad
			_fx.draw_pass_2 = _grass_quad
		_:
			_fx.draw_passes = 1
			_fx.draw_pass_1 = _dirt_quad


## Квад-спрайт покрытия: текстура CC0-нарезки, биллборд, без освещения.
func _quad(tex: Texture2D, scale: float) -> QuadMesh:
	var quad := QuadMesh.new()
	var side: float = B.run_dust_size * scale
	quad.size = Vector2(side, side)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = mat
	return quad
