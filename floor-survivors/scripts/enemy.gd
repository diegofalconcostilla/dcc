extends CharacterBody2D
class_name Enemy

signal died(point_value: int, death_position: Vector2)

var radius := 12.0
var speed := 70.0
var hp := 20.0
var max_hp := 20.0
var contact_damage := 8.0
var xp_value := 3.0
var point_value := 10

const DODGE_DURATION := 0.35
const DODGE_SPEED_MULTIPLIER := 1.4
const DODGE_LINE_TOLERANCE := 60.0  # how close to a laser's path counts as "in danger"

# A laser travels at 900px/s (see Laser.SPEED) with a 14px hit radius — an
# enemy starting right on the beam's line only has enough time to physically
# sidestep clear of that radius if it's >~130px along the beam's path when
# fired (dodge speed 98px/s * transit time > 14px). Since real engagements
# happen well inside that range (auto-attack range is 140px, contact damage
# triggers at ~28px), a "successful" dodge roll on a close enemy is often a
# geometrically wasted roll — the beam can outrun the sidestep. Rather than
# make enemies dodge unrealistically fast, a successful line-dodge grants a
# brief damage-immunity window instead (covers any laser's full possible
# flight time — max_range 260 / SPEED 900 ≈ 0.29s), so a "you dodged" roll
# reliably means "you don't get hit," matching what the roll is telling the
# player, regardless of how little physical space there was to react in.
const LASER_DODGE_IFRAME := 0.3

# Set by EnemySpawner: the source of the System AI's live aggression multiplier.
var spawner: EnemySpawner

var _contact_cooldown := 0.0
var _dodge_timer := 0.0
var _dodge_dir := Vector2.ZERO
var _laser_iframe_timer := 0.0

# Presentation-only state (nothing here feeds back into gameplay).
const HIT_FLASH_TIME := 0.09
var _hit_flash := 0.0
var _facing := Vector2.DOWN
var _aggression_visual := 1.0
var _spin_phase := randf() * TAU
var _tint_shift := randf_range(-0.04, 0.04)
var _spikes := PackedVector2Array()  # precomputed spike segments, rotated at draw time

func _ready() -> void:
	add_to_group("enemies")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	_build_spikes()

func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var dir: Vector2
		var aggression := spawner.get_aggression() if is_instance_valid(spawner) else 1.0
		var move_speed := speed * aggression
		if _dodge_timer > 0.0:
			_dodge_timer -= delta
			dir = _dodge_dir
			move_speed *= DODGE_SPEED_MULTIPLIER
		else:
			dir = (player.global_position - global_position).normalized()
		velocity = dir * move_speed
		move_and_slide()
		_facing = dir
		_aggression_visual = aggression
		if _laser_iframe_timer > 0.0:
			_laser_iframe_timer -= delta
		if _contact_cooldown > 0.0:
			_contact_cooldown -= delta
		elif global_position.distance_to(player.global_position) <= radius + 16.0:
			if player.has_method("take_damage"):
				var damage := contact_damage * aggression
				player.take_damage(damage)
				_contact_cooldown = 0.5
				var floor_node := get_tree().get_first_node_in_group("floor_controller")
				if floor_node and floor_node.has_method("register_damage_taken"):
					floor_node.register_damage_taken(damage)
	if _hit_flash > 0.0:
		_hit_flash -= delta
	queue_redraw()

## Short radial spikes around the body, built once per enemy (drawn as a single
## multiline each frame, so it stays cheap with a crowd on screen).
func _build_spikes() -> void:
	var count := 7
	for i in count:
		var a := TAU * float(i) / count
		_spikes.append(Vector2.from_angle(a) * (radius * 0.85))
		_spikes.append(Vector2.from_angle(a) * (radius * 1.38))

func _body_color() -> Color:
	# Healthy crimson -> scorched orange as it takes damage; each enemy gets a
	# small fixed hue shift so a crowd isn't a flat wall of one color.
	var t: float = hp / max_hp
	var c := UIStyle.HP_RED.lerp(Color8(255, 140, 50), 1.0 - t)
	c.h = fposmod(c.h + _tint_shift, 1.0)
	return c

func _draw() -> void:
	var time := Time.get_ticks_msec() / 1000.0
	var body := _body_color()
	var flashing := _hit_flash > 0.0
	if flashing:
		body = body.lerp(Color.WHITE, 0.85)

	# Ground shadow.
	draw_set_transform(Vector2(0, radius * 0.55), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, radius * 1.1, Color(0, 0, 0, 0.35))
	# Slowly spinning spikes (behind the body).
	draw_set_transform(Vector2.ZERO, _spin_phase + time * 0.9, Vector2.ONE)
	draw_multiline(_spikes, body.darkened(0.35), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Body: dark rim, fill, sheen.
	draw_circle(Vector2.ZERO, radius + 1.5, Color(0.12, 0.02, 0.04))
	draw_circle(Vector2.ZERO, radius, body)
	draw_circle(Vector2(-radius * 0.28, -radius * 0.32), radius * 0.5, body.lightened(0.22))

	# Eyes track the direction of travel and glow hotter the more aggressive
	# the System AI currently has enemies.
	var heat := clampf((_aggression_visual - 1.0) / 0.6, 0.0, 1.0)
	var eye_color := Color(1.0, 0.95, 0.75).lerp(Color(1.0, 0.25, 0.2), heat)
	var perp := Vector2(-_facing.y, _facing.x)
	var eye_center := _facing * radius * 0.35
	for side in [-1.0, 1.0]:
		var eye: Vector2 = eye_center + perp * radius * 0.36 * side
		draw_circle(eye, radius * 0.29, Color(0.1, 0.02, 0.04))
		draw_circle(eye, radius * 0.23, Color(0.98, 0.95, 0.9))
		draw_circle(eye + _facing * radius * 0.08, radius * 0.13, eye_color.darkened(0.3) if heat < 0.5 else eye_color)
	# Mid-dodge telegraph: cool ring so the player can see "that one saw it coming".
	if _dodge_timer > 0.0:
		draw_arc(Vector2.ZERO, radius + 5.0, time * 8.0, time * 8.0 + TAU * 0.75, 20, Color(UIStyle.CYAN, 0.85), 2.0)

	# Thin health pip once damaged.
	if hp < max_hp:
		var w := radius * 1.9
		var y := -radius - 9.0
		draw_rect(Rect2(-w * 0.5, y, w, 3.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-w * 0.5, y, w * clampf(hp / max_hp, 0.0, 1.0), 3.0), UIStyle.HP_RED.lightened(0.15))

func take_damage(amount: float, crit: bool = false) -> void:
	hp -= amount
	_hit_flash = HIT_FLASH_TIME
	var fx := FxLayer.of(self)
	if fx:
		var label_color := Color(1.0, 0.82, 0.25) if crit else Color(1.0, 0.96, 0.86)
		fx.float_text(global_position + Vector2(randf_range(-8.0, 8.0), -radius - 6.0), str(int(round(amount))), label_color, 20.0 if crit else 15.0, 0.7, 42.0)
		fx.sparks(global_position, Color(1.0, 0.85, 0.6), 3, 120.0, 8.0, 0.2)
	if hp <= 0.0:
		if fx:
			_death_fx(fx)
		died.emit(point_value, global_position)
		queue_free()

## Small burst in the enemy's own colors; Boss overrides for a bigger one.
func _death_fx(fx: FxLayer) -> void:
	var c := _body_color()
	fx.burst(global_position, c, 9, 170.0, 3.0, 0.5)
	fx.sparks(global_position, c.lightened(0.3), 6, 220.0, 12.0, 0.3)
	fx.ring(global_position, c.lightened(0.2), radius * 0.6, radius * 2.4, 0.3, 2.5)

func scale_difficulty(factor: float) -> void:
	hp *= factor
	max_hp = hp
	speed *= min(factor, 1.3)
	contact_damage *= factor

## Called by a just-landed Bomb on every enemy in its blast range + margin.
## Rolls `chance` (see the System AI's bomb_dodge_chance, floor.gd's
## character_profile) and, on success, flees radially away from the bomb for
## `duration` — Bomb passes its own fuse length here, not DODGE_DURATION,
## since a fixed short dodge used to end well before the bomb actually went
## off, letting enemies wander right back into the blast on their way back
## to chasing the player.
func try_dodge_point(from: Vector2, chance: float, duration: float = DODGE_DURATION) -> void:
	if _dodge_timer > 0.0 or randf() >= chance:
		return
	_dodge_dir = (global_position - from).normalized()
	if _dodge_dir == Vector2.ZERO:
		_dodge_dir = Vector2.RIGHT.rotated(randf() * TAU)
	_dodge_timer = duration
	_dodge_fx()

## Called by a just-fired Laser on every enemy, regardless of position — cheap
## to check and the laser is already gone by the time a far-away enemy would
## matter. Rolls `chance` (see the System AI's missile_dodge_chance) only if
## this enemy is actually near the laser's path, and on success sidesteps
## perpendicular to it for DODGE_DURATION — a fixed short window is fine here
## since the projectile passes in a fraction of a second either way.
func try_dodge_line(origin: Vector2, dir: Vector2, max_range: float, chance: float) -> void:
	if _dodge_timer > 0.0:
		return
	var to_enemy := global_position - origin
	var projection := to_enemy.dot(dir)
	if projection < 0.0 or projection > max_range:
		return
	var perpendicular := to_enemy - dir * projection
	if perpendicular.length() > DODGE_LINE_TOLERANCE:
		return
	if randf() >= chance:
		return
	_dodge_dir = perpendicular.normalized()
	if _dodge_dir == Vector2.ZERO:
		_dodge_dir = dir.rotated(PI / 2.0)
	_dodge_timer = DODGE_DURATION
	_laser_iframe_timer = LASER_DODGE_IFRAME
	_dodge_fx()

## True while a successful line-dodge's damage-immunity window is active (see
## LASER_DODGE_IFRAME) — checked by Laser before applying damage.
func is_dodging_laser() -> bool:
	return _laser_iframe_timer > 0.0

## "DODGED" callout — makes the System AI's counter-play visible at the moment
## it happens, not just when a bomb whiffs.
func _dodge_fx() -> void:
	var fx := FxLayer.of(self)
	if fx:
		fx.float_text(global_position + Vector2(0, -radius - 8.0), "DODGED", UIStyle.CYAN, 12.0, 0.6, 30.0)
