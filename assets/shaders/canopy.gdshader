// Крона деревьев Леса, сгенерированных EZ-Tree (П5.9, переделка под
// реальную демо-сцену): карточки листьев с альфа-текстурой вида
// (pine/oak/aspen/ash из репозитория ez-tree), цвет — текстура × тон
// пресета × инстанс-тон острова. Свет — wrap-Ламберт с небесным
// заполнителем и просветом солнца сквозь листву (владелец просил).
// Ветер — формула ez-tree (#createLeafMaterial): смещение по UV.y
// (черешок → кончик) с фазой из 3D-симплекс-шума по мировому положению
// (инстансы вращаются произвольно — фаза по миру, у соседних листьев
// вразнобой); ветви, как в демо, неподвижны.
// Simplex noise 3D: https://github.com/ashima/webgl-noise (как в ez-tree).
shader_type spatial;
render_mode specular_disabled, cull_disabled, depth_draw_opaque;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 leaf_tint : source_color = vec3(1.0);
uniform float alpha_cut = 0.5;
uniform float wind_strength = 0.15;
uniform float wind_freq = 0.5;
uniform float wind_noise_scale = 24.0;

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
	// Ветер ez-tree: фаза шума по миру, смещение растёт к кончику листа
	// (UV.y); направление (0.5, 0, 0.5) — мировое, поворачивается в
	// пространство объекта (инстансы стоят с произвольным yaw).
	float offset = 6.2832 * simplex3(world_pos / wind_noise_scale);
	float t = TIME * wind_freq;
	float sway = wind_strength * UV.y
		* (0.5 * sin(t + offset)
			+ 0.3 * sin(2.0 * t + 1.3 * offset)
			+ 0.2 * sin(5.0 * t + 1.5 * offset));
	VERTEX += (inverse(MODEL_MATRIX) * vec4(0.5, 0.0, 0.5, 0.0)).xyz * sway;
}

void fragment() {
	vec4 leaf = texture(leaf_tex, UV);
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA = leaf.a;
	ALBEDO = leaf.rgb * leaf_tint * COLOR.rgb;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = 0.5;
	float lambert = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	// Небесный заполнитель: теневая сторона кроны читается тёмной глубиной,
	// а не угольной дырой (ambient из Environment в кастомный light() не
	// доходит, внутри густой кроны ATTENUATION ≈ 0).
	float sky_fill = clamp(0.5 + 0.5 * NORMAL.y, 0.0, 1.0) * 0.25;
	float lit = max(lambert * ATTENUATION, sky_fill);
	DIFFUSE_LIGHT += LIGHT_COLOR * ALBEDO * lit;
	// Просвет насквозь: солнце за кроной относительно камеры.
	float backlight = pow(max(-dot(VIEW, LIGHT), 0.0), 2.5);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ALBEDO * backlight * 0.55;
}
