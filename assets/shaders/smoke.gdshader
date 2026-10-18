// Дым костра (доработка П5.13, живой огонь): мягкий круглый клуб на
// партикл-кваде — кромку клубит симплекс-шум (тот же, что в fire/
// forest_ground; без решётчатых артефактов value-noise), альфа по
// lifetime приходит из COLOR.a рампы партиклов. Билборд, без освещения;
// цвет — нейтральный тёплый серый, чтобы ночью читался отсветом костра.
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled;

uniform vec4 smoke_color : source_color = vec4(0.62, 0.6, 0.58, 1.0);
// Радиус плотной части клуба (0..0.5 от половины квада).
uniform float core = 0.16;
// Сила шума кромки.
uniform float wobble = 0.1;
// Общая непрозрачность (дым лёгкий).
uniform float density = 0.4;

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

void vertex() {
	// Билборд вручную (у spatial-шейдеров нет render_mode billboard):
	// базис MODELVIEW заменяется на единичный с сохранением масштаба —
	// квад всегда развёрнут к камере; позицию несёт трансляция частицы.
	MODELVIEW_MATRIX = VIEW_MATRIX * MODEL_MATRIX;
	MODELVIEW_MATRIX[0].xyz = vec3(1.0, 0.0, 0.0) * length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX[1].xyz = vec3(0.0, 1.0, 0.0) * length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX[2].xyz = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	// Партиклы не дают уникального времени рождения: клуб живёт рампой
	// альфы, а шум кромки дрейфует по TIME + положение квада (у каждого
	// клуба своя фаза, INSTANCE_CUSTOM нет у ParticleProcessMaterial).
	vec2 from_center = UV - vec2(0.5);
	float r = length(from_center);
	float edge = 0.5 - wobble * 0.5 * (
		0.65 * simplex2d(from_center * 5.0 + vec2(TIME * 0.35, 3.0))
		+ 0.35 * simplex2d(from_center * 11.0 + vec2(7.0, TIME * 0.5)));
	float puff = 1.0 - smoothstep(core, edge, r);
	ALPHA = puff * COLOR.a * density;
	ALBEDO = smoke_color.rgb;
}
