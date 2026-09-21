extends Node2D
class_name Laser

## Right-click ability prop: a traveling projectile (previously an instant
## hitscan beam), so it can be seen — and dodged — in flight instead of just
## landing immediately. Travels in a straight line and deals damage to the
## first enemy it touches, or fades out at max range. The moment it's fired,
## every enemy near its path gets one dodge roll (see Enemy.try_dodge_line),
## using the player's per-run laser-usage dodge chance (see
## Player.get_missile_dodge_chance).

const SPEED := 900.0
const HIT_RADIUS := 14.0

var damage := 12.0
var direction := Vector2.RIGHT
var max_range := 260.0
var dodge_chance := 0.0

var _traveled := 0.0
var _origin := Vector2.ZERO

func _ready() -> void:
	add_to_group("lasers")
	_origin = global_position
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("try_dodge_line"):
			enemy.try_dodge_line(_origin, direction, max_range, dodge_chance)
	var fx := FxLayer.of(self)
	if fx:
		fx.sparks(_origin + direction * 18.0, UIStyle.CYAN, 4, 200.0, 10.0, 0.18, direction, 0.9)  # muzzle flash
	queue_redraw()

func _physics_process(delta: float) -> void:
	var step := SPEED * delta
	global_position += direction * step
	_traveled += step
	var fx := FxLayer.of(self)
	if fx:
		fx.burst(global_position, Color(UIStyle.CYAN, 0.55), 1, 25.0, 2.6, 0.22)  # fading trail motes
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to(enemy.global_position) <= HIT_RADIUS:
			if enemy.has_method("is_dodging_laser") and enemy.is_dodging_laser():
				continue  # successfully dodged — beam passes through, may still hit someone else
			if enemy.has_method("take_damage"):
				enemy.take_damage(damage)
			if fx:
				fx.sparks(global_position, Color(0.75, 0.95, 1.0), 8, 260.0, 14.0, 0.25, -direction, 2.2)
				fx.flash(global_position, UIStyle.CYAN, 14.0, 0.14)
			queue_free()
			return
	if _traveled >= max_range:
		if fx:
			fx.sparks(global_position, UIStyle.CYAN, 3, 100.0, 8.0, 0.2)  # fizzle at max range
		queue_free()

func _draw() -> void:
	# Hot white core, cyan glow, and a tapering tail — readable at 900px/s.
	var back := -direction
	var pts := PackedVector2Array([Vector2.ZERO, back * 22.0, back * 58.0])
	draw_polyline_colors(pts, PackedColorArray([Color(UIStyle.CYAN, 0.35), Color(UIStyle.CYAN, 0.2), Color(UIStyle.CYAN, 0.0)]), 11.0)
	draw_polyline_colors(pts, PackedColorArray([Color(1, 1, 1, 1.0), Color(UIStyle.CYAN, 0.85), Color(UIStyle.CYAN, 0.0)]), 3.5)
	draw_circle(Vector2.ZERO, 8.0, Color(UIStyle.CYAN, 0.28))
	draw_circle(Vector2.ZERO, 4.0, Color(0.85, 0.97, 1.0))
