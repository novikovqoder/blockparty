// Крона деревьев Леса, сгенерированных EZ-Tree (П5.9, переделка под
// реальную демо-сцену): карточки листьев с альфа-текстурой вида
// (pine/oak/aspen/ash из репозитория ez-tree), цвет — текстура × тон
// пресета × инстанс-тон острова.
// П18 Сборка 1 п.1 «Материалы как в демо»: свой light() (wrap-Ламберт,
// небесный заполнитель, просвет солнца) убран — свет считает стандартный
// PBR Godot, у демо MeshStandardMaterial (metalness 0, roughness 1).
// Нормали листвы — «круглые» roundedNormals генератора ez-tree
// (normal = направление листа + вершина от центра листа, options.js
// default true) запечены прямо в GLB — П18 больше не подменяет их
// сферическими от центра кроны. Двустороннее освещение без переворота
// нормали задней грани, как в демо ('normal *= faceDirection' отключали):
// у Godot в стандартном пути такого переворота нет — обе стороны карточки
// освещаются нормалью листа как есть.
// Ветер — формула ez-tree (#createLeafMaterial): смещение по UV.y
// (черешок → кончик) с фазой из 3D-симплекс-шума по мировому положению
// (инстансы вращаются произвольно — фаза по миру, у соседних листьев
// вразнобой); ветви, как в демо, неподвижны.
// Simplex noise 3D: https://github.com/ashima/webgl-noise (как в ez-tree).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 leaf_tint : source_color = vec3(1.0);
uniform float alpha_cut = 0.5;
uniform float wind_strength = 0.15;
uniform float wind_freq = 0.5;
uniform float wind_noise_scale = 24.0;
// П17 п.1: ширина антиалиасинга края выреза (alpha-to-coverage при MSAA).
// Не ноль — только на ULTRA (MSAA 4x там есть; IslandView.set_quality):
// кромка листвы получает полупрозрачный субпиксельный край вместо рваного
// стенсила. На уровнях без MSAA значение 0 — остаётся scissor
// + coverage-мипы (tools/make_leaf_mips.gd).
uniform float a2c_edge = 0.0;
// П17 п.2 (после П18 — только AO): доля запечённого AO глубины кроны в
// COLOR.rgb (1 — затенение внутри кроны действует, 0 — «плоская» листва,
// как до П17). F3-галочка «Объём кроны» сводит к 0 для замера цены.
uniform float volume_mix = 1.0;
// П18 Сборка 1 п.3 «LOD умнее демо»: порог выреза во время перетекания
// уровней двигает IslandView (порог пресета → 1.0 — полное отсечение);
// вне перехода равен alpha_cut. Отдельный от alpha_cut uniform, чтобы
// возвращать порог пресета, не читая manifest заново.
uniform float reveal = 1.0;

varying vec3 world_pos;

// П17 п.4 «Туман крон»: кроны уходят в туман чуть раньше Environment
// (FOG_DENSITY выше fog_density баланса) и в более тёмный тон с зелёным
// сдвигом (FOG_TINT против day_fog палитры: ×0.75 яркости, G +(R+B)*0.06)
// — дальний лес остаётся зелёной массой, а не светлой пеленой. Запись в
// FOG в fragment() смешивает финальный пиксель с этим тоном (пользователь
// fog(): процессорной функции тумана в Godot нет, docs 4.7 spatial).
// Плотность Environment-тумана НЕ трогаем — только тон и старт крон.
const vec3 FOG_TINT = vec3(0.435, 0.613, 0.715);
const float FOG_DENSITY = 0.004;

// Камера передаётся параметром: built-in CAMERA_POSITION_WORLD доступен
// только в процессорных функциях, внутри пользовательских — нет.
vec4 fog(vec3 position_world, vec3 camera_world) {
	float depth = length(position_world - camera_world);
	float amount = 1.0 - exp(-pow(depth * FOG_DENSITY, 2.0));
	return vec4(FOG_TINT, amount);
}

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
	// Порог выреза: alpha_cut пресета, в перетекании LOD растёт до 1.0
	// (IslandView ведёт reveal; 1.0 — порог пресета, 0.0 — всё отсечено).
	ALPHA_SCISSOR_THRESHOLD = alpha_cut + (1.0 - alpha_cut) * (1.0 - reveal);
	// A2C-край действует только при MSAA (ULTRA); без MSAA — нейтрален.
	ALPHA_ANTIALIASING_EDGE = a2c_edge;
	ALPHA = leaf.a;
	// Объём кроны (П17 п.2, после П18 — только AO): COLOR.rgb — запечённый
	// AO глубины; при volume_mix = 0 AO нейтрален. Нормали — от генератора
	// ez-tree (roundedNormals в GLB), шейдер их не меняет.
	ALBEDO = leaf.rgb * leaf_tint * mix(vec3(1.0), COLOR.rgb, volume_mix);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	FOG = fog(world_pos, CAMERA_POSITION_WORLD);
}
