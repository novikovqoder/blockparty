// Трава, папоротники и цветы Леса (П5.9, блок 3): пучки-островки
// MultiMesh с градиентом травинки (тёмное основание → светлые кончики —
// uniform-цвета из visual_palette.tres), ветер волнами и плавным спадом
// густоты от камеры. Нормали травинок запечены вертикально вверх: трава
// затеняется как земля и не отслаивается от неё; качание читается
// силуэтом, а не бликами («не пластик»). Оттенок пучка — instance-цвет
// MultiMesh (brightness + примесь сухого), он умножает градиент.
// Густота у камеры: от fade_start до fade_end травинки плавно схлопываются
// по высоте (куст «садится» в землю), дальше поляна читается цветом земли
// из forest_ground.gdshader — жёсткой границы нет ни по цвету, ни по
// геометрии. Ветер: вес по квадрату высоты травинки, две гармоники и
// медленные порывы волной по миру — поле не качается синхронно.
shader_type spatial;
render_mode specular_disabled, cull_disabled;

uniform vec3 base_color : source_color = vec3(0.25, 0.36, 0.18);
uniform vec3 tip_color : source_color = vec3(0.66, 0.77, 0.40);
// 1 — красить градиентом основание→кончик (трава), 0 — цвет вершин
// (папоротник, цветы).
uniform float use_gradient = 1.0;
// Тон теневой стороны (совпадает с lowpoly/ground — единая гамма).
uniform vec3 shadow_tint : source_color = vec3(0.82, 0.87, 0.98);

// --- Ветер ---
uniform float wind_amplitude = 0.10;
uniform float wind_freq = 1.9;
uniform vec2 wind_direction = vec2(0.85, 0.45);

// --- Спад густоты от камеры, м ---
uniform float fade_start = 40.0;
uniform float fade_end = 58.0;

// Отношение высоты травинки (0 основание, 1 кончик) — в UV.y меша.
varying float blade_t;
// Instance-оттенок пучка (COLOR = вершины × instance).
varying vec3 tint;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	blade_t = UV.y;
	tint = COLOR.rgb;

	// Ветер: вес растёт к кончику, порыв — волна по миру. Длина волны ~28 м
	// (доработка под эталон: прежние ~90 м в кадре читались как ровное
	// качание — гребень не было видно); бежит ~5 м/с — перекат по поляне.
	float weight = blade_t * blade_t;
	float gust = 0.55 + 0.45 * sin(world.x * 0.22 + world.z * 0.16 + TIME * 1.1);
	float phase = world.x * 0.9 + world.z * 0.7;
	vec2 sway = wind_direction * (
		sin(TIME * wind_freq + phase)
		+ 0.4 * sin(TIME * wind_freq * 2.6 + phase * 1.7));
	VERTEX.xz += sway * wind_amplitude * weight * gust;

	// Спад густоты: травинки «садятся» в землю между fade_start и fade_end.
	float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float keep = 1.0 - smoothstep(fade_start, fade_end, dist);
	VERTEX.y *= keep;
}

void fragment() {
	// Нормаль травинки — вертикаль (запечена в меше), мягкий свет как у
	// земли: трава не бликует и не отслаивается от рельефа.
	vec3 gradient = mix(base_color, tip_color, blade_t);
	ALBEDO = mix(COLOR.rgb, gradient * tint, use_gradient);
}

void light() {
	// Тот же wrap-Ламберт, что у земли Леса (forest_ground.gdshader):
	// трава и рельеф считаются одним светом — пятна травы не «вырезаются».
	float ndl = dot(vec3(0.0, 1.0, 0.0), LIGHT);
	float wrap = 0.35;
	float lambert = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	vec3 tinted = mix(ALBEDO * shadow_tint, ALBEDO, smoothstep(0.0, 0.35, ndl));
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * tinted * lambert;
}
