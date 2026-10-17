// Крона процедурных деревьев Леса (П5.9, блок 4 + доработка под эталон
// EZ-Tree): карточка листвы — гроздь листьев с альфа-текстурой (листики
// читаются по краям, между ними прозрачные «дыры» — сквозь крону видны
// небо и дальние деревья), цвет — вершинный (глубина кроны запечена
// генератором) × оттенки грозди из текстуры. Свет — wrap-Ламберт с
// широким переносом (крона читается мягким объёмом) и просвет солнца
// сквозь листву. Ветер — заметное качание волнами по миру (согласован
// с корой tree_bark и билбордом tree_billboard) плюс мелкая дрожь
// кончиков карточек: крона колышется, как на эталоне, а не «плавает»
// одной глыбой.
shader_type spatial;
render_mode specular_disabled, cull_disabled, depth_draw_opaque;

// Гроздь листьев (RGB — затемнение к черешку и подсветка кончиков,
// A — форма листьев с прозрачными «дырами»); хвойные — веточка с иглами.
uniform sampler2D cluster_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec2 wind_direction = vec2(0.85, 0.45);
uniform float wind_amplitude = 0.25;
uniform float wind_freq = 0.55;

varying vec3 world_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Качание волнами: две синусоиды от фазы по ветру, медленный порыв
	// волной по лесу; вес растёт с высотой — ствол стоит, крона плывёт.
	float phase = dot(world_pos.xz, wind_direction) * 0.08;
	float t = TIME * wind_freq;
	float gust = 0.75 + 0.25 * sin(dot(world_pos.xz, vec2(0.05, 0.035)) + TIME * 0.6);
	float sway = (0.6 * sin(t + phase) + 0.3 * sin(2.3 * t + 1.7 * phase)) * gust;
	float weight = smoothstep(0.5, 6.0, VERTEX.y);
	// Дрожь кончиков: карточка держится черешком за ветку (UV.y 0 → 1
	// от черешка к кончику), фаза — от позиции карточки, соседние грозди
	// дрожат вразнобой.
	float flutter = sin(5.2 * t + hash12(floor(world_pos.xz * 4.0)) * 6.2832);
	vec3 shift = vec3(wind_direction.x, 0.0, wind_direction.y)
		* wind_amplitude * weight * (sway + flutter * 0.08 * UV.y);
	vec4 mv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	mv.xyz += (VIEW_MATRIX * vec4(shift, 0.0)).xyz;
	VERTEX = (INV_VIEW_MATRIX * mv).xyz;
}

void fragment() {
	vec4 cluster = texture(cluster_tex, UV);
	if (cluster.a < 0.5) {
		discard;
	}
	ALBEDO = COLOR.rgb * cluster.rgb;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = 0.5;
	float lambert = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	// Небесный заполнитель: теневая сторона кроны читается тёмно-зелёной
	// глубиной, а не угольной дырой (ambient из Environment до кастомного
	// light() не доходит, а ATTENUATION внутри густой кроны ≈ 0 — камера
	// вплотную к кроне видела сплошной уголь, точка 2 тура П5.7). Небо
	// тенью не блокируется, поэтому fill без ATTENUATION; масштаб дня и
	// ночи даёт LIGHT_COLOR, hemisphere — верх кроны чуть светлее низа.
	float sky_fill = clamp(0.5 + 0.5 * NORMAL.y, 0.0, 1.0) * 0.25;
	float lit = max(lambert * ATTENUATION, sky_fill);
	DIFFUSE_LIGHT += LIGHT_COLOR * ALBEDO * lit;
	// Просвет насквозь: солнце за кроной относительно камеры.
	float backlight = pow(max(-dot(VIEW, LIGHT), 0.0), 2.5);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ALBEDO * backlight * 0.55;
}
