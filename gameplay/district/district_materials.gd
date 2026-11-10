# Материалы района (постапокалипсис): PBR-наборы Poly Haven / ambientCG
# (CC0, assets/third_party) на шейдере district_surface + простые
# материалы стекла, проёмов и швов. Кэш на процесс.
class_name DistrictMaterials
extends RefCounted

const SHADER: Shader = preload("res://assets/shaders/district_surface.gdshader")
const PH: String = "res://assets/third_party/polyhaven.com/"

static var _cache: Dictionary = {}


static func _tex(set_name: String, kind: String) -> Texture2D:
	for suffix: String in [kind, kind.replace("diffuse", "diff")]:
		var path := "%s%s/%s_%s_1k.jpg" % [PH, set_name, set_name, suffix]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	push_error("Нет текстуры %s (%s)" % [set_name, kind])
	return null


## Поверхность набора Poly Haven: размер повтора (м), тон, доля мха.
static func surface(
	set_name: String, tile_m: float = 2.0, tint: Color = Color.WHITE,
	moss: float = 0.2, moss_ground_m: float = 1.5, metal: float = 0.0,
	streaks: float = 0.0
) -> ShaderMaterial:
	var key := "%s|%.2f|%s|%.2f|%.2f|%.2f|%.2f" % [
		set_name, tile_m, tint.to_html(), moss, moss_ground_m, metal, streaks]
	if _cache.has(key):
		return _cache[key]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("albedo_tex", _tex(set_name, "diffuse"))
	material.set_shader_parameter("normal_tex", _tex(set_name, "nor_gl"))
	material.set_shader_parameter("arm_tex", _tex(set_name, "arm"))
	material.set_shader_parameter("moss_tex", _tex("concrete_moss", "diffuse"))
	material.set_shader_parameter("tile_m", tile_m)
	material.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	material.set_shader_parameter("moss_amount", moss)
	material.set_shader_parameter("moss_ground_m", moss_ground_m)
	material.set_shader_parameter("metal_mult", metal)
	material.set_shader_parameter("streak_amount", streaks)
	_cache[key] = material
	return material


static func plain(
	name: String, color: Color, roughness: float, metallic: float = 0.0,
	unshaded: bool = false
) -> StandardMaterial3D:
	if _cache.has(name):
		return _cache[name]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cache[name] = material
	return material


## Плющ на стенах: карточки листьев (текстура листа дуба ez-tree, вырез по
## альфе), двусторонние, тёмная зелень с разбросом тона по вершинам.
static func ivy_material() -> StandardMaterial3D:
	if _cache.has("district_ivy"):
		return _cache["district_ivy"]
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/visual/trees/leaves/oak_mips.res")
	material.albedo_color = Color(0.62, 0.75, 0.48)
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.8
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.backlight_enabled = true
	material.backlight = Color(0.25, 0.3, 0.12)
	_cache["district_ivy"] = material
	return material


## Набор материалов дома по ключам MeshKit. brick — кирпичные руины.
static func house_set(brick: bool = false) -> Dictionary:
	var wall: Material = surface("red_brick_03", 1.6, Color(0.78, 0.72, 0.7), 0.34, 2.5, 0.0, 0.6) \
		if brick else surface("dirty_concrete", 5.3, Color(0.86, 0.85, 0.8), 0.18, 2.5, 0.0, 0.85)
	return {
		&"wall": wall,
		&"plinth": surface("concrete_slab_wall", 2.4, Color(0.55, 0.55, 0.52), 0.5, 1.2, 0.0, 0.6),
		&"roof": surface("asphalt_02", 3.0, Color(0.42, 0.42, 0.43), 0.5, 0.0),
		&"concrete": surface("concrete_slab_wall", 2.4, Color(0.8, 0.8, 0.78), 0.25, 1.5),
		&"balcony": surface("peeling_painted_wall", 2.0, Color(0.75, 0.82, 0.85), 0.12, 0.0),
		&"metal": surface("rusty_painted_metal", 1.6, Color(0.8, 0.8, 0.8), 0.0, 0.0, 0.6),
		&"boards": surface("weathered_peeling_timber", 1.4, Color(0.85, 0.85, 0.85), 0.05, 0.0),
		&"frame": plain("district_frame", Color(0.72, 0.71, 0.66), 0.75),
		&"glass": plain("district_glass", Color(0.05, 0.055, 0.055), 0.12, 0.3),
		&"ivy": ivy_material(),
		&"void": plain("district_void", Color(0.012, 0.012, 0.014), 1.0, 0.0, true),
		&"seam": plain("district_seam", Color(0.16, 0.16, 0.16), 0.95),
	}
