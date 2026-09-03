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

func get_loot(tier: String, context: Dictionary) -> Dictionary:
	var prompt := _build_loot_prompt(tier, context)
	var raw: Variant = await _request_json(prompt, DEFAULT_TIMEOUT_SEC)
	if raw != null:
		var validated := LootGenerator.validate_and_clamp(raw, tier)
		if not validated.is_empty():
			print("[OllamaClient] loot: LLM-generated (tier=%s)" % tier)
			return validated
		print("[OllamaClient] loot: LLM response failed validation, using fallback")
	else:
		print("[OllamaClient] loot: no/invalid response, using fallback")
	return LootGenerator.generate_loot(tier, context)

func get_achievement(context: Dictionary) -> Variant:
	var prompt := _build_achievement_prompt(context)
	var raw: Variant = await _request_json(prompt, DEFAULT_TIMEOUT_SEC)
	if raw != null and typeof(raw) == TYPE_DICTIONARY:
		if raw.get("earned", false) == true and typeof(raw.get("achievement")) == TYPE_DICTIONARY:
			var ach: Dictionary = raw["achievement"]
			var title: String = str(ach.get("title", "")).left(60).strip_edges()
			var description: String = str(ach.get("description", "")).left(160).strip_edges()
			if title != "" and description != "":
				print("[OllamaClient] achievement: LLM-generated")
				return {"title": title, "description": description, "tone": str(ach.get("tone", "comedic"))}
		print("[OllamaClient] achievement: LLM says none earned (or malformed earned=true)")
		return null
	print("[OllamaClient] achievement: no/invalid response, using local fallback rules")
	return AchievementGenerator.generate(context)

func _build_loot_prompt(tier: String, context: Dictionary) -> String:
	var floor_num: int = context.get("floor", 1)
	var points: int = context.get("points_this_floor", 0)
	var damage: float = context.get("damage_taken_this_floor", 0.0)
	var budget: float = LootGenerator.TIER_POWER_BUDGET.get(tier, 4)
	var allowed_slots: String = ", ".join(LootGenerator.ALLOWED_SLOTS)
	var allowed_stats: String = ", ".join(LootGenerator.ALLOWED_STATS)

	var lines := PackedStringArray([
		"You are a loot generator for a dark-comedy sci-fi dungeon-crawler game (Dungeon Crawler Carl-inspired).",
		"A player just cleared floor %d with %d points and %d damage taken, earning a \"%s\" tier loot box." % [floor_num, points, int(damage), tier],
		"",
		"Generate ONE item. Respond with ONLY a JSON object, no other text, matching exactly this shape:",
		"{\"name\": string, \"flavor_text\": string (<=140 chars, darkly comedic), \"slot\": one of [%s], \"effects\": [{\"stat\": string, \"value\": number}, ...]}" % allowed_slots,
		"",
		"Rules:",
		"- \"stat\" must be one of: %s" % allowed_stats,
		"- Effect values should sum to roughly a power budget of %.1f (damage counts 1:1, attack_speed/crit_chance are fractions like 0.05-0.15, range is in pixels ~15-30, max_hp is ~10-20)." % budget,
		"- 1 to 3 effects only.",
		"- Keep flavor_text short and punchy.",
	])
	return "\n".join(lines)

func _build_achievement_prompt(context: Dictionary) -> String:
	var floor_num: int = context.get("floor", 1)
	var outcome: String = context.get("outcome", "")
	var points: int = context.get("points", 0)
	var damage: float = context.get("damage_taken", 0.0)

	var lines := PackedStringArray([
		"You are an achievement generator for a dark-comedy sci-fi dungeon-crawler game (Dungeon Crawler Carl-inspired), styled like a snarky reality-show announcer.",
		"A player just finished floor %d, outcome \"%s\", with %d points and %d damage taken." % [floor_num, outcome, points, int(damage)],
		"",
		"Decide if this run deserves a special achievement. Be selective: most runs should NOT get one — only for something notably good, notably bad, or funny.",
		"",
		"Respond with ONLY a JSON object, no other text, matching exactly this shape:",
		"{\"earned\": boolean, \"achievement\": {\"title\": string (<=60 chars), \"description\": string (<=160 chars), \"tone\": \"heroic\"|\"comedic\"|\"grim\"} or null}",
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
