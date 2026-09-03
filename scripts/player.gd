extends CharacterBody2D
class_name Player

signal died
signal xp_changed(current: float, needed: float)
signal hp_changed(current: float, max_hp: float)
signal leveled_up(level: int)

const SPEED := 220.0
const RADIUS := 16.0

const CARL_COOLDOWN := 0.6
const CARL_RANGE := 140.0
const DONUT_COOLDOWN := 0.4
const DONUT_RANGE := 100.0
const MIN_COOLDOWN := 0.08

var max_hp := 100.0
var hp := 100.0
var level := 1
var xp := 0.0
var xp_to_next := 10.0

var active_form := "carl"  # or "donut"

# Live combat stats, recomputed from the form's base + accumulated bonuses
# whenever the form switches or a bonus is applied (see _recompute_form_stats).
# This keeps loot/level-up bonuses from being wiped by switch_form().
var attack_damage := 8.0
var attack_range := CARL_RANGE
var attack_cooldown := CARL_COOLDOWN
var crit_chance := 0.0

var _range_bonus := 0.0
var _cooldown_multiplier := 1.0

var _attack_timer := 0.0
var _damage_flash := 0.0
var _attack_flash_target := Vector2.ZERO
var _attack_flash_timer := 0.0

func _ready() -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)
	_recompute_form_stats()

func _physics_process(delta: float) -> void:
	_handle_movement()
	_handle_attack(delta)
	if _damage_flash > 0.0:
		_damage_flash -= delta
	if _attack_flash_timer > 0.0:
		_attack_flash_timer -= delta
	queue_redraw()

func _handle_movement() -> void:
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

func _draw() -> void:
	var color := Color(0.9, 0.7, 0.1) if active_form == "carl" else Color(0.8, 0.3, 0.6)
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

func gain_xp(amount: float) -> void:
	xp += amount
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = xp_to_next * 1.25 + 5.0
		leveled_up.emit(level)
	xp_changed.emit(xp, xp_to_next)

func switch_form() -> void:
	active_form = "donut" if active_form == "carl" else "carl"
	# Donut: faster, shorter base range. Carl: slower, longer base range.
	# Accumulated bonuses (loot/upgrades) carry over — see _recompute_form_stats.
	_recompute_form_stats()

func _recompute_form_stats() -> void:
	var base_cooldown := DONUT_COOLDOWN if active_form == "donut" else CARL_COOLDOWN
	var base_range := DONUT_RANGE if active_form == "donut" else CARL_RANGE
	attack_cooldown = max(MIN_COOLDOWN, base_cooldown * _cooldown_multiplier)
	attack_range = base_range + _range_bonus

func apply_upgrade(upgrade_id: String) -> void:
	match upgrade_id:
		"damage":
			attack_damage *= 1.25
		"speed":
			_cooldown_multiplier *= 0.85
			_recompute_form_stats()
		"range":
			_range_bonus += 25.0
			_recompute_form_stats()
		"max_hp":
			max_hp += 20.0
			hp += 20.0
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
				_recompute_form_stats()
			"range":
				_range_bonus += value
				_recompute_form_stats()
			"max_hp":
				max_hp += value
				hp += value
				hp_changed.emit(hp, max_hp)
			"crit_chance":
				crit_chance = min(1.0, crit_chance + value)
