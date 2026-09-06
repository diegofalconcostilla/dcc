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

func _ready() -> void:
	_reroll_boss_threshold()

func _process(delta: float) -> void:
	elapsed += delta
	_timer -= delta
	spawn_interval = max(0.35, 1.4 - elapsed * 0.01)
	if _timer <= 0.0:
		_timer = spawn_interval
		_spawn_enemy()

func _spawn_enemy() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var enemy := Enemy.new()
	var angle := randf() * TAU
	var spawn_radius := 500.0
	enemy.position = player.global_position + Vector2(cos(angle), sin(angle)) * spawn_radius
	var difficulty_factor := 1.0 + elapsed / 60.0
	get_parent().add_child(enemy)
	enemy.scale_difficulty(difficulty_factor)
	enemy.speed *= floor_speed_multiplier
	enemy.died.connect(_on_enemy_died.bind(enemy.xp_value))

func _spawn_boss() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	_boss_active = true
	_kills_since_last_boss = 0
	var boss := Boss.new()
	var angle := randf() * TAU
	boss.position = player.global_position + Vector2(cos(angle), sin(angle)) * 500.0
	var difficulty_factor := 1.0 + elapsed / 60.0
	get_parent().add_child(boss)
	boss.scale_difficulty(difficulty_factor)
	boss.speed *= floor_speed_multiplier
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
