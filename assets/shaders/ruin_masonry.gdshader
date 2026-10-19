// Кладка руин (доработка-2 П5.13, П4): белый угловатый блок заменён
// камнем с текстурой. Трипланарная развёртка по мировой позиции и
// производной нормали (меши предметов не несут UV и нормалей — грани
// low-poly): соседние блоки стены sampled одной мировой сеткой, швы
// кладки непрерывны через блоки, растяжения на гранях нет.
// Текстуры CC0: polyhaven old_stone_wall_02 (диффуз + нормали,
// «выщербленность» кладки читается картой нормалей), ambientCG Moss001
// (мох). Мох — по верхним граням (мировая нормаль вверх) островками
// из симплекса с мягким переходом; на боках — редкие потёки у верхней
// кромки. Вершинный цвет меша — тонировка деталей (карниз/проём темнее),
// общий тон — uniform tint (текстура средне-тёмная, мир пастельный —
// камень высветляется и уходит в холод).
// Свет — та же двухступенчатая toon-модель, что у lowpoly.gdshader:
// руины в одном стиле с деревней и скалами; спекуляр камня слабый GGX.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert,
	specular_schlick_ggx;

uniform sampler2D masonry_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D masonry_normal : filter_linear_mipmap_anisotropic;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap_anisotropic;

// Общий тон кладки (линейный множитель поверх текстуры): текстура
// средне-тёмная тёплая, палитра острова светлая холодная — камень
// высветляем и уводим в серо-голубой.
uniform vec3 tint = vec3(1.55, 1.62, 1.72);
// Размер тайла кладки, м (полагаем квадрат 2048 px ≈ 2.6 м камня).
uniform float tile_m = 2.6;
// Сила нормалей кладки.
uniform float normal_strength = 0.85;

// Мох: густота (0 — голый камень), масштаб пятен и кромки, тон.
uniform float moss_amount = 0.65;
uniform float moss_patch_scale = 2.6;
uniform float moss_edge_scale = 6.0;
uniform vec3 moss_tint : source_color = vec3(1.05, 1.1, 0.9);
uniform float moss_tile_m = 1.3;

// Блик мокрого камня (слабый).
uniform float rock_roughness = 0.82;
uniform float rock_specular = 0.025;

// Тон теневой стороны граней — дефолт uniform shadow_tint lowpoly.
const vec3 SHADOW_TINT = vec3(0.82, 0.87, 0.98);

varying vec3 world_pos;

// Симплекс-шум 2D (Ian McEwan / Ashima Arts, публичный webgl-noise) —
// тот же, что в forest_ground.gdshader.
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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Плоская нормаль грани (меш без нормалей — как lowpoly.gdshader).
	vec3 face_n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));

	// Трипланарные веса по мировой нормали: верх несёт XZ-плоскость,
	// бока — ZY/XY; резкость 4 — переходы узкие, граней немного.
	vec3 tri_w = pow(abs(face_n), vec3(4.0));
	tri_w /= (tri_w.x + tri_w.y + tri_w.z);
	vec2 uv_top = world_pos.xz / tile_m;
	vec2 uv_x = world_pos.zy / tile_m;
	vec2 uv_z = world_pos.xy / tile_m;

	vec3 stone = tint * COLOR.rgb * (
		tri_w.y * texture(masonry_tex, uv_top).rgb
		+ tri_w.x * texture(masonry_tex, uv_x).rgb
		+ tri_w.z * texture(masonry_tex, uv_z).rgb);

	// Мох: пятна симплекса на верхней полусфере (мягкий порог по наклону
	// грани), рваная кромка — шум вдвое мельче; на боках — только редкие
	// потёки у самой верхней кромки. Текстура мха — тем же трипланаром,
	// тайл мельче камня.
	float patch = 0.5 + 0.5 * simplex2d(world_pos.xz / moss_patch_scale);
	float edge = 0.5 + 0.5 * simplex2d(world_pos.xz / moss_edge_scale);
	float top_face = smoothstep(0.45, 0.85, face_n.y);
	float side_leak = smoothstep(0.75, 0.98, face_n.y)
		* 0.5 * smoothstep(0.35, 0.75, abs(face_n.x) + abs(face_n.z) - 0.4);
	float moss_mask = clamp(moss_amount
		* (top_face * smoothstep(0.62, 0.78, patch * 0.65 + edge * 0.35)
			+ side_leak * smoothstep(0.55, 0.8, edge)),
		0.0, 1.0);
	vec2 muv_top = world_pos.xz / moss_tile_m;
	vec2 muv_x = world_pos.zy / moss_tile_m;
	vec2 muv_z = world_pos.xy / moss_tile_m;
	vec3 moss = moss_tint * (
		tri_w.y * texture(moss_tex, muv_top).rgb
		+ tri_w.x * texture(moss_tex, muv_x).rgb
		+ tri_w.z * texture(moss_tex, muv_z).rgb);

	ALBEDO = mix(stone, moss, moss_mask);
	ROUGHNESS = mix(rock_roughness, 0.95, moss_mask);

	// Нормали кладки: карта nor_gl двумя компонентами ложится на
	// касательные оси доминирующей плоскости (как dirt_normal у земли
	// Леса) — тангентного пространства и UV у меша нет.
	float sx = sign(face_n.x);
	float sz = sign(face_n.z);
	vec2 n_top = texture(masonry_normal, uv_top).rg * 2.0 - 1.0;
	vec2 n_x = texture(masonry_normal, uv_x).rg * 2.0 - 1.0;
	vec2 n_z = texture(masonry_normal, uv_z).rg * 2.0 - 1.0;
	vec3 perturb = normal_strength * (
		tri_w.y * (n_top.x * vec3(1.0, 0.0, 0.0) + n_top.y * vec3(0.0, 0.0, 1.0))
		+ tri_w.x * (n_x.x * vec3(0.0, 0.0, sx) + n_x.y * vec3(0.0, 1.0, 0.0))
		+ tri_w.z * (n_z.x * vec3(sz, 0.0, 0.0) + n_z.y * vec3(0.0, 1.0, 0.0)));
	vec3 world_n = normalize(face_n + perturb);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);
}

// Свет — toon-модель lowpoly.gdshader: руины в одном стиле с миром.
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float step1 = smoothstep(0.0, 0.35, ndl);
	float step2 = smoothstep(0.35, 0.75, ndl);
	float shade = 0.35 * step1 + 0.65 * step2;
	vec3 tinted = mix(ALBEDO * SHADOW_TINT, ALBEDO, shade);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * tinted * shade;
	vec3 half_v = normalize(LIGHT + VIEW);
	float ndh = max(dot(NORMAL, half_v), 0.0);
	float a2 = ROUGHNESS * ROUGHNESS;
	a2 *= a2;
	float d_ggx = a2 / (3.14159 * pow(ndh * ndh * (a2 - 1.0) + 1.0, 2.0));
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * d_ggx * rock_specular;
}
