// Рельеф острова вне сектора Леса (П5.13, блок 3): Terrain3D с шейдером
// поверх color-карты. Вершинная часть — облегчённый шейдер Terrain3D
// v1.0.2 (addons/terrain_3d/extras/shaders/lightweight.gdshader, MIT,
// © Cory Petkovsek, Roope Palmroos и контрибьюторы): клипмап-вершины,
// геоморфинг LOD, дырки из control-карты, сглаженные нормали из карты
// высот. Фрагментная часть — наша: цвет из запечённой color-карты
// (terrain.gd point_color: песок/трава/камень/снег по высоте и уклону,
// тон зоны, террасы) × макро-вариация пятнами (~7 м и ~1.6 м) — крупные
// цветовые пятна полуреализма без фототекстур.
// Лес (x < 0, z < 0) рендерят прежние чанки с ForestGround — там
// control-карта ставит дырки, эти вершины получают NaN и отсекаются.
shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx,skip_vertex_transform;

// Defined Constants (Terrain3D)
#define SKIP_PASS 0
#define VERTEX_PASS 1
#define FRAGMENT_PASS 2

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	#define fma(a, b, c) ((a) * (b) + (c))
	#define dFdxCoarse(a) dFdx(a)
	#define dFdyCoarse(a) dFdy(a)
#endif

// Private uniforms (Terrain3D)
uniform vec3 _camera_pos = vec3(0.f);
uniform float _mesh_size = 48.f;
uniform uint _background_mode = 0u; // NONE: за пределами регионов — пустота
uniform uint _mouse_layer = 0x80000000u;
uniform float _vertex_spacing = 1.0;
uniform float _vertex_density = 1.0;
uniform float _region_size = 1024.0;
uniform float _region_texel_size = 0.0009765625; // = 1./_region_size
uniform int _region_map_size = 32;
uniform int _region_map[1024];
uniform vec2 _region_locations[1024];
uniform highp sampler2DArray _height_maps : repeat_disable;
uniform highp sampler2DArray _control_maps : repeat_disable;
uniform highp sampler2DArray _color_maps : source_color, filter_linear_mipmap, repeat_disable;

// Public uniforms
uniform bool flat_terrain_normals = false;
// Макро-вариация: два пятна шума, амплитуда в долях цвета.
uniform float macro_scale : hint_range(0.5, 32.0) = 7.0;
uniform float macro_detail_scale : hint_range(0.25, 8.0) = 1.6;
uniform float macro_strength : hint_range(0.0, 0.3) = 0.09;
// Гашение вариации у мировых осей x = 0 / z = 0 (П5.13, блок 4, планка Ж:
// бесшовность): у кромки Леса ForestGround печатает в border_map точный
// point_color соседей — вариация здесь давала бы цветовой скачок на стыке;
// на стыке узлов East/West вариация непрерывна по мировым координатам,
// но гасится синхронно с обеих сторон — обе стороны сходятся к одному
// запечённому цвету.
const float EDGE_FADE_M = 6.0;
// Шероховатость земли: матовая, блики только у кромки воды (вода — свой шейдер).
uniform float ground_roughness : hint_range(0.5, 1.0) = 0.96;

// Varyings
varying vec3 v_normal;
varying vec3 v_vertex;
varying mat3 TBN;


////////////////////////
// Vertex (Terrain3D)
////////////////////////

// Takes in world space XZ (UV) coordinates & search depth (only applicable for background mode none)
// Returns ivec3 with:
// XY: (0 to _region_size - 1) coordinates within a region
// Z: layer index used for texturearrays, -1 if not in a region
// Параметр переименован (uv → coord): идентификатор uv конфликтует
// со встроенным UV в Godot 4.7 (в апстрим-шейдере — uv).
ivec3 get_index_coord(const vec2 coord, const int search) {
	vec2 r_uv = round(coord);
	vec2 o_uv = mod(r_uv,_region_size);
	ivec2 pos;
	int bounds, layer_index = -1;
	for (int i = -1; i < clamp(search, SKIP_PASS, FRAGMENT_PASS); i++) {
		if ((layer_index == -1 && _background_mode == 0u ) || i < 0) {
			r_uv -= i == -1 ? vec2(0.0) : vec2(float(o_uv.x <= o_uv.y), float(o_uv.y <= o_uv.x));
			pos = ivec2(floor((r_uv) * _region_texel_size)) + (_region_map_size / 2);
			bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
			layer_index = (_region_map[ pos.y * _region_map_size + pos.x ] * bounds - 1);
		}
	}
	return ivec3(ivec2(mod(r_uv,_region_size)), layer_index);
}

// Takes in descaled (world_space / region_size) world to region space XZ (UV2) coordinates, returns vec3 with:
// XY: (0. to 1.) coordinates within a region
// Z: layer index used for texturearrays, -1 if not in a region
vec3 get_index_uv(const vec2 uv2) {
	ivec2 pos = ivec2(floor(uv2)) + (_region_map_size / 2);
	int bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
	int layer_index = _region_map[ pos.y * _region_map_size + pos.x ] * bounds - 1;
	return vec3(uv2 - _region_locations[layer_index], float(layer_index));
}

void vertex() {
	// Get vertex of flat plane in world coordinates and set world UV
	v_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Camera distance to vertex on flat plane
	float v_vertex_xz_dist = length(v_vertex.xz - _camera_pos.xz);

	// Geomorph vertex, set end and start for linear height interpolate
	float scale = MODEL_MATRIX[0][0];
	float vertex_lerp = smoothstep(0.55, 0.95, (v_vertex_xz_dist / scale - _mesh_size - 4.0) / (_mesh_size - 2.0));
	vec2 v_fract = fract(VERTEX.xz * 0.5) * 2.0;
	// For LOD0 morph from a regular grid to an alternating grid to align with LOD1+
	vec2 shift = (scale < _vertex_spacing + 1e-6) ? // LOD0 or not
		// Shift from regular to symetric
		mix(v_fract, vec2(v_fract.x, -v_fract.y),
			round(fract(round(mod(v_vertex.z * _vertex_density, 4.0)) *
			round(mod(v_vertex.x * _vertex_density, 4.0)) * 0.25))
			) :
		// Symetric shift
		v_fract * round((fract(v_vertex.xz * 0.25 / scale) - 0.5) * 4.0);
	vec2 start_pos = v_vertex.xz * _vertex_density;
	vec2 end_pos = (v_vertex.xz - shift * scale) * _vertex_density;
	v_vertex.xz -= shift * scale * vertex_lerp;

	// UV coordinates in world space. Values are 0 to _region_size within regions
	UV = v_vertex.xz * _vertex_density;

	// UV coordinates in region space + texel offset. Values are 0 to 1 within regions
	UV2 = fma(UV, vec2(_region_texel_size), vec2(0.5 * _region_texel_size));

	// Discard vertices for Holes. 1 lookup
	ivec3 v_region = get_index_coord(start_pos, VERTEX_PASS);
	uint control = floatBitsToUint(texelFetch(_control_maps, v_region, 0)).r;
	bool hole = bool(control >> 2u & 0x1u);

	// Show holes to all cameras except mouse camera (on exactly 1 layer)
	if ( !(CAMERA_VISIBLE_LAYERS == _mouse_layer) &&
			(hole || (_background_mode == 0u && v_region.z == -1))) {
		v_vertex.x = 0. / 0.;
	} else {
		// Set final vertex height & calculate vertex normals. 3 lookups
		ivec3 uv_a = get_index_coord(start_pos, VERTEX_PASS);
		ivec3 uv_b = get_index_coord(end_pos, VERTEX_PASS);
		float h = mix(texelFetch(_height_maps, uv_a, 0).r,texelFetch(_height_maps, uv_b, 0).r,vertex_lerp);
		v_vertex.y = h;

		// Vertex normals
		float u = mix(texelFetch(_height_maps, get_index_coord(start_pos + vec2(1,0), VERTEX_PASS), 0).r,
			texelFetch(_height_maps, get_index_coord(end_pos + vec2(1,0), VERTEX_PASS), 0).r, vertex_lerp);
		float v = mix(texelFetch(_height_maps, get_index_coord(start_pos + vec2(0,1), VERTEX_PASS), 0).r,
			texelFetch(_height_maps, get_index_coord(end_pos + vec2(0,1), VERTEX_PASS), 0).r, vertex_lerp);

		v_normal = normalize(vec3(h - u, _vertex_spacing, h - v));
	}

	// Convert model space to view space w/ skip_vertex_transform render mode
	VERTEX = (VIEW_MATRIX * vec4(v_vertex, 1.0)).xyz;

	// Apply terrain normals
	vec3 w_tangent = normalize(cross(v_normal, vec3(0.0, 0.0, 1.0)));
	vec3 w_binormal = normalize(cross(v_normal, w_tangent));
	TBN = mat3(w_tangent, w_binormal, v_normal);

	NORMAL = normalize((VIEW_MATRIX * vec4(v_normal, 0.0)).xyz);
	BINORMAL = normalize((VIEW_MATRIX * vec4(w_binormal, 0.0)).xyz);
	TANGENT = normalize((VIEW_MATRIX * vec4(w_tangent, 0.0)).xyz);
}


////////////////////////
// Fragment (наш)
////////////////////////

// Хэш и value-noise: детерминированные цветовые пятна без текстур.
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	// Конвенция Terrain3D (lightweight/minimum): fragment() обязан объявлять
	// локальную `uv` — Terrain3DMaterial инжектит в override-шейдер код
	// градиентов mip-выборок, ссылающийся на этот идентификатор. Без него
	// Godot 4.7.2 падает с «Unknown identifier in expression: 'uv'».
	vec2 uv = UV;
	vec2 uv2 = UV2;
	vec3 region_uv = get_index_uv(uv2);
	vec4 base = region_uv.z > -1.0
		? texture(_color_maps, region_uv) : vec4(1.0);

	// Макро-вариация: крупные пятна + мелкая деталь, вокруг единицы.
	// uv = мировые координаты вершины (vertex_spacing = 1 м).
	float macro = value_noise(uv / macro_scale) - 0.5;
	float detail = value_noise(uv / macro_detail_scale) - 0.5;
	float variation = (macro * 0.7 + detail * 0.3) * 2.0 * macro_strength;
	// Кромки доменов (планка Ж): вариация гаснет у осей x = 0 / z = 0 —
	// кромка Леса и стык узлов сходятся к точному цвету color-карты.
	variation *= smoothstep(0.0, EDGE_FADE_M, min(abs(uv.x), abs(uv.y)));

	// Плоские нормали (для стилизации) не используются: сглаженные
	// нормали рельефа уже в NORMAL от вершинного прохода.
	ALBEDO = base.rgb * (1.0 + variation);
	ROUGHNESS = ground_roughness;
	SPECULAR = 0.03;
}
