// Пламя костра (vfx-fix, визуальный блок д): конус с колышущимися
// вершинами (сильнее к верхушке) и градиентом угли→языки. Аддитивный,
// без освещения; TIME гоняет анимацию — со стороны это живой огонь.
// Вершинный градиент берём из локальной высоты (VERTEX.y), а не UV:
// раскладка UV примитивов различается между мешами.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Цвет углей (низ) и языков (верх).
uniform vec4 base_color : source_color = vec4(1.0, 0.32, 0.04, 1.0);
uniform vec4 tip_color : source_color = vec4(1.0, 0.85, 0.35, 1.0);
// Высота меша, м — нормировка VERTEX.y в градиент [0, 1].
uniform float height = 0.7;
uniform float speed = 2.4;

void vertex() {
	float up = clamp(VERTEX.y / height, 0.0, 1.0);
	float sway = up * up;
	VERTEX.x += sin(TIME * speed + VERTEX.z * 7.0) * 0.07 * sway;
	VERTEX.z += cos(TIME * speed * 1.27 + VERTEX.x * 7.0) * 0.07 * sway;
}

void fragment() {
	float up = clamp(VERTEX.y / height, 0.0, 1.0);
	// Мерцание кромки пламени: два неравных такта, чтобы не пульсировать.
	float flicker = 0.82 + 0.11 * sin(TIME * 8.0 + up * 5.0)
		+ 0.07 * sin(TIME * 13.7);
	vec3 flame = mix(base_color.rgb, tip_color.rgb, pow(up, 0.75)) * flicker;
	ALBEDO = flame;
	EMISSION = flame * 1.5;
	// Кромка тает кверху, у земли пламя плотное.
	ALPHA = mix(1.0, 0.25, up);
}
