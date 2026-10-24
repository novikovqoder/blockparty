# Тесты частиц из-под ног (переделка П9 по замечанию владельца): порция
# только в момент шага — детект по клипам героя BU (loco_walk/loco_run:
# по 2 шага на цикл, один на стопу), таблица покрытий и скоростей
# (камень — 0; шаг по траве — не больше 1; бег — 2–4/2–5/1–3), размер
# спрайтов не больше 3 см, материалы без аддитива и свечения, альфа
# в пределах, кэп 24 частицы на игрока, дальние чужие выключены.
extends GutTest

const ART: IslandArt = preload("res://gameplay/world/island_art.res")
const B: Balance = preload("res://gameplay/balance.tres")
const HERO_SCENE: PackedScene = preload("res://assets/hero_bu/hero_bu.tscn")
const ANIMS: AnimationLibrary = preload(
	"res://assets/hero/hero_sword_anims.res")


func before_each() -> void:
	pass


# --- Детект шага по клипам героя BU ---

func test_step_detection_walk_two_per_cycle() -> void:
	var rig := _rig("loco_walk")
	var steps := _play(rig, 2.2)
	assert_eq(steps, 4, "2 цикла ходьбы = 4 шага (по 2 на цикл, L и R)")


func test_step_detection_run_two_per_cycle() -> void:
	var rig := _rig("loco_run")
	var steps := _play(rig, 1.4)
	assert_eq(steps, 4, "2 цикла бега = 4 шага (по 2 на цикл, L и R)")


func test_step_detection_idle_and_standing_still() -> void:
	var rig := _rig("loco_walk")
	# Стоим (скорость ниже порога анимаций): цикл крутится, шагов нет.
	var fx: FootFx = rig["fx"]
	_play(rig, 2.2, 0.1)
	assert_eq(fx.stats_steps, 0, "стоя (клип идёт) детект молчит")
	# В воздухе — тоже.
	_play(rig, 2.2, B.run_speed, false)
	assert_eq(fx.stats_steps, 0, "в воздухе шагов нет")


func test_far_viewer_culled() -> void:
	var rig := _rig("loco_run")
	var fx: FootFx = rig["fx"]
	var far := Vector3(B.footfx_remote_range + 5.0, 0.0, 0.0)
	var dt := 1.0 / 60.0
	var msec := 0
	for i: int in 84:  # 1.4 с = 2 цикла бега
		rig["player"].advance(dt)
		msec += 17
		fx.update(B.run_speed, true, far, msec)
	assert_eq(fx.stats_steps, 0, "дальше порога — детект выключен")
	for i: int in 84:
		rig["player"].advance(dt)
		msec += 17
		fx.update(B.run_speed, true, Vector3.ZERO, msec)
	assert_gt(fx.stats_steps, 0, "вблизи — шаги детектируются")


# --- Таблица покрытий и скоростей ---

func test_stone_no_particles() -> void:
	var fx := _fx_at(_find_kind(ForestGround.Surface.STONE))
	var bursts := fx.stats_bursts
	for i: int in 8:
		fx._fire(fx.get_parent().global_position, B.run_speed, 1.0, false)
		fx.jump(B.run_speed)
		fx.land(B.run_speed)
	assert_eq(fx.stats_bursts, bursts,
		"сухой камень: ни шага, ни прыжка, ни приземления — 0 частиц")
	assert_eq(fx.stats_last_count, 0, "последняя порция на камне — пустая")


func test_walk_grass_at_most_one() -> void:
	var fx := _fx_at(_find_kind(ForestGround.Surface.GRASS))
	for i: int in 12:
		fx._fire(fx.get_parent().global_position, B.walk_speed, 1.0, false)
		assert_lte(fx.stats_last_count, 1,
			"шаг по траве — не больше 1 частицы (%d-я порция)" % i)


func test_walk_dirt_zero() -> void:
	var fx := _fx_at(_plaza())
	for i: int in 12:
		fx._fire(fx.get_parent().global_position, B.walk_speed, 1.0, false)
		assert_eq(fx.stats_last_count, 0, "шаг по земле — можно 0")


func test_run_within_owner_table() -> void:
	var cases := [
		{"kind": ForestGround.Surface.GRASS,
			"lo": B.footfx_grass_run.x, "hi": B.footfx_grass_run.y},
		{"kind": ForestGround.Surface.MUD,
			"lo": B.footfx_mud_run.x, "hi": B.footfx_mud_run.y},
		{"kind": ForestGround.Surface.PUDDLE,
			"lo": B.footfx_mud_run.x, "hi": B.footfx_mud_run.y},
		{"kind": ForestGround.Surface.DIRT,
			"lo": B.footfx_dirt_run.x, "hi": B.footfx_dirt_run.y},
	]
	for entry: Dictionary in cases:
		var fx := _fx_at(_find_kind(entry["kind"]))
		var pos: Vector3 = fx.get_parent().global_position
		for i: int in 24:
			fx._fire(pos, B.run_speed, 1.0, false)
			assert_between(fx.stats_last_count, entry["lo"], entry["hi"],
				"бег по покрытию %d — порция в таблице" % entry["kind"])


func test_jump_and_land_slightly_bigger() -> void:
	var fx := _fx_at(_plaza())
	var pos: Vector3 = fx.get_parent().global_position
	# Беговая порция по земле: 1–3 крупинки; приземление — множитель
	# 1.5 (никогда не меньше 2 — «чуть больше обычной»), не больше пула.
	for i: int in 12:
		fx._fire(pos, B.run_speed, 1.0, false)
	fx.land(B.run_speed)
	assert_between(fx.stats_last_count,
		roundi(B.footfx_dirt_run.x * B.footfx_burst_mult),
		FootFx.POOL_SOLID_AMOUNT,
		"приземление — порция чуть больше обычной (не больше пула)")
	# Приземление на камне — ничего.
	var stone := _fx_at(_find_kind(ForestGround.Surface.STONE))
	stone.land(B.run_speed)
	assert_eq(stone.stats_last_count, 0, "приземление на камень — 0")


# --- Вид частиц: размер, материалы ---

func test_particle_sizes_within_half_to_three_cm() -> void:
	var fx := _fx_at(_plaza())
	var quads := {
		"травинка": fx._blade_quad, "крошка грязи": fx._crumb_quad,
		"крупинка": fx._grain_quad, "капля": fx._drop_quad,
		"пылинка": fx._dust_quad,
	}
	for name: String in quads:
		var side: Vector2 = quads[name].size
		var biggest: float = maxf(side.x, side.y)
		assert_lte(biggest, B.footfx_size_max,
			"%s не больше %.2f м (квад %.1f×%.1f см)" % [
				name, B.footfx_size_max, side.x * 100.0, side.y * 100.0])
		assert_gte(minf(side.x, side.y), 0.005,
			"%s не меньше 0,5 см" % name)


func test_materials_no_additive_no_glow_alpha_capped() -> void:
	var fx := _fx_at(_plaza())
	var quads := [fx._blade_quad, fx._crumb_quad, fx._grain_quad,
		fx._drop_quad, fx._dust_quad]
	for quad: QuadMesh in quads:
		var mat := quad.material as StandardMaterial3D
		assert_eq(mat.blend_mode, BaseMaterial3D.BLEND_MODE_MIX,
			"смешивание обычное, не аддитивное")
		assert_false(mat.emission_enabled, "без свечения")
		assert_eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA,
			"прозрачность альфой")
		assert_not_null(mat.albedo_texture, "спрайт-нарезка есть")
	# Альфа порций: твёрдые ≤ 0.6, пылинка ≤ 0.25 (после реальной порции).
	var dirt_pos := _plaza()
	fx._fire(dirt_pos, B.run_speed, 1.0, false)
	for proc: ParticleProcessMaterial in fx._solid_proc:
		assert_lte(proc.color.a, 0.6, "альфа твёрдой частицы ≤ 0.6")
	for proc: ParticleProcessMaterial in fx._dust_proc:
		assert_lte(proc.color.a, 0.25, "альфа пылинки ≤ 0.25")
	assert_lte(B.footfx_life_solid, 0.7, "жизнь твёрдой ≤ 0.7 с")
	assert_gte(B.footfx_life_solid, 0.3, "жизнь твёрдой ≥ 0.3 с")


func test_pool_cap_24_per_player() -> void:
	var fx := _fx_at(_plaza())
	var total: int = 0
	for emitter: GPUParticles3D in fx._solid:
		total += emitter.amount
	for emitter: GPUParticles3D in fx._dust:
		total += emitter.amount
	assert_lte(total, 24, "не больше 24 частиц на игрока одновременно")
	assert_eq(fx._solid.size() + fx._dust.size(), 6,
		"пул эмиттеров построен (4 твёрдых + 2 пыли)")


# --- Покрытия под ногами согласованы с весами окраски ---

func test_surface_kind_matches_ground_weights() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = ForestGround.MOSS_SEED
	noise.frequency = ForestGround.MOSS_FREQUENCY
	var seen := {"stone": 0, "grass": 0, "mud": 0, "puddle": 0, "dirt": 0}
	for z: int in range(0, ForestGround.MAP_M, 3):
		for x: int in range(0, ForestGround.MAP_M, 3):
			var wx := float(x) - 128.0
			var wz := float(z) - 128.0
			var w_rock: float = smoothstep(
				ForestGround.ROCK_SLOPE_SOFT, ForestGround.ROCK_SLOPE_FULL,
				ForestGround._slope(ART, x, z))
			var h: float = ART.heights[z * IslandGen.POINTS + x]
			var w_wet: float = 1.0 - smoothstep(
				ForestGround.WET_H_FULL, ForestGround.WET_H_SOFT, h)
			var w_path: float = maxf(
				ForestGround._path_weight(wx, wz),
				ForestGround._plaza_weight(wx, wz))
			var pos := Vector3(wx, 0.0, wz)
			var kind := ForestGround.surface_kind(ART, pos)
			if w_rock >= 0.5:
				assert_eq(kind, ForestGround.Surface.STONE,
					"крутой склон (%d, %d) — камень" % [x, z])
				seen["stone"] += 1
			elif w_path >= 0.5:
				assert_eq(kind, ForestGround.Surface.DIRT,
					"тропа/гравий (%d, %d) — земля" % [x, z])
				seen["dirt"] += 1
			elif w_wet >= ForestGround.PUDDLE_WET:
				assert_eq(kind, ForestGround.Surface.PUDDLE,
					"самая низкая точка (%d, %d) — лужа" % [x, z])
				seen["puddle"] += 1
			elif w_wet >= ForestGround.MUD_WET:
				assert_eq(kind, ForestGround.Surface.MUD,
					"влажная низина (%d, %d) — грязь" % [x, z])
				seen["mud"] += 1
			elif ForestGround._moss_weight(noise, x, z, 0.0, w_wet) >= 0.35:
				assert_eq(kind, ForestGround.Surface.GRASS,
					"мох (%d, %d) — трава" % [x, z])
				seen["grass"] += 1
	assert_gt(seen["stone"], 0, "на острове есть камень")
	assert_gt(seen["grass"], 0, "на острове есть трава")
	assert_gt(seen["mud"], 0, "на острове есть грязь (влажные низины)")


# --- Помощники ---

## Стенд детекта: сцена героя + AnimationPlayer + FootFx на корне.
## Возвращает {root, player, fx}; корень освобождается тестом.
func _rig(clip: String) -> Dictionary:
	var root := Node3D.new()
	add_child_autofree(root)
	var hero: Node3D = HERO_SCENE.instantiate()
	root.add_child(hero)
	var player := AnimationPlayer.new()
	hero.add_child(player)
	player.add_animation_library(&"sword", ANIMS)
	player.play(StringName("sword/" + clip))
	var fx := FootFx.new()
	fx.name = "FootFx"
	root.add_child(fx)
	fx.setup(ART)
	return {"root": root, "player": player, "fx": fx}


## Прокрутить клип сек (симулированное время — тик 17 мс); возвращает
## число детектированных шагов. speed/on_floor можно переопределить.
func _play(
	rig: Dictionary, seconds: float, speed: float = -1.0,
	on_floor: bool = true,
) -> int:
	var fx: FootFx = rig["fx"]
	var dt := 1.0 / 60.0
	var ticks := roundi(seconds / dt)
	var msec := 0
	var hspeed: float = speed \
		if speed >= 0.0 \
		else (B.walk_speed if rig["player"].current_animation \
				== "sword/loco_walk" else B.run_speed)
	for i: int in ticks:
		rig["player"].advance(dt)
		msec += 17
		fx.update(hspeed, on_floor, Vector3.ZERO, msec)
	return fx.stats_steps


## FootFx на корне в точке покрытия; корень — ребёнок теста.
func _fx_at(pos: Vector3) -> FootFx:
	var root := Node3D.new()
	add_child_autofree(root)
	root.global_position = pos
	var fx := FootFx.new()
	fx.name = "FootFx"
	root.add_child(fx)
	fx.setup(ART)
	return fx


## Точка первого встреченного покрытия (карта острова, шаг 3 м).
func _find_kind(kind: int) -> Vector3:
	for z: int in range(0, ForestGround.MAP_M, 3):
		for x: int in range(0, ForestGround.MAP_M, 3):
			var pos := Vector3(float(x) - 128.0, 0.0, float(z) - 128.0)
			if ForestGround.surface_kind(ART, pos) == kind:
				return pos
	fail_test("покрытие %d не найдено на острове" % kind)
	return Vector3.ZERO


## Центр гравийной Площади — заведомо утоптанная земля.
func _plaza() -> Vector3:
	return Vector3(ForestGround.PLAZA_CENTER.x, 0.0,
		ForestGround.PLAZA_CENTER.y)
