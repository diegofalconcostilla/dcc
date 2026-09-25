extends CanvasLayer
class_name TouchControls

## On-screen controls for phones (added by floor.gd only on touchscreens, or
## with env DCC_TOUCH=1 for testing on a PC):
##   - left thumb: floating joystick (touch anywhere on the left, drag) -> move
##   - right thumb: drag -> aim stick, fires the laser that way while held;
##     a quick tap (no drag) -> bomb lands on the tapped spot
##   - pause button (top, right of center): opens the Esc menu
## Nothing auto-aims: every shot goes where the player points. Player reads
## `active` / `move_vector` / `aim_vector` and gets touch_bomb() calls. Godot's mouse-from-touch emulation stays on so the Esc menu's
## buttons work by tapping; Player ignores the emulated clicks while active.

static var active := false
static var move_vector := Vector2.ZERO
static var aim_vector := Vector2.ZERO  # unit vector while the right thumb is aiming, else zero

const JOY_RADIUS := 70.0
const JOY_ZONE := 0.42        # left share of the screen that starts the joystick
const AIM_RADIUS := 60.0
const AIM_DEADZONE := 18.0   # px of drag before a right-thumb touch counts as aiming
const TAP_MAX_SEC := 0.3     # a right-thumb touch released sooner, undragged, is a bomb tap
const PAUSE_RADIUS := 24.0
const TOP_DEAD_ZONE := 90.0   # HUD panels live up there; taps pass through

var player: Player
var _joy_finger := -1
var _joy_origin := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _aim_finger := -1
var _aim_origin := Vector2.ZERO
var _aim_knob := Vector2.ZERO
var _aim_dragged := false
var _aim_pressed_at := 0.0
var _canvas: Control

static func wanted() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") \
		or OS.get_environment("DCC_TOUCH") == "1"

func _ready() -> void:
	layer = 50
	active = true
	move_vector = Vector2.ZERO
	aim_vector = Vector2.ZERO
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)

func _exit_tree() -> void:
	active = false
	move_vector = Vector2.ZERO
	aim_vector = Vector2.ZERO

func _process(delta: float) -> void:
	visible = not get_tree().paused
	_canvas.queue_redraw()

func _size() -> Vector2:
	return _canvas.get_viewport_rect().size

func _pause_center() -> Vector2:
	return Vector2(_size().x * 0.68, 34.0)

func _input(event: InputEvent) -> void:
	if get_tree().paused or player == null or not is_instance_valid(player):
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_press(event.index, event.position)
		elif event.index == _joy_finger:
			_joy_finger = -1
			move_vector = Vector2.ZERO
		elif event.index == _aim_finger:
			var quick := Time.get_ticks_msec() / 1000.0 - _aim_pressed_at <= TAP_MAX_SEC
			if not _aim_dragged and quick:
				# Screen -> world through the camera, then the same bomb as a mouse click.
				player.touch_bomb(_canvas.get_viewport().get_canvas_transform().affine_inverse() * _aim_origin)
			_aim_finger = -1
			aim_vector = Vector2.ZERO
	elif event is InputEventScreenDrag:
		if event.index == _joy_finger:
			var offset: Vector2 = (event.position - _joy_origin).limit_length(JOY_RADIUS)
			_joy_knob = _joy_origin + offset
			move_vector = offset / JOY_RADIUS
		elif event.index == _aim_finger:
			var aim: Vector2 = event.position - _aim_origin
			_aim_knob = _aim_origin + aim.limit_length(AIM_RADIUS)
			if aim.length() >= AIM_DEADZONE:
				_aim_dragged = true
				aim_vector = aim.normalized()

func _on_press(finger: int, pos: Vector2) -> void:
	if pos.distance_to(_pause_center()) <= PAUSE_RADIUS * 1.6:
		_open_pause_menu()
	elif pos.y < TOP_DEAD_ZONE:
		return
	elif pos.x < _size().x * JOY_ZONE:
		if _joy_finger == -1:
			_joy_finger = finger
			_joy_origin = pos
			_joy_knob = pos
	elif _aim_finger == -1:
		_aim_finger = finger
		_aim_origin = pos
		_aim_knob = pos
		_aim_dragged = false
		_aim_pressed_at = Time.get_ticks_msec() / 1000.0

## PauseMenu listens for ui_cancel (Esc); feed it the same action.
func _open_pause_menu() -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	Input.parse_input_event(ev)

func _draw_controls() -> void:
	var ink := Color(1, 1, 1, 0.55)
	var faint := Color(1, 1, 1, 0.14)
	# Joystick: a resting hint when idle, base + knob while held.
	if _joy_finger == -1:
		var hint := Vector2(130.0, _size().y - 130.0)
		_canvas.draw_arc(hint, JOY_RADIUS, 0.0, TAU, 48, faint, 2.0)
		_canvas.draw_circle(hint, 22.0, faint)
	else:
		_canvas.draw_circle(_joy_origin, JOY_RADIUS, Color(0, 0, 0, 0.25))
		_canvas.draw_arc(_joy_origin, JOY_RADIUS, 0.0, TAU, 48, ink, 2.0)
		_canvas.draw_circle(_joy_knob, 26.0, Color(UIStyle.GOLD, 0.7))

	# Right thumb: aim stick while dragging (laser color, cooldown wipe on the knob).
	var laser_ready := player != null and is_instance_valid(player) and player.get_laser_cooldown_fraction() <= 0.0
	if _aim_finger != -1 and _aim_dragged:
		_canvas.draw_circle(_aim_origin, AIM_RADIUS, Color(0, 0, 0, 0.25))
		_canvas.draw_arc(_aim_origin, AIM_RADIUS, 0.0, TAU, 48, Color(UIStyle.CYAN, 0.8), 2.0)
		_canvas.draw_circle(_aim_knob, 24.0, Color(UIStyle.CYAN, 0.75 if laser_ready else 0.35))
	else:
		var hint := Vector2(_size().x - 130.0, _size().y - 130.0)
		_canvas.draw_arc(hint, AIM_RADIUS, 0.0, TAU, 48, Color(UIStyle.CYAN, 0.16), 2.0)
		_canvas.draw_circle(hint, 20.0, Color(UIStyle.CYAN, 0.12))
	var font := ThemeDB.fallback_font
	_canvas.draw_string(font, Vector2(_size().x - 290.0, _size().y - 18.0), "drag: laser    tap: bomb", HORIZONTAL_ALIGNMENT_RIGHT, 270.0, 13, Color(1, 1, 1, 0.4))

	# Pause.
	var pc := _pause_center()
	_canvas.draw_circle(pc, PAUSE_RADIUS, Color(0, 0, 0, 0.45))
	_canvas.draw_arc(pc, PAUSE_RADIUS, 0.0, TAU, 32, ink, 2.0)
	_canvas.draw_rect(Rect2(pc + Vector2(-8, -9), Vector2(5, 18)), Color.WHITE)
	_canvas.draw_rect(Rect2(pc + Vector2(3, -9), Vector2(5, 18)), Color.WHITE)
