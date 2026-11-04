// Поле травы вокруг игрока (П17, сборка 3): фотосканы Poly Haven с цветом,
// запечённым в вершины (bundle-режим tools/decimate_polyhaven). Атласные UV
// сканов не годятся для ветра «по UV.y» (как зафиксировано в
// ground_details.gd:_to_instance) — парус пучка здесь высота вершины
// (VERTEX.y, пучки до ~0.45 м). Ветер — та же формула трёх синусов с фазой
// симплекс-шума по миру, что у крон (canopy.gdshader), амплитуда меньше
// (0.05–0.08). Спад густоты от камеры — по канону grass_field.gdshader
// (fade_start/fade_end). Приминание возле персонажа — uniform press_pos
// (его ставит world_scene позицией активного игрока; на сервере/ботах не
// используется): вершины в радиусе press_radius плавно прижимаются к земле
// и расходятся наружу до 35 % высоты пучка.
// Simplex noise 3D: https://github.com/ashima/webgl-noise (как в canopy).
shader_type spatial;
render_mode specular_disabled, cull_disabled, depth_draw_opaque;

uniform float wind_strength = 0.07;
uniform float wind_freq = 0.5;
uniform float wind_noise_scale = 24.0;
uniform float fade_start = 25.0;
uniform float fade_end = 41.0;
// Позиция приминания (мировая); y < -100 — «никого рядом» (дефолт).
uniform vec3 press_pos = vec3(0.0, -1000.0, 0.0);
uniform float press_radius = 0.8;

varying vec3 world_pos;

vec3 mod289(vec3 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 mod289(vec4 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 permute(vec4 x) {
	return mod289(((x * 34.0) + 1.0) * x);
}

vec4 taylorInvSqrt(vec4 r) {
	return 1.79284291400159 - 0.85373472095314 * r;
}

float simplex3(vec3 v) {
	const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
	const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

	vec3 i = floor(v + dot(v, C.yyy));
	vec3 x0 = v - i + dot(i, C.xxx);

	vec3 g = step(x0.yzx, x0.xyz);
	vec3 l = 1.0 - g;
	vec3 i1 = min(g.xyz, l.zxy);
	vec3 i2 = max(g.xyz, l.zxy);

	vec3 x1 = x0 - i1 + C.xxx;
	vec3 x2 = x0 - i2 + C.yyy;
	vec3 x3 = x0 - D.yyy;

	i = mod289(i);
	vec4 p = permute(permute(permute(
			i.z + vec4(0.0, i1.z, i2.z, 1.0))
			+ i.y + vec4(0.0, i1.y, i2.y, 1.0))
			+ i.x + vec4(0.0, i1.x, i2.x, 1.0));

	float n_ = 0.142857142857;
	vec3 ns = n_ * D.wyz - D.xzx;

	vec4 j = p - 49.0 * floor(p * ns.z * ns.z);

	vec4 x_ = floor(j * ns.z);
	vec4 y_ = floor(j - 7.0 * x_);

	vec4 x = x_ * ns.x + ns.yyyy;
	vec4 y = y_ * ns.x + ns.yyyy;
	vec4 h = 1.0 - abs(x) - abs(y);

	vec4 b0 = vec4(x.xy, y.xy);
	vec4 b1 = vec4(x.zw, y.zw);

	vec4 s0 = floor(b0) * 2.0 + 1.0;
	vec4 s1 = floor(b1) * 2.0 + 1.0;
	vec4 sh = -step(h, vec4(0.0));

	vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
	vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

	vec3 g0 = vec3(a0.xy, h.x);
	vec3 g1 = vec3(a0.zw, h.y);
	vec3 g2 = vec3(a1.xy, h.z);
	vec3 g3 = vec3(a1.zw, h.w);

	vec4 norm = taylorInvSqrt(vec4(dot(g0, g0), dot(g1, g1), dot(g2, g2), dot(g3, g3)));
	g0 *= norm.x;
	g1 *= norm.y;
	g2 *= norm.z;
	g3 *= norm.w;

	vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
	m = m * m;
	return 42.0 * dot(m * m, vec4(dot(g0, x0), dot(g1, x1), dot(g2, x2), dot(g3, x3)));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Парус пучка: качание растёт с высотой вершины, у земли почти нет.
	float height_norm = clamp(VERTEX.y / 0.45, 0.0, 1.0);
	// Ветер листвы (canopy): фаза по миру, направление мировое — в базис
	// объекта (инстансы стоят с произвольным yaw и наклоном по нормали).
	float offset = 6.2832 * simplex3(world_pos / wind_noise_scale);
	float t = TIME * wind_freq;
	float sway = wind_strength * height_norm
		* (0.5 * sin(t + offset)
			+ 0.3 * sin(2.0 * t + 1.3 * offset)
			+ 0.2 * sin(5.0 * t + 1.5 * offset));
	VERTEX += (inverse(MODEL_MATRIX) * vec4(0.5, 0.0, 0.5, 0.0)).xyz * sway;
	// Приминание: у персонажа вершины прижимаются к земле (до 35 % высоты)
	// и расходятся наружу — пучок «раздвигается» вокруг ног.
	vec3 away = world_pos - press_pos;
	vec3 flat_away = vec3(away.x, 0.0, away.z);
	float press = (1.0 - smoothstep(0.0, press_radius, length(flat_away)))
		* height_norm;
	VERTEX.y *= 1.0 - 0.35 * press;
	VERTEX += (inverse(MODEL_MATRIX)
		* vec4(flat_away / (length(flat_away) + 0.0001), 0.0)).xyz
		* VERTEX.y * 0.35 * press;
	// Спад густоты: пучки «садятся» в землю между fade_start и fade_end
	// (по канону grass_field.gdshader; дистанция — до камеры).
	float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float keep = 1.0 - smoothstep(fade_start, fade_end, dist);
	VERTEX.y *= keep;
}

void fragment() {
	// COLOR — запечённый цвет скана × инстанс-тон раскладки.
	ALBEDO = COLOR.rgb;
}

void light() {
	// Мягкий свет листвы (canopy): wrap-Ламберт с небесным заполнителем —
	// нижние травинки читаются тенью, а не угольной дырой.
	float ndl = dot(NORMAL, LIGHT);
	float wrap = 0.5;
	float lambert = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	float sky_fill = clamp(0.5 + 0.5 * NORMAL.y, 0.0, 1.0) * 0.25;
	float lit = max(lambert * ATTENUATION, sky_fill);
	DIFFUSE_LIGHT += LIGHT_COLOR * ALBEDO * lit;
}
