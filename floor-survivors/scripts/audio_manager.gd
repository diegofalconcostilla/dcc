extends Node

## Autoload: the adaptive 8-bit soundtrack (see plan.md's "Music" section; the
## audio itself is synthesized by tools/make_chiptune.py into assets/audio/).
##
## Five sample-locked loop stems (pad, bass, drums, lead, menace) play together
## through one AudioStreamSynchronized and each is faded up/down with the state
## of the fight — chiefly the System AI's live threat (the director's per-second
## numbers on the floor controller), plus enemy count, boss presence and player
## HP. Short one-shot stingers mark level-ups, bosses, floor clear and game over.
##
## This node only *observes* the floor (by polling the "floor_controller" group)
## and never touches gameplay. Which stems play is presentation, a fixed mapping
## from values the AI already chose — it isn't itself an AI decision.
## M toggles mute.

const AUDIO_DIR := "res://assets/audio/"
const STEMS := ["pad", "bass", "drums", "lead", "menace"]
# Per-stem trim (dB) so the mix balances when every layer is up.
const STEM_TRIM_DB := {"pad": -9.0, "bass": -5.0, "drums": -6.0, "lead": -8.0, "menace": -8.0}
const FADE_SPEED := 0.7        # linear gain change per second
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const MUSIC_BUS_DB := -4.0
const STING_DUCK_DB := 7.0     # how far music dips under a stinger
const STING_DUCK_SEC := 1.6

var _music_player: AudioStreamPlayer
var _sync: AudioStreamSynchronized
var _gain := {}                # stem -> current linear gain 0..1
var _stings := {}              # name -> AudioStreamPlayer
var _duck := 0.0               # 1 right after a stinger, decays to 0
var _started := false

var _last_level := 0
var _last_boss_count := 0
var _last_floor_active := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep fading through the floor-end pause
	_ensure_bus(MUSIC_BUS, MUSIC_BUS_DB)
	_ensure_bus(SFX_BUS, -2.0)
	_build_music()
	for sting in ["level_up", "floor_clear", "boss", "game_over"]:
		var stream := load(AUDIO_DIR + "sting_%s.wav" % sting) as AudioStream
		if stream == null:
			push_warning("[AudioManager] missing stinger %s (run tools/make_chiptune.py, then reimport)" % sting)
			continue
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = SFX_BUS
		add_child(p)
		_stings[sting] = p

func _ensure_bus(bus_name: String, volume_db: float) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_volume_db(idx, volume_db)

func _build_music() -> void:
	_sync = AudioStreamSynchronized.new()
	_sync.stream_count = STEMS.size()
	for i in STEMS.size():
		var stem: String = STEMS[i]
		var wav := load(AUDIO_DIR + "music_%s.wav" % stem) as AudioStreamWAV
		if wav == null:
			push_warning("[AudioManager] missing stem %s (run tools/make_chiptune.py, then reimport)" % stem)
			_sync = null
			return
		# Imported WAVs don't loop by default; the stems are cut to loop exactly.
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / 2  # 16-bit mono
		_sync.set_sync_stream(i, wav)
		_sync.set_sync_stream_volume(i, -80.0)
		_gain[stem] = 0.0
	_music_player = AudioStreamPlayer.new()
	_music_player.stream = _sync
	_music_player.bus = MUSIC_BUS
	add_child(_music_player)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		var idx := AudioServer.get_bus_index(MUSIC_BUS)
		AudioServer.set_bus_mute(idx, not AudioServer.is_bus_mute(idx))
		var sfx := AudioServer.get_bus_index(SFX_BUS)
		AudioServer.set_bus_mute(sfx, AudioServer.is_bus_mute(idx))

func _process(delta: float) -> void:
	var floor_node := get_tree().get_first_node_in_group("floor_controller")
	if floor_node == null or _sync == null or floor_node.player == null:
		return
	if not _started:
		_music_player.play()
		_started = true
		print("[AudioManager] music started (%d stems)" % STEMS.size())
		_last_level = floor_node.player.level

	_detect_events(floor_node)
	var targets := _layer_targets(floor_node)
	_duck = maxf(0.0, _duck - delta / STING_DUCK_SEC)
	var duck_db := -STING_DUCK_DB * _duck
	for i in STEMS.size():
		var stem: String = STEMS[i]
		_gain[stem] = move_toward(_gain[stem], targets[stem], FADE_SPEED * delta)
		var gain: float = _gain[stem]
		var db: float = -80.0 if gain <= 0.001 else linear_to_db(gain) + float(STEM_TRIM_DB[stem]) + duck_db
		_sync.set_sync_stream_volume(i, db)

## Which layers should be up right now, 0..1 each.
func _layer_targets(floor_node: Node) -> Dictionary:
	if not floor_node.floor_active:
		# Floor over: everything drops away except a thin pad under the stinger
		# and the floor-end toasts (game over silences even that).
		var dead: bool = floor_node.player.hp <= 0.0
		return {"pad": 0.0 if dead else 0.5, "bass": 0.0, "drums": 0.0, "lead": 0.0, "menace": 0.0}

	var threat := _threat(floor_node)
	var enemies := get_tree().get_nodes_in_group("enemies").size()
	var boss := get_tree().get_nodes_in_group("bosses").size() > 0
	var hp_frac: float = floor_node.player.hp / maxf(floor_node.player.max_hp, 1.0)
	# Menace rises with the System AI's threat, with a boss on the field, and as
	# the player nears death (that's the heartbeat).
	var menace := clampf((threat - 0.6) / 0.8, 0.0, 1.0)
	menace = maxf(menace, clampf((0.45 - hp_frac) / 0.25, 0.0, 1.0))
	if boss:
		menace = maxf(menace, 0.9)
	return {
		"pad": 0.9,
		"bass": 1.0,
		"drums": clampf(float(enemies) / 8.0, 0.0, 1.0) if not boss else 1.0,
		"lead": clampf(0.55 + threat * 0.5, 0.0, 1.0),
		"menace": menace,
	}

## Sum of how far each of the director's live numbers sits from neutral,
## normalized per field (same scoring the curator's THREAT_BUDGET uses), so
## ~0 is calm and ~2 is the budget's ceiling.
func _threat(floor_node: Node) -> float:
	if floor_node.director == null:
		return 0.0
	var live: Dictionary = floor_node.director.live
	var total := 0.0
	total += CuratorGenerator._threat_score(live.get("bomb_dodge_chance", 0.0), 0.0, CuratorGenerator.DODGE_CHANCE_RANGE.y)
	total += CuratorGenerator._threat_score(live.get("missile_dodge_chance", 0.0), 0.0, CuratorGenerator.DODGE_CHANCE_RANGE.y)
	total += CuratorGenerator._threat_score(live.get("spawn_interval_multiplier", 1.0), 1.0, CuratorGenerator.SPAWN_INTERVAL_MULT_RANGE.x)
	total += CuratorGenerator._threat_score(live.get("spawn_radius_multiplier", 1.0), 1.0, CuratorGenerator.SPAWN_RADIUS_MULT_RANGE.x)
	total += CuratorGenerator._threat_score(live.get("aggression_multiplier", 1.0), 1.0, CuratorGenerator.AGGRESSION_MULT_RANGE.y)
	return total

func _detect_events(floor_node: Node) -> void:
	var player = floor_node.player
	if player.level > _last_level:
		_play_sting("level_up")
	_last_level = player.level

	var boss_count := get_tree().get_nodes_in_group("bosses").size()
	if boss_count > 0 and _last_boss_count == 0:
		_play_sting("boss")
	_last_boss_count = boss_count

	var active: bool = floor_node.floor_active
	if _last_floor_active and not active:
		_play_sting("game_over" if player.hp <= 0.0 else "floor_clear")
	_last_floor_active = active

func _play_sting(sting: String) -> void:
	var p: AudioStreamPlayer = _stings.get(sting)
	if p == null:
		return
	p.play()
	_duck = 1.0
	print("[AudioManager] sting: %s" % sting)
