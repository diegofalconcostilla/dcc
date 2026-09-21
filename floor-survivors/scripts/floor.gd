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

# Running "curator" character profile — see plan.md's "Long-term direction"
# section. Fixed-shape, replaced (not appended to) twice per floor: once at
# the timer's halfway point, once at floor-end.
var character_profile := CuratorGenerator.DEFAULT_PROFILE.duplicate(true)
var _mid_floor_curator_done := false
var _curator_busy := false

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
	if not _mid_floor_curator_done and time_remaining <= floor_duration / 2.0:
		_mid_floor_curator_done = true
		_run_mid_floor_curator()
	if time_remaining <= 0.0:
		_end_floor("cleared")

## Fire-and-forget: awaits the Ollama call internally without blocking
## _process (GDScript coroutines yield at their first `await` and resume
## later on their own). Guarded by _mid_floor_curator_done so it only fires
## once per floor.
func _run_mid_floor_curator() -> void:
	_curator_busy = true
	character_profile = await ollama.get_curator_update({
		"floor": current_floor,
		"phase": "mid_floor",
		"points_this_floor": floor_points,
		"damage_taken_this_floor": floor_damage_taken,
		"distance_moved": player.floor_distance_moved,
		"bombs_thrown": player.floor_bombs_thrown,
		"missiles_cast": player.floor_missiles_cast,
	}, character_profile)
	_curator_busy = false
	await _apply_curator_profile()

## Hands the System AI's latest tactical numbers to the live spawner and, if
## it left a taunt, shows it to the player. Called after every curator_update
## resolves (mid-floor, floor-end, and once right after a fresh spawner is
## created so a new floor doesn't silently reset to a neutral tactic).
func _apply_curator_profile() -> void:
	if spawner:
		spawner.apply_profile(character_profile)
	var commentary: String = character_profile.get("ai_commentary", "")
	if commentary != "":
		hud.show_toast("System AI: %s" % commentary)
		# Give the taunt a moment on screen before anything else can overwrite
		# it (floor-end otherwise moves straight into the next floor's toast).
		await get_tree().create_timer(2.5).timeout

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
	spawner.boss_spawned.connect(_on_boss_spawned)
	spawner.boss_died.connect(_on_boss_died)
	spawner.apply_profile(character_profile)  # carry the System AI's current tactic into the new floor

func _on_player_hp_changed(current: float, max_hp: float) -> void:
	hud.update_hp(current, max_hp)

func _on_player_xp_changed(current: float, needed: float) -> void:
	hud.update_xp(current, needed)

func _on_player_leveled_up(level: int) -> void:
	hud.update_level(level)
	player.apply_level_up_bonus()

func _on_enemy_died(point_value: int, _death_position: Vector2) -> void:
	total_points += point_value
	floor_points += point_value
	hud.update_points(total_points)

func _on_boss_spawned() -> void:
	hud.show_toast("A boss has appeared!")

func _on_boss_died(point_value: int, death_position: Vector2) -> void:
	hud.show_toast("Boss defeated! +%d points" % point_value)
	_on_enemy_died(point_value, death_position)

func register_damage_taken(amount: float) -> void:
	floor_damage_taken += amount

func _on_player_died() -> void:
	_end_floor("collapsed")

func _end_floor(outcome: String) -> void:
	if not floor_active:
		return
	floor_active = false
	get_tree().paused = true

	var floor_end_context := {
		"floor": current_floor,
		"outcome": outcome,
		"points": floor_points,
		"damage_taken": floor_damage_taken,
		"distance_moved": player.floor_distance_moved,
		"bombs_thrown": player.floor_bombs_thrown,
		"missiles_cast": player.floor_missiles_cast,
	}

	if outcome == "collapsed":
		# Character died: no achievements, no loot — just a narrated end to
		# the run (see OllamaClient.get_game_over_message).
		var death_message: String = await ollama.get_game_over_message(floor_end_context, character_profile)
		hud.show_toast(death_message)
		print("Floor %d ended: outcome=collapsed. %s" % [current_floor, death_message])
		await get_tree().create_timer(3.5).timeout
	else:
		# Loot is achievement-gated: no achievement, no loot box. This is
		# decided before loot generation, on purpose, so the loot call (when it
		# happens) can reference the achievement and generate something
		# thematically tied to it, rather than the two being generated
		# independently.
		var result: Dictionary = await ollama.get_achievement(floor_end_context, character_profile)
		if result.get("earned", false):
			var achievement: Dictionary = result["achievement"]
			await get_tree().create_timer(3.5).timeout
			hud.show_toast("Achievement unlocked: %s — %s" % [achievement["title"], achievement["description"]])
			print("Achievement: %s" % achievement)
			await get_tree().create_timer(3.5).timeout

			var tier := LootGenerator.compute_tier(current_floor, floor_points, floor_damage_taken, character_profile.get("loot_generosity_multiplier", 1.0))
			hud.show_toast("Opening [%s] loot box..." % tier.to_upper())
			var loot: Dictionary = await ollama.get_loot(tier, {
				"floor": current_floor,
				"points_this_floor": floor_points,
				"damage_taken_this_floor": floor_damage_taken,
			}, character_profile, achievement)
			player.apply_loot(loot)
			hud.show_toast("Loot: [%s] %s — %s" % [tier.to_upper(), loot["name"], loot["flavor_text"]])
			print("Floor %d ended: outcome=%s tier=%s loot=%s achievement=%s" % [current_floor, outcome, tier, loot, achievement["title"]])
			await get_tree().create_timer(3.0).timeout
		else:
			var message: String = result.get("message", "")
			hud.show_toast(message)
			print("Floor %d ended: outcome=%s, no achievement, no loot. %s" % [current_floor, outcome, message])
			await get_tree().create_timer(2.0).timeout

	# If the mid-floor call is still in flight (e.g. a cold Ollama load outlasting
	# a short DCC_FLOOR_DURATION test floor), wait for it so its result can't
	# land after — and clobber — this floor-end update.
	while _curator_busy:
		await get_tree().process_frame
	_curator_busy = true
	character_profile = await ollama.get_curator_update({
		"floor": current_floor,
		"phase": "floor_end",
		"outcome": outcome,
		"points_this_floor": floor_points,
		"damage_taken_this_floor": floor_damage_taken,
		"distance_moved": player.floor_distance_moved,
		"bombs_thrown": player.floor_bombs_thrown,
		"missiles_cast": player.floor_missiles_cast,
	}, character_profile)
	_curator_busy = false
	await _apply_curator_profile()

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
	_mid_floor_curator_done = false
	player.reset_floor_stats()

	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("pickups"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("bombs"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("lasers"):
		node.queue_free()
	spawner.queue_free()
	_spawn_enemy_spawner()

	hud.update_floor(current_floor, MAX_FLOOR)
	hud.show_toast("Floor %d — collapses in %d:00" % [current_floor, int(floor_duration / 60.0)])

	floor_active = true
	get_tree().paused = false
