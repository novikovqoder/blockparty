// Поле травы и цветов демо ez-tree (П18 Сборка 2, grass.js): пучок —
// 3 скрещенные плоскости из grass.glb (6 треугольников), цветы —
// flower_{white,blue,yellow}.glb по поверхностям. Материал — PBR без
// ручного light(), как у демо MeshStandardMaterial (metalness 0,
// roughness из GLB): albedo = текстура × albedo поверхности (цветы)
// × инстанс-тон COLOR (раскладка травы) × затемнение материала демо
// (color ×0.6, grass.js:147), alphaTest 0.5, двусторонняя сторона.
// Эмиссия 0x308040 × 0.05 — «небольшой свет, чтобы трава имела цвет
// там, где не освещена» (grass.js:133); заодно убирает «угольные»
// кляксы в тени, на которые жаловались по сборке П17 (старое поле
// считало свет ручным light() с небесным заполнителем 0.25).
// Ветер — формула листвы демо (#createLeafMaterial, canopy.gdshader):
// три синуса с фазой 3D-симплекс-шума по миру, парус — высота вершины
// от основания (VERTEX.y / model_height); амплитуда/мастаб шума — те
// же, что у крон (IslandView передаёт 0.5·k и 70·k): трава качается
// вместе с деревьями.
// Кромка поля (задание П18: «масштаб к нулю, не обрыв»): между
// fade_start и fade_end пучок стягивается к точке посадки — дистанция
// до камеры, раскладка при этом не пересобирается и не «плывёт».
// Simplex noise 3D: https://github.com/ashima/webgl-noise (как в canopy).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 albedo_color : source_color = vec3(1.0);
uniform float roughness_v = 1.0;
// Затемнение материала демо (grass.js:147 «Decrease grass brightness»).
uniform float mat_dim = 0.6;
uniform vec3 emission_color : source_color = vec3(0.188, 0.502, 0.251);
uniform float emission_energy = 0.05;
uniform float alpha_cut = 0.5;
// Кромка поля: масштаб пучка к нулю от дистанции до камеры.
uniform float fade_start = 80.0;
uniform float fade_end = 100.0;
// Ветер листвы демо (canopy): амплитуда в метрах, частота, масштаб шума.
uniform float wind_strength = 0.19;
uniform float wind_freq = 0.5;
uniform float wind_noise_scale = 26.6;
// Высота модели в локальных единицах GLB — нормировка паруса (трава 2,
// цветы ~86); у травы вершины от основания, height_norm 0..1.
uniform float model_height = 2.0;

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
	// Парус: качание растёт с высотой вершины от основания пучка.
	float height_norm = clamp(VERTEX.y / model_height, 0.0, 1.0);
	// Ветер листвы (canopy): фаза шума по миру, направление мировое
	// (0.5, 0, 0.5) — в базис объекта, инстансы стоят с yaw и наклоном.
	float offset = 6.2832 * simplex3(world_pos / wind_noise_scale);
	float t = TIME * wind_freq;
	float sway = wind_strength * height_norm
		* (0.5 * sin(t + offset)
			+ 0.3 * sin(2.0 * t + 1.3 * offset)
			+ 0.2 * sin(5.0 * t + 1.5 * offset));
	VERTEX += (inverse(MODEL_MATRIX) * vec4(0.5, 0.0, 0.5, 0.0)).xyz * sway;
	// Кромка поля: пучок стягивается к точке посадки (масштаб к нулю,
	// не обрыв); вырожденные треугольники не растеризуются.
	float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float keep = 1.0 - smoothstep(fade_start, fade_end, dist);
	VERTEX *= keep;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	// COLOR — инстанс-тон раскладки травы (у цветов use_colors выключен,
	// COLOR нейтрален); albedo_color — цвет поверхности цветка из GLB.
	ALBEDO = tex.rgb * albedo_color * COLOR.rgb * mat_dim;
	EMISSION = emission_color * emission_energy;
	ROUGHNESS = roughness_v;
	METALLIC = 0.0;
}
