// Пламя костра (vfx-fix блок д; доработка П5.13 — живой огонь): конус,
// объём которого колышут два сведённых в FBM октавы симплекс-шума —
// вершины гуляют у верхушки (в vertex), кромка тает языками (в fragment:
// шум ползёт вверх по TIME, маска высоты растворяется с шумовым краем).
// Симплекс (Ian McEwan / Ashima Arts, тот же, что в forest_ground) не
// имеет решётчатой структуры — полосатых артефактов value-noise нет.
// Аддитивный, без освещения; градиент угли→языки по локальной высоте
// (VERTEX.y), а не UV: раскладка UV примитивов различается между мешами.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Цвет углей (низ) и языков (верх).
uniform vec4 base_color : source_color = vec4(1.0, 0.32, 0.04, 1.0);
uniform vec4 tip_color : source_color = vec4(1.0, 0.85, 0.35, 1.0);
// Высота меша, м — нормировка VERTEX.y в градиент [0, 1].
uniform float height = 0.7;
// Скорость огня: гуляние вершин и ползущий вверх узор кромки.
uniform float speed = 2.4;
// Масштаб шума языков (по X и по высоте).
uniform float tongue_scale = 5.5;
// Доля шума в маске высоты: больше — рваные языки, меньше — ровный конус.
uniform float tongue_noise = 0.38;

// Симплекс-шум 2D (Ian McEwan / Ashima Arts, публичный webgl-noise).
vec3 mod289(vec3 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}
vec2 mod289(vec2 x) {
	return x - floor(x * (1.0 / 289.0)) * 289.0;
}
vec3 permute(vec3 x) {
	return mod289(((x * 34.0) + 1.0) * x);
}
float simplex2d(vec2 v) {
	const vec4 C = vec4(
		0.211324865405187, 0.366025403784439,
		-0.577350269189626, 0.024390243902439);
	vec2 i = floor(v + dot(v, C.yy));
	vec2 x0 = v - i + dot(i, C.xx);
	vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec4 x12 = x0.xyxy + C.xxzz;
	x12.xy -= i1;

	i = mod289(i);
	vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0))
		+ i.x + vec3(0.0, i1.x, 1.0));

	vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
	m = m * m;
	m = m * m;

	vec3 x = 2.0 * fract(p * C.www) - 1.0;
	vec3 h = abs(x) - 0.5;
	vec3 ox = floor(x + 0.5);
	vec3 a0 = x - ox;

	m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);

	vec3 g;
	g.x = a0.x * x0.x + h.x * x0.y;
	g.yz = a0.yz * x12.xz + h.yz * x12.yw;
	return 130.0 * dot(m, g);
}

// FBM из двух октав симплекса: крупное гуляние + мелкая рябь.
float fire_noise(vec2 v) {
	return 0.65 * simplex2d(v) + 0.35 * simplex2d(v * 2.3 + 17.0);
}

void vertex() {
	float up = clamp(VERTEX.y / height, 0.0, 1.0);
	float sway = up * up;
	vec2 n = vec2(
		fire_noise(vec2(VERTEX.x * tongue_scale, TIME * speed * 0.6)),
		fire_noise(vec2(VERTEX.z * tongue_scale + 31.0, TIME * speed * 0.7)));
	VERTEX.xz += n * 0.08 * sway;
	// Дыхание высоты: конус чуть вытягивается и опадает.
	VERTEX.y *= 1.0 + 0.07 * simplex2d(vec2(TIME * speed * 0.8, 4.0)) * sway;
}

void fragment() {
	float up = clamp(VERTEX.y / height, 0.0, 1.0);
	// Узор пламени: шум ползёт вверх (−TIME по оси высоты), сужаясь к
	// верхушке, — раскалённые ядра рвутся к кончику и гаснут.
	float core = fire_noise(vec2(
		VERTEX.x * tongue_scale,
		VERTEX.y * tongue_scale * 0.8 - TIME * speed * 1.6));
	// Маска высоты с шумовым краем: низ плотный, верх тает языками.
	float flame = up + core * tongue_noise;
	float dissolve = 1.0 - smoothstep(0.35, 1.0, flame);
	// Яркость ядра: где шум выше — горячее (белее).
	float heat = clamp(0.5 + 0.5 * core, 0.0, 1.0);
	vec3 flame_color = mix(base_color.rgb, tip_color.rgb, pow(up, 0.65));
	flame_color = mix(flame_color, tip_color.rgb, heat * 0.35 * up);
	float flicker = 0.85 + 0.1 * simplex2d(vec2(TIME * 8.0, up * 5.0))
		+ 0.06 * simplex2d(vec2(TIME * 13.7, 9.0));
	ALBEDO = flame_color * flicker;
	EMISSION = ALBEDO * 1.6;
	// Плотное у углей, языки тают кверху; совсем без резкой кромки.
	ALPHA = dissolve * mix(1.0, 0.55, up);
}
