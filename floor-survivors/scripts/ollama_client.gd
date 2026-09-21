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

	ContentLogger.log_event({
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
	var prompt := _build_achievement_prompt(context, profile)
	var raw: Variant = await _request_json(prompt, DEFAULT_TIMEOUT_SEC)
	var achievement: Variant = null
	var message := ""
	var source: String

	if raw != null and typeof(raw) == TYPE_DICTIONARY:
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
	ContentLogger.log_event({
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

	ContentLogger.log_event({
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
		var validated := CuratorGenerator.validate_and_clamp(raw)
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

	ContentLogger.log_event({
		"kind": "curator",
		"context": context,
		"previous_profile": previous_profile,
		"prompt": prompt,
		"raw_response": raw,
		"source": source,
		"result": result,
	})
	return result

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

func _build_achievement_prompt(context: Dictionary, profile: Dictionary = {}) -> String:
	var floor_num: int = context.get("floor", 1)
	var points: int = context.get("points", 0)
	var damage: float = context.get("damage_taken", 0.0)
	var distance: float = context.get("distance_moved", 0.0)
	var bombs: int = context.get("bombs_thrown", 0)
	var missiles: int = context.get("missiles_cast", 0)

	var lines := PackedStringArray([
		"You are an achievement generator for a dark-comedy sci-fi dungeon-crawler game (Dungeon Crawler Carl-inspired), styled like a snarky reality-show announcer.",
		"A player just cleared floor %d with %d points and %d damage taken." % [floor_num, points, int(damage)],
		"Movement/ability stats for this floor: moved %d px total, threw %d bombs (area damage), cast %d magic missiles (single-target)." % [int(distance), bombs, missiles],
		"",
		"Decide if this run deserves a special achievement. Be selective: most runs should NOT get one — only for something notably good, notably bad, or funny. Feel free to call out a distinctive playstyle from the movement/ability stats: barely moving, kiting constantly, spamming one ability, never using an ability, etc.",
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
		"Previous profile + tactic: %s" % JSON.stringify(previous_profile),
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
		"You also maintain ai_approach: your OWN chosen long-term strategy for how you intend to play this entire run, in your own words (<=160 chars). This is different from \"tactic\" above — tactic is just the specific tool you're reaching for THIS cycle; ai_approach is the overarching plan those tactics are in service of (e.g. \"Grind them down slowly through attrition and stinginess rather than flashy kills\", \"Spoil them with easy wins early to make the eventual gut-punch land harder\", \"Focus everything on whichever ability they lean on — deny them their crutch\"). If the previous profile's ai_approach is empty, this is your first read on them — establish one now. If it's already set, KEEP IT STABLE and reuse it near-verbatim unless something in this window (a near-death, a boss kill, a big shift in their play) genuinely justifies evolving your strategy — don't rewrite it just for variety.",
		"",
		"Produce an UPDATED profile + tactic of the exact same shape — refine it, don't just repeat it verbatim. It must fully replace the previous one (fixed size, not a growing log), so drop stale notable_moments if better ones exist now.",
		"",
		"Respond with ONLY a JSON object, no other text, matching exactly this shape:",
		"{\"playstyle_tags\": [string, ...] (0-3 short tags), \"risk_profile\": \"reckless\"|\"balanced\"|\"cautious\", \"dominant_ability\": \"bomb\"|\"missile\"|\"auto_attack\"|\"balanced\", \"combat_style_summary\": string (<=140 chars), \"narrative_arc\": string (<=200 chars, the running character legend), \"notable_moments\": [string, ...] (0-3 entries, <=80 chars each), \"tone\": \"heroic\"|\"comedic\"|\"grim\"|\"chaotic\", \"tactic\": \"none\"|\"ambush\"|\"swarm\"|\"counter_bomb\"|\"counter_laser\"|\"aggression\"|\"early_boss\", \"bomb_dodge_chance\": number (0.0-0.6), \"missile_dodge_chance\": number (0.0-0.6), \"spawn_interval_multiplier\": number (0.3-1.0), \"spawn_radius_multiplier\": number (0.3-1.0), \"aggression_multiplier\": number (1.0-1.6), \"boss_threshold_multiplier\": number (0.3-1.0), \"loot_generosity_multiplier\": number (0.7-1.4), \"ai_approach\": string (<=160 chars), \"ai_commentary\": string (<=140 chars, a gloating in-character one-liner about what you're about to do to them)}",
	])
	return "\n".join(lines)

## POSTs to Ollama with format=json and races the response against a timeout.
## Returns the parsed inner JSON (the model's actual output) on success, or
## null on any failure (HTTP error, timeout, malformed JSON at either layer).
func _request_json(prompt: String, timeout_sec: float) -> Variant:
	var http := HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS  # keep polling even if the tree is paused
	add_child(http)

	var body := JSON.stringify({
		"model": MODEL,
		"prompt": prompt,
		"format": "json",
		"stream": false,
	})
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
	while not state["done"] and Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame

	http.queue_free()

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
