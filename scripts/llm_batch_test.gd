extends SceneTree

## Headless batch-test harness for the LLM content pipeline. Sweeps a matrix
## of synthetic floor contexts against the local Ollama server directly
## (bypassing real gameplay) so many loot/achievement samples can be
## generated quickly and reviewed for quality via ContentLogger's output
## under res://logs/. Every call goes through the same OllamaClient code
## path as a real run, so fallback/validation behavior is exercised too.
##
## Run with:
##   godot --headless --path . --script res://scripts/llm_batch_test.gd

const TIERS := ["common", "uncommon", "rare", "epic", "legendary"]
const FLOORS := [1, 5, 10]
const ACHIEVEMENT_DAMAGE_SAMPLES := [0.0, 40.0]
const ACHIEVEMENT_OUTCOMES := ["cleared", "collapsed"]

const TIER_POINTS := {
	"common": 20,
	"uncommon": 100,
	"rare": 250,
	"epic": 500,
	"legendary": 900,
}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var ollama := OllamaClient.new()
	root.add_child(ollama)

	var loot_total := FLOORS.size() * TIERS.size()
	var loot_done := 0
	for floor_num in FLOORS:
		for tier in TIERS:
			loot_done += 1
			print("[batch] loot %d/%d: floor=%d tier=%s" % [loot_done, loot_total, floor_num, tier])
			await ollama.get_loot(tier, {
				"floor": floor_num,
				"points_this_floor": TIER_POINTS[tier],
				"damage_taken_this_floor": 20.0,
			})

	var ach_total := FLOORS.size() * ACHIEVEMENT_OUTCOMES.size() * ACHIEVEMENT_DAMAGE_SAMPLES.size()
	var ach_done := 0
	for floor_num in FLOORS:
		for outcome in ACHIEVEMENT_OUTCOMES:
			for damage in ACHIEVEMENT_DAMAGE_SAMPLES:
				ach_done += 1
				print("[batch] achievement %d/%d: floor=%d outcome=%s damage=%.0f" % [ach_done, ach_total, floor_num, outcome, damage])
				await ollama.get_achievement({
					"floor": floor_num,
					"outcome": outcome,
					"points": 200,
					"damage_taken": damage,
				})

	print("[batch] done — see res://logs/ for the JSONL output")
	quit()
