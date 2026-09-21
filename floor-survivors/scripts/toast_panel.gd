extends PanelContainer
class_name ToastPanel

## A message card with an accent-colored border, small caps header, optional
## bold title and wrapped body. Pops in, holds, fades. The System AI's taunts
## use the typewriter reveal so they read as being *transmitted at* the player.
## New messages replace whatever is showing (same behavior as the old label).

const CARD_WIDTH := 480.0

var _header: Label
var _title: Label
var _body: Label
var _style := UIStyle.panel_style()
var _tween: Tween

func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", _style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	add_child(box)
	_header = _make_label(11, true)
	box.add_child(_header)
	_title = _make_label(21, true)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = CARD_WIDTH
	box.add_child(_title)
	_body = _make_label(15, false)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = CARD_WIDTH
	box.add_child(_body)
	resized.connect(func() -> void: pivot_offset = size * 0.5)

func set_card_width(width: float) -> void:
	_title.custom_minimum_size.x = width
	_body.custom_minimum_size.x = width

func _make_label(font_size: int, bold: bool) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	if bold:
		label.add_theme_font_override("font", UIStyle.font(true))
	return label

## header: small caps line above; title: optional bold line; body: main text.
func pop(header: String, title: String, body: String, accent: Color, duration: float, typewriter: bool = false) -> void:
	if _tween:
		_tween.kill()
	_style.bg_color = Color(accent.darkened(0.82), 0.9)
	_style.border_color = Color(accent, 0.85)
	_style.set_border_width_all(2)
	_style.shadow_color = Color(accent, 0.22)
	_style.shadow_size = 10
	_header.text = header
	_header.visible = header != ""
	_header.add_theme_color_override("font_color", accent)
	_title.text = title
	_title.visible = title != ""
	_title.add_theme_color_override("font_color", accent.lightened(0.35))
	_body.text = body
	_body.visible = body != ""
	_title.visible_ratio = 1.0
	_body.visible_ratio = 1.0
	visible = true
	modulate.a = 0.0
	scale = Vector2(0.94, 0.94)

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, 0.15)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if typewriter:
		var target := _body if body != "" else _title
		target.visible_ratio = 0.0
		var reveal := clampf(target.text.length() * 0.022, 0.3, 1.6)
		_tween.tween_property(target, "visible_ratio", 1.0, reveal)
	_tween.set_parallel(false)  # the rest runs as sequential steps after the pop-in group
	_tween.tween_interval(maxf(0.1, duration - 0.6))
	_tween.tween_property(self, "modulate:a", 0.0, 0.4)
	_tween.tween_callback(func() -> void: visible = false)
