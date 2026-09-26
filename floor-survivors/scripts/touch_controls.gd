extends CanvasLayer
class_name TouchControls

## On-screen controls for phones (added by floor.gd only on touchscreens, or
## with env DCC_TOUCH=1 for testing on a PC). Both thumbs work the same way,
## anywhere on screen; the gesture decides what a touch does:
##   - drag -> floating joystick where the thumb landed -> move
##   - press and hold still -> the laser keeps firing from Carl toward the
##     finger (slide it afterwards to follow a target)
##   - double-tap a spot -> bomb lands there
##   - pause button (top, right of center): opens the Esc menu
## History (2026-09-25): a drag-to-aim laser stick was hard to use; then a
## left-half joystick made shooting to the left awkward (the thumb was there).
## Nothing auto-aims. Player reads `active` / `move_vector` / `aim_vector` and
## gets touch_bomb() calls. Godot's mouse-from-touch emulation stays on so the
## Esc menu's buttons work by tapping; Player ignores those emulated clicks.

static var active := false
static var move_vector := Vector2.ZERO
static var aim_vector := Vector2.ZERO  # unit vector Carl -> held finger, else zero

const JOY_RADIUS := 70.0
const DRAG_PX := 20.0           # a touch that moves this far is a joystick
const HOLD_SEC := 0.12          # a touch held this long without moving is aiming
const PAUSE_RADIUS := 24.0
const TOP_DEAD_ZONE := 90.0     # HUD panels live up there; taps pass through
const DOUBLE_TAP_SEC := 0.35
const DOUBLE_TAP_PX := 70.0

var player: Player
## finger index -> {"start": Vector2, "pos": Vector2, "t": float, "mode": "pending"|"joy"|"aim"}
var _touches := {}
var _joy_finger := -1
var _aim_finger := -1
var _last_tap_pos := Vector2(-9999, -9999)
var _last_tap_time := -10.0
var _bomb_mark_pos := Vector2.ZERO  # brief ring where a bomb was ordered
var _bomb_mark := 0.0
var _canvas: Control
var _build := ""  # stamp from res://build_info.txt (tools/build_android.py), to tell builds apart

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
	if FileAccess.file_exists("res://build_info.txt"):
		_build = "build " + FileAccess.get_file_as_string("res://build_info.txt").strip_edges()

func _exit_tree() -> void:
	active = false
	move_vector = Vector2.ZERO
	aim_vector = Vector2.ZERO

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _process(delta: float) -> void:
	_bomb_mark = maxf(0.0, _bomb_mark - delta)
	visible = not get_tree().paused
	# A touch that stayed still long enough starts aiming.
	for finger in _touches:
		var t: Dictionary = _touches[finger]
		if t.mode == "pending" and _now() - t.t >= HOLD_SEC:
			_set_mode(finger, "aim")
	# Re-aim every frame: Carl and the camera move under a finger held still.
	aim_vector = Vector2.ZERO
	if _aim_finger != -1 and player != null and is_instance_valid(player):
		var to_finger := _to_world(_touches[_aim_finger].pos) - player.global_position
		if to_finger.length() > 4.0:
			aim_vector = to_finger.normalized()
	_canvas.queue_redraw()

func _size() -> Vector2:
	return _canvas.get_viewport_rect().size

func _pause_center() -> Vector2:
	return Vector2(_size().x * 0.68, 34.0)

func _to_world(screen_pos: Vector2) -> Vector2:
	return _canvas.get_viewport().get_canvas_transform().affine_inverse() * screen_pos

func _set_mode(finger: int, mode: String) -> void:
	_touches[finger].mode = mode
	if mode == "joy":
		_joy_finger = finger
	elif mode == "aim":
		_aim_finger = finger  # the newest aiming finger wins

func _input(event: InputEvent) -> void:
	if get_tree().paused or player == null or not is_instance_valid(player):
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_press(event.index, event.position)
		else:
			_on_release(event.index)
	elif event is InputEventScreenDrag and _touches.has(event.index):
		var t: Dictionary = _touches[event.index]
		t.pos = event.position
		if t.mode == "pending" and t.pos.distance_to(t.start) >= DRAG_PX:
			# A second dragging thumb while one already steers: treat it as aiming.
			_set_mode(event.index, "joy" if _joy_finger == -1 else "aim")
		if event.index == _joy_finger:
			move_vector = (t.pos - t.start).limit_length(JOY_RADIUS) / JOY_RADIUS

func _on_press(finger: int, pos: Vector2) -> void:
	if pos.distance_to(_pause_center()) <= PAUSE_RADIUS * 1.6:
		_open_pause_menu()
		return
	if pos.y < TOP_DEAD_ZONE:
		return
	var now := _now()
	if now - _last_tap_time <= DOUBLE_TAP_SEC and pos.distance_to(_last_tap_pos) <= DOUBLE_TAP_PX:
		player.touch_bomb(_to_world(pos))
		_bomb_mark_pos = pos
		_bomb_mark = 0.4
		_last_tap_time = -10.0  # a third tap starts a new pair
	else:
		_last_tap_time = now
		_last_tap_pos = pos
	_touches[finger] = {"start": pos, "pos": pos, "t": now, "mode": "pending"}

func _on_release(finger: int) -> void:
	_touches.erase(finger)
	if finger == _joy_finger:
		_joy_finger = -1
		move_vector = Vector2.ZERO
	if finger == _aim_finger:
		_aim_finger = -1
		# Hand aiming back to another finger still holding, if any.
		for other in _touches:
			if _touches[other].mode == "aim":
				_aim_finger = other

## PauseMenu listens for ui_cancel (Esc); feed it the same action.
func _open_pause_menu() -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	Input.parse_input_event(ev)

func _draw_controls() -> void:
	var ink := Color(1, 1, 1, 0.55)
	# Joystick base + knob while a thumb is steering.
	if _joy_finger != -1:
		var t: Dictionary = _touches[_joy_finger]
		var knob: Vector2 = t.start + (t.pos - t.start).limit_length(JOY_RADIUS)
		_canvas.draw_circle(t.start, JOY_RADIUS, Color(0, 0, 0, 0.25))
		_canvas.draw_arc(t.start, JOY_RADIUS, 0.0, TAU, 48, ink, 2.0)
		_canvas.draw_circle(knob, 26.0, Color(UIStyle.GOLD, 0.7))

	# Held aim point: a crosshair ring big enough to show around the fingertip.
	if _aim_finger != -1:
		var at: Vector2 = _touches[_aim_finger].pos
		var ready := player != null and is_instance_valid(player) and player.get_laser_cooldown_fraction() <= 0.0
		_canvas.draw_arc(at, 38.0, 0.0, TAU, 40, Color(UIStyle.CYAN, 0.85 if ready else 0.45), 2.5)
		for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			_canvas.draw_line(at + dir * 30.0, at + dir * 46.0, Color(UIStyle.CYAN, 0.85), 2.5)
	if _bomb_mark > 0.0:
		_canvas.draw_arc(_bomb_mark_pos, 30.0 + (0.4 - _bomb_mark) * 60.0, 0.0, TAU, 40, Color(UIStyle.AMBER, _bomb_mark * 2.0), 3.0)

	var font := ThemeDB.fallback_font
	_canvas.draw_string(font, Vector2(_size().x - 400.0, _size().y - 18.0), "drag: move    hold still: laser    double-tap: bomb",
		HORIZONTAL_ALIGNMENT_RIGHT, 380.0, 13, Color(1, 1, 1, 0.4))
	if _build != "":
		_canvas.draw_string(font, Vector2(12.0, _size().y - 10.0), _build, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.3))

	# Pause.
	var pc := _pause_center()
	_canvas.draw_circle(pc, PAUSE_RADIUS, Color(0, 0, 0, 0.45))
	_canvas.draw_arc(pc, PAUSE_RADIUS, 0.0, TAU, 32, ink, 2.0)
	_canvas.draw_rect(Rect2(pc + Vector2(-8, -9), Vector2(5, 18)), Color.WHITE)
	_canvas.draw_rect(Rect2(pc + Vector2(3, -9), Vector2(5, 18)), Color.WHITE)
