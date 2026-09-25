extends SceneTree

## Headless harness for the System AI's `ai_approach` stability (see plan.md,
## "ai_approach investigation"). Plays a synthetic multi-floor run through the
## real OllamaClient.get_curator_update path — mid-floor + floor-end per floor,
## each cycle fed the previous cycle's result, exactly like floor.gd does — and
## prints how the approach text moves. Scripted contexts vary the play (bomb-
## heavy, laser-heavy, a near-death floor) so a *justified* change has something
## to react to. Set DCC_APPROACH_FLOORS (default 5) to lengthen the run.
##
## Run with:
##   godot --headless --path . --script res://scripts/llm_approach_test.gd

# [bombs, lasers, damage] for a full floor; the mid-floor call sees about half.
const FLOOR_PLAYS := [
	[40, 90, 10.0],
	[45, 95, 12.0],
	[20, 40, 160.0],  # near-death: a real turning point
	[60, 30, 5.0],
	[10, 110, 20.0],
	[35, 70, 8.0],
	[50, 50, 30.0],
	[25, 85, 15.0],
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var ollama := OllamaClient.new()
	root.add_child(ollama)
	var floors_env := OS.get_environment("DCC_APPROACH_FLOORS")
	var floors := mini(int(floors_env) if floors_env != "" else 5, FLOOR_PLAYS.size())

	var profile := CuratorGenerator.DEFAULT_PROFILE.duplicate(true)
	var approaches: Array[String] = []
	var cycles := 0
	var changes := 0
	for f in floors:
		var play: Array = FLOOR_PLAYS[f]
		for phase in ["mid_floor", "floor_end"]:
			var share := 0.5 if phase == "mid_floor" else 1.0
			var context := {
				"floor": f + 1,
				"phase": phase,
				"outcome": "cleared" if phase == "floor_end" else "",
				"points_this_floor": int(600 * share),
				"damage_taken_this_floor": float(play[2]) * share,
				"distance_moved": 3000.0 * share,
				"bombs_thrown": int(play[0] * share),
				"missiles_cast": int(play[1] * share),
			}
			var before: String = str(profile.get("ai_approach", ""))
			profile = await ollama.get_curator_update(context, profile)
			var after: String = str(profile.get("ai_approach", ""))
			cycles += 1
			var changed := cycles > 1 and after != before
			if changed:
				changes += 1
			approaches.append(after)
			print("[approach] f%d %-9s tactic=%-13s %s | %s" % [f + 1, phase, profile.get("tactic"), "CHANGED" if changed else ("set    " if cycles == 1 else "kept   "), after])
	print("[approach] SUMMARY cycles=%d changes_after_first=%d/%d distinct=%d" % [cycles, changes, cycles - 1, _distinct(approaches)])
	quit()

func _distinct(items: Array[String]) -> int:
	var seen := {}
	for s in items:
		seen[s] = true
	return seen.size()
