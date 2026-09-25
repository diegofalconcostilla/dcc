extends RefCounted
class_name UIStyle

## Single home for the game's look: palette, fonts, the shared Theme, and the
## per-floor color schemes. Everything is drawn in code (no image assets), so
## this is what keeps HUD, world art and effects reading as one game. Purely
## presentational — nothing here touches gameplay numbers.

# --- Palette -------------------------------------------------------------
# Dark, cold "Syndicate broadcast" UI; warm gold for the crawler, hot magenta-red
# for the System AI, so who-is-who is readable at a glance.
const INK := Color8(9, 10, 16)
const PANEL_BG := Color(0.043, 0.051, 0.082, 0.84)
const PANEL_BORDER := Color8(52, 60, 88)
const TEXT := Color8(233, 230, 220)
const TEXT_DIM := Color8(138, 145, 170)

const GOLD := Color8(242, 181, 58)        # Carl
const PINK := Color8(255, 130, 190)       # Donut
const SYSTEM := Color8(255, 59, 92)       # System AI
const AMBER := Color8(255, 176, 46)       # warnings, bombs
const CYAN := Color8(90, 205, 255)        # laser, ability accents
const MINT := Color8(90, 255, 170)        # XP
const HP_RED := Color8(226, 52, 78)
const BOSS_PURPLE := Color8(176, 77, 255)

const TIER_COLORS := {
	"common": Color8(184, 188, 200),
	"uncommon": Color8(94, 203, 107),
	"rare": Color8(77, 155, 255),
	"epic": Color8(181, 102, 255),
	"legendary": Color8(255, 171, 46),
}

# Presentation of the System AI's tactic names (CuratorGenerator.ALLOWED_TACTICS).
const TACTIC_LABELS := {
	"none": "OBSERVING",
	"ambush": "AMBUSH",
	"swarm": "SWARM",
	"counter_bomb": "COUNTER-BOMB",
	"counter_laser": "COUNTER-LASER",
	"aggression": "AGGRESSION",
	"early_boss": "EARLY BOSS",
}
const TACTIC_COLORS := {
	"none": Color8(138, 145, 170),
	"ambush": Color8(255, 150, 60),
	"swarm": Color8(255, 59, 92),
	"counter_bomb": Color8(255, 176, 46),
	"counter_laser": Color8(90, 205, 255),
	"aggression": Color8(255, 40, 40),
	"early_boss": Color8(190, 90, 255),
}

# --- Per-floor look --------------------------------------------------------
# Index = floor number - 1. `base` is the ground color, `accent` tints grid
# seams/motifs and the HUD floor chip. Kept dark and low-saturation so enemies,
# telegraphs and pickups always pop against the ground.
const FLOOR_LOOKS := [
	{"name": "The Welcome Mat", "base": Color(0.062, 0.070, 0.098), "accent": Color(0.42, 0.52, 0.78)},
	{"name": "Sewer Sublevel", "base": Color(0.050, 0.082, 0.066), "accent": Color(0.36, 0.78, 0.52)},
	{"name": "Rust Belt", "base": Color(0.098, 0.062, 0.050), "accent": Color(0.90, 0.52, 0.30)},
	{"name": "Fungal Annex", "base": Color(0.046, 0.082, 0.090), "accent": Color(0.30, 0.82, 0.86)},
	{"name": "The Velvet Pit", "base": Color(0.082, 0.052, 0.108), "accent": Color(0.72, 0.46, 0.96)},
	{"name": "Sulfur Springs", "base": Color(0.092, 0.090, 0.046), "accent": Color(0.92, 0.88, 0.32)},
	{"name": "Blood Bank", "base": Color(0.106, 0.044, 0.060), "accent": Color(0.96, 0.32, 0.42)},
	{"name": "Cold Storage", "base": Color(0.062, 0.090, 0.116), "accent": Color(0.58, 0.84, 1.00)},
	{"name": "The Bone Orchard", "base": Color(0.100, 0.092, 0.082), "accent": Color(0.90, 0.84, 0.70)},
	{"name": "Syndicate Penthouse", "base": Color(0.040, 0.040, 0.060), "accent": Color(1.00, 0.78, 0.30)},
]

static var _font_regular: SystemFont
static var _font_bold: SystemFont
static var _theme: Theme

static func floor_look(floor_num: int) -> Dictionary:
	return FLOOR_LOOKS[clampi(floor_num - 1, 0, FLOOR_LOOKS.size() - 1)]

static func tier_color(tier: String) -> Color:
	return TIER_COLORS.get(tier.to_lower(), TEXT)

static func tactic_label(tactic: String) -> String:
	return TACTIC_LABELS.get(tactic, tactic.replace("_", " ").to_upper())

static func tactic_color(tactic: String) -> Color:
	return TACTIC_COLORS.get(tactic, SYSTEM)

## Bahnschrift ships with Windows 10+ and has the squared, techy look we want;
## SystemFont falls back down the list (and finally to Godot's built-in font)
## on machines without it, so this never hard-fails.
static func font(bold: bool = false) -> Font:
	if _font_regular == null:
		_font_regular = SystemFont.new()
		_font_regular.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
		_font_bold = SystemFont.new()
		_font_bold.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
		_font_bold.font_weight = 700
	return _font_bold if bold else _font_regular

static func panel_style(bg: Color = PANEL_BG, border: Color = PANEL_BORDER, radius: int = 6, margin: int = 10, border_width: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	return sb

static func bar_style(color: Color, radius: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	return sb

## The shared Theme every HUD Control inherits (built once, cached).
static func build_theme() -> Theme:
	if _theme != null:
		return _theme
	var theme := Theme.new()
	theme.default_font = font(false)
	theme.default_font_size = 15
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	theme.set_constant("outline_size", "Label", 3)
	theme.set_stylebox("panel", "PanelContainer", panel_style())
	theme.set_stylebox("background", "ProgressBar", bar_style(Color(0.09, 0.10, 0.15, 0.9), 4))
	theme.set_stylebox("fill", "ProgressBar", bar_style(CYAN, 4))
	_add_menu_styles(theme)
	_theme = theme
	return theme

## Button (also used as the ON/OFF toggles) and HSlider looks for the Esc menu.
## The focus box is a bright outline so keyboard navigation is always visible.
static func _add_menu_styles(theme: Theme) -> void:
	var normal := _button_box(Color(0.09, 0.10, 0.15, 0.95), PANEL_BORDER)
	var hover := _button_box(Color(0.13, 0.15, 0.23, 0.98), CYAN.darkened(0.25))
	var pressed := _button_box(Color(0.30, 0.22, 0.06, 0.98), GOLD)
	var focus := _button_box(Color(0, 0, 0, 0), GOLD, 2)
	focus.draw_center = false
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("hover_pressed", "Button", pressed)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", GOLD.lightened(0.3))
	theme.set_color("font_hover_pressed_color", "Button", GOLD.lightened(0.5))
	theme.set_font_size("font_size", "Button", 17)

	var track := bar_style(Color(0.09, 0.10, 0.15, 0.95), 4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := bar_style(GOLD.darkened(0.15), 4)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var grabber := _dot_texture(GOLD.lightened(0.25))
	theme.set_icon("grabber", "HSlider", grabber)
	theme.set_icon("grabber_highlight", "HSlider", grabber)

static func _button_box(bg: Color, border: Color, border_width: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

static func _dot_texture(color: Color, size: int = 18) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var alpha := clampf(c + 0.5 - Vector2(x, y).distance_to(Vector2(c, c)), 0.0, 1.0)
			img.set_pixel(x, y, Color(color, alpha))
	return ImageTexture.create_from_image(img)
