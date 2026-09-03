extends RefCounted
class_name AchievementGenerator

## Static utility, same seam as LootGenerator: local rules for now, will be
## replaced by an Ollama call summarizing the floor run (see plan.md).

static func generate(run_summary: Dictionary) -> Variant:
	if run_summary.get("damage_taken", 999.0) <= 0.0:
		return {
			"title": "Untouchable",
			"description": "Cleared the floor without taking a single hit.",
			"tone": "heroic",
		}
	if run_summary.get("outcome", "") == "collapsed":
		return {
			"title": "Buried in Rubble",
			"description": "The floor ran out of patience before you did.",
			"tone": "grim",
		}
	return null
