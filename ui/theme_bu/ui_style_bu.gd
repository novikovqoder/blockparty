class_name UiStyleBU
extends RefCounted
## Палитра, шрифты и тема меню Born Unblessed. Все цвета меню берутся отсюда.

const BG: Color = Color("0a0405")
const TEXT: Color = Color("ede0da")
const TEXT_STRONG: Color = Color("f4e8e2")
const TEXT_SOFT: Color = Color("d2beb8")
const TEXT_MUTED: Color = Color("c2a9a3")
const TEXT_DIM: Color = Color("a8918b")
const TEXT_FAINT: Color = Color("9a8580")
const ACCENT: Color = Color("e0303c")
const ACCENT_DEEP: Color = Color("b0141f")
const ACCENT_LINE: Color = Color("d4202e")
const ACCENT_TEXT: Color = Color("f08a7e")
const BORDER: Color = Color(0.94, 0.59, 0.55, 0.35)
const HAIRLINE: Color = Color(0.93, 0.88, 0.85, 0.12)
const PANEL: Color = Color(0.047, 0.016, 0.02, 0.78)

const CORMORANT_PATH: String = "res://ui/theme_bu/fonts/Cormorant-Variable.ttf"
const MANROPE_PATH: String = "res://ui/theme_bu/fonts/Manrope-Variable.ttf"

static var _fonts: Dictionary[String, FontVariation] = {}
static var _theme: Theme = null


## Шрифт заголовков (Cormorant) нужной толщины: 500, 600 или 700.
static func display(weight: int = 700) -> FontVariation:
	return _variant(CORMORANT_PATH, weight)


## Шрифт текста (Manrope) нужной толщины: 400–800.
static func body(weight: int = 500) -> FontVariation:
	return _variant(MANROPE_PATH, weight)


## Заголовочный шрифт с разрядкой между буквами (в пикселях).
static func display_spaced(weight: int, spacing: int) -> FontVariation:
	var key: String = "spaced:%d:%d" % [weight, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var fv: FontVariation = FontVariation.new()
	fv.base_font = display(weight)
	fv.spacing_glyph = spacing
	_fonts[key] = fv
	return fv


static func _variant(path: String, weight: int) -> FontVariation:
	var key: String = "%s:%d" % [path, weight]
	if _fonts.has(key):
		return _fonts[key]
	var fv: FontVariation = FontVariation.new()
	var base: FontFile = load(path) as FontFile
	fv.base_font = base
	var wght_tag: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	fv.variation_opentype = {wght_tag: weight}
	_fonts[key] = fv
	return fv


static func flat_box(color: Color = Color(0, 0, 0, 0), border: Color = Color(0, 0, 0, 0), border_width: int = 0) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_content_margin_all(0)
	return sb


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t: Theme = Theme.new()
	t.default_font = body(500)
	t.default_font_size = 18
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	for st: String in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		t.set_stylebox(st, "Button", empty)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", ACCENT_TEXT)
	t.set_color("font_focus_color", "Button", ACCENT_TEXT)
	t.set_color("font_pressed_color", "Button", ACCENT_TEXT)
	t.set_color("font_hover_pressed_color", "Button", ACCENT_TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_FAINT)
	t.set_color("font_color", "Label", TEXT)
	# Ползунок: тонкая линия и ромб.
	var track: StyleBoxFlat = flat_box(Color(0.93, 0.88, 0.85, 0.2))
	track.content_margin_top = 1
	track.content_margin_bottom = 1
	var fill: StyleBoxFlat = flat_box(ACCENT_LINE)
	fill.content_margin_top = 1
	fill.content_margin_bottom = 1
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var grab: Texture2D = diamond_texture(14, TEXT_STRONG)
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", diamond_texture(16, ACCENT_TEXT))
	t.set_icon("grabber_disabled", "HSlider", grab)
	_theme = t
	return t


static func diamond_texture(size: int, color: Color) -> ImageTexture:
	var img: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c: float = (float(size) - 1.0) * 0.5
	for y: int in size:
		for x: int in size:
			var d: float = absf(float(x) - c) + absf(float(y) - c)
			var a: float = clampf(c + 0.5 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * a))
	return ImageTexture.create_from_image(img)


## Мягкое круглое пятно (для свечений, угольков, вспышки).
static func radial_texture(size: int = 128) -> GradientTexture2D:
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = size
	tex.height = size
	return tex


static func draw_diamond(ci: CanvasItem, center: Vector2, half: float, color: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array([
		center + Vector2(0, -half), center + Vector2(half, 0),
		center + Vector2(0, half), center + Vector2(-half, 0),
	])
	ci.draw_colored_polygon(pts, color)
