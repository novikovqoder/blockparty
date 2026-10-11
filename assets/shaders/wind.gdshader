// Ветер для растительности (vfx-fix, визуальный блок б): шейдер lowpoly
// плюс вершинное покачивание. Качается только часть растения выше
// wind_weight_base (низ травы и ствол стоят на земле), амплитуда нарастает
// плавно по высоте вершины. Фаза у каждого экземпляра своя — от мировой
// позиции (MODEL_MATRIX у MultiMesh — трансформ инстанса), порывы —
// медленная волна по миру: поле не качается синхронно. Сила и частота
// задаются на тип растения материалом в IslandView (трава — мелко и часто,
// кусты — медленнее, ветви деревьев — широко и размашисто). Нормаль на
// грань считается во фрагменте по dFdx/dFdy — наклон качающейся грани
// подхватывается автоматически.
shader_type spatial;
render_mode specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 emission_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 0.0;
// Оттенок теневой стороны граней.
uniform vec3 shadow_tint : source_color = vec3(0.82, 0.87, 0.98);
// --- Ветер ---
// Амплитуда покачивания, м (на верхушке растения).
uniform float wind_amplitude = 0.05;
// Частота покачивания, Гц-подобная (рад/с в sin).
uniform float wind_freq = 1.6;
// Высоты начала и полного размаха качания, м (вес 0 → 1).
uniform float wind_weight_base = 0.0;
uniform float wind_weight_span = 0.4;
// Направление ветра в XZ (длина — доля амплитуды по каждой оси).
uniform vec2 wind_direction = vec2(0.85, 0.45);

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float weight = smoothstep(
		wind_weight_base, wind_weight_base + wind_weight_span, VERTEX.y);
	// Порывы: медленная волна по миру — качание волнами по всему полю.
	float gust = 0.55 + 0.45 * sin(world.x * 0.07 + world.z * 0.05 + TIME * 0.9);
	// Две гармоники: основной наклон + мелкая дрожь листьев.
	float phase = world.x * 0.9 + world.z * 0.7;
	vec2 sway = wind_direction * (
		sin(TIME * wind_freq + phase)
		+ 0.4 * sin(TIME * wind_freq * 2.6 + phase * 1.7));
	VERTEX.xz += sway * wind_amplitude * weight * gust;
}

void fragment() {
	NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	ALBEDO = COLOR.rgb * albedo.rgb;
	if (emission_energy > 0.0) {
		EMISSION = emission_color.rgb * emission_energy;
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// Две мягкие ступени: тень → полутень (0.35) → полный свет (1.0).
	float step1 = smoothstep(0.0, 0.35, ndl);
	float step2 = smoothstep(0.35, 0.75, ndl);
	float shade = 0.35 * step1 + 0.65 * step2;
	vec3 tinted = mix(ALBEDO * shadow_tint, ALBEDO, shade);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * tinted * shade;
}
