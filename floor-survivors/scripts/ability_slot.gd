extends Control
class_name AbilitySlot

## One HUD ability button (bomb / laser): icon, mouse-button label and a
## cooldown wipe that drains downward, with a brief flash when it comes ready.
## Display only — the cooldown fraction is pushed in by the HUD.

var kind := "bomb"
var key_text := "LMB"
var accent := UIStyle.AMBER

var _cooldown := 0.0
var _ready_flash := 0.0
var _style := StyleBoxFlat.new()

func _init() -> void:
	custom_minimum_size = Vector2(62, 58)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style.set_corner_radius_all(6)
	_style.set_border_width_all(2)

func set_cooldown(fraction: float) -> void:
	if is_equal_approx(fraction, _cooldown):
		return
	if _cooldown > 0.0 and fraction <= 0.0:
		_ready_flash = 1.0
	_cooldown = fraction
	queue_redraw()

func _process(delta: float) -> void:
	if _ready_flash > 0.0:
		_ready_flash = maxf(0.0, _ready_flash - delta * 4.0)
		queue_redraw()

func _draw() -> void:
	var is_ready := _cooldown <= 0.0
	var rect := Rect2(Vector2.ZERO, size)
	_style.bg_color = UIStyle.PANEL_BG
	_style.border_color = accent if is_ready else UIStyle.PANEL_BORDER
	draw_style_box(_style, rect)

	# Icon, centered in the upper part of the slot.
	var c := Vector2(size.x * 0.5, size.y * 0.42)
	var a := 1.0 if is_ready else 0.5
	if kind == "bomb":
		draw_circle(c + Vector2(0, 2), 10.0, Color(0.05, 0.05, 0.07, a))
		draw_circle(c + Vector2(0, 2), 8.2, Color(0.28, 0.28, 0.36, a))
		draw_circle(c + Vector2(-2.5, -0.5), 2.6, Color(0.7, 0.7, 0.8, a))
		draw_line(c + Vector2(4, -6), c + Vector2(8, -12), Color(0.75, 0.6, 0.35, a), 2.0)
		draw_circle(c + Vector2(8.5, -12.5), 3.0, Color(accent, a))
	else:
		draw_line(c + Vector2(-10, 9), c + Vector2(10, -9), Color(accent, 0.3 * a), 8.0)
		draw_line(c + Vector2(-10, 9), c + Vector2(10, -9), Color(1, 1, 1, a), 2.5)
		draw_circle(c + Vector2(10, -9), 3.5, Color(accent, a))

	# Cooldown wipe: drains from the top down to nothing.
	if _cooldown > 0.0:
		draw_rect(Rect2(3, 3, size.x - 6, (size.y - 6) * _cooldown), Color(0, 0, 0, 0.62))
	if _ready_flash > 0.0:
		draw_rect(rect, Color(accent, 0.35 * _ready_flash))

	draw_string(UIStyle.font(true), Vector2(0, size.y - 6), key_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color(UIStyle.TEXT, 0.9 if is_ready else 0.5))
