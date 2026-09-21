extends Node
class_name SystemDirector

## The System AI's moment-to-moment hand on the floor. The curator (twice per
## floor) sets the standing strategy and narrative; this node lets the same AI
## adjust the fight every second. It works by asking the LLM for a short plan
## of per-second "beats" (see OllamaClient.get_director_plan), playing one beat
## per second, and requesting the next plan *before* the current one runs out
## so plans chain without gaps despite multi-second model latency. What the
## beats contain is entirely the LLM's decision; this node only schedules
## them, eases the live numbers toward each beat (so per-second steps don't
## snap), and falls back to the curator's standing numbers when no fresh plan
## exists (Ollama down/slow). See plan.md's "Live director" section.

const BEAT_SEC := 1.0
# Ask for the next plan once this many beats (or fewer) of the current one
# remain — roughly one model round-trip's worth, so the new plan lands about
# when the old one ends.
const PREFETCH_BEATS_REMAINING := 3.0
# If the next plan is late, keep the last beat going this long before easing
# back to the curator's standing numbers.
const HOLD_LAST_BEAT_SEC := 4.0
# Exponential approach rate (per second) of the live numbers toward the
# current beat's targets.
const SMOOTH_RATE := 4.0
const RETRY_BASE_SEC := 1.0
const RETRY_MAX_SEC := 15.0

var floor_node: Node
## The numbers currently in force (smoothed) — floor.gd merges these over the
## curator profile in get_effective_profile().
var live := {}
var current_tactic := "none"

var _plan: Array = []
var _plan_age := 0.0
var _request_in_flight := false
var _retry_cooldown := 0.0
var _fail_streak := 0
var _generation := 0  # bumped by reset() so a response from a previous floor is dropped
var _last_snapshot := {}
var _last_beat := {}

func _ready() -> void:
	var baseline := _baseline_targets()
	for field in DirectorGenerator.BEAT_FIELDS:
		live[field] = baseline[field]

## Called at the start of each floor: drop the old plan (it was written about a
## different floor) and let the live numbers ease back to the curator's.
func reset() -> void:
	_generation += 1
	_plan = []
	_plan_age = 0.0
	_last_snapshot = {}
	_last_beat = {}
	_retry_cooldown = 0.0
	_fail_streak = 0

func _process(delta: float) -> void:
	if floor_node == null or not floor_node.floor_active:
		return

	var target := _current_target()
	current_tactic = str(target.get("tactic", "none"))
	var blend := 1.0 - exp(-SMOOTH_RATE * delta)
	for field in DirectorGenerator.BEAT_FIELDS:
		live[field] = lerpf(live[field], target[field], blend)
	if not _plan.is_empty():
		_plan_age += delta
	_retry_cooldown = maxf(0.0, _retry_cooldown - delta)

	# Stay out of the way of the curator's own (larger, once-per-half-floor)
	# call so the two don't queue behind each other on the local Ollama.
	if _request_in_flight or _retry_cooldown > 0.0 or floor_node._curator_busy:
		return
	var beats_remaining := float(_plan.size()) - _plan_age / BEAT_SEC
	if _plan.is_empty() or beats_remaining <= PREFETCH_BEATS_REMAINING:
		_request_plan()

## The beat to ease toward right now: the plan's current beat, the last beat
## held briefly if the next plan is late, else the curator's standing numbers.
func _current_target() -> Dictionary:
	if not _plan.is_empty():
		var index := int(_plan_age / BEAT_SEC)
		if index < _plan.size():
			_last_beat = _plan[index]
			return _last_beat
		if _plan_age < _plan.size() * BEAT_SEC + HOLD_LAST_BEAT_SEC:
			return _plan[_plan.size() - 1]
		_plan = []  # stale: fall through to the standing numbers
	return _baseline_targets()

func _baseline_targets() -> Dictionary:
	var baseline := {"tactic": "none"}
	var profile: Dictionary = floor_node.character_profile if floor_node else CuratorGenerator.DEFAULT_PROFILE
	for field in DirectorGenerator.BEAT_FIELDS:
		baseline[field] = profile.get(field, CuratorGenerator.DEFAULT_PROFILE[field])
	baseline["tactic"] = profile.get("tactic", "none")
	return baseline

## Fire-and-forget (same pattern as floor.gd's curator call): awaits the model
## without blocking _process.
func _request_plan() -> void:
	_request_in_flight = true
	var generation := _generation
	var context := _build_context()
	var plan: Array = await floor_node.ollama.get_director_plan(context, floor_node.character_profile)
	_request_in_flight = false
	if generation != _generation:
		return  # a new floor started while this was in flight
	if plan.is_empty():
		_fail_streak += 1
		_retry_cooldown = minf(RETRY_BASE_SEC * pow(2.0, _fail_streak - 1), RETRY_MAX_SEC)
		return
	_fail_streak = 0
	# The new plan starts *now* (beat 0 plays on arrival) and replaces whatever
	# was left of the old one — the latest read on the fight wins.
	_plan = plan
	_plan_age = 0.0

## Live telemetry for the model: current state plus what changed since the
## previous request (deltas — cheap, and more informative than raw totals).
func _build_context() -> Dictionary:
	var player: Player = floor_node.player
	var now := {
		"points": floor_node.floor_points,
		"damage": floor_node.floor_damage_taken,
		"bombs": player.floor_bombs_thrown,
		"missiles": player.floor_missiles_cast,
		"distance": player.floor_distance_moved,
		"clock": Time.get_ticks_msec() / 1000.0,
	}
	var context := {
		"floor": floor_node.current_floor,
		"seconds_left": floor_node.time_remaining,
		"hp": player.hp,
		"max_hp": player.max_hp,
		"enemies": get_tree().get_nodes_in_group("enemies").size(),
		"bosses": get_tree().get_nodes_in_group("bosses").size(),
		"previous_beat": JSON.stringify(_last_beat) if not _last_beat.is_empty() else "",
	}
	# First look of a floor: everything counts, back to the floor's start.
	var elapsed: float = floor_node.floor_duration - floor_node.time_remaining
	var before: Dictionary = _last_snapshot if not _last_snapshot.is_empty() else {"points": 0, "damage": 0.0, "bombs": 0, "missiles": 0, "distance": 0.0, "clock": now["clock"] - elapsed}
	context["points_delta"] = now["points"] - before["points"]
	context["damage_delta"] = now["damage"] - before["damage"]
	context["bombs_delta"] = now["bombs"] - before["bombs"]
	context["missiles_delta"] = now["missiles"] - before["missiles"]
	context["distance_delta"] = now["distance"] - before["distance"]
	context["window_sec"] = now["clock"] - before["clock"]
	_last_snapshot = now
	return context
