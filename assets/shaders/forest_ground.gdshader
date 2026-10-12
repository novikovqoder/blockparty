// Реалистичная земля Леса (П5.7, блок 1): сектор [-128..0)² острова красится
// поверх тех же low-poly чанков — меш и коллизия не меняются. Пять наборов
// ambientCG (подстилка/влажная земля/мох/камень/тропа, CC0 — LICENSES.md)
// смешиваются по картам 128 × 128 (1 пиксель = 1 м), запечённым ForestGround
// из высот острова: уклон → камень, низины → влажная земля, пятна мха —
// фиксированный шум, полилиния тропа и полоса Площади → утоптанный гравий.
// Веса оверлеев — RGBA weight_map (r камень, g влага, b мох, a тропа);
// край сектора гасится в border_map: RGB — точный цвет соседнего low-poly
// чанка (TerrainBuilder.point_color), A — вес края: у самой границы текстура
// растворяется в плоском цвете соседа, шва нет (SPEC 2.5).
// UV — из мировых координат (планарная проекция XZ): у чанков нет UV и
// касательных, поэтому нормали текстур (NormalGL, OpenGL-конвенция:
// R +X, G +Y, B +Z наружу) переводятся в мировой базис планарной карты
// (X → X, Y → Z, Z → Y) и примешиваются к геометрической нормали.
// Свет у края сектора — та же toon-модель и плоская нормаль грани, что у
// соседних low-poly чанков (см. light()): совпадают и albedo, и освещение,
// поэтому шов на границе зон исключён по построению, а не на глаз.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley,
	specular_schlick_ggx;

// Пять наборов текстур ambientCG (albedo + нормаль).
uniform sampler2D litter_albedo : source_color, filter_linear_mipmap,
	repeat_enable;
uniform sampler2D litter_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D wet_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D wet_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D path_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D path_normal : filter_linear_mipmap, repeat_enable;

// Карты покраски сектора (128 × 128, край — clamp).
uniform sampler2D weight_map : filter_linear;
uniform sampler2D border_map : source_color, filter_linear;

// Размер текстуры в метрах × scale (период повтора = 1/scale).
uniform float litter_scale = 0.35;
uniform float wet_scale = 0.4;
uniform float moss_scale = 0.45;
uniform float rock_scale = 0.3;
uniform float path_scale = 0.5;
// Сила детали нормалей и затемнение влажной земли.
uniform float bump_strength = 1.0;
uniform float wet_darken = 0.75;

// Тон теневой стороны граней — тот же, что дефолт uniform shadow_tint
// шейдера lowpoly (соседние чанки): у края Лес считается светом соседа.
const vec3 SHADOW_TINT = vec3(0.82, 0.87, 0.98);

varying vec3 world_pos;
// Вес края сектора (border_map.a), семплится в vertex: он нужен в light(),
// а туда varyings из fragment() не передаются.
varying float edge_w;

// --- Разбивка повтора (П5.8, часть A: «плитка» на открытых местах) ---
// Каждая текстура семплится дважды — в своём масштабе и в повёрнутом
// (золотой угол, другой период), смешение ведёт низкочастотный шум:
// глазу не за что зацепиться, сетка повтора не читается. Поверх —
// макровариация яркости крупными пятнами (~25 м): поляна неоднородна.
const float DETAIL_ROT = 2.39996;  // золотой угол, рад
uniform float detail2_scale = 0.71;  // период второй копии к первой
uniform float macro_scale = 0.04;  // период макропятен, 1/м (~25 м)
uniform float macro_strength = 0.16;  // размах яркости макропятен

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Альбедо слоя с разбивкой повтора: две копии, смешанные местным шумом.
vec3 layer_albedo(sampler2D tex, vec2 uv) {
	float c = cos(DETAIL_ROT);
	float s = sin(DETAIL_ROT);
	vec2 uv2 = vec2(uv.x * c - uv.y * s, uv.x * s + uv.y * c) * detail2_scale;
	float mask = smoothstep(0.35, 0.65, vnoise(uv * 0.13));
	return mix(texture(tex, uv).rgb, texture(tex, uv2).rgb, mask);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 sector_uv = (world_pos.xz + vec2(128.0)) / 128.0;
	edge_w = textureLod(border_map, sector_uv, 0.0).a;
}

// Нормаль планарной карты (OpenGL-конвенция) в мировой базис: X → X,
// Y → Z, Z → Y.
vec3 to_world_basis(vec3 nm) {
	return normalize(vec3(nm.x, nm.z, nm.y));
}

void fragment() {
	vec2 sector_uv = (world_pos.xz + vec2(128.0)) / 128.0;
	vec4 w = texture(weight_map, sector_uv);
	vec4 border = texture(border_map, sector_uv);

	vec2 uv_l = world_pos.xz * litter_scale;
	vec2 uv_w = world_pos.xz * wet_scale;
	vec2 uv_m = world_pos.xz * moss_scale;
	vec2 uv_r = world_pos.xz * rock_scale;
	vec2 uv_p = world_pos.xz * path_scale;

	vec3 albedo = layer_albedo(litter_albedo, uv_l);
	vec3 detail = to_world_basis(texture(litter_normal, uv_l).rgb * 2.0 - 1.0);
	float roughness = 0.95;

	// Оверлеи: средневзвешенно по нормализованным весам, итоговая доля
	// смешения — clamp суммы (веса почти не пересекаются: камень на
	// склонах, влага в низинах, мох не на камне).
	float total = w.r + w.g + w.b + w.a;
	if (total > 1e-3) {
		vec3 over_a = (
			layer_albedo(rock_albedo, uv_r) * w.r
			+ layer_albedo(wet_albedo, uv_w) * w.g * wet_darken
			+ layer_albedo(moss_albedo, uv_m) * w.b
			+ layer_albedo(path_albedo, uv_p) * w.a) / total;
		vec3 over_n = (
			(texture(rock_normal, uv_r).rgb * 2.0 - 1.0) * w.r
			+ (texture(wet_normal, uv_w).rgb * 2.0 - 1.0) * w.g
			+ (texture(moss_normal, uv_m).rgb * 2.0 - 1.0) * w.b
			+ (texture(path_normal, uv_p).rgb * 2.0 - 1.0) * w.a) / total;
		float k = clamp(total, 0.0, 1.0);
		albedo = mix(albedo, over_a, k);
		detail = mix(detail, to_world_basis(over_n), k);
		// Влажная земля бликует: грубость падает с долей влаги.
		roughness = mix(roughness, 0.55, clamp(w.g, 0.0, 1.0));
	}

	// Макровариация яркости: крупные пятна ~25 м (перед кромкой — у самой
	// границы альбедо всё равно заменяется плоским цветом соседа).
	albedo *= 1.0 + macro_strength * (vnoise(world_pos.xz * macro_scale) - 0.5) * 2.0;

	// Край сектора: тонировка цветом соседней зоны, у границы вес 1 —
	// плоский цвет соседа (текстурная деталь гаснет вместе с ним).
	albedo = mix(albedo, border.rgb, border.a);
	detail = mix(detail, vec3(0.0, 1.0, 0.0), border.a);

	ALBEDO = albedo;
	ROUGHNESS = mix(roughness, 0.95, border.a);
	// Геометрическая нормаль рельефа + деталь текстур (планарный базис).
	vec3 shaded = normalize(normalize(NORMAL)
		+ (detail - vec3(0.0, 1.0, 0.0)) * bump_strength);
	// У самой границы — та же плоская нормаль на грань (dFdx/dFdy), что у
	// соседних low-poly чанков: вместе с toon-светом из light() грань у
	// края по построению считается тем же цветом, что у соседа, — шва нет.
	vec3 flat_n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = mix(shaded, flat_n, border.a);
}

// Прямой свет: внутри сектора — Ламберт с GGX-бликом (влажная земля
// поблёскивает), к краю — в точности та же двухступенчатая toon-модель,
// что в light() шейдера lowpoly (ступени и SHADOW_TINT совпадают).
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float step1 = smoothstep(0.0, 0.35, ndl);
	float step2 = smoothstep(0.35, 0.75, ndl);
	float shade = 0.35 * step1 + 0.65 * step2;
	vec3 toon = LIGHT_COLOR * ATTENUATION
		* mix(ALBEDO * SHADOW_TINT, ALBEDO, shade) * shade;
	vec3 lambert = LIGHT_COLOR * ATTENUATION * ALBEDO * clamp(ndl, 0.0, 1.0);
	DIFFUSE_LIGHT += mix(lambert, toon, edge_w);
	// GGX-блик (D-член, диэлектрик F ≈ 0.04); у соседа спекуляра нет —
	// к краю блик гасится, иначе на границе вспыхивал бы.
	vec3 half_v = normalize(LIGHT + VIEW);
	float ndh = max(dot(NORMAL, half_v), 0.0);
	float a2 = ROUGHNESS * ROUGHNESS;
	a2 *= a2;
	float d_ggx = a2 / (3.14159 * pow(ndh * ndh * (a2 - 1.0) + 1.0, 2.0));
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * d_ggx * 0.04 * (1.0 - edge_w);
}
