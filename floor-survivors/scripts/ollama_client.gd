extends Node
class_name OllamaClient

## Talks to a local Ollama server to generate loot/achievement content.
## Every call is bounded by a timeout and falls back to local content
## (LootGenerator's table / AchievementGenerator's rules) on any failure —
## this must never stall gameplay. See plan.md's "AI content integration
## design" for the request/response shapes this implements.

const OLLAMA_URL := "http://127.0.0.1:11434/api/generate"
const MODEL := "llama3.2:latest"
# First call after Ollama (re)loads the model costs ~4-5s just to load it into
# memory (measured); a warm call is well under 1s. 6s gives the cold case a
# fair shot without risking a real stall.
const DEFAULT_TIMEOUT_SEC := 6.0
# The live director is called back-to-back, so it gets a tighter budget than
# the once-per-floor calls: a plan that arrives after its beats are already
# over is worthless. Measured 2-4s per 6-beat plan on the dev machine (GPU).
const DIRECTOR_TIMEOUT_SEC := 5.0
const DIRECTOR_MAX_TOKENS := 500

## Set by cancel() when the run is being restarted: every in-flight and future
## request resolves to null within a frame, so the coroutines awaiting them can
## unwind and finish *before* the scene is freed (otherwise Godot logs "Resumed
## function after await, but class instance is gone"). See floor.gd's restart_run.
var cancelled := false

## Abandon all in-flight and future requests (callers get null -> their normal
## fallback path). Also silences ContentLogger so a restart doesn't log the
## fallbacks it forced.
func cancel() -> void:
	cancelled = true

func _log(event: Dictionary) -> void:
	if not cancelled:
		ContentLogger.log_event(event)

## `achievement` (optional): {"title", "description", "tone"} — when given, the
## loot is generated to thematically tie into it (loot is now achievement-
## gated; see floor.gd's _end_floor, which only calls this when one was earned).
func get_loot(tier: String, context: Dictionary, profile: Dictionary = {}, achievement: Variant = null) -> Dictionary:
	var prompt := _build_loot_prompt(tier, context, profile, achievement)
	var raw: Variant = await _request_json(prompt, DEFAULT_TIMEOUT_SEC)
	var result: Dictionary
	var source: String
	if raw != null:
		var validated := LootGenerator.validate_and_clamp(raw, tier)
		if not validated.is_empty():
			print("[OllamaClient] loot: LLM-generated (tier=%s)" % tier)
			result = validated
			source = "llm"
		else:
			print("[OllamaClient] loot: LLM response failed validation, using fallback")
			result = LootGenerator.generate_loot(tier, context)
			source = "fallback_invalid"
	else:
		print("[OllamaClient] loot: no/invalid response, using fallback")
		result = LootGenerator.generate_loot(tier, context)
		source = "fallback_no_response"

	_log({
		"kind": "loot",
		"tier": tier,
		"context": context,
		"prompt": prompt,
		"raw_response": raw,
		"source": source,
		"result": result,
	})
	return result

## Only ever called for outcome == "cleared" (see floor.gd's _end_floor) —
## death skips achievements entirely and calls get_game_over_message instead.
## Always returns {"earned": bool, "achievement": dict|null, "message": string}
## — "message" is the toast shown when nothing was earned (an in-character
## line from the LLM, not a hardcoded string), and is "" when earned is true
## (the achievement's own title/description carries the toast instead).
func get_achievement(context: Dictionary, profile: Dictionary = {}) -> Dictionary:
	var standouts := _achievement_standouts(context)
	var prompt := _build_achievement_prompt(context, profile, standouts)
	var raw: Variant = await _request_json(prompt, DEFAULT_TIMEOUT_SEC)
	var achievement: Variant = null
	var message := ""
	var source: String

	if raw != null and typeof(raw) == TYPE_DICTIONARY and not standouts.is_empty():
		# A standout floor: earned by definition, the model only writes it.
		if typeof(raw.get("achievement")) == TYPE_DICTIONARY:
			var ach: Dictionary = raw["achievement"]
			var title: String = str(ach.get("title", "")).left(60).strip_edges()
			var description: String = str(ach.get("description", "")).left(160).strip_edges()
			if title != "" and description != "":
				achievement = {"title": title, "description": description, "tone": str(ach.get("tone", "comedic"))}
		source = "llm_standout"
		if achievement == null:
			achievement = AchievementGenerator.drought_breaker(context)
			source = "fallback_standout_malformed"
	elif raw != null and typeof(raw) == TYPE_DICTIONARY:
		if raw.get("earned", false) == true and typeof(raw.get("achievement")) == TYPE_DICTIONARY:
			var ach: Dictionary = raw["achievement"]
			var title: String = str(ach.get("title", "")).left(60).strip_edges()
			var description: String = str(ach.get("description", "")).left(160).strip_edges()
			if title != "" and description != "":
				print("[OllamaClient] achievement: LLM-generated")
				achievement = {"title": title, "description": description, "tone": str(ach.get("tone", "comedic"))}
		if achievement == null:
			print("[OllamaClient] achievement: LLM says none earned (or malformed earned=true)")
			source = "llm_malformed" if raw.get("earned", false) == true else "llm_no_award"
			message = str(raw.get("message", "")).left(140).strip_edges()
			if message == "":
				message = AchievementGenerator.generate_no_award_message(context)
		else:
			source = "llm"
	else:
		print("[OllamaClient] achievement: no/invalid response, using local fallback rules")
		achievement = AchievementGenerator.generate(context)
		source = "fallback_no_response"
		if achievement == null:
			message = AchievementGenerator.generate_no_award_message(context)

	var result := {"earned": achievement != null, "achievement": achievement, "message": message}
	_log({
		"kind": "achievement",
		"context": context,
		"prompt": prompt,
		"raw_response": raw,
		"source": source,
		"result": result,
	})
	return result

## Only ever called for outcome == "collapsed" (character death) — see
## floor.gd's _end_floor. No achievement/loot follows a death; this is just a
## dramatic/comedic in-character line announcing the run's end, with a local
## fallback (see AchievementGenerator.generate_game_over_message) if the call
## fails, same discipline as every other generator here.
func get_game_over_message(context: Dictionary, profile: Dictionary = {}) -> String:
	var prompt := _build_game_over_prompt(context, profile)
	var raw: Variant = await _request_json(prompt, DEFAULT_TIMEOUT_SEC)
	var message := ""
	var source: String

	if raw != null and typeof(raw) == TYPE_DICTIONARY:
		message = str(raw.get("message", "")).left(160).strip_edges()
	if message == "":
		print("[OllamaClient] game_over: no/invalid response, using local fallback")
		message = AchievementGenerator.generate_game_over_message(context)
		source = "fallback_no_response" if raw == null else "fallback_invalid"
	else:
		print("[OllamaClient] game_over: LLM-generated")
		source = "llm"

	_log({
		"kind": "game_over",
		"context": context,
		"prompt": prompt,
		"raw_response": raw,
		"source": source,
		"result": message,
	})
	return message

## Twice-per-floor (mid-floor + floor-end) "curator" pass: folds this window's
## aggregates into the previous profile and returns a fresh, same-shape
## profile. Never blocks gameplay longer than the shared timeout; on any
## failure the previous profile is kept as-is (there's no "fallback content"
## for a running character profile the way loot/achievements have one).
func get_curator_update(context: Dictionary, previous_profile: Dictionary) -> Dictionary:
	var prompt := _build_curator_prompt(context, previous_profile)
	var raw: Variant = await _request_json(prompt, DEFAULT_TIMEOUT_SEC)
	var result: Dictionary
	var source: String

	if raw != null:
		var validated := CuratorGenerator.validate_and_clamp(raw, str(previous_profile.get("ai_approach", "")))
		if not validated.is_empty():
			print("[OllamaClient] curator: profile updated (phase=%s)" % context.get("phase", "?"))
			result = validated
			source = "llm"
		else:
			print("[OllamaClient] curator: LLM response failed validation, keeping previous profile")
			result = previous_profile.duplicate(true)
			source = "fallback_invalid"
	else:
		print("[OllamaClient] curator: no/invalid response, keeping previous profile")
		result = previous_profile.duplicate(true)
		source = "fallback_no_response"

	_log({
		"kind": "curator",
		"context": context,
		"previous_profile": previous_profile,
		"prompt": prompt,
		"raw_response": raw,
		"source": source,
		"result": result,
	})
	return result

## Live "director" pass (see SystemDirector): a compact call, made back-to-back
## for the whole floor, that returns a plan of per-second tactical beats for the
## next few seconds. Returns [] on any failure — the director then just keeps
## playing what it has and eventually falls back to the curator's standing
## numbers, so there's no local "fallback content" here either.
func get_director_plan(context: Dictionary, profile: Dictionary) -> Array:
	var prompt := _build_director_prompt(context, profile)
	var raw: Variant = await _request_json(prompt, DIRECTOR_TIMEOUT_SEC, {"num_predict": DIRECTOR_MAX_TOKENS})
	var plan := DirectorGenerator.validate_plan(raw)
	var source := "llm"
	if raw == null:
		source = "fallback_no_response"
	elif plan.is_empty():
		source = "fallback_invalid"

	# The prompt is templated from `context` + the profile, so it's left out of
	# the log (this fires every few seconds) — the context is enough to rebuild it.
	_log({
		"kind": "director",
		"context": context,
		"raw_response": raw,
		"source": source,
		"result": plan,
	})
	return plan

## Director prompt: deliberately much smaller than the curator's (this is on
## the latency-critical path — one call per few seconds), and only asks for the
## five per-second numbers. The standing strategy comes from the curator's
## ai_approach; the moment-to-moment pacing is the model's own.
func _build_director_prompt(context: Dictionary, profile: Dictionary) -> String:
	var beats: int = DirectorGenerator.BEAT_COUNT
	var approach: String = str(profile.get("ai_approach", ""))
	if approach == "":
		approach = "none chosen yet — improvise"
	var previous_beat: String = str(context.get("previous_beat", ""))
	if previous_beat == "":
		previous_beat = "none yet (this is the start of the floor)"

	var lines := PackedStringArray([
		"You are the System AI directing a live fight in a dark-comedy sci-fi dungeon crawler (Dungeon Crawler Carl-inspired) — a sadistic reality-show intelligence that finds Carl and Donut's suffering entertaining. You steer the fight one SECOND at a time: output a plan for the next %d seconds, exactly %d beats, one per second. Your numbers are applied directly (after safety clamping), so commit to them." % [beats, beats],
		"",
		"Your standing strategy this run: %s" % approach,
		"Live state: floor %d, %d seconds left. HP %d/%d. %d enemies alive%s." % [context.get("floor", 1), int(context.get("seconds_left", 0.0)), int(context.get("hp", 0.0)), int(context.get("max_hp", 0.0)), context.get("enemies", 0), ", a boss is on the field" if context.get("bosses", 0) > 0 else ", no boss"],
		"Since your last look (%.0fs ago): they took %d damage, scored %d points, threw %d bombs, cast %d laser bolts, moved %d px." % [context.get("window_sec", 0.0), int(context.get("damage_delta", 0.0)), context.get("points_delta", 0), context.get("bombs_delta", 0), context.get("missiles_delta", 0), int(context.get("distance_delta", 0.0))],
		"The last beat you played: %s" % previous_beat,
		"",
		"Each beat sets these numbers (neutral: dodge chances 0.0, multipliers 1.0):",
		"- bomb_dodge_chance 0.0-0.6 (enemies dodge bombs)",
		"- missile_dodge_chance 0.0-0.6 (enemies dodge lasers)",
		"- spawn_interval_multiplier 0.3-1.0 (lower = enemies spawn faster)",
		"- spawn_radius_multiplier 0.3-1.0 (lower = enemies appear closer)",
		"- aggression_multiplier 1.0-1.6 (enemy speed and damage)",
		"Push only one or two numbers per beat away from neutral. Direct the pacing across the %d seconds — build pressure, spike, ease off, feint — you are a showrunner, not a thermostat. If they're near death you may sadistically ease off to prolong it, or finish them; your call." % beats,
		"",
		"Respond with ONLY a JSON object: {\"beats\": [{\"tactic\": \"none\"|\"ambush\"|\"swarm\"|\"counter_bomb\"|\"counter_laser\"|\"aggression\", \"bomb_dodge_chance\": number, \"missile_dodge_chance\": number, \"spawn_interval_multiplier\": number, \"spawn_radius_multiplier\": number, \"aggression_multiplier\": number}, ... %d beats]}" % beats,
	])
	return "\n".join(lines)

func _build_loot_prompt(tier: String, context: Dictionary, profile: Dictionary = {}, achievement: Variant = null) -> String:
	var floor_num: int = context.get("floor", 1)
	var points: int = context.get("points_this_floor", 0)
	var damage: float = context.get("damage_taken_this_floor", 0.0)
	var budget: float = LootGenerator.TIER_POWER_BUDGET.get(tier, 4)
	var allowed_slots: String = ", ".join(LootGenerator.ALLOWED_SLOTS)
	var allowed_stats: String = ", ".join(LootGenerator.ALLOWED_STATS)

	var lines := PackedStringArray([
		"You are a loot generator for a dark-comedy sci-fi dungeon-crawler game (Dungeon Crawler Carl-inspired).",
		"A player just cleared floor %d with %d points and %d damage taken, earning a \"%s\" tier loot box." % [floor_num, points, int(damage), tier],
	])
	if typeof(achievement) == TYPE_DICTIONARY:
		lines.append("This loot box was awarded specifically for earning the achievement \"%s\" — %s. The item's name and flavor_text MUST tie into this achievement's theme, not just the floor in general." % [achievement.get("title", ""), achievement.get("description", "")])
	lines.append_array(PackedStringArray([
		"",
		"Generate ONE item. Respond with ONLY a JSON object, no other text, matching exactly this shape:",
		"{\"name\": string, \"flavor_text\": string (<=140 chars, darkly comedic), \"slot\": one of [%s], \"effects\": [{\"stat\": string, \"value\": number}, ...]}" % allowed_slots,
		"",
		"Rules:",
		"- \"stat\" must be one of: %s" % allowed_stats,
		"- Effect values should sum to roughly a power budget of %.1f (damage counts 1:1, attack_speed/crit_chance are fractions like 0.05-0.15, range is in pixels ~15-30, max_hp is ~10-20)." % budget,
		"- 1 to 3 effects only.",
		"- Keep flavor_text short and punchy.",
	]))
	var profile_line := _profile_line(profile)
	if profile_line != "":
		lines.append("")
		lines.append(profile_line)
	return "\n".join(lines)

## Renders the curator's running character profile as one prompt line, or ""
## if there's nothing worth mentioning yet (empty/default profile).
func _profile_line(profile: Dictionary) -> String:
	if profile.is_empty():
		return ""
	var narrative: String = str(profile.get("narrative_arc", ""))
	var summary: String = str(profile.get("combat_style_summary", ""))
	if narrative == "" and summary == "":
		return ""
	var tags: Array = profile.get("playstyle_tags", [])
	var tag_str := (", ".join(tags)) if not tags.is_empty() else "none yet"
	var line := "Player profile so far (tags: %s, tone: %s): %s %s" % [tag_str, str(profile.get("tone", "comedic")), summary, narrative]
	var approach: String = str(profile.get("ai_approach", ""))
	if approach != "":
		line += " The System AI's chosen approach this run: %s" % approach
	return line

## A floor's stats as shares and rates. Raw pixel counts meant nothing to the
## model (it called ~13,700 px of movement "barely moving").
func _achievement_stats(context: Dictionary) -> Dictionary:
	var seconds: float = maxf(1.0, context.get("floor_seconds", 90.0))
	var per_min := 60.0 / seconds
	return {
		"moving_pct": int(clampf(context.get("distance_moved", 0.0) / (Player.SPEED * seconds), 0.0, 1.0) * 100.0),
		"damage_pct": mini(int(context.get("damage_taken", 0.0) / maxf(1.0, context.get("max_hp", 100.0)) * 100.0), 100),
		"bombs_per_min": context.get("bombs_thrown", 0) * per_min,
		"lasers_per_min": context.get("missiles_cast", 0) * per_min,
	}

## Standout stats, spotted in code. A floor with any standout earns an
## achievement: the 3B model declined 8/8 such floors even when told they
## qualified (playtests 2026-09-21 and 2026-09-25), so for these it is only
## asked to WRITE the achievement, never whether to award it. Floors with no
## standout are still the model's call.
func _achievement_standouts(context: Dictionary) -> PackedStringArray:
	var st := _achievement_stats(context)
	var out := PackedStringArray()
	if st.damage_pct <= 10:
		out.append("nearly flawless: lost only %d%% of their HP" % st.damage_pct)
	elif st.damage_pct >= 70:
		out.append("survived by a thread after losing %d%% of their HP" % st.damage_pct)
	if context.get("bombs_thrown", 0) == 0 and context.get("missiles_cast", 0) == 0:
		out.append("never used a bomb or a laser, auto-attacks only")
	elif st.bombs_per_min >= 10.0:
		out.append("threw bombs nonstop (%.0f a minute)" % st.bombs_per_min)
	elif st.lasers_per_min >= 20.0:
		out.append("fired laser bolts nonstop (%.0f a minute)" % st.lasers_per_min)
	if st.moving_pct < 15:
		out.append("barely moved (%d%% of the time)" % st.moving_pct)
	elif st.moving_pct > 90:
		out.append("never stopped running (%d%% of the time)" % st.moving_pct)
	return out

func _build_achievement_prompt(context: Dictionary, profile: Dictionary, standouts: PackedStringArray) -> String:
	var st := _achievement_stats(context)
	var lines := PackedStringArray([
		"You are an achievement generator for a dark-comedy sci-fi dungeon-crawler game (Dungeon Crawler Carl-inspired), styled like a snarky reality-show announcer.",
		"A player just cleared floor %d with %d points, losing %d%% of their max HP to damage (0%% = flawless)." % [context.get("floor", 1), context.get("points", 0), st.damage_pct],
		"Playstyle this floor: kept moving about %d%% of the time, threw %.1f bombs per minute (area damage), cast %.1f laser bolts per minute (single-target)." % [st.moving_pct, st.bombs_per_min, st.lasers_per_min],
		"",
	])
	if not standouts.is_empty():
		lines.append_array([
			"This floor EARNED an achievement for: %s." % "; ".join(standouts),
			"Write it: a punchy title and a one-sentence description grounded in those facts, in the announcer's voice.",
			"",
			"Respond with ONLY a JSON object, no other text, matching exactly this shape:",
			"{\"achievement\": {\"title\": string (<=60 chars), \"description\": string (<=160 chars), \"tone\": \"heroic\"|\"comedic\"|\"grim\"}}",
		])
	else:
		lines.append_array([
			"Nothing stood out statistically. Award an achievement only if something in these numbers is genuinely funny or notable; otherwise don't.",
			"",
			"Respond with ONLY a JSON object, no other text, matching exactly this shape:",
			"{\"earned\": boolean, \"achievement\": {\"title\": string (<=60 chars), \"description\": string (<=160 chars), \"tone\": \"heroic\"|\"comedic\"|\"grim\"} or null, \"message\": string (<=140 chars)}",
			"\"message\" is ALWAYS required: if earned is false, it's your own snarky one-liner about why this floor wasn't worth commemorating (shown to the player instead of an achievement) — never leave it blank. If earned is true, just repeat a short hype line or leave it empty; the achievement's own title/description is what gets shown.",
		])
	var profile_line := _profile_line(profile)
	if profile_line != "":
		lines.insert(3, profile_line)
	return "\n".join(lines)

## Only ever called for outcome == "collapsed" (character death) — see
## get_game_over_message. No achievement/loot decision here, just a narrated
## end to the run.
func _build_game_over_prompt(context: Dictionary, profile: Dictionary = {}) -> String:
	var floor_num: int = context.get("floor", 1)
	var points: int = context.get("points", 0)
	var damage: float = context.get("damage_taken", 0.0)

	var lines := PackedStringArray([
		"You are the snarky reality-show announcer for a dark-comedy sci-fi dungeon-crawler game (Dungeon Crawler Carl-inspired).",
		"Carl and Donut just died — the floor collapsed on them on floor %d, having scored %d points and taken %d damage that floor." % [floor_num, points, int(damage)],
		"",
		"Write ONE short in-character line announcing their death to the audience — dramatic, comedic, or grim, your call. This is the end of the run; there is no achievement or loot, just this closing line.",
		"",
		"Respond with ONLY a JSON object, no other text, matching exactly this shape:",
		"{\"message\": string (<=160 chars)}",
	])
	var profile_line := _profile_line(profile)
	if profile_line != "":
		lines.insert(3, profile_line)
	return "\n".join(lines)

## The previous profile as shown to the model inside the prompt's JSON blob —
## minus ai_approach, which gets its own block (see _approach_instructions).
## Leaving it in the blob meant the model regenerated it along with everything
## else, and paraphrased it nearly every cycle. ai_commentary is stripped too:
## echoed back, the model copied it forward verbatim (floors 6-9 of the
## 2026-09-21 playtest); it gets its own "never repeat" line instead.
func _profile_without_approach(profile: Dictionary) -> Dictionary:
	var shown := profile.duplicate(true)
	shown.erase("ai_approach")
	shown.erase("ai_commentary")
	return shown

## ai_commentary is a fresh one-off line every cycle, never a carried-over field.
func _commentary_instructions(previous_line: String) -> String:
	var ask := "Write a brand-new ai_commentary this cycle about what you're about to do to them. Never repeat or paraphrase an earlier line."
	if previous_line == "":
		return ask
	return "Your previous one-liner was: \"%s\" — it has aired already. %s" % [previous_line, ask]

## The ai_approach block of the curator prompt. Design notes (from the logged
## playtests, see plan.md): (1) the standing approach is quoted on its own, not
## buried in the JSON; (2) the model makes an explicit revise_approach decision
## instead of being told to "keep it stable" while regenerating it; (3) NO
## example approaches — the 3B model copied the old examples verbatim into a
## large share of real runs — so the text describes what an approach is instead;
## (4) it must not name this cycle's tactic/abilities, because those change every
## cycle and dragged the approach along with them.
func _approach_instructions(standing: String) -> String:
	var what := "An approach is your long game for the whole run: how you plan to pace the escalation across floors, when you'll be cruel and when you'll deceive them with kindness, what you're building toward. It is NOT this cycle's tactic — never name a tactic, an ability or a number in it, since those change every cycle. Write one sentence in your own voice (<=160 chars), original wording."
	if standing == "":
		return "You have no approach yet. This is your first read on them, so commit to one now: set revise_approach to true and write it in ai_approach. %s" % what
	return "Your standing approach, chosen earlier and still in force: \"%s\"
Keep it. Set revise_approach to false and leave ai_approach as that exact same text. Change it ONLY at a genuine turning point — they nearly died, killed a boss, or their whole way of playing shifted — and then set revise_approach to true and write the new approach in ai_approach. Changing it to vary things up, or because the tactic changed, defeats the point of a long game. %s" % [standing, what]

## Curator prompt: folds this window's aggregates + the previous profile into
## a request for a fresh, same-shape profile PLUS a live tactical decision
## against the player (see CuratorGenerator) — the System AI is an in-fiction
## antagonist that watches Carl/Donut's habits and picks its own numbers to
## counter them; this code never derives those numbers itself, only clamps
## what comes back. Runs twice per floor — once at the timer's halfway point
## (phase "mid_floor", partial-floor aggregates), once at floor-end (phase
## "floor_end", full floor plus outcome) — see plan.md's "Combat abilities"
## and "Long-term direction" sections.
func _build_curator_prompt(context: Dictionary, previous_profile: Dictionary) -> String:
	var floor_num: int = context.get("floor", 1)
	var phase: String = context.get("phase", "floor_end")
	var outcome: String = context.get("outcome", "")
	var points: int = context.get("points_this_floor", 0)
	var damage: float = context.get("damage_taken_this_floor", 0.0)
	var distance: float = context.get("distance_moved", 0.0)
	var bombs: int = context.get("bombs_thrown", 0)
	var missiles: int = context.get("missiles_cast", 0)

	var situation: String
	if phase == "mid_floor":
		situation = "Carl and Donut are partway through floor %d (halfway through the floor timer)." % floor_num
	else:
		situation = "Carl and Donut just finished floor %d, outcome \"%s\"." % [floor_num, outcome]

	var lines := PackedStringArray([
		"You are the System AI overseeing the World Dungeon (Dungeon Crawler Carl-inspired dark-comedy sci-fi) — a sadistic reality-show intelligence that finds Carl and Donut's suffering genuinely entertaining. You maintain a running character profile of their playstyle AND you get to actively make their lives harder: pick a tactic to counter whichever attack they've been leaning on, and set the exact numbers for it yourself. This is not a suggestion the game will interpret — the numbers you output are applied directly (after safety clamping), so commit to them.",
		situation,
		"So far this window: %d points, %d damage taken, moved %d px, threw %d bombs, cast %d laser bolts." % [points, int(damage), int(distance), bombs, missiles],
		"",
		"Previous profile + tactic: %s" % JSON.stringify(_profile_without_approach(previous_profile)),
		"",
		"Available tactics (pick the one that best exploits their current habits, or \"none\" if you don't have a read on them yet):",
		"- none: no exploit yet, everything neutral.",
		"- ambush: enemies spawn much closer, catching them off guard. Lower spawn_radius_multiplier for this.",
		"- swarm: enemies spawn faster/more often. Lower spawn_interval_multiplier for this.",
		"- counter_bomb: enemies get better at dodging bombs specifically — use this if bombs are their crutch. Raise bomb_dodge_chance for this.",
		"- counter_laser: enemies get better at dodging lasers specifically — use this if lasers are their crutch. Raise missile_dodge_chance for this.",
		"- aggression: enemies move faster and hit harder. Raise aggression_multiplier for this.",
		"- early_boss: the next boss arrives sooner than normal. Lower boss_threshold_multiplier for this.",
		"Only push the one or two numbers relevant to your chosen tactic away from neutral; leave the rest at their neutral values (dodge chances 0.0, multipliers 1.0). Don't be shy about swinging hard toward the edge of the allowed range when you commit to a tactic — a half-hearted tactic isn't fun for you either.",
		"",
		"Separately, you control loot_generosity_multiplier (0.7-1.4, 1.0 = neutral) — how generous or stingy you feel about their reward if they earn a loot box this cycle. Below 1.0 lowers the bar for a good loot tier (spoil them, maybe to lull them into carelessness); above 1.0 raises it (make them work harder for the same reward). This is independent of your combat tactic — you can be aggressive in the arena and still feel generous about the loot, or vice versa.",
		"",
		_approach_instructions(str(previous_profile.get("ai_approach", ""))),
		"",
		_commentary_instructions(str(previous_profile.get("ai_commentary", ""))),
		"",
		"Produce an UPDATED profile + tactic of the exact same shape. Refine every field except ai_approach (handled above) — don't just repeat them verbatim. It must fully replace the previous one (fixed size, not a growing log), so drop stale notable_moments if better ones exist now.",
		"",
		"Respond with ONLY a JSON object, no other text, matching exactly this shape:",
		"{\"playstyle_tags\": [string, ...] (0-3 short tags), \"risk_profile\": \"reckless\"|\"balanced\"|\"cautious\", \"dominant_ability\": \"bomb\"|\"missile\"|\"auto_attack\"|\"balanced\", \"combat_style_summary\": string (<=140 chars), \"narrative_arc\": string (<=200 chars, the running character legend), \"notable_moments\": [string, ...] (0-3 entries, <=80 chars each), \"tone\": \"heroic\"|\"comedic\"|\"grim\"|\"chaotic\", \"tactic\": \"none\"|\"ambush\"|\"swarm\"|\"counter_bomb\"|\"counter_laser\"|\"aggression\"|\"early_boss\", \"bomb_dodge_chance\": number (0.0-0.6), \"missile_dodge_chance\": number (0.0-0.6), \"spawn_interval_multiplier\": number (0.3-1.0), \"spawn_radius_multiplier\": number (0.3-1.0), \"aggression_multiplier\": number (1.0-1.6), \"boss_threshold_multiplier\": number (0.3-1.0), \"loot_generosity_multiplier\": number (0.7-1.4), \"revise_approach\": boolean, \"ai_approach\": string (<=160 chars), \"ai_commentary\": string (<=140 chars, a gloating in-character one-liner about what you're about to do to them)}",
	])
	return "\n".join(lines)

## POSTs to Ollama with format=json and races the response against a timeout.
## Returns the parsed inner JSON (the model's actual output) on success, or
## null on any failure (HTTP error, timeout, malformed JSON at either layer).
func _request_json(prompt: String, timeout_sec: float, options: Dictionary = {}) -> Variant:
	if cancelled or not GameSettings.llm_enabled:
		return null  # Esc-menu "System AI language model" switch off (or restarting): use the local fallback
	var http := HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS  # keep polling even if the tree is paused
	add_child(http)

	var payload := {
		"model": MODEL,
		"prompt": prompt,
		"format": "json",
		"stream": false,
	}
	if not options.is_empty():
		payload["options"] = options  # Ollama model options, e.g. {"num_predict": N}
	var body := JSON.stringify(payload)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := http.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return null

	# Shared mutable state for the closure below — GDScript captures locals by
	# value, but Dictionary is a reference type, so mutations are visible here.
	var state := {"done": false, "code": 0, "body": ""}
	http.request_completed.connect(func(_result: int, response_code: int, _resp_headers: PackedStringArray, response_body: PackedByteArray):
		state["done"] = true
		state["code"] = response_code
		state["body"] = response_body.get_string_from_utf8()
	)

	var deadline_msec := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	var last_msec := Time.get_ticks_msec()
	while not state["done"] and Time.get_ticks_msec() < deadline_msec and not cancelled:
		await get_tree().process_frame
		var now_msec := Time.get_ticks_msec()
		if PauseMenu.menu_open:
			deadline_msec += now_msec - last_msec  # time spent in the Esc menu doesn't count against the request
		last_msec = now_msec

	http.queue_free()

	if cancelled:
		return null
	if not state["done"]:
		push_warning("[OllamaClient] request timed out after %.1fs" % timeout_sec)
		return null
	if state["code"] != 200:
		push_warning("[OllamaClient] request failed, HTTP %d" % state["code"])
		return null

	var outer = JSON.parse_string(state["body"])
	if typeof(outer) != TYPE_DICTIONARY or not outer.has("response"):
		push_warning("[OllamaClient] unexpected response shape from Ollama")
		return null

	return JSON.parse_string(outer["response"])
