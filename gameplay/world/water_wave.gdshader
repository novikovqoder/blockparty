// Вода (раздел 6 SPEC): плоскость с простым шейдером волн — спокойное
// вертикальное покачивание вершин и полупрозрачный цвет из палитры.
// vfx-fix, баг 4: сдвиг только по Y (горизонтальный сдвиг шуршал кромкой
// по пляжу), длина волны ≥ 3 шагов сетки плоскости — без алиасинга.
shader_type spatial;
render_mode blend_mix, depth_draw_always;

uniform vec4 water_color : source_color = vec4(0.5, 0.78, 0.91, 0.55);
uniform float wave_height = 0.04;
uniform float wave_length = 8.0;
uniform float wave_speed = 0.6;

void vertex() {
	// Две спокойные волны: вдоль X и вдоль Z, вдвое разные по частоте.
	vec3 pos = VERTEX;
	pos.y += (sin(pos.x * TAU / wave_length + TIME * wave_speed)
		+ sin(pos.z * TAU / (wave_length * 1.7) + TIME * wave_speed * 1.3))
		* wave_height * 0.5;
	VERTEX = pos;
}

void fragment() {
	ALBEDO = water_color.rgb;
	ALPHA = water_color.a;
	ROUGHNESS = 0.25;
}
