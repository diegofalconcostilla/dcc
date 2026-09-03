extends Node
class_name EnemySpawner

signal enemy_died(point_value: int, death_position: Vector2)

var floor_speed_multiplier := 1.0
var elapsed := 0.0
var spawn_interval := 1.4
var _timer := 0.0

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
	enemy.died.connect(_on_enemy_died)

func _on_enemy_died(point_value: int, death_position: Vector2) -> void:
	enemy_died.emit(point_value, death_position)
	var orb := XPOrb.new()
	orb.position = death_position
	get_parent().add_child(orb)
