extends Node
class_name EnemySpawner

signal enemy_died(point_value: int, death_position: Vector2)
signal boss_spawned()
signal boss_died(point_value: int, death_position: Vector2)

# A boss spawns once this many regular kills have landed since the last one;
# the threshold is rerolled within this range each time. Placeholder pending
# playtesting.
const BOSS_KILL_MIN := 15
const BOSS_KILL_MAX := 25

var floor_speed_multiplier := 1.0
var elapsed := 0.0
var spawn_interval := 1.4
var _timer := 0.0

var _kills_since_last_boss := 0
var _next_boss_threshold := 0
var _boss_active := false

# Live tactical modifiers set by the System AI's curator profile (see
# apply_profile) — neutral (no-op) until it decides otherwise. This spawner
# never derives these itself; it only applies whatever numbers the LLM chose,
# clamped by CuratorGenerator. See plan.md's "Combat abilities" section.
var _spawn_interval_mult := 1.0
var _spawn_radius_mult := 1.0
var _aggression_mult := 1.0
var _boss_threshold_mult := 1.0

func _ready() -> void:
	_reroll_boss_threshold()

func _process(delta: float) -> void:
	elapsed += delta
	_timer -= delta
	spawn_interval = max(0.35, (1.4 - elapsed * 0.01) * _spawn_interval_mult)
	if _timer <= 0.0:
		_timer = spawn_interval
		_spawn_enemy()

## Applies the System AI's latest tactical numbers (see CuratorGenerator's
## DEFAULT_PROFILE for the neutral baseline of each field). Safe to call
## repeatedly with an unchanged profile — normalizes the boss threshold
## against the *previous* multiplier rather than compounding it.
func apply_profile(profile: Dictionary) -> void:
	var new_boss_mult: float = profile.get("boss_threshold_multiplier", 1.0)
	if not _boss_active and _boss_threshold_mult > 0.0 and new_boss_mult != _boss_threshold_mult:
		_next_boss_threshold = max(3, int(_next_boss_threshold * (new_boss_mult / _boss_threshold_mult)))
	_boss_threshold_mult = new_boss_mult
	_spawn_interval_mult = profile.get("spawn_interval_multiplier", 1.0)
	_spawn_radius_mult = profile.get("spawn_radius_multiplier", 1.0)
	_aggression_mult = profile.get("aggression_multiplier", 1.0)

func _spawn_enemy() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var enemy := Enemy.new()
	var angle := randf() * TAU
	var spawn_radius := 500.0 * _spawn_radius_mult
	enemy.position = player.global_position + Vector2(cos(angle), sin(angle)) * spawn_radius
	var difficulty_factor := 1.0 + elapsed / 60.0
	get_parent().add_child(enemy)
	enemy.scale_difficulty(difficulty_factor)
	enemy.speed *= floor_speed_multiplier * _aggression_mult
	enemy.contact_damage *= _aggression_mult
	enemy.died.connect(_on_enemy_died.bind(enemy.xp_value))

func _spawn_boss() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	_boss_active = true
	_kills_since_last_boss = 0
	var boss := Boss.new()
	var angle := randf() * TAU
	boss.position = player.global_position + Vector2(cos(angle), sin(angle)) * (500.0 * _spawn_radius_mult)
	var difficulty_factor := 1.0 + elapsed / 60.0
	get_parent().add_child(boss)
	boss.scale_difficulty(difficulty_factor)
	boss.speed *= floor_speed_multiplier * _aggression_mult
	boss.contact_damage *= _aggression_mult
	boss.died.connect(_on_boss_died.bind(boss.xp_value))
	boss_spawned.emit()

func _on_enemy_died(point_value: int, death_position: Vector2, xp_value: float) -> void:
	enemy_died.emit(point_value, death_position)
	_spawn_xp_orb(death_position, xp_value)
	_kills_since_last_boss += 1
	if not _boss_active and _kills_since_last_boss >= _next_boss_threshold:
		_spawn_boss()

func _on_boss_died(point_value: int, death_position: Vector2, xp_value: float) -> void:
	_boss_active = false
	_reroll_boss_threshold()
	boss_died.emit(point_value, death_position)
	_spawn_xp_orb(death_position, xp_value)

func _reroll_boss_threshold() -> void:
	_next_boss_threshold = randi_range(BOSS_KILL_MIN, BOSS_KILL_MAX)

func _spawn_xp_orb(death_position: Vector2, xp_value: float) -> void:
	var orb := XPOrb.new()
	orb.position = death_position
	orb.value = xp_value
	get_parent().add_child(orb)
