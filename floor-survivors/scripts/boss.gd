extends Enemy
class_name Boss

## A much tougher enemy periodically spawned after a run of regular kills
## (see EnemySpawner._next_boss_threshold). Reuses Enemy's group, movement,
## and combat plumbing — just scaled-up stats and a distinct look.
## Placeholder multipliers pending playtesting.
const HP_MULTIPLIER := 12.0
const DAMAGE_MULTIPLIER := 2.5
const SPEED_MULTIPLIER := 0.7
const XP_MULTIPLIER := 15.0
const POINTS_MULTIPLIER := 10.0
const RADIUS_MULTIPLIER := 2.2

func _init() -> void:
	radius *= RADIUS_MULTIPLIER
	hp *= HP_MULTIPLIER
	max_hp = hp
	contact_damage *= DAMAGE_MULTIPLIER
	speed *= SPEED_MULTIPLIER
	xp_value *= XP_MULTIPLIER
	point_value = int(point_value * POINTS_MULTIPLIER)

func _ready() -> void:
	super._ready()
	add_to_group("bosses")

func _draw() -> void:
	var t: float = hp / max_hp
	draw_circle(Vector2.ZERO, radius, Color(0.55, 0.1, 0.65))
	draw_arc(Vector2.ZERO, radius + 6.0, 0.0, TAU * t, 32, Color(0.9, 0.15, 0.15), 4.0)
