# Финал «Короткой тропы» (П5.5): когда стоят все четыре вехи, между ними
# проявляется светлая лента на земле — от Площади через оба мостка до
# ворот руин — и остаётся до конца сессии всем игрокам. Маршрут не режет
# дно Расщелины напрямую: по кромке ко второму мостку и вниз — по тропе
# можно идти. Лента следует рельефу по карте арта, на мостках лежит
# на настиле. Процедурная геометрия и мягкое свечение — без ассетов;
# в headless строится безопасно (рендера нет, логика от неё не зависит).
class_name TrailFx
extends Node3D

const B: Balance = preload("res://gameplay/balance.tres")
const PAL: Palette = preload("res://assets/palette.tres")

## Шаг выборки маршрута, м.
const SAMPLE_STEP: float = 1.5
## Подъём ленты над землёй и настилом, м — не мерцает с рельефом.
const LIFT: float = 0.08
## Полоса мостка: половина ширины настила с запасом на стык с кромкой, м.
const BRIDGE_HALF_W: float = 1.3
## Скользящее среднее высот: столько соседних выборок с каждой стороны.
const SMOOTH: int = 3
## Ширина ленты и её прозрачность после проявления (визуальные числа).
const WIDTH: float = 1.4
const ALPHA: float = 0.6
## Свечение после проявления: кремовый на светлом песке должен читаться.
const GLOW: float = 2.0


## Проявить тропу на острове: art — запечённые высоты (как у вех).
static func spawn(parent: Node3D, art: IslandArt) -> void:
	var fx := TrailFx.new()
	parent.add_child(fx)
	fx._run(art)


func _run(art: IslandArt) -> void:
	var samples := _sample_path(art)
	if samples.size() < 2:
		return
	_smooth_heights(samples)
	var mesh := MeshInstance3D.new()
	mesh.name = "TrailRibbon"
	mesh.mesh = _build_mesh(samples)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := _build_material()
	mesh.material_override = material
	add_child(mesh)
	# Проявление: альфа и свечение нарастают, лента «проступает» из травы.
	var tween := create_tween().set_parallel(true)
	tween.tween_method(
		func(a: float) -> void: material.albedo_color.a = a, 0.0, ALPHA, B.quest_trail_fade_in
	)
	tween.tween_method(
		func(e: float) -> void: material.emission_energy_multiplier = e,
		0.0, GLOW, B.quest_trail_fade_in
	)


## Маршрут тропы: вехи Финна плюс путевые точки спуска вторым мостком —
## прямая веха 3 → веха 4 прошла бы по дну Расщелины, а тропа — дорога,
# по которой идут: кромка → мосток → южный подход → ворота.
func _waypoints() -> Array[Vector2]:
	var bridge_x := float(IslandGen.BRIDGE_X[1])
	var path: Array[Vector2] = []
	var flags: Array[Vector2] = QuestLayout.FLAG_POINTS
	path.append(flags[0])
	path.append(flags[1])
	path.append(flags[2])
	path.append(Vector2(bridge_x, float(IslandGen.CREVASSE_Z1) + 4.0))
	path.append(Vector2(bridge_x, float(IslandGen.CREVASSE_Z0) - 6.0))
	path.append(flags[3])
	return path


## Выборки маршрута: точки каждые SAMPLE_STEP с высотой рельефа
## (на мостке — настил).
func _sample_path(art: IslandArt) -> Array[Vector3]:
	var samples: Array[Vector3] = []
	var path := _waypoints()
	for i: int in path.size() - 1:
		var from: Vector2 = path[i]
		var to: Vector2 = path[i + 1]
		var length := from.distance_to(to)
		var count := maxi(1, int(round(length / SAMPLE_STEP)))
		for j: int in count:
			var t := float(j) / float(count)
			var x := lerpf(from.x, to.x, t)
			var z := lerpf(from.y, to.y, t)
			samples.append(Vector3(x, _point_height(art, x, z), z))
	# Замыкающая точка — точно у последней вехи.
	var last: Vector2 = path[path.size() - 1]
	samples.append(
		Vector3(last.x, _point_height(art, last.x, last.y), last.y)
	)
	return samples


## Высота ленты в точке: на мостках — настил, иначе земля из карты арта.
func _point_height(art: IslandArt, x: float, z: float) -> float:
	for bx: int in IslandGen.BRIDGE_X:
		if absf(x - float(bx)) <= BRIDGE_HALF_W \
				and z >= float(IslandGen.CREVASSE_Z0) - 2.0 \
				and z <= float(IslandGen.CREVASSE_Z1) + 2.0:
			return IslandGen.BRIDGE_DECK_H + LIFT
	return QuestLayout.ground_height(art, x, z) + LIFT


## Скользящее среднее по вертикали: стыки «кромка ↔ мосток» без ступенек.
func _smooth_heights(samples: Array[Vector3]) -> void:
	var source: Array[float] = []
	for s: Vector3 in samples:
		source.append(s.y)
	for i: int in samples.size():
		var total := 0.0
		var count := 0
		for j: int in range(maxi(0, i - SMOOTH), mini(samples.size(), i + SMOOTH + 1)):
			total += source[j]
			count += 1
		samples[i].y = total / float(count)


## Плоская лента-полоса вдоль выборок (двусторонний материал — winding
## не важен, нормали не нужны: unshaded).
func _build_mesh(samples: Array[Vector3]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := WIDTH * 0.5
	for i: int in samples.size() - 1:
		var a: Vector3 = samples[i]
		var b: Vector3 = samples[i + 1]
		var dir := (b - a).normalized()
		if dir.length_squared() < 0.5:
			dir = _segment_dir(samples, i)
		var side := Vector3(-dir.z, 0.0, dir.x) * half
		var a_l := a + side
		var a_r := a - side
		var b_l := b + side
		var b_r := b - side
		st.add_vertex(a_l)
		st.add_vertex(a_r)
		st.add_vertex(b_l)
		st.add_vertex(b_l)
		st.add_vertex(a_r)
		st.add_vertex(b_r)
	st.index()
	return st.commit()


## Направление в выборке i по соседям (центральная разность): для почти
## вертикальных стыков сегментов.
func _segment_dir(samples: Array[Vector3], i: int) -> Vector3:
	var prev := samples[maxi(0, i - 1)]
	var next := samples[mini(samples.size() - 1, i + 1)]
	var flat := Vector3(next.x - prev.x, 0.0, next.z - prev.z)
	return flat.normalized() if flat.length_squared() > 0.001 else Vector3.FORWARD


## Светлая полупрозрачная лента с мягким свечением (стиль квестовых
# огоньков — beacon_glow).
func _build_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(PAL.beacon_glow, 0.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = PAL.beacon_glow
	material.emission_energy_multiplier = 0.0
	return material
