extends Node2D

const DEFAULT_FLOOR_DURATION := 90.0
const MAX_FLOOR := 10
# Per-floor cumulative speed bump for monsters (floor 1 = 1.0x, floor 10 = ~2.35x).
# Placeholder value pending playtesting, same as the tier thresholds in LootGenerator.
const FLOOR_SPEED_STEP := 0.15

var player: Player
var hud: GameHud
var spawner: EnemySpawner
var ollama: OllamaClient

var floor_duration := DEFAULT_FLOOR_DURATION
var current_floor := 1
var time_remaining := 0.0
var total_points := 0
var floor_points := 0
var floor_damage_taken := 0.0
var floor_active := true

func _ready() -> void:
	floor_duration = _resolve_floor_duration()
	time_remaining = floor_duration
	add_to_group("floor_controller")
	add_child(BackgroundGrid.new())
	ollama = OllamaClient.new()
	add_child(ollama)
	_spawn_player()
	_spawn_hud()
	_spawn_enemy_spawner()

## Testing hook: set env var DCC_FLOOR_DURATION (e.g. "3") to shorten floors
## for quickly exercising the floor-clear -> loot/achievement flow and its logs,
## without having to wait out the real 90s each time.
func _resolve_floor_duration() -> float:
	var override := OS.get_environment("DCC_FLOOR_DURATION")
	if override != "" and override.is_valid_float():
		return float(override)
	return DEFAULT_FLOOR_DURATION

func _process(delta: float) -> void:
	if not floor_active:
		return
	time_remaining = max(0.0, time_remaining - delta)
	hud.update_timer(time_remaining)
	if time_remaining <= 0.0:
		_end_floor("cleared")

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_TAB and player and floor_active:
			player.switch_form()

func _spawn_player() -> void:
	player = Player.new()
	player.add_to_group("player")
	player.global_position = Vector2.ZERO
	add_child(player)
	player.hp_changed.connect(_on_player_hp_changed)
	player.xp_changed.connect(_on_player_xp_changed)
	player.leveled_up.connect(_on_player_leveled_up)
	player.died.connect(_on_player_died)

	var camera := Camera2D.new()
	camera.zoom = Vector2(1.5, 1.5)
	player.add_child(camera)
	camera.make_current()

func _spawn_hud() -> void:
	hud = GameHud.new()
	add_child(hud)
	hud.upgrade_chosen.connect(_on_upgrade_chosen)
	hud.update_hp(player.hp, player.max_hp)
	hud.update_xp(player.xp, player.xp_to_next)
	hud.update_level(player.level)
	hud.update_points(total_points)
	hud.update_floor(current_floor, MAX_FLOOR)

func _spawn_enemy_spawner() -> void:
	spawner = EnemySpawner.new()
	spawner.floor_speed_multiplier = 1.0 + float(current_floor - 1) * FLOOR_SPEED_STEP
	add_child(spawner)
	spawner.enemy_died.connect(_on_enemy_died)

func _on_player_hp_changed(current: float, max_hp: float) -> void:
	hud.update_hp(current, max_hp)

func _on_player_xp_changed(current: float, needed: float) -> void:
	hud.update_xp(current, needed)

func _on_player_leveled_up(level: int) -> void:
	hud.update_level(level)
	hud.show_level_up_choice()

func _on_upgrade_chosen(upgrade_id: String) -> void:
	player.apply_upgrade(upgrade_id)

func _on_enemy_died(point_value: int, _death_position: Vector2) -> void:
	total_points += point_value
	floor_points += point_value
	hud.update_points(total_points)

func register_damage_taken(amount: float) -> void:
	floor_damage_taken += amount

func _on_player_died() -> void:
	_end_floor("collapsed")

func _end_floor(outcome: String) -> void:
	if not floor_active:
		return
	floor_active = false
	get_tree().paused = true

	var tier := LootGenerator.compute_tier(floor_points, floor_damage_taken)
	hud.show_toast("Floor %d %s! Opening [%s] loot box..." % [current_floor, outcome, tier.to_upper()])
	var loot: Dictionary = await ollama.get_loot(tier, {
		"floor": current_floor,
		"points_this_floor": floor_points,
		"damage_taken_this_floor": floor_damage_taken,
	})
	player.apply_loot(loot)
	hud.show_toast("Floor %d %s! Loot: [%s] %s — %s" % [current_floor, outcome, tier.to_upper(), loot["name"], loot["flavor_text"]])
	print("Floor %d ended: outcome=%s tier=%s loot=%s" % [current_floor, outcome, tier, loot])

	var achievement = await ollama.get_achievement({
		"floor": current_floor,
		"outcome": outcome,
		"points": floor_points,
		"damage_taken": floor_damage_taken,
	})
	if achievement != null:
		await get_tree().create_timer(3.5).timeout
		hud.show_toast("Achievement unlocked: %s — %s" % [achievement["title"], achievement["description"]])
		print("Achievement: %s" % achievement)
		await get_tree().create_timer(3.5).timeout
	else:
		await get_tree().create_timer(3.0).timeout

	if outcome == "cleared" and current_floor < MAX_FLOOR:
		_start_next_floor()
	else:
		var final_text := ""
		if outcome == "cleared":
			final_text = "Run complete! Cleared all %d floors with %d points." % [MAX_FLOOR, total_points]
		else:
			final_text = "Run over on floor %d. Final score: %d points." % [current_floor, total_points]
		hud.show_toast(final_text)

func _start_next_floor() -> void:
	current_floor += 1
	floor_points = 0
	floor_damage_taken = 0.0
	time_remaining = floor_duration

	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("pickups"):
		node.queue_free()
	spawner.queue_free()
	_spawn_enemy_spawner()

	hud.update_floor(current_floor, MAX_FLOOR)
	hud.show_toast("Floor %d — collapses in %d:00" % [current_floor, int(floor_duration / 60.0)])

	floor_active = true
	get_tree().paused = false
