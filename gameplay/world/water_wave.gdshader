// Вода (раздел 6 SPEC): плоскость с шейдером. vfx-fix, визуальный блок (а):
// — мягкие волны: три спокойные синусоиды по вершинам (Y-only, длина ≥ 3
//   шагов сетки — без алиасинга, баг 4);
// — блики солнца: нормаль в фрагменте из производных тех же волн плюс
//   мелкая рябь (вершины не трогает), низкая шероховатость;
// — пена у береговой кромки и прозрачность на мелководье: глубина воды
//   из depth-текстуры (расстояние от поверхности до рельефа под фрагментом).
// П5.13, блок 2 (дух Sea of Thieves, без копирования платных ассетов):
// — мягкое отражение неба: френель — у ног вода прозрачная, к горизонту
//   зеркальная; цвет неба (верх/горизонт) по высоте отражённого луча —
//   закатное небо само попадает в воду; цвета ведёт DayCycle по часам мира;
// — дорожка светила: глинт вдоль отражённого луча к солнцу днём и луне
//   ночью, рябь нормалей рвёт его в мягкие блики;
// — пена не только у кромки: гребни волн у мелководья вспениваются.
// Если depth-текстура недоступна (чёрная выборка), линейная глубина сцены
// получается меньше глубины фрагмента — water_depth зажимается в 0 и
// пена/прозрачность мягко отключаются, вода остаётся обычной.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

uniform vec4 water_color : source_color = vec4(0.5, 0.78, 0.91, 0.55);
uniform vec4 shallow_color : source_color = vec4(0.62, 0.88, 0.95, 0.55);
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 1.0, 0.92);
// Небо для мягкого отражения: верх и горизонт — DayCycle мешает палитры
// времён суток, вода живёт вместе с небом (ночью отражение темнеет само).
uniform vec4 sky_top_color : source_color = vec4(0.35, 0.55, 0.85, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.75, 0.85, 0.95, 1.0);
// Направление на светило (солнце днём, луна ночью) и цвет его дорожки.
uniform vec3 sun_direction = vec3(0.4, 0.7, 0.2);
uniform vec4 glint_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);
// Сила дорожки: день — 1.0, ночь — приглушённая (энергия в цвете).
uniform float glint_strength = 1.0;
// Доля отражения неба в альбедо на френеле (0 — выключить).
uniform float reflect_strength = 0.75;
uniform float wave_height = 0.045;
uniform float wave_length = 8.0;
uniform float wave_speed = 0.6;
// Мелкая рябь только нормалями (сила наклона, без сдвига вершин).
uniform float ripple_strength = 0.055;
// Полоса пены: вода мельче этого — пена (м).
uniform float foam_width = 0.5;
// Глубина сцены под поверхностью (Godot 4.7: DEPTH_TEXTURE убран в
// пользу uniform с hint_depth_texture).
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

varying vec3 world_pos;


// Высота волн в мировой точке XZ — одна функция для вершин и нормалей.
float wave_height_at(vec2 p) {
	return (
		sin(p.x * TAU / wave_length + TIME * wave_speed)
		+ sin(p.y * TAU / (wave_length * 1.7) + TIME * wave_speed * 1.3)
		+ sin((p.x + p.y) * TAU / (wave_length * 3.1)
			+ TIME * wave_speed * 0.8)
	) * (wave_height / 3.0);
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 pos = VERTEX;
	pos.y += wave_height_at(world_pos.xz);
	VERTEX = pos;
}


void fragment() {
	// Нормаль: наклон волн (центральная разность) + мелкая рябь.
	float e = 0.4;
	float hx = wave_height_at(world_pos.xz + vec2(e, 0.0))
		- wave_height_at(world_pos.xz - vec2(e, 0.0));
	float hz = wave_height_at(world_pos.xz + vec2(0.0, e))
		- wave_height_at(world_pos.xz - vec2(0.0, e));
	vec2 ripple = vec2(
		sin(world_pos.x * 1.9 + world_pos.z * 1.3 + TIME * 1.6),
		sin(world_pos.z * 2.3 - world_pos.x * 1.1 + TIME * 2.0));
	vec3 normal = normalize(vec3(
		-hx / (2.0 * e) + ripple.x * ripple_strength,
		1.0,
		-hz / (2.0 * e) + ripple.y * ripple_strength));
	NORMAL = (VIEW_MATRIX * vec4(normal, 0.0)).xyz;

	// Глубина воды под фрагментом: линейная глубина сцены минус фрагмент
	// (стандартный сниппет разложения NDC через INV_PROJECTION_MATRIX).
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	scene_view /= scene_view.w;
	float water_depth = max(-scene_view.z - (-VERTEX.z), 0.0);
	water_depth = min(water_depth, 4.0);
	float shallow = 1.0 - smoothstep(0.0, 1.2, water_depth);

	// Цвет и прозрачность: мелководье светлее и прозрачнее (видно дно).
	vec3 albedo = mix(water_color.rgb, shallow_color.rgb, shallow * 0.6);
	float alpha = mix(water_color.a, water_color.a * 0.45, shallow);

	// Мягкое отражение неба: френель — у ног прозрачная вода, к горизонту
	// зеркальная; небо по высоте отражённого луча (горизонт → зенит).
	float facing = clamp(dot(-VIEW, NORMAL), 0.0, 1.0);
	float fresnel = 0.04 + 0.96 * pow(1.0 - facing, 4.0);
	vec3 refl_world = normalize(
		(INV_VIEW_MATRIX * vec4(reflect(VIEW, NORMAL), 0.0)).xyz);
	vec3 sky = mix(sky_horizon_color.rgb, sky_top_color.rgb,
		smoothstep(0.0, 0.6, refl_world.y));
	albedo = mix(albedo, sky,
		clamp(reflect_strength * fresnel, 0.0, 0.85));
	alpha = mix(alpha, 0.92, clamp(reflect_strength * fresnel, 0.0, 0.6));

	// Дорожка светила: глинт вдоль отражённого луча, рябь нормалей рвёт
	// сплошную полосу в блики; ближе к горизонту (френель) — заметнее.
	float glint = pow(max(dot(refl_world, normalize(sun_direction)), 0.0), 120.0);
	EMISSION = glint_color.rgb * glint * glint_strength
		* (0.35 + 0.65 * fresnel);

	// Пена: полоса у кромки (дыхание по времени, «крапинки» волной) и
	// гребни волн на мелководье — прибой без физики, но живой.
	float crest = smoothstep(0.45, 0.9,
		wave_height_at(world_pos.xz) / max(wave_height, 0.001));
	float crest_foam = crest * (1.0 - smoothstep(0.15, 0.9, water_depth)) * 0.5;
	float foam_mask = max(1.0 - smoothstep(0.04, foam_width, water_depth),
		crest_foam);
	float speckle = sin(world_pos.x * 14.0 + sin(world_pos.z * 11.0) * 4.0
		+ TIME * 1.2) * 0.5 + 0.5;
	float foam = foam_mask * (0.65 + 0.35 * speckle);
	albedo = mix(albedo, foam_color.rgb, clamp(foam, 0.0, 1.0));
	alpha = mix(alpha, foam_color.a, clamp(foam, 0.0, 1.0));

	ALBEDO = albedo;
	ALPHA = alpha;
	METALLIC = 0.02;
	ROUGHNESS = mix(0.14, 0.30, shallow);
	SPECULAR = 0.5;
}
