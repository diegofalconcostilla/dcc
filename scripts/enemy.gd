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

var _contact_cooldown := 0.0
var _dodge_timer := 0.0
var _dodge_dir := Vector2.ZERO
var _laser_iframe_timer := 0.0

func _ready() -> void:
	add_to_group("enemies")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)

func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var dir: Vector2
		var move_speed := speed
		if _dodge_timer > 0.0:
			_dodge_timer -= delta
			dir = _dodge_dir
			move_speed *= DODGE_SPEED_MULTIPLIER
		else:
			dir = (player.global_position - global_position).normalized()
		velocity = dir * move_speed
		move_and_slide()
		if _laser_iframe_timer > 0.0:
			_laser_iframe_timer -= delta
		if _contact_cooldown > 0.0:
			_contact_cooldown -= delta
		elif global_position.distance_to(player.global_position) <= radius + 16.0:
			if player.has_method("take_damage"):
				player.take_damage(contact_damage)
				_contact_cooldown = 0.5
				var floor_node := get_tree().get_first_node_in_group("floor_controller")
				if floor_node and floor_node.has_method("register_damage_taken"):
					floor_node.register_damage_taken(contact_damage)
	queue_redraw()

func _draw() -> void:
	var t: float = hp / max_hp
	draw_circle(Vector2.ZERO, radius, Color(0.8, 0.2 + 0.4 * (1.0 - t), 0.2))

func take_damage(amount: float) -> void:
	hp -= amount
	if hp <= 0.0:
		died.emit(point_value, global_position)
		queue_free()

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

## True while a successful line-dodge's damage-immunity window is active (see
## LASER_DODGE_IFRAME) — checked by Laser before applying damage.
func is_dodging_laser() -> bool:
	return _laser_iframe_timer > 0.0
