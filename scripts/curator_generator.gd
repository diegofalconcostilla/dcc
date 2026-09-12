extends RefCounted
class_name CuratorGenerator

## Static utility, same seam as LootGenerator/AchievementGenerator: validates
## and clamps the "System AI"'s output — a running character profile (for
## loot/achievement flavor consistency) PLUS a live tactical decision against
## the player, both of which replace themselves each cycle (never grow).
## The System AI is the in-fiction antagonist (see plan.md's Concept section)
## — it watches Carl/Donut's habits and picks a tactic meant to counter
## whichever attack they've leaned on, using dedicated numeric fields it
## controls directly. Code only clamps those fields into safe ranges — it
## never computes them from a formula; the adaptation itself is the LLM's
## call. `ai_approach` is the one field meant to stay stable across many
## cycles rather than being freely re-picked each time — the model's own
## self-chosen long-term strategy for the run (see plan.md's "Long-term
## direction" section), which it's prompted to preserve unless it decides a
## real turning point justifies changing it. See plan.md's "Long-term
## direction" and "Combat abilities" sections.

const ALLOWED_RISK_PROFILES := ["reckless", "balanced", "cautious"]
const ALLOWED_DOMINANT_ABILITIES := ["bomb", "missile", "auto_attack", "balanced"]
const ALLOWED_TONES := ["heroic", "comedic", "grim", "chaotic"]
const ALLOWED_TACTICS := ["none", "ambush", "swarm", "counter_bomb", "counter_laser", "aggression", "early_boss"]

const MAX_TAGS := 3
const MAX_NOTABLE_MOMENTS := 3
const TAG_MAX_LEN := 24
const SUMMARY_MAX_LEN := 140
const NARRATIVE_MAX_LEN := 200
const MOMENT_MAX_LEN := 80
const COMMENTARY_MAX_LEN := 140
const APPROACH_MAX_LEN := 160

# Safety ranges for the System AI's tactical numbers — it picks the value
# within these bounds, code just clamps rather than trusting raw output for
# balance (same discipline as LootGenerator's power budget).
const DODGE_CHANCE_RANGE := Vector2(0.0, 0.6)
const SPAWN_INTERVAL_MULT_RANGE := Vector2(0.3, 1.0)   # lower = faster spawns
const SPAWN_RADIUS_MULT_RANGE := Vector2(0.3, 1.0)     # lower = enemies land closer (ambush)
const AGGRESSION_MULT_RANGE := Vector2(1.0, 1.6)       # enemy speed & contact damage
const BOSS_THRESHOLD_MULT_RANGE := Vector2(0.3, 1.0)   # lower = next boss arrives sooner
const LOOT_GENEROSITY_RANGE := Vector2(0.7, 1.4)       # lower = easier to hit a high loot tier (generous), higher = stingier

# Aggregate safety net across the six combat-difficulty fields (the two dodge
# chances, spawn interval/radius, aggression, boss threshold — everything
# EXCEPT loot_generosity_multiplier, which isn't a difficulty lever). Each
# field's clamped value contributes a normalized 0-1 "threat" score (0 =
# neutral, 1 = the field maxed out at its extreme). THREAT_BUDGET == 2.0
# matches the prompt's own instruction to push only the one or two numbers
# relevant to the chosen tactic and leave the rest neutral — a compliant
# response never gets touched by this. It only kicks in if the model ignores
# that instruction and cranks several levers at once (a real risk with the
# local 3B model — plan.md notes it doing exactly this in one observed run),
# scaling every field's deviation from neutral down proportionally, same
# discipline as LootGenerator scaling down an over-budget item's effects
# rather than rejecting the response outright.
const THREAT_BUDGET := 2.0

const DEFAULT_PROFILE := {
	"playstyle_tags": [],
	"risk_profile": "balanced",
	"dominant_ability": "balanced",
	"combat_style_summary": "",
	"narrative_arc": "",
	"notable_moments": [],
	"tone": "comedic",
	"tactic": "none",
	"bomb_dodge_chance": 0.0,
	"missile_dodge_chance": 0.0,
	"spawn_interval_multiplier": 1.0,
	"spawn_radius_multiplier": 1.0,
	"aggression_multiplier": 1.0,
	"boss_threshold_multiplier": 1.0,
	"loot_generosity_multiplier": 1.0,
	"ai_commentary": "",
	"ai_approach": "",
}

## Validates and clamps a raw (untrusted, possibly LLM-generated) profile.
## Returns {} if it's unusable (caller should keep the previous profile).
static func validate_and_clamp(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}

	var risk_profile: String = str(raw.get("risk_profile", ""))
	if not (risk_profile in ALLOWED_RISK_PROFILES):
		risk_profile = DEFAULT_PROFILE["risk_profile"]

	var dominant_ability: String = str(raw.get("dominant_ability", ""))
	if not (dominant_ability in ALLOWED_DOMINANT_ABILITIES):
		dominant_ability = DEFAULT_PROFILE["dominant_ability"]

	var tone: String = str(raw.get("tone", ""))
	if not (tone in ALLOWED_TONES):
		tone = DEFAULT_PROFILE["tone"]

	var tactic: String = str(raw.get("tactic", ""))
	if not (tactic in ALLOWED_TACTICS):
		tactic = DEFAULT_PROFILE["tactic"]

	var combat_style_summary: String = str(raw.get("combat_style_summary", "")).left(SUMMARY_MAX_LEN).strip_edges()
	var narrative_arc: String = str(raw.get("narrative_arc", "")).left(NARRATIVE_MAX_LEN).strip_edges()
	var ai_commentary: String = str(raw.get("ai_commentary", "")).left(COMMENTARY_MAX_LEN).strip_edges()
	var ai_approach: String = str(raw.get("ai_approach", "")).left(APPROACH_MAX_LEN).strip_edges()

	var tags := []
	var raw_tags = raw.get("playstyle_tags", [])
	if typeof(raw_tags) == TYPE_ARRAY:
		for t in raw_tags:
			if tags.size() >= MAX_TAGS:
				break
			var tag: String = str(t).left(TAG_MAX_LEN).strip_edges()
			if tag != "":
				tags.append(tag)

	var moments := []
	var raw_moments = raw.get("notable_moments", [])
	if typeof(raw_moments) == TYPE_ARRAY:
		for m in raw_moments:
			if moments.size() >= MAX_NOTABLE_MOMENTS:
				break
			var moment: String = str(m).left(MOMENT_MAX_LEN).strip_edges()
			if moment != "":
				moments.append(moment)

	# Each entry: [clamped value, neutral value, extreme value at full threat].
	var threat_fields := {
		"bomb_dodge_chance": [_clamp_field(raw.get("bomb_dodge_chance"), DODGE_CHANCE_RANGE, DEFAULT_PROFILE["bomb_dodge_chance"]), 0.0, DODGE_CHANCE_RANGE.y],
		"missile_dodge_chance": [_clamp_field(raw.get("missile_dodge_chance"), DODGE_CHANCE_RANGE, DEFAULT_PROFILE["missile_dodge_chance"]), 0.0, DODGE_CHANCE_RANGE.y],
		"spawn_interval_multiplier": [_clamp_field(raw.get("spawn_interval_multiplier"), SPAWN_INTERVAL_MULT_RANGE, DEFAULT_PROFILE["spawn_interval_multiplier"]), 1.0, SPAWN_INTERVAL_MULT_RANGE.x],
		"spawn_radius_multiplier": [_clamp_field(raw.get("spawn_radius_multiplier"), SPAWN_RADIUS_MULT_RANGE, DEFAULT_PROFILE["spawn_radius_multiplier"]), 1.0, SPAWN_RADIUS_MULT_RANGE.x],
		"aggression_multiplier": [_clamp_field(raw.get("aggression_multiplier"), AGGRESSION_MULT_RANGE, DEFAULT_PROFILE["aggression_multiplier"]), 1.0, AGGRESSION_MULT_RANGE.y],
		"boss_threshold_multiplier": [_clamp_field(raw.get("boss_threshold_multiplier"), BOSS_THRESHOLD_MULT_RANGE, DEFAULT_PROFILE["boss_threshold_multiplier"]), 1.0, BOSS_THRESHOLD_MULT_RANGE.x],
	}

	var total_threat := 0.0
	for key in threat_fields:
		var f: Array = threat_fields[key]
		total_threat += _threat_score(f[0], f[1], f[2])

	if total_threat > THREAT_BUDGET:
		var scale: float = THREAT_BUDGET / total_threat
		for key in threat_fields:
			var f: Array = threat_fields[key]
			threat_fields[key][0] = f[1] + (f[0] - f[1]) * scale

	return {
		"playstyle_tags": tags,
		"risk_profile": risk_profile,
		"dominant_ability": dominant_ability,
		"combat_style_summary": combat_style_summary,
		"narrative_arc": narrative_arc,
		"notable_moments": moments,
		"tone": tone,
		"tactic": tactic,
		"bomb_dodge_chance": threat_fields["bomb_dodge_chance"][0],
		"missile_dodge_chance": threat_fields["missile_dodge_chance"][0],
		"spawn_interval_multiplier": threat_fields["spawn_interval_multiplier"][0],
		"spawn_radius_multiplier": threat_fields["spawn_radius_multiplier"][0],
		"aggression_multiplier": threat_fields["aggression_multiplier"][0],
		"boss_threshold_multiplier": threat_fields["boss_threshold_multiplier"][0],
		"loot_generosity_multiplier": _clamp_field(raw.get("loot_generosity_multiplier"), LOOT_GENEROSITY_RANGE, DEFAULT_PROFILE["loot_generosity_multiplier"]),
		"ai_commentary": ai_commentary,
		"ai_approach": ai_approach,
	}

## Clamps one untrusted numeric field into [range.x, range.y], or returns
## `fallback` (a neutral, no-op value) if it's missing/not a number.
static func _clamp_field(raw_value: Variant, range: Vector2, fallback: float) -> float:
	if not (raw_value is float or raw_value is int):
		return fallback
	return clampf(float(raw_value), range.x, range.y)

## Normalizes how far `value` sits from `neutral` toward `extreme` into 0-1
## (0 = neutral, 1 = fully at the extreme) — see THREAT_BUDGET above.
static func _threat_score(value: float, neutral: float, extreme: float) -> float:
	if is_equal_approx(extreme, neutral):
		return 0.0
	return absf(value - neutral) / absf(extreme - neutral)
