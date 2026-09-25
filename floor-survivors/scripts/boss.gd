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

## Horns instead of Enemy's little spikes: fewer, longer, heavier.
func _build_spikes() -> void:
	var count := 9
	for i in count:
		var a := TAU * float(i) / count
		_spikes.append(Vector2.from_angle(a) * (radius * 0.9))
		_spikes.append(Vector2.from_angle(a) * (radius * 1.6))

func _body_color() -> Color:
	return UIStyle.BOSS_PURPLE.darkened(0.35)

func _draw() -> void:
	var time := Time.get_ticks_msec() / 1000.0
	var t: float = clampf(hp / max_hp, 0.0, 1.0)
	var flashing := _hit_flash > 0.0
	var body := _body_color()
	if flashing:
		body = body.lerp(Color.WHITE, 0.8)
	var pulse := 0.5 + 0.5 * sin(time * 3.0)

	# Menacing aura + shadow.
	draw_circle(Vector2.ZERO, radius + 26.0 + 4.0 * pulse, Color(UIStyle.BOSS_PURPLE, 0.06))
	draw_circle(Vector2.ZERO, radius + 14.0 + 3.0 * pulse, Color(UIStyle.BOSS_PURPLE, 0.10))
	draw_set_transform(Vector2(0, radius * 0.6), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, radius * 1.15, Color(0, 0, 0, 0.4))
	# Health ring, starting at the top and draining clockwise.
	draw_arc(Vector2.ZERO, radius + 7.0, 0.0, TAU, 48, Color(0, 0, 0, 0.55), 5.0)
	draw_arc(Vector2.ZERO, radius + 7.0, -PI / 2.0, -PI / 2.0 + TAU * t, 48, Color(0.95, 0.2, 0.3), 4.0)
	if _uses_sprite():
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var heat := clampf((_aggression_visual - 1.0) / 0.6, 0.0, 1.0)
		_draw_sprite(flashing, heat, radius * SPRITE_HEIGHT_RADII)
		if _dodge_timer > 0.0:
			draw_arc(Vector2.ZERO, radius + 10.0, time * 8.0, time * 8.0 + TAU * 0.75, 28, Color(UIStyle.CYAN, 0.85), 3.0)
		return

	# Slow-turning horns (over the ring).
	draw_set_transform(Vector2.ZERO, time * 0.35, Vector2.ONE)
	draw_multiline(_spikes, Color(0.08, 0.02, 0.1), 9.0)
	draw_multiline(_spikes, Color(0.55, 0.2, 0.7), 5.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Body: rim, fill, layered shading.
	draw_circle(Vector2.ZERO, radius + 2.5, Color(0.08, 0.02, 0.1))
	draw_circle(Vector2.ZERO, radius, body)
	draw_circle(Vector2(0, radius * 0.12), radius * 0.72, body.darkened(0.25))
	draw_circle(Vector2(-radius * 0.3, -radius * 0.36), radius * 0.42, body.lightened(0.18))

	# Two burning eyes with slit pupils.
	var perp := Vector2(-_facing.y, _facing.x)
	var eye_center := _facing * radius * 0.32
	for side in [-1.0, 1.0]:
		var eye: Vector2 = eye_center + perp * radius * 0.38 * side
		draw_circle(eye, radius * 0.34, Color(1.0, 0.2, 0.2, 0.22 + 0.12 * pulse))
		draw_circle(eye, radius * 0.22, Color(1.0, 0.85, 0.3))
		draw_circle(eye, radius * 0.12, Color(0.9, 0.1, 0.1))
	if _dodge_timer > 0.0:
		draw_arc(Vector2.ZERO, radius + 10.0, time * 8.0, time * 8.0 + TAU * 0.75, 28, Color(UIStyle.CYAN, 0.85), 3.0)

func _death_fx(fx: FxLayer) -> void:
	fx.burst(global_position, UIStyle.BOSS_PURPLE, 30, 300.0, 4.5, 0.9)
	fx.burst(global_position, Color(1.0, 0.85, 0.4), 14, 220.0, 3.0, 0.7)
	fx.sparks(global_position, Color(1.0, 0.5, 0.6), 18, 380.0, 22.0, 0.5)
	fx.flash(global_position, Color(1.0, 0.9, 0.9), radius * 2.5, 0.25)
	fx.ring(global_position, UIStyle.BOSS_PURPLE.lightened(0.3), radius, radius * 5.0, 0.7, 5.0)
	fx.ring(global_position, Color(1.0, 0.85, 0.5), radius * 0.5, radius * 3.2, 0.5, 3.0)
	fx.shake(7.0)
