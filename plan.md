# DCC — 2D Dungeon Crawler (Dungeon Crawler Carl-inspired)

## Concept

A 2D dungeon crawler drawing on the setting/tone of Matt Dinniman's *Dungeon Crawler Carl* (Book 1):

- Earth destroyed and rebuilt into a multi-level "World Dungeon" by an alien corporation (the Syndicate).
- Survivors ("crawlers") fight down through numbered floors, broadcast as an intergalactic reality show.
- Two-character party: a human crawler + a companion pet that gains sapience/magic partway in.
- RPG mechanics: races/classes, mobs and bosses, XP, loot boxes, a "System AI" dispensing info/rewards.
- Hard time limit per floor — miss the stairs down before it expires and the floor collapses.
- Dark-comedy tone; a "being watched" meta layer (audience reactions, interviews) as a possible scoring/commentary hook.

## Decisions made so far

- **Engine: Godot** — free, open-source, purpose-built 2D tooling (scene editor, tilemaps, animation, physics), scriptable in GDScript or C#. Chosen over Pygame (pure Python, no editor, more manual work) and Unity (heavier, new language, more suited to larger scope).
- **Build: standard Godot 4.7.2 (GDScript-only, no Mono/.NET)**, installed via winget (`winget install --id GodotEngine.GodotEngine`). Runtime LLM content generation doesn't need C# — GDScript's `HTTPRequest` node + built-in `JSON` class are enough to call a hosted LLM API or a local Python service asynchronously.
- Longer-term interest: build an AI/LLM content-generation workflow (extending the orchestration patterns from `ollama-research-agent`) to help generate game content, potentially at runtime (not just offline authoring) — the plan is Godot (GDScript) firing async HTTP requests at a hosted LLM API or a small local Python service and parsing JSON back into game state.
- **Combat/movement: real-time, free movement (not grid-based), Vampire Survivors-style** — free-roam movement, auto/simplified attacking against swarms of enemies, XP pickups and level-up choices. This pairs naturally with the per-floor time-limit-collapse mechanic: the floor timer becomes the "survive the clock" pressure that structure already relies on.
- **Party model: Carl + Donut as one unit** — single shared XP pool (no split), one moves/is controlled as usual, and the player can switch which of the two is the active attacker. The non-active character does nothing while switched out (no passive support/damage). No separate leveling tracks per character for now.
- **Loot-box tier system: performance-driven quality** — the tier of loot (common/uncommon/rare/etc., Carl-style) is determined by in-run performance: points scored and damage received. Better performance (more points, less damage taken) → higher-tier loot.
- **Reality-show meta layer deprioritized** — out of scope for now; focus is on core mechanics (movement/combat, loot, XP) and the LLM content experiment.
- **First AI/LLM integration target — and the core focus of this project right now: loot-box content + achievements.** Rather than procedural floor generation or dialogue, the goal is to see how much can be pushed onto an LLM for these two content types specifically. Other AI use cases (level layout, dialogue, etc.) stay longer-term/later.
- **LLM backend: local Ollama**, called directly from Godot via `HTTPRequest` (no intermediary Python service) — reuses the `ollama-research-agent` model-serving setup, free, private, no API key. Traded off against hosted Claude API (higher quality, costs per call) since the point of this phase is exploring local-LLM content generation.
- **Achievement trigger granularity: per floor-clear/exit**, not per notable event — one LLM call summarizing that floor's run, which decides whether an achievement was earned. Keeps call volume low and content easy to reason about; can revisit event-level triggers later if per-floor feels thin.
- **Loot-box LLM call: async with local fallback** — the box opens immediately client-side; if the Ollama response isn't back within a timeout, a pre-written local template for that tier is used instead so gameplay never stalls waiting on the model.

## AI content integration design (loot + achievements)

This is the core experiment: how much real content generation (not just flavor text) can an LLM own, while staying safe/balanced and never blocking gameplay. Both features hit Ollama directly from GDScript via `HTTPRequest`, `POST http://localhost:11434/api/generate`, with `"format": "json"` and `"stream": false` so a single response body contains the full JSON payload to parse.

### Loot-box generation

**Trigger:** player opens a loot box. Tier is *not* LLM-decided — it's computed deterministically client-side first, from a performance formula over that floor's points and damage taken (exact formula/thresholds still TBD — see open questions). The LLM only fills in the box's contents within that tier's constraints.

**Request (conceptual body sent as the Ollama prompt, structured before templating into text):**
```json
{
  "tier": "rare",
  "power_budget": 12,
  "allowed_slots": ["weapon", "armor", "trinket", "consumable"],
  "allowed_stats": ["damage", "attack_speed", "crit_chance", "max_hp", "move_speed", "armor"],
  "context": {
    "floor": 3,
    "points_this_floor": 1240,
    "damage_taken_this_floor": 35,
    "recent_events": ["killed_elite_goblin", "no_hit_streak_45s"],
    "current_loadout": ["Rusty Shiv (weapon)", "Cracked Buckler (armor)"]
  }
}
```
The prompt instructs the model to return **only** JSON, no prose, matching the response schema below.

**Response schema (target JSON the model must produce):**
```json
{
  "name": "string",
  "flavor_text": "string, <=140 chars",
  "slot": "weapon | armor | trinket | consumable",
  "effects": [
    { "stat": "damage", "value": 8 },
    { "stat": "crit_chance", "value": 0.05 }
  ]
}
```

**Client-side validation (never trust raw model output for balance):**
- `slot` must be one of `allowed_slots`, else fallback template.
- Each `effects[].stat` must be in `allowed_stats`; unknown stats are dropped.
- Each `effects[].value` clamped to a per-stat/per-tier min/max range.
- Sum of normalized effect values checked against `power_budget`; if it overshoots (with some tolerance, e.g. 1.15x), scale all values down proportionally.
- `name`/`flavor_text` length-clamped.
- If JSON parsing fails, required fields are missing, or the request times out → use a pre-written local fallback item for that tier. The late response (if it eventually arrives) is discarded rather than swapped in — keeps the flow simple for this phase.

### Achievement generation

**Trigger:** floor exit (whether cleared via stairs or lost to floor collapse) — one call per floor, not per event.

**Request (conceptual body):**
```json
{
  "floor": 3,
  "outcome": "cleared | collapsed",
  "points": 1240,
  "damage_taken": 35,
  "kills": 18,
  "time_remaining_pct": 0.22,
  "notable_events": ["no_hit_streak_45s", "killed_boss:Goblin_King", "near_death:hp_1"]
}
```

**Response schema:**
```json
{
  "earned": true,
  "achievement": {
    "title": "string",
    "description": "string",
    "tone": "heroic | comedic | grim"
  }
}
```
`achievement` is `null` when `earned` is `false`. Achievements are pure bonus/flavor (no mechanical effect for now), so unlike loot there's no local fallback needed — if the call fails or returns invalid JSON, that floor simply awards no achievement.

### Implementation status (verified working end-to-end)

`scripts/ollama_client.gd` (`OllamaClient`, one instance per `Floor`) implements this design and is live: `get_loot()`/`get_achievement()` POST to Ollama, race the response against a timeout, and fall back to local content on any failure. `scripts/loot_generator.gd` gained `validate_and_clamp()` — the actual safety net described above (whitelists `slot`/`stat`, drops unknown stats, scales effect values down if they overshoot the tier's power budget by >15% rather than rejecting the item outright).

Confirmed with real Ollama calls (model: `llama3.2:latest`, `DCC_FLOOR_DURATION=3` env var override for fast iteration — see below): the model reliably returns valid JSON loot with creative names/flavor text and in-budget effects, and the achievement generator correctly stays selective (mostly declines, occasionally fires).

**Resolved implementation questions:**
- **Model: `llama3.2:latest`** (3B, already pulled locally) — good speed/quality balance among the three models available (`qwen2.5:7b`, `llava:latest`, `llama3.2:latest`).
- **Timeout: 6s**, not the originally-proposed ~3s — measured a cold model-load costs ~4.5s by itself (one-time per Ollama restart/idle-unload), while a warm call is well under 1s. Floors are ≥90s apart normally, well past Ollama's default keep-alive, so warm calls are the common case.
- **Gotcha found and fixed:** Godot's `HTTPRequest` resolving `"localhost"` was hanging/timing out on Windows even though `curl http://localhost:11434` worked fine (classic IPv6-loopback-first resolution issue) — `OllamaClient.OLLAMA_URL` uses `127.0.0.1` explicitly instead.
- **Testing hook:** `floor.gd` reads env var `DCC_FLOOR_DURATION` (e.g. `DCC_FLOOR_DURATION=3`) to shorten floors from the real 90s for quickly exercising the floor-clear → LLM-call → log flow.
- **Still open:** exact power-budget numbers/stat ranges per tier are the original placeholders, untuned; the point/damage-taken → tier formula is likewise still a placeholder.

## Long-term direction: full RPG driven by player-behavior AI

**Vision (stated 2026-09-06):** the loot/achievement LLM integration is the first step toward a larger goal — evolving DCC into an RPG where the LLM's decisions (loot, achievements, and eventually dialogue/narrative/difficulty) are shaped by the player's *entire* behavioral history (movement patterns, ability usage, risk-taking, decisions made), not just the current floor's raw stats.

**Feasibility constraint driving the design:** the LLM backend is a local model (`llama3.2:latest`, 6s call timeout, gameplay must never block on it — see "AI content integration design" above). Raw event streams (every position sample, every input) are far too large to hand the model directly — this must be solved with layering, not brute force.

**Chosen architecture — two layers, kept deliberately separate:**

1. **Raw event log (local-only, full fidelity).** Extend the existing `ContentLogger` JSONL-append pattern (currently used for loot/achievement decisions, see `scripts/content_logger.gd`) to also record movement/ability events. This never gets sent to the LLM directly — it's for later offline analysis and as future curator-agent input.
2. **Code-side numeric aggregation (cheap, deterministic, already partly built).** `Player` tracks running per-floor totals — `floor_distance_moved`, `floor_bombs_thrown`, `floor_missiles_cast` — reset each floor via `reset_floor_stats()`, fed into the achievement prompt as plain numbers. This stays as-is; a sum or average is not something worth spending an LLM call on.

**New third layer — a "curator" LLM pass (periodic, narrative-focused):** where option 2 falls short is qualitative/narrative synthesis — condensing accumulated free text (past loot flavor text, past achievement titles/descriptions) plus this window's numeric aggregates into a running "character profile" that then feeds into *future* loot/achievement calls (and later, dialogue/difficulty decisions), keeping the AI's output consistent with the player's established playstyle and story-so-far.

Key design constraint: **the curator profile must replace itself each cycle, not append.** It has to stay a fixed size regardless of how many floors have passed (floor 2's profile and floor 9's profile must cost the same tokens), or "lightweight" breaks down over a long run. Each curation call takes {previous profile + this window's raw events/aggregates} and produces a new profile of the same shape — never a growing list.

Should run **every N floors, not every floor** — stacking a third sequential local-model call onto the existing loot+achievement pair at every single floor-end risks compounding latency (each call can cost ~4-5s cold). Exact N still open.

**Drafted curator output schema (not yet implemented):**
```json
{
  "playstyle_tags": ["kiter", "bomb_reliant"],
  "risk_profile": "cautious",
  "dominant_ability": "bomb",
  "combat_style_summary": "Hangs back and lets bombs do the work, rarely engages directly.",
  "narrative_arc": "Once reckless, now visibly gun-shy after the floor-3 boss nearly ended the run.",
  "notable_moments": [
    "Cleared floor 4 without taking a hit",
    "Nearly died to the first boss"
  ],
  "tone": "grim"
}
```
- `playstyle_tags`: 0-3 short enum-like tags.
- `risk_profile`: enum `reckless | balanced | cautious`, derived from damage-taken/points ratio.
- `dominant_ability`: enum `bomb | missile | auto_attack | balanced`.
- `combat_style_summary`: <=140 chars, one line.
- `narrative_arc`: <=200 chars, the running "character legend" carried forward each cycle.
- `notable_moments`: 0-3 entries, <=80 chars each — bounded, so old moments are expected to silently drop off as new ones crowd them out (completeness traded for fixed size, same tradeoff as the profile as a whole).
- `tone`: enum `heroic | comedic | grim | chaotic`, kept for consistency with future loot/achievement flavor text.

All fields need the same client-side validation discipline as loot/achievements already have (`LootGenerator.validate_and_clamp`, achievement title/description clamps in `ollama_client.gd`) — bounded enums and length-clamped strings, never trusting raw model output. **Not yet implemented** — this is a design sketch pending: the every-N-floors cadence, where the profile is stored (likely alongside `floor_points`/`floor_damage_taken` on `floor.gd`, or a small dedicated resource), and the curator's own prompt/request shape.

## Open questions / next steps

- [x] First playable slice built — single floor, 90s survive-the-timer loop (`scenes/Floor.tscn` + `scripts/`): free movement, auto-attack nearest enemy, ramping enemy spawner, contact damage, XP pickups + level-up choice screen, floor ends on timer expiry or player death, `LootGenerator`/`AchievementGenerator` wired with local fallback content (Ollama call is the next step, not yet connected — see AI integration section). Verified error-free via headless run (`godot --headless --path . --quit-after N`) and confirmed rendering visually (screenshot of the running game window).
- [x] Expanded to 10 sequential floors — same 90s timer per floor; clearing one auto-starts the next (`floor.gd`: `current_floor`/`MAX_FLOOR`). Each floor bumps a monster speed multiplier (`FLOOR_SPEED_STEP = 0.15`, so floor 10 ≈ 2.35x floor 1's speed), stacking with the existing within-floor elapsed-time ramp. Points accumulate across the whole run (shown in HUD); points/damage-taken used for the loot tier formula reset each floor. Dying ends the run at whatever floor you're on; clearing floor 10 ends it as "run complete." Not yet playtested for feel — user is testing this locally.
- [x] LLM-generated loot + achievements — see "AI content integration design" > "Implementation status" above. Live Ollama calls confirmed working end-to-end with real generated content.
- [x] Loot is now mechanically applied to the player — `Player.apply_loot()` (fixed alongside a pre-existing bug where `switch_form()` silently wiped range/speed bonuses on Carl/Donut switch).
- [ ] Known gaps as of the LLM-loot build: no "stairs" mechanic (floor-clear = survive the timer, not reach an exit, per the earlier VS-style decision); only one enemy type/no bosses; no restart/game-over UI after a full run ends (reload the scene manually); the 0.15-per-floor speed step and the loot tier/power-budget numbers are all still untuned placeholders.
- [ ] Loot/leveling specifics still open (party model, tier system, and AI scope now decided — see above): exact point/damage formula for tier thresholds, XP curve, what a VS-style level-up choice screen offers (weapons vs. passive upgrades vs. loot-box openings)
- [ ] Companion pet mechanic — how Donut's abilities/magic work mechanically when she's the active attacker (non-active behavior now decided — does nothing, see above)
- [x] Godot install/setup on this machine — installed via winget, v4.7.2 standard build confirmed working
- [x] Reality-show meta layer — deprioritized, out of scope for now
- [x] AI content-generation request/response shape for loot-box content + achievements — see "AI content integration design" section above; remaining implementation-level TBDs (tier formula, stat ranges, model choice, timeout) listed there
- [ ] Start Ollama and pick/pull a local model to use for this experiment
- [ ] Implement the "curator" LLM pass described above — decide the every-N-floors cadence, where the profile is stored, and wire its output into future loot/achievement prompts
- [ ] Read further into the books for more concrete material (floor themes, specific enemies/items) to draw from

## Reference

- Plot research notes (Book 1): World Dungeon is an 18-level structure; protagonist Carl (Coast Guard vet) and Princess Donut (his ex's cat, becomes sapient via an enchanted biscuit); tutorial guide Mordecai; floors 1–2 covered in book 1 along with early audience/interview beats (host Odette) and a set-up quest for Donut (hunting Blood Sultanate royalty by floor nine).
