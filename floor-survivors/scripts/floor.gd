extends Node2D

const DEFAULT_FLOOR_DURATION := 90.0
const MAX_FLOOR := 10
# Per-floor cumulative speed bump for monsters (floor 1 = 1.0x, floor 10 = ~2.35x).
# Placeholder value pending playtesting, same as the tier thresholds in LootGenerator.
const FLOOR_SPEED_STEP := 0.15
# The loot-box chime is one sample; higher tiers just ring higher.
const LOOT_STING_PITCH := {"common": 0.85, "uncommon": 0.93, "rare": 1.0, "epic": 1.12, "legendary": 1.25}

var player: Player
var hud: GameHud
var spawner: EnemySpawner
var ollama: OllamaClient
var background: BackgroundGrid
var overlay: ScreenOverlay

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
var _last_hp := 100.0  # presentation only: lets the hit flash tell damage from healing
var _mid_floor_curator_done := false
var _curator_busy := false
# Longest the mid-floor curator waits for an in-flight director request
# (a director call times out at OllamaClient.DIRECTOR_TIMEOUT_SEC = 5s).
const CURATOR_WAIT_MAX := 5.5
# Floors in a row allowed without an achievement before one is guaranteed.
const ACHIEVEMENT_DROUGHT_MAX := 2
var _floors_without_achievement := 0

# Restart bookkeeping (see restart_run): _flows counts the coroutines that are
# awaiting the LLM / a delay (the mid-floor curator call and the floor-end
# sequence), and _quitting tells them to bail out. Reloading the scene only
# after _flows hits 0 is what keeps a mid-request restart from leaving orphaned
# awaits behind.
var _quitting := false
var _flows := 0

# The System AI's live per-second hand on the fight, layered over the curator's
# standing numbers (see get_effective_profile).
var director: SystemDirector

func _ready() -> void:
	floor_duration = _resolve_floor_duration()
	time_remaining = floor_duration
	add_to_group("floor_controller")
	background = BackgroundGrid.new()
	add_child(background)
	add_child(FxLayer.new())
	overlay = ScreenOverlay.new()
	add_child(overlay)
	ollama = OllamaClient.new()
	add_child(ollama)
	_spawn_player()
	_spawn_hud()
	_spawn_enemy_spawner()
	director = SystemDirector.new()
	director.floor_node = self  # set before add_child so its _ready can read the profile
	add_child(director)
	add_child(PauseMenu.new())
	hud.show_floor_banner(current_floor, MAX_FLOOR)
	# Testing hook (see DebugCapture): only active when DCC_CAPTURE_DIR is set.
	if OS.get_environment("DCC_CAPTURE_DIR") != "":
		add_child(DebugCapture.new())

## The tactical numbers actually in force: the curator's profile (twice per
## floor) with the director's live per-second numbers merged over the top.
## Player (dodge chances) and EnemySpawner (spawn/aggression) read this, not
## character_profile directly.
func get_effective_profile() -> Dictionary:
	var effective := character_profile.duplicate()
	if director:
		effective.merge(director.live, true)
	return effective

## Testing hook: set env var DCC_FLOOR_DURATION (e.g. "3") to shorten floors
## for quickly exercising the floor-clear -> loot/achievement flow and its logs,
## without having to wait out the real 90s each time.
func _resolve_floor_duration() -> float:
	var override := OS.get_environment("DCC_FLOOR_DURATION")
	if override != "" and override.is_valid_float():
		return float(override)
	return DEFAULT_FLOOR_DURATION

func _process(delta: float) -> void:
	if not floor_active or _quitting:
		return
	time_remaining = max(0.0, time_remaining - delta)
	hud.update_timer(time_remaining)
	if spawner:
		spawner.apply_profile(get_effective_profile())  # idempotent; keeps the director's per-second numbers live
	hud.update_system_tactic(director.current_tactic if director else "none", spawner.get_aggression() if spawner else 1.0)
	hud.update_abilities(player.get_bomb_cooldown_fraction(), player.get_laser_cooldown_fraction())
	var boss := get_tree().get_first_node_in_group("bosses") as Boss
	hud.update_boss(clampf(boss.hp / boss.max_hp, 0.0, 1.0) if is_instance_valid(boss) else -1.0)
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
	_flows += 1
	_curator_busy = true  # the director stops starting new requests from here on
	# ...and the curator waits out one already in flight, so it doesn't spend its
	# 6s timeout queued behind it on the same Ollama (5/10 mid-floor calls timed
	# out that way in the 2026-09-21 playtest). Capped so a stuck request can't
	# hold the curator forever.
	var waited := 0.0
	while director and director.is_request_in_flight() and waited < CURATOR_WAIT_MAX and not _quitting:
		await get_tree().process_frame
		waited += get_process_delta_time()
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
	if not _quitting:
		await _apply_curator_profile()
	_flows -= 1

## Hands the System AI's latest tactical numbers to the live spawner and, if
## it left a taunt, shows it to the player. Called after every curator_update
## resolves (mid-floor, floor-end, and once right after a fresh spawner is
## created so a new floor doesn't silently reset to a neutral tactic).
func _apply_curator_profile() -> void:
	if spawner:
		spawner.apply_profile(get_effective_profile())
	var commentary: String = character_profile.get("ai_commentary", "")
	if commentary != "":
		hud.show_toast(commentary, "system", 4.5)
		# Give the taunt a moment on screen before anything else can overwrite
		# it (floor-end otherwise moves straight into the next floor's toast).
		await _wait(2.5)

## Sleeps `seconds` of real time (it keeps running through the floor-end pause,
## like the SceneTreeTimers it replaces) but returns early if a restart begins,
## so nothing is left waiting when the scene is freed.
func _wait(seconds: float) -> void:
	var end_msec := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end_msec and not _quitting:
		await get_tree().process_frame

## Restarts the run (HUD's R on the run-over card, the Esc menu). Cancels the
## in-flight LLM requests, waits for every coroutine that was awaiting them to
## finish unwinding, then reloads — so nothing resumes after the scene is gone
## (the old "R during an Ollama request logs script errors" bug).
func restart_run() -> void:
	if _quitting:
		return
	_quitting = true
	ollama.cancel()
	while _flows > 0 or director.is_request_in_flight():
		await get_tree().process_frame
	get_tree().paused = false
	get_tree().reload_current_scene()

func _spawn_player() -> void:
	player = Player.new()
	player.add_to_group("player")
	player.global_position = Vector2.ZERO
	add_child(player)
	if TouchControls.wanted():  # phones: joystick + aim stick overlay
		var touch := TouchControls.new()
		touch.player = player
		add_child(touch)
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
	spawner.floor_number = current_floor
	add_child(spawner)
	spawner.enemy_died.connect(_on_enemy_died)
	spawner.boss_spawned.connect(_on_boss_spawned)
	spawner.boss_died.connect(_on_boss_died)
	spawner.apply_profile(get_effective_profile())  # carry the System AI's current tactic into the new floor

func _on_player_hp_changed(current: float, max_hp: float) -> void:
	if current < _last_hp:
		overlay.pulse_hit(clampf((_last_hp - current) / 20.0, 0.35, 1.0))  # bigger hit, bigger flash
	_last_hp = current
	hud.update_hp(current, max_hp)
	overlay.set_hp(current, max_hp)

func _on_player_xp_changed(current: float, needed: float) -> void:
	hud.update_xp(current, needed)

func _on_player_leveled_up(level: int) -> void:
	hud.update_level(level)
	hud.show_level_up(level)
	var fx := FxLayer.of(self)
	if fx:
		fx.ring(player.global_position, UIStyle.MINT, Player.RADIUS, 120.0, 0.6, 4.0)
		fx.burst(player.global_position, UIStyle.MINT, 14, 200.0, 3.0, 0.6)
	player.apply_level_up_bonus()

func _on_enemy_died(point_value: int, _death_position: Vector2) -> void:
	total_points += point_value
	floor_points += point_value
	hud.update_points(total_points)

func _on_boss_spawned() -> void:
	var subtitle := "Something large has noticed you."
	var boss := get_tree().get_first_node_in_group("bosses") as Boss
	if boss and boss.sprite_entry.has("name"):
		subtitle = "%s has noticed you." % boss.sprite_entry["name"]
	hud.show_banner("BOSS APPROACHING", subtitle, UIStyle.BOSS_PURPLE, 2.4)
	var fx := FxLayer.of(self)
	if fx:
		fx.shake(5.0)

func _on_boss_died(point_value: int, death_position: Vector2) -> void:
	hud.show_toast("+%d points" % point_value, "boss", 3.5, Color.TRANSPARENT, "Boss defeated")
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
	hud.show_floor_end(outcome)
	_flows += 1
	await _run_floor_end(outcome)
	_flows -= 1

## The floor-end sequence. Every await is followed by a _quitting check so a
## restart (restart_run) can cut it short.
func _run_floor_end(outcome: String) -> void:
	var floor_end_context := {
		"floor": current_floor,
		"outcome": outcome,
		"points": floor_points,
		"damage_taken": floor_damage_taken,
		"distance_moved": player.floor_distance_moved,
		"bombs_thrown": player.floor_bombs_thrown,
		"missiles_cast": player.floor_missiles_cast,
		"floor_seconds": floor_duration,
		"max_hp": player.max_hp,
	}

	var run_over_note := ""  # the LLM's game-over line, shown on the run-over card
	if outcome == "collapsed":
		# Character died: no achievements, no loot — just a narrated end to
		# the run (see OllamaClient.get_game_over_message).
		var death_message: String = await ollama.get_game_over_message(floor_end_context, character_profile)
		if _quitting:
			return
		hud.show_toast(death_message, "death", 6.0)
		run_over_note = death_message
		print("Floor %d ended: outcome=collapsed. %s" % [current_floor, death_message])
		await _wait(3.5)
	else:
		# Loot is achievement-gated: no achievement, no loot box. This is
		# decided before loot generation, on purpose, so the loot call (when it
		# happens) can reference the achievement and generate something
		# thematically tied to it, rather than the two being generated
		# independently.
		var result: Dictionary = await ollama.get_achievement(floor_end_context, character_profile)
		if _quitting:
			return
		# Circuit breaker: the 2026-09-21 playtest cleared all 10 floors with zero
		# achievements (so zero loot). Past a drought, a local achievement is
		# guaranteed so the loot feature can't go dark for a whole run.
		if result.get("earned", false):
			_floors_without_achievement = 0
		else:
			_floors_without_achievement += 1
			if _floors_without_achievement > ACHIEVEMENT_DROUGHT_MAX:
				print("Achievement drought (%d floors): awarding a local one" % _floors_without_achievement)
				result = {"earned": true, "achievement": AchievementGenerator.drought_breaker(floor_end_context), "message": ""}
				_floors_without_achievement = 0
		if result.get("earned", false):
			var achievement: Dictionary = result["achievement"]
			await _wait(3.5)
			if _quitting:
				return
			hud.show_toast(achievement["description"], "achievement", 6.0, Color.TRANSPARENT, achievement["title"])
			AudioManager.play_sting("achievement")
			print("Achievement: %s" % achievement)
			await _wait(3.5)
			if _quitting:
				return

			var tier := LootGenerator.compute_tier(current_floor, floor_points, floor_damage_taken, character_profile.get("loot_generosity_multiplier", 1.0))
			hud.show_toast("", "loot", 4.0, UIStyle.tier_color(tier), "Opening %s loot box..." % tier.to_upper())
			var loot: Dictionary = await ollama.get_loot(tier, {
				"floor": current_floor,
				"points_this_floor": floor_points,
				"damage_taken_this_floor": floor_damage_taken,
			}, character_profile, achievement)
			if _quitting:
				return
			player.apply_loot(loot)
			hud.show_toast(loot["flavor_text"], "loot", 7.0, UIStyle.tier_color(tier), "%s  [%s]" % [loot["name"], tier.to_upper()])
			AudioManager.play_sting("loot", LOOT_STING_PITCH.get(tier, 1.0))
			print("Floor %d ended: outcome=%s tier=%s loot=%s achievement=%s" % [current_floor, outcome, tier, loot, achievement["title"]])
			await _wait(3.0)
		else:
			var message: String = result.get("message", "")
			hud.show_toast(message)
			print("Floor %d ended: outcome=%s, no achievement, no loot. %s" % [current_floor, outcome, message])
			await _wait(2.0)
	if _quitting:
		return

	# If the mid-floor call is still in flight (e.g. a cold Ollama load outlasting
	# a short DCC_FLOOR_DURATION test floor), wait for it so its result can't
	# land after — and clobber — this floor-end update.
	while _curator_busy:
		await get_tree().process_frame
	if _quitting:
		return
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
	if _quitting:
		return
	await _apply_curator_profile()
	if _quitting:
		return

	if outcome == "cleared" and current_floor < MAX_FLOOR:
		_start_next_floor()
	else:
		var final_text := ""
		if outcome == "cleared":
			final_text = "Run complete! Cleared all %d floors with %d points." % [MAX_FLOOR, total_points]
		else:
			final_text = "Run over on floor %d. Final score: %d points." % [current_floor, total_points]
		hud.show_run_over(outcome, run_over_note if run_over_note != "" else final_text, {"floor": current_floor, "points": total_points, "level": player.level})

func _start_next_floor() -> void:
	current_floor += 1
	floor_points = 0
	floor_damage_taken = 0.0
	time_remaining = floor_duration
	_mid_floor_curator_done = false
	player.reset_floor_stats()
	director.reset()

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
	hud.show_floor_banner(current_floor, MAX_FLOOR)
	background.set_floor_theme(current_floor)

	floor_active = true
	get_tree().paused = false
