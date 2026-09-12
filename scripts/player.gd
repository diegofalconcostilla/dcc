extends CharacterBody2D
class_name Player

signal died
signal xp_changed(current: float, needed: float)
signal hp_changed(current: float, max_hp: float)
signal leveled_up(level: int)

const SPEED := 220.0
const RADIUS := 16.0

const BASE_ATTACK_COOLDOWN := 0.6
const BASE_ATTACK_RANGE := 140.0
const MIN_COOLDOWN := 0.08

# Left-click: bomb thrown at the cursor, landing instantly but not exploding
# until its fuse runs out (see Bomb) — damages everything within its radius.
# Right-click: a laser bolt fired toward the cursor as an actual traveling
# projectile (see Laser), not an instant hit. Both telegraphed on purpose so
# enemies get a chance to dodge (see Enemy.try_dodge_point/try_dodge_line) —
# placeholders pending playtesting.
const BOMB_COOLDOWN := 1.2
const BOMB_RADIUS := 60.0
const BOMB_DAMAGE := 20.0
const BOMB_MAX_RANGE := 220.0

const MISSILE_COOLDOWN := 0.5
const MISSILE_DAMAGE := 12.0
const MISSILE_RANGE := 260.0

# Flat per-level stat bumps applied automatically on level-up (no player
# choice — see apply_level_up_bonus). Placeholder values pending playtesting.
const LEVEL_UP_DAMAGE_BONUS := 1.5
const LEVEL_UP_RANGE_BONUS := 6.0
const LEVEL_UP_COOLDOWN_REDUCTION := 0.03
const LEVEL_UP_MAX_HP_BONUS := 8.0
const MIN_COOLDOWN_MULTIPLIER := 0.3

# XP threshold growth per level: xp_to_next = xp_to_next * XP_GROWTH_MULT +
# XP_GROWTH_ADD (2026-09-11, simulation-tuned — see plan.md's XP curve
# tuning notes). The original 1.25x/+5 growth compounded faster than the
# player's own kill throughput could keep up with: a Monte Carlo simulation
# of the actual combat/level math showed level-ups collapsing from 5/floor on
# floor 1 to exactly 1/floor (sometimes 0) by floor 4 onward — meaning the
# only non-loot source of player power growth stalled for most of a 10-floor
# run while enemies keep scaling up regardless. These gentler constants keep
# at least ~1 level-up every floor throughout a full run instead.
const XP_GROWTH_MULT := 1.12
const XP_GROWTH_ADD := 4.0

var max_hp := 100.0
var hp := 100.0
var level := 1
var xp := 0.0
var xp_to_next := 10.0

# Live combat stats, recomputed from the base values + accumulated bonuses
# whenever a bonus is applied (see _recompute_stats).
var attack_damage := 8.0
var attack_range := BASE_ATTACK_RANGE
var attack_cooldown := BASE_ATTACK_COOLDOWN
var crit_chance := 0.0

var _range_bonus := 0.0
var _cooldown_multiplier := 1.0

# Per-floor play-pattern tracking, fed into the achievement prompt so it can
# call out movement/ability habits (see reset_floor_stats, called by floor.gd
# at the start of each floor).
var floor_distance_moved := 0.0
var floor_bombs_thrown := 0
var floor_missiles_cast := 0

var _attack_timer := 0.0
var _bomb_timer := 0.0
var _missile_timer := 0.0
var _damage_flash := 0.0
var _attack_flash_target := Vector2.ZERO
var _attack_flash_timer := 0.0

func _ready() -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)
	_recompute_stats()

func _physics_process(delta: float) -> void:
	_handle_movement(delta)
	_handle_attack(delta)
	_bomb_timer = max(0.0, _bomb_timer - delta)
	_missile_timer = max(0.0, _missile_timer - delta)
	if _damage_flash > 0.0:
		_damage_flash -= delta
	if _attack_flash_timer > 0.0:
		_attack_flash_timer -= delta
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_throw_bomb()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cast_missile()

func _handle_movement(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1
	velocity = dir.normalized() * SPEED if dir != Vector2.ZERO else Vector2.ZERO
	move_and_slide()
	floor_distance_moved += velocity.length() * delta

func _handle_attack(delta: float) -> void:
	_attack_timer -= delta
	if _attack_timer > 0.0:
		return
	var target := _find_nearest_enemy()
	if target == null:
		return
	_attack_timer = attack_cooldown
	var damage := attack_damage
	if randf() < crit_chance:
		damage *= 2.0
	if target.has_method("take_damage"):
		target.take_damage(damage)
	_attack_flash_target = to_local(target.global_position)
	_attack_flash_timer = 0.1

func _find_nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := attack_range
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var dist: float = global_position.distance_to(enemy.global_position)
		if dist <= nearest_dist:
			nearest = enemy
			nearest_dist = dist
	return nearest

## Left-click ability: throws a bomb at the cursor (clamped to BOMB_MAX_RANGE)
## that lands instantly but doesn't explode until its fuse runs out (see
## Bomb) — the delay is what gives enemies a window to dodge.
func _throw_bomb() -> void:
	if _bomb_timer > 0.0:
		return
	_bomb_timer = BOMB_COOLDOWN
	floor_bombs_thrown += 1
	var impact := _clamp_to_range(get_global_mouse_position(), BOMB_MAX_RANGE)
	var bomb := Bomb.new()
	bomb.global_position = impact
	bomb.damage = BOMB_DAMAGE
	bomb.radius = BOMB_RADIUS
	bomb.dodge_chance = _get_character_profile().get("bomb_dodge_chance", 0.0)
	get_parent().add_child(bomb)

## Right-click ability: fires a laser bolt toward the cursor as an actual
## traveling projectile (see Laser), not an instant hit — so enemies in its
## path get a chance to dodge before it reaches them.
func _cast_missile() -> void:
	if _missile_timer > 0.0:
		return
	var aim_dir := (get_global_mouse_position() - global_position).normalized()
	if aim_dir == Vector2.ZERO:
		return
	_missile_timer = MISSILE_COOLDOWN
	floor_missiles_cast += 1
	var laser := Laser.new()
	laser.global_position = global_position
	laser.direction = aim_dir
	laser.damage = MISSILE_DAMAGE
	laser.max_range = MISSILE_RANGE
	laser.dodge_chance = _get_character_profile().get("missile_dodge_chance", 0.0)
	get_parent().add_child(laser)

## The System AI's current read on the player, kept on the floor controller
## (see floor.gd's character_profile) — dodge chances come straight from its
## bomb_dodge_chance/missile_dodge_chance fields. Never computed locally;
## this is just where Player looks it up. {} (all defaults) if unavailable.
func _get_character_profile() -> Dictionary:
	var floor_node := get_tree().get_first_node_in_group("floor_controller")
	if floor_node and "character_profile" in floor_node:
		return floor_node.character_profile
	return {}

func _clamp_to_range(world_pos: Vector2, max_range: float) -> Vector2:
	var offset := world_pos - global_position
	if offset.length() > max_range:
		offset = offset.normalized() * max_range
	return global_position + offset

func _draw() -> void:
	var color := Color(0.9, 0.7, 0.1)
	if _damage_flash > 0.0:
		color = Color(1, 1, 1)
	draw_circle(Vector2.ZERO, RADIUS, color)
	if _attack_flash_timer > 0.0:
		draw_line(Vector2.ZERO, _attack_flash_target, Color(1, 1, 0, 0.6), 2.0)

func take_damage(amount: float) -> void:
	hp -= amount
	_damage_flash = 0.15
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		died.emit()

func reset_floor_stats() -> void:
	floor_distance_moved = 0.0
	floor_bombs_thrown = 0
	floor_missiles_cast = 0

func gain_xp(amount: float) -> void:
	xp += amount
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = xp_to_next * XP_GROWTH_MULT + XP_GROWTH_ADD
		leveled_up.emit(level)
	xp_changed.emit(xp, xp_to_next)

func _recompute_stats() -> void:
	attack_cooldown = max(MIN_COOLDOWN, BASE_ATTACK_COOLDOWN * _cooldown_multiplier)
	attack_range = BASE_ATTACK_RANGE + _range_bonus

## Called on every level-up: a flat, automatic bump to all four core stats.
## Trainable spells/abilities (a separate, player-chosen system) come later.
func apply_level_up_bonus() -> void:
	attack_damage += LEVEL_UP_DAMAGE_BONUS
	_range_bonus += LEVEL_UP_RANGE_BONUS
	_cooldown_multiplier = max(MIN_COOLDOWN_MULTIPLIER, _cooldown_multiplier - LEVEL_UP_COOLDOWN_REDUCTION)
	_recompute_stats()
	max_hp += LEVEL_UP_MAX_HP_BONUS
	hp += LEVEL_UP_MAX_HP_BONUS
	hp_changed.emit(hp, max_hp)

## Applies a LootGenerator item's effects to the character's live stats.
## Unknown stat keys are ignored (forward-compatible with future loot content).
func apply_loot(loot: Dictionary) -> void:
	for effect in loot.get("effects", []):
		var stat: String = effect.get("stat", "")
		var value: float = effect.get("value", 0.0)
		match stat:
			"damage":
				attack_damage += value
			"attack_speed":
				_cooldown_multiplier *= max(0.1, 1.0 - value)
				_recompute_stats()
			"range":
				_range_bonus += value
				_recompute_stats()
			"max_hp":
				max_hp += value
				hp += value
				hp_changed.emit(hp, max_hp)
			"crit_chance":
				crit_chance = min(1.0, crit_chance + value)
