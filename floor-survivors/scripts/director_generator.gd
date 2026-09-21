extends RefCounted
class_name DirectorGenerator

## Static utility, same seam as CuratorGenerator: validates and clamps the
## System AI's live "director" output — a short plan of per-second beats, each
## a tactic label plus the same tactical numbers the curator sets. The curator
## sets the standing strategy twice per floor; the director steers the fight
## moment to moment (see plan.md's "Live director" section). Code only clamps
## (via CuratorGenerator.clamp_tactics, so beats get the same ranges and joint
## threat budget as the curator's numbers) — the pacing itself is the LLM's call.

const BEAT_COUNT := 6

# Fields a beat controls. boss_threshold_multiplier is deliberately absent — it
# counts kills, so it's meaningless at per-second granularity and stays with
# the curator.
const BEAT_FIELDS := [
	"bomb_dodge_chance",
	"missile_dodge_chance",
	"spawn_interval_multiplier",
	"spawn_radius_multiplier",
	"aggression_multiplier",
]

## Returns an Array of beat Dictionaries ({"tactic": String, plus BEAT_FIELDS
## as floats}), at most BEAT_COUNT long. [] if the response is unusable
## (caller keeps whatever it was playing).
static func validate_plan(raw: Variant) -> Array:
	if typeof(raw) != TYPE_DICTIONARY:
		return []
	var raw_beats: Variant = raw.get("beats")
	if typeof(raw_beats) != TYPE_ARRAY:
		return []

	var plan := []
	for raw_beat in raw_beats:
		if plan.size() >= BEAT_COUNT:
			break
		if typeof(raw_beat) != TYPE_DICTIONARY:
			continue
		var tactic: String = str(raw_beat.get("tactic", ""))
		if not (tactic in CuratorGenerator.ALLOWED_TACTICS):
			tactic = "none"
		var tactics := CuratorGenerator.clamp_tactics(raw_beat)
		var beat := {"tactic": tactic}
		for field in BEAT_FIELDS:
			beat[field] = tactics[field]
		plan.append(beat)
	return plan
