extends SceneTree
func _initialize() -> void:
	_measure.call_deferred()

func _measure() -> void:
	Engine.physics_ticks_per_second = 480
	var t0 := Time.get_ticks_msec()
	for i: int in 960:
		await physics_frame
	var dt := Time.get_ticks_msec() - t0
	print("960 тиков за %d мс" % dt)
	quit()
