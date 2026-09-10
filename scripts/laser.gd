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
	queue_redraw()

func _physics_process(delta: float) -> void:
	var step := SPEED * delta
	global_position += direction * step
	_traveled += step
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to(enemy.global_position) <= HIT_RADIUS:
			if enemy.has_method("take_damage"):
				enemy.take_damage(damage)
			queue_free()
			return
	if _traveled >= max_range:
		queue_free()

func _draw() -> void:
	draw_line(Vector2.ZERO, -direction * 20.0, Color(0.4, 0.8, 1.0, 0.9), 3.0)
