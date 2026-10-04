// Общий шейдер low-poly (раздел 16 SPEC): плоская нормаль на грань через
// производные позиции (dFdx/dFdy — меш может быть индексированным, вершины
// не дублируются), цвет — вершинный × instance-цвет × параметр albedo,
// мягкий двухступенчатый переход света в тень с лёгким холодным оттенком
// в полутени («мультяшный» тон без контуров). Тени приходят в ATTENUATION
// внутри light(), туман применяет движок к обычному spatial-шейдеру сам.
// Используется рельефом, предметами и мобами; персонажи-«мармеладки»
// сглаженные — обычный StandardMaterial3D.
shader_type spatial;
render_mode specular_disabled;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 emission_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 0.0;
// Оттенок теневой стороны граней.
uniform vec3 shadow_tint : source_color = vec3(0.82, 0.87, 0.98);

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
