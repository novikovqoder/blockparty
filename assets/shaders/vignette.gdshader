// Виньетка (vfx-fix, визуальный блок е): мягкое затемнение углов кадра —
// взгляд собирается к центру, край экрана не спорит с солнцем неба.
// Полноэкранный ColorRect поверх 3D, под HUD; только «Высокое качество».
shader_type canvas_item;

// Сила затемнения в самом углу кадра и границы спада (доля радиуса):
// центр кадра чистый, темнеют только края.
uniform float strength : hint_range(0.0, 1.0) = 0.35;
uniform float softness : hint_range(0.1, 1.0) = 0.45;

void fragment() {
	vec2 from_center = UV - vec2(0.5);
	// Учёт аспекта: без него углы широкого кадра темнеют сильнее сторон.
	from_center.x *= SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y * 9.0 / 16.0;
	float vignette = smoothstep(softness, 0.85, length(from_center));
	COLOR = vec4(vec3(0.0), vignette * strength);
}
