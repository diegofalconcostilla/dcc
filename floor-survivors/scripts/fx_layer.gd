extends Node2D
class_name FxLayer

## One node that owns every short-lived world-space effect (death bursts,
## sparks, shockwave rings, floating damage numbers) plus screen shake. A single
## `_draw()` walks a pooled list instead of spawning a node per particle, so the
## cost stays flat no matter how many enemies die at once. Purely visual —
## gameplay code only ever *calls* into this, it never reads from it.

enum Kind { DOT, SPARK, RING, FLASH, TEXT }

const MAX_FX := 480

class Fx:
	var kind := Kind.DOT
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var color := Color.WHITE
	var life := 0.0
	var max_life := 1.0
	var size := 2.0        # dot radius / spark length / ring start radius / font size
	var size_end := 0.0    # ring end radius
	var width := 2.0
	var drag := 0.0
	var text := ""

var _live: Array[Fx] = []
var _pool: Array[Fx] = []
var _shake := 0.0
var _shake_active := false

static var _instance: FxLayer

## The active layer for whatever scene `node` is in, or null (e.g. headless
## tests with no floor). Cached, re-looked-up if the scene was reloaded.
static func of(node: Node) -> FxLayer:
	if not is_instance_valid(_instance):
		_instance = node.get_tree().get_first_node_in_group("fx_layer") as FxLayer
	return _instance

func _ready() -> void:
	add_to_group("fx_layer")
	z_index = 20  # above enemies, bombs, pickups
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep animating under the end-of-floor pause

func _process(delta: float) -> void:
	_update_shake(delta)
	if _live.is_empty():
		return
	var i := _live.size() - 1
	while i >= 0:
		var fx := _live[i]
		fx.life -= delta
		if fx.life <= 0.0:
			_live[i] = _live[_live.size() - 1]
			_live.pop_back()
			_pool.append(fx)
		else:
			fx.pos += fx.vel * delta
			if fx.drag > 0.0:
				fx.vel *= maxf(0.0, 1.0 - fx.drag * delta)
		i -= 1
	queue_redraw()

func _draw() -> void:
	var font := UIStyle.font(true)
	for fx in _live:
		var t := 1.0 - fx.life / fx.max_life  # 0 at birth -> 1 at death
		var fade := 1.0 - t
		match fx.kind:
			Kind.DOT:
				draw_circle(fx.pos, fx.size * (1.0 - 0.6 * t), Color(fx.color.r, fx.color.g, fx.color.b, fx.color.a * fade))
			Kind.SPARK:
				var dir := fx.vel.normalized()
				draw_line(fx.pos, fx.pos - dir * fx.size * fade, Color(fx.color.r, fx.color.g, fx.color.b, fx.color.a * fade), fx.width)
			Kind.RING:
				var r := lerpf(fx.size, fx.size_end, 1.0 - fade * fade)  # ease-out
				draw_arc(fx.pos, r, 0.0, TAU, 40, Color(fx.color.r, fx.color.g, fx.color.b, fx.color.a * fade), maxf(1.0, fx.width * fade))
			Kind.FLASH:
				draw_circle(fx.pos, fx.size * (0.6 + 0.4 * t), Color(fx.color.r, fx.color.g, fx.color.b, fx.color.a * fade * fade))
			Kind.TEXT:
				var size := int(fx.size) + (3 if t < 0.12 else 0)  # tiny pop on spawn
				var col := Color(fx.color.r, fx.color.g, fx.color.b, fx.color.a * minf(1.0, fade * 2.0))
				draw_string_outline(font, fx.pos, fx.text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, size, 4, Color(0, 0, 0, col.a * 0.9))
				draw_string(font, fx.pos, fx.text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, size, col)

func _acquire() -> Fx:
	if _live.size() >= MAX_FX:
		return null  # cheap safety valve: under extreme load, drop new eye candy
	var fx: Fx = _pool.pop_back() if not _pool.is_empty() else Fx.new()
	_live.append(fx)
	return fx

## Radial puff of round particles — deaths, pickups.
func burst(pos: Vector2, color: Color, count: int, speed: float, size: float = 2.6, life: float = 0.45) -> void:
	for i in count:
		var fx := _acquire()
		if fx == null:
			return
		fx.kind = Kind.DOT
		fx.pos = pos
		fx.vel = Vector2.from_angle(randf() * TAU) * speed * randf_range(0.35, 1.0)
		fx.color = color
		fx.size = size * randf_range(0.7, 1.2)
		fx.max_life = life * randf_range(0.7, 1.15)
		fx.life = fx.max_life
		fx.drag = 3.0

## Streaks flying outward — hit sparks, explosions.
func sparks(pos: Vector2, color: Color, count: int, speed: float, length: float = 12.0, life: float = 0.28, dir: Vector2 = Vector2.ZERO, spread: float = TAU) -> void:
	var base := dir.angle() if dir != Vector2.ZERO else 0.0
	for i in count:
		var fx := _acquire()
		if fx == null:
			return
		fx.kind = Kind.SPARK
		fx.pos = pos
		var angle := base + randf_range(-spread * 0.5, spread * 0.5)
		fx.vel = Vector2.from_angle(angle) * speed * randf_range(0.5, 1.0)
		fx.color = color
		fx.size = length * randf_range(0.6, 1.0)
		fx.width = 2.0
		fx.max_life = life * randf_range(0.7, 1.1)
		fx.life = fx.max_life
		fx.drag = 4.0

## Expanding shockwave outline.
func ring(pos: Vector2, color: Color, from_radius: float, to_radius: float, life: float = 0.35, width: float = 3.0) -> void:
	var fx := _acquire()
	if fx == null:
		return
	fx.kind = Kind.RING
	fx.pos = pos
	fx.vel = Vector2.ZERO
	fx.color = color
	fx.size = from_radius
	fx.size_end = to_radius
	fx.width = width
	fx.max_life = life
	fx.life = life
	fx.drag = 0.0

## Soft filled flash — the "pop" at the center of an explosion.
func flash(pos: Vector2, color: Color, radius: float, life: float = 0.18) -> void:
	var fx := _acquire()
	if fx == null:
		return
	fx.kind = Kind.FLASH
	fx.pos = pos
	fx.vel = Vector2.ZERO
	fx.color = color
	fx.size = radius
	fx.max_life = life
	fx.life = life
	fx.drag = 0.0

## Rising, fading number/label (damage numbers, "DODGED").
func float_text(pos: Vector2, text: String, color: Color, size: float = 16.0, life: float = 0.7, rise: float = 40.0) -> void:
	var fx := _acquire()
	if fx == null:
		return
	fx.kind = Kind.TEXT
	fx.pos = pos
	fx.vel = Vector2(randf_range(-8.0, 8.0), -rise)
	fx.color = color
	fx.size = size
	fx.text = text
	fx.max_life = life
	fx.life = life
	fx.drag = 1.6

## Adds camera shake (pixels of offset, decays quickly). Takes the max of the
## current and requested strength so overlapping hits don't stack into chaos.
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount * UIStyle.SHAKE_SCALE)

func _update_shake(delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	if _shake > 0.05:
		camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
		_shake = maxf(0.0, _shake - (6.0 + _shake * 4.0) * delta)
		_shake_active = true
	elif _shake_active:
		camera.offset = Vector2.ZERO
		_shake_active = false
