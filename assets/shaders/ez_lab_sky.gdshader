// Небо лаборатории ezTree (П18-ЛАБОРАТОРИЯ): точная копия градиента демо
// (src/app/shaders/skybox.frag) — mix(низ, верх, dir.y*0.5+0.5) и диск
// солнца pow(dot, 1000/sun_size). Цвета — пресет SkyboxOptions демо
// (0x6fa2ef / 0x2053ff / 0xffe5b0). Без облаков: наш Sky3D-купол с кучевостью
// в лаборатории не ставится — сравнивается свет, а не погода.
shader_type sky;

uniform vec3 sky_low : source_color = vec3(0.4353, 0.6353, 0.9373);
uniform vec3 sky_high : source_color = vec3(0.1255, 0.3255, 1.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.898, 0.6902);
// Направление НА солнце (мировое, нормализованное) — ставит EzLab вместе
// с DirectionalLight3D, чтобы диск висел там же, куда светит свет.
uniform vec3 sun_dir = vec3(0.0, 0.8829, 0.4695);
uniform float sun_size = 1.0;

void sky() {
	vec3 direction = normalize(EYEDIR);
	float t = direction.y * 0.5 + 0.5;
	vec3 sky_color = mix(sky_low, sky_high, t);
	float sun_intensity = pow(max(dot(direction, normalize(sun_dir)), 0.0),
		1000.0 / max(sun_size, 0.001));
	COLOR = sky_color + sun_color * sun_intensity;
}
