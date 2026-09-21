extends RefCounted
class_name AchievementGenerator

## Static utility, same seam as LootGenerator: local rules/fallback text for
## floor-end narrative content, used when the Ollama call fails or returns
## something unusable (see OllamaClient.get_achievement/get_game_over_message).
##
## generate() is only ever called for outcome == "cleared" (see floor.gd's
## _end_floor) — death never awards an achievement, so there's no "collapsed"
## rule here; see generate_game_over_message() for that case instead.

static func generate(run_summary: Dictionary) -> Variant:
	if run_summary.get("damage_taken", 999.0) <= 0.0:
		return {
			"title": "Untouchable",
			"description": "Cleared the floor without taking a single hit.",
			"tone": "heroic",
		}
	if run_summary.get("bombs_thrown", 0) == 0 and run_summary.get("missiles_cast", 0) == 0:
		return {
			"title": "Old Reliable",
			"description": "Cleared the floor on auto-attacks alone — never touched a bomb or missile.",
			"tone": "comedic",
		}
	if run_summary.get("distance_moved", 999.0) < 200.0:
		return {
			"title": "The Statue",
			"description": "Barely moved a muscle the entire floor and still made it out.",
			"tone": "comedic",
		}
	return null

## Local fallback for the "no achievement earned" toast, used only if the
## Ollama call fails/returns invalid — otherwise the LLM's own "message" field
## (see OllamaClient._build_achievement_prompt) is shown instead.
static func generate_no_award_message(run_summary: Dictionary) -> String:
	return "Floor %d cleared. Nothing worth broadcasting this time." % run_summary.get("floor", 0)

## Local fallback for the death/game-over toast (see
## OllamaClient.get_game_over_message) — used only if that call fails.
static func generate_game_over_message(run_summary: Dictionary) -> String:
	return "Floor %d collapsed on top of them. Final score: %d." % [run_summary.get("floor", 0), run_summary.get("points", 0)]
