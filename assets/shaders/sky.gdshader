// Небо (vfx-fix, визуальный блок в): градиент суток + процедурные облака.
// Цвета top/horizon/ground и направление/цвет солнца каждый кадр задаёт
// DayCycle (та же математика DayMath — «живой градиент по времени суток»);
// здесь только картинка. Облака — четыре октавы value-шума на плоскости
// над головой (uv = направление.xz / y), медленно дрейфуют по TIME,
// подсвечены солнцем с серебристым краем к диску; у горизонта сгущаются
// перспективой. Солнце — маленький диск с мягким гало, за облаками
// прячется. Ночью облака темнеют и слабеют (цвет тоже ведёт DayCycle).
shader_type sky;

uniform vec4 top_color : source_color = vec4(0.44, 0.64, 0.85, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.74, 0.83, 0.9, 1.0);
uniform vec4 ground_color : source_color = vec4(0.30, 0.40, 0.47, 1.0);
// Направление НА солнце (нормализовано).
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.38;
// Дрейф облаков, единиц uv в секунду.
uniform float cloud_speed = 0.004;


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


float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += vnoise(p) * amp;
		p = p * 2.13 + vec2(17.7, 9.1);
		amp *= 0.5;
	}
	return sum;
}


void sky() {
	vec3 dir = EYEDIR;
	float up = clamp(dir.y, -1.0, 1.0);
	vec3 col;
	if (up >= 0.0) {
		col = mix(horizon_color.rgb, top_color.rgb, pow(up, 0.55));
	} else {
		// Под горизонтом (дно за морем) — спокойный тёмный тон.
		col = mix(horizon_color.rgb, ground_color.rgb, clamp(-up * 4.0, 0.0, 1.0));
	}

	// Облака: плоскость над головой; у самого горизонта растворяются.
	float horizon_fade = smoothstep(0.02, 0.16, up);
	vec2 uv = dir.xz / max(up, 0.06) * 0.35;
	uv += vec2(TIME * cloud_speed, TIME * cloud_speed * 0.7);
	float n = fbm(uv);
	float cover = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.42, n);
	cover *= horizon_fade * 0.9;

	// Освещение облака: мягко от высоты солнца, серебристый край к диску.
	float to_sun = clamp(dot(dir, normalize(sun_direction)), 0.0, 1.0);
	float sun_up = clamp(sun_direction.y, 0.0, 1.0);
	vec3 lit = cloud_color.rgb * (0.55 + 0.45 * sun_up);
	lit += sun_color.rgb * pow(to_sun, 8.0) * 0.3;

	// Солнце: диск с гало; сквозь облака видно ослабленно.
	float disk = smoothstep(0.9993, 0.9997, to_sun);
	float halo = pow(to_sun, 160.0) * 0.45;
	col = mix(col, lit, cover);
	col += sun_color.rgb * (halo + disk * 3.0) * (1.0 - cover);

	COLOR = vec4(col, 1.0);
}
