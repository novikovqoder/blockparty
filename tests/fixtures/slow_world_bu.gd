extends Node3D
## Учебный «мир» для теста экрана загрузки: тяжёлый _ready и сигнал world_ready через 0.5 с.

signal world_ready

func _ready() -> void:
	var s: float = 0.0
	for i: int in 300000:
		s += sqrt(float(i))
	get_tree().create_timer(0.5).timeout.connect(func() -> void: world_ready.emit())
