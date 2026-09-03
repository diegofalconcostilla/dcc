extends RefCounted
class_name LootGenerator

## Static utility: computes loot tier from run performance, generates the
## local-fallback loot table, and validates/clamps LLM-generated loot before
## it's trusted (see OllamaClient, which calls validate_and_clamp() on the
## raw model output and falls back to generate_loot() if it doesn't pass).

const ALLOWED_SLOTS := ["weapon", "armor", "trinket", "consumable"]
const ALLOWED_STATS := ["damage", "attack_speed", "crit_chance", "max_hp", "range"]

const TIER_POWER_BUDGET := {
	"common": 4,
	"uncommon": 7,
	"rare": 12,
	"epic": 18,
	"legendary": 26,
}

# How much of a tier's power budget one unit of each stat "costs" — used to
# normalize/clamp LLM-proposed effects against the tier budget. Placeholder
# weights pending real playtesting.
const STAT_COST := {
	"damage": 1.0,        # 1 damage = 1 power
	"attack_speed": 40.0, # 0.1 (10%) attack speed = 4 power
	"crit_chance": 60.0,  # 0.1 (10%) crit chance = 6 power
	"max_hp": 0.5,         # 10 max hp = 5 power
	"range": 0.3,          # 20 range = 6 power
}

const FALLBACK_ITEMS := {
	"common": [
		{"name": "Dented Shiv", "flavor_text": "Barely sharper than a butter knife.", "slot": "weapon", "effects": [{"stat": "damage", "value": 2}]},
		{"name": "Patched Vest", "flavor_text": "Smells like the last guy who wore it.", "slot": "armor", "effects": [{"stat": "max_hp", "value": 10}]},
	],
	"uncommon": [
		{"name": "Serrated Cleaver", "flavor_text": "Leaves a mess. On purpose.", "slot": "weapon", "effects": [{"stat": "damage", "value": 4}, {"stat": "attack_speed", "value": 0.05}, {"stat": "range", "value": 15}]},
	],
	"rare": [
		{"name": "Voidglass Dagger", "flavor_text": "Hums faintly when enemies are near.", "slot": "weapon", "effects": [{"stat": "damage", "value": 8}, {"stat": "crit_chance", "value": 0.05}, {"stat": "range", "value": 20}]},
	],
	"epic": [
		{"name": "Syndicate Prototype Blade", "flavor_text": "Not FDA approved for interdimensional use.", "slot": "weapon", "effects": [{"stat": "damage", "value": 14}, {"stat": "attack_speed", "value": 0.1}, {"stat": "range", "value": 25}]},
	],
	"legendary": [
		{"name": "Odette's Favorite", "flavor_text": "The audience is going wild.", "slot": "weapon", "effects": [{"stat": "damage", "value": 22}, {"stat": "crit_chance", "value": 0.1}, {"stat": "attack_speed", "value": 0.15}, {"stat": "range", "value": 30}]},
	],
}

# Performance -> tier. Thresholds are placeholders pending real playtesting data.
static func compute_tier(points: int, damage_taken: float) -> String:
	var score := float(points) - damage_taken * 2.0
	if score < 50:
		return "common"
	elif score < 150:
		return "uncommon"
	elif score < 350:
		return "rare"
	elif score < 700:
		return "epic"
	else:
		return "legendary"

static func generate_loot(tier: String, _context: Dictionary) -> Dictionary:
	var pool: Array = FALLBACK_ITEMS.get(tier, FALLBACK_ITEMS["common"])
	return pool[randi() % pool.size()]

## Validates and clamps a raw (untrusted, possibly LLM-generated) loot dictionary.
## Returns {} if it's unusable (caller should fall back to generate_loot()).
static func validate_and_clamp(raw: Variant, tier: String) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}

	var name: String = str(raw.get("name", "")).left(40).strip_edges()
	var flavor_text: String = str(raw.get("flavor_text", "")).left(140).strip_edges()
	var slot: String = str(raw.get("slot", ""))
	if name == "" or not (slot in ALLOWED_SLOTS):
		return {}

	var raw_effects = raw.get("effects", [])
	if typeof(raw_effects) != TYPE_ARRAY:
		return {}

	var effects := []
	var total_power := 0.0
	for e in raw_effects:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var stat: String = str(e.get("stat", ""))
		if not (stat in ALLOWED_STATS):
			continue
		var raw_value = e.get("value", 0)
		if not (raw_value is float or raw_value is int):
			continue
		var value: float = float(raw_value)
		if value <= 0.0:
			continue
		effects.append({"stat": stat, "value": value})
		total_power += value * STAT_COST.get(stat, 1.0)

	if effects.is_empty():
		return {}

	var budget: float = TIER_POWER_BUDGET.get(tier, 4)
	if total_power > budget * 1.15:
		var scale: float = (budget * 1.15) / total_power
		for e in effects:
			e["value"] *= scale

	return {"name": name, "flavor_text": flavor_text, "slot": slot, "effects": effects}
