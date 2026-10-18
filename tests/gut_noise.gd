# Тестовый хелпер (не тест — GUT не подхватывает: без префикса test_):
# пометка известного шума сторонних аддонов «handled», чтобы движковые
# warning'и не роняли тесты (GUT по умолчанию считает любую engine-ошибку
# падением теста).
class_name GutNoise


## Terrain3D 1.0.2 при первом add_child узла в процессе роняет движковый
## warning «instance_reset_physics_interpolation() is deprecated» (compat-
## бинд Godot 4.7.2 вызывается из C++ аддона; collision-ресурс до add_child
## недоступен, лечить со стороны проекта нечем). Пометим handled по
## документированному полю GutTrackedError (addons/gut/gut_tracked_error.gd),
## точечно по тексту — остальные ошибки теста остаются фатальными.
static func ignore_terrain3d_deprecation(test: GutTest) -> void:
	if test.gut == null:
		return
	for err: Object in test.gut.error_tracker.get_errors_for_test():
		if str(err.code).contains("instance_reset_physics_interpolation") \
				or str(err.rationale) \
					.contains("instance_reset_physics_interpolation"):
			err.handled = true
