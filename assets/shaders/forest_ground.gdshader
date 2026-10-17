// Земля Леса (П5.9 переделка, П2): смешивание травы и грунта текстурами
// по схеме демо ez-tree (src/app/ground.js) — трава и земля тайлятся
// 1 повтор / 30 м, пятнистость задаёт симплекс-шум масштаба 100 м:
//   n = 0.5 + 0.5 * simplex2d(world.xz / 100)
//   s = smoothstep(patchiness - 0.1, patchiness + 0.1, n)
//   albedo = mix(grass, dirt, s)
// Симплекс не имеет решётчатой структуры (в отличие от прежнего value-noise
// на квадратной сетке — его «полосы» на склонах и рябь видел владелец),
// текстуры идут с мип-мапами и линейной фильтрацией — муара нет.
// Текстуры — CC0 (ambientcg Grass001, polyhaven forest_ground_05):
// одноимённые текстуры демо (ground/*.jpg) лицензионно не описаны
// (textures/LICENSE.md репозитория ez-tree покрывает только bark и leaves),
// поэтому заменены ближайшими по тону CC0; оттенок сведён к демо
// uniform-тонами (grass_tint/dirt_tint).
// Поверх базы — оверлеи рельефа Леса (веса запекает ForestGround:
// камень на склонах, влага в низинах, пятна мха, тропа и Площадь) и
// мягкий край сектора (border_map: RGB — цвет соседнего low-poly чанка,
// A — вес края; шва на границе Леса нет).
// Свет: внутри — мягкий wrap-Ламберт и нормаль карты высот (сглаженные
// склоны оврага без огранки), у края — та же toon-модель и плоская
// нормаль соседних low-poly чанков.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert,
	specular_schlick_ggx;

// Цвета оверлеев (source_color — sRGB в линейный переводит движок).
uniform vec3 wet_color : source_color = vec3(0.31, 0.26, 0.20);
uniform vec3 moss_color : source_color = vec3(0.33, 0.44, 0.24);
uniform vec3 rock_color : source_color = vec3(0.53, 0.54, 0.55);
uniform vec3 path_color : source_color = vec3(0.61, 0.50, 0.36);

// Текстуры травы и грунта (CC0) и тон к палитре демо: средний тон демо
// grass.jpg rgb(66,70,43), dirt_color.jpg rgb(73,57,49) — CC0-замены
// светлее, тон сводится умножением (в sRGB).
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D dirt_normal : filter_linear_mipmap_anisotropic;
uniform vec3 grass_tint : source_color = vec3(0.96, 0.76, 1.08);
uniform vec3 dirt_tint : source_color = vec3(0.83, 0.84, 1.07);

// Размер пятна травы/грунта и пестрота смешивания — параметры демо
// (GrassOptions: scale 100, patchiness 0.7).
uniform float noise_scale = 100.0;
uniform float patchiness = 0.7;
// Повтор текстуры, м на тайл (демо: uv / 30).
uniform float tile_m = 30.0;
// Сила нормалей грунта (normalScale демо = 1).
uniform float normal_strength = 1.0;

// Карты покраски сектора (128 × 128, край — clamp).
uniform sampler2D weight_map : filter_linear_mipmap_anisotropic;
uniform sampler2D border_map : source_color, filter_linear_mipmap_anisotropic;

// Карта честных нормалей рельефа (П5.9 переделка, П3): ForestGround печёт
// её из карты высот конечными разностями, кодировка n·0.5+0.5 (данные,
// не цвет — без source_color). На крутых стенках оврага нормаль смотрит
// поперёк склона — сглаженное поле нормалей заменяет сглаживание
// «к вертикали», белая огранка больших low-poly граней исчезает.
uniform sampler2D relief_normal : filter_linear_mipmap_anisotropic;

// Сглаживание огранки рельефа: 0 — плоские грани меша, 1 — честная
// нормаль карты высот.
uniform float soften = 0.7;
// Блик влажной земли (грубость и сила).
uniform float wet_roughness = 0.45;
uniform float wet_specular = 0.03;

// Тон теневой стороны граней — тот же, что дефолт uniform shadow_tint
// шейдера lowpoly (соседние чанки): у края Лес считается светом соседа.
const vec3 SHADOW_TINT = vec3(0.82, 0.87, 0.98);

varying vec3 world_pos;
// Вес края сектора (border_map.a), семплится в vertex: он нужен в light(),
// а туда varyings из fragment() не передаются.
varying float edge_w;

// Симплекс-шум 2D (Ian McEwan / Ashima Arts, публичный webgl-noise) —
// тот же, что в шейдере земли демо.
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
	vec2 sector_uv = (world_pos.xz + vec2(128.0)) / 128.0;
	edge_w = textureLod(border_map, sector_uv, 0.0).a;
}

void fragment() {
	vec2 sector_uv = (world_pos.xz + vec2(128.0)) / 128.0;
	vec4 w = texture(weight_map, sector_uv);
	vec4 border = texture(border_map, sector_uv);

	// База — трава и грунт текстурами, пятнистость — симплекс (схема
	// демо ground.js: карта_fragment). Тайл 30 м, шум 100 м.
	vec2 uv = world_pos.xz;
	vec3 grass_color = texture(grass_tex, uv / tile_m).rgb * grass_tint;
	vec3 dirt_color = texture(dirt_tex, uv / tile_m).rgb * dirt_tint;
	float n = 0.5 + 0.5 * simplex2d(uv / noise_scale);
	float s = smoothstep(patchiness - 0.1, patchiness + 0.1, n);
	vec3 albedo = mix(grass_color, dirt_color, s);

	// Оверлеи рельефа по весам карты (веса почти не пересекаются: камень
	// на склонах, влага в низинах, мох не на камне).
	float total = clamp(w.r + w.g + w.b + w.a, 0.0, 1.0);
	vec3 overlay = (
		rock_color * w.r
		+ wet_color * w.g
		+ moss_color * w.b
		+ path_color * w.a);
	albedo = mix(albedo, overlay, total);

	// Край сектора: тонировка цветом соседней зоны, у границы вес 1 —
	// плоский цвет соседа.
	albedo = mix(albedo, border.rgb, border.a);

	ALBEDO = albedo;
	ROUGHNESS = mix(mix(0.95, wet_roughness, clamp(w.g, 0.0, 1.0)), 0.95, border.a);

	// Нормаль: плоская грань рельефа, сглаженная честным полем нормалей
	// из карты высот (карта мировая — переводится в видовой базис), у
	// самой границы — в точности плоская грань соседа.
	vec3 flat_n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	vec3 relief_n = normalize((VIEW_MATRIX * vec4(
		texture(relief_normal, sector_uv).xyz * 2.0 - 1.0, 0.0)).xyz);
	NORMAL = normalize(mix(flat_n, relief_n, soften * (1.0 - edge_w)));
	// Рельеф грунта — нормали polyhaven (OpenGL Y+), сила как в демо.
	NORMAL_MAP = texture(dirt_normal, uv / tile_m).rgb;
	NORMAL_MAP_DEPTH = normal_strength * (1.0 - edge_w);
}

// Прямой свет: внутри сектора — мягкий wrap-Ламберт, к краю — в точности
// та же двухступенчатая toon-модель, что в light() шейдера lowpoly.
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = 0.35;
	float lambert = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	vec3 wrap_diff = LIGHT_COLOR * ATTENUATION * ALBEDO * lambert;
	float step1 = smoothstep(0.0, 0.35, ndl);
	float step2 = smoothstep(0.35, 0.75, ndl);
	float shade = 0.35 * step1 + 0.65 * step2;
	vec3 toon = LIGHT_COLOR * ATTENUATION
		* mix(ALBEDO * SHADOW_TINT, ALBEDO, shade) * shade;
	DIFFUSE_LIGHT += mix(wrap_diff, toon, edge_w);
	// Влажная земля чуть блещет (D-член GGX, диэлектрик F ≈ 0.04);
	// у соседа спекуляра нет — к краю блик гасится.
	vec3 half_v = normalize(LIGHT + VIEW);
	float ndh = max(dot(NORMAL, half_v), 0.0);
	float a2 = ROUGHNESS * ROUGHNESS;
	a2 *= a2;
	float d_ggx = a2 / (3.14159 * pow(ndh * ndh * (a2 - 1.0) + 1.0, 2.0));
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * d_ggx * wet_specular * (1.0 - edge_w);
}
