# Золотая цель (разделы 6, 7.4 SPEC): быстро летает по сложной траектории
# (фигура Лиссажу) на бонусной секции. Умирает только от ударов двух РАЗНЫХ
# игроков в пределах golden_hit_window — состояние считает хост
# (GoldenTracker), здесь траектория и индикация «цель задета».
class_name GoldenMob
extends Mob

const PAL: Palette = preload("res://assets/palette.tres")

var _visual: Node2D
var _vulnerable_left: float = 0.0


func _init() -> void:
	super(Vector2(28, 28))


## Смещение от точки спавна: сумма двух несоизмеримых синусов — «сложная
## траектория», чистая функция времени (раздел 6).
func compute_offset(t: float) -> Vector2:
	return trajectory(params, t)


static func trajectory(params: Dictionary, t: float) -> Vector2:
	var span_x: float = params.get("span_x", 360.0)
	var span_y: float = params.get("span_y", 120.0)
	var period_x: float = params.get("period_x", 3.2)
	var period_y: float = params.get("period_y", 4.6)
	var phase: float = params.get("phase", 0.0)
	var x: float = span_x * sin(TAU * t / period_x + phase)
	var y: float = span_y * sin(TAU * t / period_y + phase * 1.7)
	return Vector2(x, y)


func _build_visual() -> void:
	# «Золотая» звезда из восьми вершин.
	var points := PackedVector2Array()
	for i: int in 8:
		var radius: float = 16.0 if i % 2 == 0 else 9.0
		var angle: float = TAU * i / 8.0 - PI * 0.5
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	_visual = Prim.polygon(points, PAL.golden)
	var core := Prim.outlined_rect(Vector2(10, 10), Color(1, 0.85, 0.3), PAL.outline, 1.5)
	_visual.add_child(core)
	add_child(_visual)


func _ready() -> void:
	super()
	# Первый удар от другого игрока — цель «заведена», мигает золотым.
	EventBus.mob_damaged.connect(_on_mob_damaged)


func _physics_process(delta: float) -> void:
	super(delta)
	_visual.rotation += TAU * delta / 4.0
	if _vulnerable_left > 0.0:
		_vulnerable_left = maxf(0.0, _vulnerable_left - delta)
		_visual.modulate = Color(1.0, 0.6, 0.3) if fmod(_vulnerable_left, 0.3) < 0.15 else Color.WHITE
	else:
		_visual.modulate = Color.WHITE


func _on_mob_damaged(damaged_id: int, _hitter_peer: int) -> void:
	if damaged_id == spawn_id:
		_vulnerable_left = B.golden_hit_window
