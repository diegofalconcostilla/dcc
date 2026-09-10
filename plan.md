# DCC — 2D Dungeon Crawler (Dungeon Crawler Carl-inspired)

## Concept

A 2D dungeon crawler drawing on the setting/tone of Matt Dinniman's *Dungeon Crawler Carl* (Book 1):

- Earth destroyed and rebuilt into a multi-level "World Dungeon" by an alien corporation (the Syndicate).
- Survivors ("crawlers") fight down through numbered floors, broadcast as an intergalactic reality show.
- Two-character party: a human crawler + a companion pet that gains sapience/magic partway in.
- RPG mechanics: races/classes, mobs and bosses, XP, loot boxes, a "System AI" dispensing info/rewards — and, as implemented, actively working against the player (see "Combat abilities" below).
- Hard time limit per floor — miss the stairs down before it expires and the floor collapses.
- Dark-comedy tone; a "being watched" meta layer (audience reactions, interviews) as a possible scoring/commentary hook.

## Decisions made so far

- **Engine: Godot** — free, open-source, purpose-built 2D tooling (scene editor, tilemaps, animation, physics), scriptable in GDScript or C#. Chosen over Pygame (pure Python, no editor, more manual work) and Unity (heavier, new language, more suited to larger scope).
- **Build: standard Godot 4.7.2 (GDScript-only, no Mono/.NET)**, installed via winget (`winget install --id GodotEngine.GodotEngine`). Runtime LLM content generation doesn't need C# — GDScript's `HTTPRequest` node + built-in `JSON` class are enough to call a hosted LLM API or a local Python service asynchronously.
- Longer-term interest: build an AI/LLM content-generation workflow (extending the orchestration patterns from `ollama-research-agent`) to help generate game content, potentially at runtime (not just offline authoring) — the plan is Godot (GDScript) firing async HTTP requests at a hosted LLM API or a small local Python service and parsing JSON back into game state.
- **Combat/movement: real-time, free movement (not grid-based), Vampire Survivors-style** — free-roam movement, auto/simplified attacking against swarms of enemies, XP pickups and level-up choices. This pairs naturally with the per-floor time-limit-collapse mechanic: the floor timer becomes the "survive the clock" pressure that structure already relies on.
- **Party model: Carl + Donut as one unit** — single shared XP pool, one controlled character. The original plan was a Tab-switch between which of the two is the active attacker (non-active does nothing); this was **superseded on 2026-09-06** by player-aimed active abilities instead (left-click bomb, right-click laser, layered on a passive auto-attack) — see the "Combat abilities" section below. No separate leveling tracks per character.
- **Loot-box tier system: performance-driven quality** — the tier of loot (common/uncommon/rare/etc., Carl-style) is determined by in-run performance: points scored and damage received. Better performance (more points, less damage taken) → higher-tier loot.
- **Reality-show meta layer deprioritized** — out of scope for now; focus is on core mechanics (movement/combat, loot, XP) and the LLM content experiment.
- **First AI/LLM integration target — and the core focus of this project right now: loot-box content + achievements.** Rather than procedural floor generation or dialogue, the goal is to see how much can be pushed onto an LLM for these two content types specifically. Other AI use cases (level layout, dialogue, etc.) stay longer-term/later.
- **LLM backend: local Ollama**, called directly from Godot via `HTTPRequest` (no intermediary Python service) — reuses the `ollama-research-agent` model-serving setup, free, private, no API key. Traded off against hosted Claude API (higher quality, costs per call) since the point of this phase is exploring local-LLM content generation.
- **Achievement trigger granularity: per floor-clear/exit**, not per notable event — one LLM call summarizing that floor's run, which decides whether an achievement was earned. Keeps call volume low and content easy to reason about; can revisit event-level triggers later if per-floor feels thin.
- **Loot-box LLM call: async with local fallback** — the box opens immediately client-side; if the Ollama response isn't back within a timeout, a pre-written local template for that tier is used instead so gameplay never stalls waiting on the model.

## AI content integration design (loot + achievements)

This is the core experiment: how much real content generation (not just flavor text) can an LLM own, while staying safe/balanced and never blocking gameplay. Both features hit Ollama directly from GDScript via `HTTPRequest`, `POST http://localhost:11434/api/generate`, with `"format": "json"` and `"stream": false` so a single response body contains the full JSON payload to parse.

### Loot-box generation

**Trigger (revised 2026-09-09): achievement-gated.** A loot box is only opened when that floor's achievement call (see below) actually earns one — no achievement, no loot. This runs achievements *before* loot at floor-end now (previously the reverse, and independent of each other), specifically so the loot call can be handed the achievement's title/description and told to make the item thematically tied to it, rather than the two being generated as unrelated flavor. Tier is still *not* LLM-decided — it's computed deterministically client-side, from the same performance formula over that floor's points and damage taken (exact formula/thresholds still TBD — see open questions). The LLM only fills in the box's contents within that tier's constraints, now steered by the achievement's theme.

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
- **Loot is now achievement-gated (2026-09-09):** `floor.gd`'s `_end_floor()` calls `get_achievement()` first; `get_loot()` (and `player.apply_loot()`) only run inside the `achievement != null` branch, passed the achievement dict so `OllamaClient._build_loot_prompt()` can instruct the model to tie the item's name/flavor_text to it. Since achievements are deliberately selective ("most runs should NOT get one"), this makes loot correspondingly rare — a real pacing change from the old every-floor loot box, not yet playtested for feel.

## Combat abilities: telegraphed attacks + a System AI that actively hunts your patterns (2026-09-09)

**Why:** the bomb and laser (formerly "magic missile") were both instant-hit — a bomb exploded the moment it landed, a missile was a hitscan beam. Diego wants enemies able to *see and react* to these attacks. The first cut of the "reaction" was a hand-coded formula (dodge chance scaling linearly with the player's lifetime bomb/missile use counts) — **rejected**: "the problem is that i would like for this adaptation to come from the llm, not a clever coded solution." Redirected further: it shouldn't just be a tuned number either — the LLM should be characterized as the game's actual antagonist (the "System AI" mentioned in this doc's Concept section), an intelligence that finds Carl and Donut's suffering entertaining and actively invents ways to counter their habits — and it should be able to reach for more than just dodge chance (new mechanical behaviors, not only tuning existing levers, per Diego's explicit choice when asked to scope this).

**Bomb (`scripts/bomb.gd`, new):** left-click now spawns a `Bomb` prop at the impact point instead of dealing damage immediately. It sits for a `FUSE_DURATION` (0.9s placeholder) — visibly pulsing via `_draw()` — before exploding for the same AOE damage as before. The instant it lands, every enemy within blast radius + a margin gets one dodge roll.

**Bug found and fixed (2026-09-09):** Diego reported enemies dodging out of the blast radius but then walking straight back into it before the bomb went off. Cause: `Enemy.try_dodge_point()` always used the fixed `DODGE_DURATION` (0.35s) regardless of caller, so a dodge ended well before a bomb's 0.9s fuse did — the enemy resumed chasing the player, and since a bomb is typically thrown roughly between the player and an approaching enemy, "chase the player" often meant walking straight back through the bomb's position while it was still live. Fix: `try_dodge_point()` now takes an optional `duration` param, and `Bomb` passes its own `FUSE_DURATION` instead of relying on the default — an enemy that dodges a bomb now flees for the bomb's entire remaining life, not a fixed short window. (`try_dodge_line`, for lasers, keeps the short fixed duration — a projectile resolves in a fraction of a second either way, so there's no equivalent gap to fall into.) Verified via a throwaway regression script reproducing the exact geometry (bomb between player and enemy) — enemy now survives undamaged instead of dying to its own dodge.

**Laser (`scripts/laser.gd`, new; replaces the old instant missile hitscan):** right-click now spawns a `Laser` prop that travels in a straight line at `SPEED` (900px/s placeholder) and damages the first enemy it touches, or fades out past `max_range`. The instant it's fired, every enemy near its path gets one dodge roll. (Internally this ability is still tracked as "missile" — `floor_missiles_cast`, `dominant_ability: "missile"`, etc. — only the projectile behavior and its presentation as a laser bolt changed, to avoid an unrelated rename across the LLM prompt/schema plumbing.)

**Dodge mechanic (`scripts/enemy.gd`):** `Enemy.try_dodge_point(from, chance)` (bombs) and `Enemy.try_dodge_line(origin, dir, max_range, chance)` (lasers) each roll `chance`, and on success set a `_dodge_timer`/`_dodge_dir` that `_physics_process` uses to override normal player-chasing movement for `DODGE_DURATION` (0.35s) at `DODGE_SPEED_MULTIPLIER` (1.4x) speed — fleeing radially from a bomb, sidestepping perpendicular to a laser's path. `Boss extends Enemy` and inherits this unchanged, so bosses dodge too. This part is pure mechanics with no adaptive logic of its own — `chance` is just a number handed in from outside; see below for where that number actually comes from.

**The System AI (`scripts/curator_generator.gd` + `scripts/ollama_client.gd` + `scripts/enemy_spawner.gd`, revised):** the existing twice-per-floor "curator" LLM call (see "Long-term direction" below) was extended rather than duplicated — the same call that maintains the narrative character profile now also outputs a live **tactic** against the player, in-character as the System AI. `CuratorGenerator`'s schema gained:
- `tactic`: enum `none | ambush | swarm | counter_bomb | counter_laser | aggression | early_boss` — mostly for flavor/toast selection and making the model commit to one coherent idea per cycle rather than nudging every number at once.
- `bomb_dodge_chance` / `missile_dodge_chance` (0.0–0.6), `spawn_interval_multiplier` / `spawn_radius_multiplier` / `boss_threshold_multiplier` (0.3–1.0, lower = more aggressive), `aggression_multiplier` (1.0–1.6) — **the LLM sets each of these numbers itself**; `CuratorGenerator.validate_and_clamp()` only clamps them into their safety range (same discipline as `LootGenerator`'s power budget) and defaults any missing/invalid one to its neutral no-op value. There is no code path anywhere that derives these from a formula over usage counts — the prompt (`OllamaClient._build_curator_prompt`) hands the model this window's bomb/laser counts plus the previous profile (which already carries its own last-chosen numbers forward) and lets it decide what to do with that, in character, each cycle.
- `ai_commentary` (<=140 chars) — an in-character taunt, shown to the player as a "System AI: ..." toast whenever it says something (`floor.gd._apply_curator_profile`), so the adaptation is visible, not just felt.

`EnemySpawner.apply_profile()` applies whatever the System AI decided to the live spawner (spawn interval/radius, aggression, boss threshold — normalizing the boss threshold against the *previous* multiplier so repeated calls with an unchanged tactic don't compound); `Player._get_character_profile()` reads `bomb_dodge_chance`/`missile_dodge_chance` straight off `floor.gd`'s `character_profile` when spawning a `Bomb`/`Laser`. Because the profile already persists across floors unmodified except by the curator's own replace-in-place updates, "learning across the whole run" (Diego's earlier explicit choice) falls out of the existing curator persistence for free — no separate lifetime counters were needed, and the ones added for the earlier formula-based attempt were removed.

**Not yet tuned/tested:** fuse duration, laser speed, dodge duration/speed, and every one of the System AI's safety ranges are first-guess placeholders, same status as the loot power budgets and floor speed step. Whether a 3B local model reliably commits to a coherent, *noticeably* aggressive tactic (per the prompt's "don't be shy" instruction) rather than playing it safe near the neutral defaults is an open question — not yet played by hand.

## Long-term direction: full RPG driven by player-behavior AI

**Vision (stated 2026-09-06):** the loot/achievement LLM integration is the first step toward a larger goal — evolving DCC into an RPG where the LLM's decisions (loot, achievements, and eventually dialogue/narrative/difficulty) are shaped by the player's *entire* behavioral history (movement patterns, ability usage, risk-taking, decisions made), not just the current floor's raw stats.

**Feasibility constraint driving the design:** the LLM backend is a local model (`llama3.2:latest`, 6s call timeout, gameplay must never block on it — see "AI content integration design" above). Raw event streams (every position sample, every input) are far too large to hand the model directly — this must be solved with layering, not brute force.

**Chosen architecture — two layers, kept deliberately separate:**

1. **Raw event log (local-only, full fidelity).** Extend the existing `ContentLogger` JSONL-append pattern (currently used for loot/achievement decisions, see `scripts/content_logger.gd`) to also record movement/ability events. This never gets sent to the LLM directly — it's for later offline analysis and as future curator-agent input.
2. **Code-side numeric aggregation (cheap, deterministic, already partly built).** `Player` tracks running per-floor totals — `floor_distance_moved`, `floor_bombs_thrown`, `floor_missiles_cast` — reset each floor via `reset_floor_stats()`, fed into the achievement prompt as plain numbers. This stays as-is; a sum or average is not something worth spending an LLM call on.

**New third layer — a "curator" LLM pass (periodic, narrative-focused):** where option 2 falls short is qualitative/narrative synthesis — condensing accumulated free text (past loot flavor text, past achievement titles/descriptions) plus this window's numeric aggregates into a running "character profile" that then feeds into *future* loot/achievement calls (and later, dialogue/difficulty decisions), keeping the AI's output consistent with the player's established playstyle and story-so-far.

Key design constraint: **the curator profile must replace itself each cycle, not append.** It has to stay a fixed size regardless of how many floors have passed (floor 2's profile and floor 9's profile must cost the same tokens), or "lightweight" breaks down over a long run. Each curation call takes {previous profile + this window's raw events/aggregates} and produces a new profile of the same shape — never a growing list.

**Cadence (decided 2026-09-09): twice per floor, timer-driven.** First curator call fires when `floor.gd`'s `time_remaining` crosses the halfway point of `floor_duration` (a new mid-floor checkpoint — no such trigger exists yet); second call fires at floor-end, piggybacking on the existing loot+achievement checkpoint in `_end_floor()`. Mid-floor call only has that window's partial events/aggregates to work with (no floor-end outcome yet); floor-end call sees the full floor. Stacking a third local-model call onto an already-busy floor-end still risks compounding latency (~4-5s cold each), so the mid-floor call is the cheaper of the two moments to add first if latency becomes a problem — it doesn't compete with the loot/achievement calls for the same instant.

**Curator output schema** (extended 2026-09-09 with the System AI's tactical fields — see "Combat abilities" below for why and how those are used; this is the complete, current schema):
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
  "tone": "grim",
  "tactic": "counter_bomb",
  "bomb_dodge_chance": 0.45,
  "missile_dodge_chance": 0.0,
  "spawn_interval_multiplier": 1.0,
  "spawn_radius_multiplier": 1.0,
  "aggression_multiplier": 1.0,
  "boss_threshold_multiplier": 1.0,
  "ai_commentary": "You throw bombs like they're free. Let's see how well you dodge what dodges you back."
}
```
- `playstyle_tags`: 0-3 short enum-like tags.
- `risk_profile`: enum `reckless | balanced | cautious`, derived from damage-taken/points ratio.
- `dominant_ability`: enum `bomb | missile | auto_attack | balanced`.
- `combat_style_summary`: <=140 chars, one line.
- `narrative_arc`: <=200 chars, the running "character legend" carried forward each cycle.
- `notable_moments`: 0-3 entries, <=80 chars each — bounded, so old moments are expected to silently drop off as new ones crowd them out (completeness traded for fixed size, same tradeoff as the profile as a whole).
- `tone`: enum `heroic | comedic | grim | chaotic`, kept for consistency with future loot/achievement flavor text.
- `tactic`: enum `none | ambush | swarm | counter_bomb | counter_laser | aggression | early_boss` — the System AI's current live tactic against the player; see "Combat abilities" for what each one drives mechanically.
- `bomb_dodge_chance` / `missile_dodge_chance`: 0.0-0.6, applied directly to `Bomb`/`Laser` spawns via `Player`.
- `spawn_interval_multiplier` / `spawn_radius_multiplier` / `boss_threshold_multiplier`: 0.3-1.0 (lower = more aggressive), applied to `EnemySpawner`.
- `aggression_multiplier`: 1.0-1.6, applied to enemy speed and contact damage.
- `ai_commentary`: <=140 chars, an in-character taunt shown to the player as a toast when non-empty.

All fields need the same client-side validation discipline as loot/achievements already have (`LootGenerator.validate_and_clamp`, achievement title/description clamps in `ollama_client.gd`) — bounded enums and length-clamped strings, never trusting raw model output. Critically, the six tactical numbers above are **never derived from a formula** — the LLM sets each one itself each cycle; code only clamps them into their safety range (see "Combat abilities" for the rejected formula-based attempt this replaced).

**Implementation status (2026-09-09): implemented.** `scripts/curator_generator.gd` (`CuratorGenerator`) validates/clamps raw model output against this exact schema, mirroring `LootGenerator.validate_and_clamp` — on failure (invalid JSON, missing fields) the previous profile is kept unchanged rather than falling back to generated content, since there's no equivalent of a "fallback item" for a character profile. `OllamaClient.get_curator_update()` implements the call + fallback + `ContentLogger` logging (`kind: "curator"`), and `floor.gd` owns `character_profile` (stored right on the floor controller, next to `floor_points`/`floor_damage_taken` as anticipated) plus the twice-per-floor cadence:
- Mid-floor: `_process()` fires `_run_mid_floor_curator()` once when `time_remaining` crosses `floor_duration / 2.0` (`_mid_floor_curator_done` guards against re-firing; reset in `_start_next_floor()`). Fire-and-forget — it awaits internally without blocking `_process()`.
- Floor-end: `_end_floor()` calls it again after the loot/achievement sequence, using the full floor's aggregates plus the outcome.
- **Race guard:** a `_curator_busy` flag serializes the two calls — if the mid-floor call is still in flight when floor-end tries to fire (realistic with a short `DCC_FLOOR_DURATION` test floor plus a cold Ollama load), `_end_floor` awaits it first so a late-arriving mid-floor result can never land after, and silently overwrite, the floor-end update.
- The resulting profile is threaded into both `get_loot()` and `get_achievement()` as an optional `profile` argument — `OllamaClient._profile_line()` renders it into one prompt line (tags/tone/summary/narrative) when non-empty, so future loot flavor text and achievements can be consistent with the player's established playstyle.

**Not yet done:** real playtesting to see whether the model's profile updates are actually coherent/stable across a run (still local `llama3.2:latest`, same quality ceiling as loot/achievements); whether twice-per-floor cadence is worth the extra latency in practice or should be pared back to once-per-floor.

## Open questions / next steps

- [x] First playable slice built — single floor, 90s survive-the-timer loop (`scenes/Floor.tscn` + `scripts/`): free movement, auto-attack nearest enemy, ramping enemy spawner, contact damage, XP pickups + level-up choice screen, floor ends on timer expiry or player death, `LootGenerator`/`AchievementGenerator` wired with local fallback content (Ollama call is the next step, not yet connected — see AI integration section). Verified error-free via headless run (`godot --headless --path . --quit-after N`) and confirmed rendering visually (screenshot of the running game window).
- [x] Expanded to 10 sequential floors — same 90s timer per floor; clearing one auto-starts the next (`floor.gd`: `current_floor`/`MAX_FLOOR`). Each floor bumps a monster speed multiplier (`FLOOR_SPEED_STEP = 0.15`, so floor 10 ≈ 2.35x floor 1's speed), stacking with the existing within-floor elapsed-time ramp. Points accumulate across the whole run (shown in HUD); points/damage-taken used for the loot tier formula reset each floor. Dying ends the run at whatever floor you're on; clearing floor 10 ends it as "run complete." Not yet playtested for feel — user is testing this locally.
- [x] LLM-generated loot + achievements — see "AI content integration design" > "Implementation status" above. Live Ollama calls confirmed working end-to-end with real generated content.
- [x] Loot is now mechanically applied to the player — `Player.apply_loot()` (fixed alongside a pre-existing bug where `switch_form()` silently wiped range/speed bonuses on Carl/Donut switch).
- [x] Boss enemies — `EnemySpawner` spawns one after a randomized 15-25 regular kills, pausing further boss spawns (not the horde) until it dies; see "Combat abilities" for how the System AI can pull the next boss in sooner (`early_boss` tactic).
- [x] Active abilities — bomb (delayed AOE) and laser (traveling projectile), both dodgeable; see "Combat abilities" section.
- [ ] Known gaps: no "stairs" mechanic (floor-clear = survive the timer, not reach an exit, per the earlier VS-style decision); no restart/game-over UI after a full run ends (reload the scene manually); the 0.15-per-floor speed step, the loot tier/power-budget numbers, and every System AI safety range are all still untuned placeholders.
- [ ] Loot/leveling specifics still open: exact point/damage formula for tier thresholds, XP curve. Level-up itself is decided and implemented — automatic flat stat bonus on every level, no choice screen (`Player.apply_level_up_bonus`) — replacing the earlier "VS-style choice screen" idea.
- [x] Companion pet / party-model question — resolved by superseding the switch-attacker plan entirely: Carl and Donut now act as one combatant with two aimed abilities plus auto-attack (see "Combat abilities"), so there's no separate "Donut as active attacker" state to design for anymore.
- [x] Godot install/setup on this machine — installed via winget, v4.7.2 standard build confirmed working
- [x] Reality-show meta layer — deprioritized, out of scope for now
- [x] AI content-generation request/response shape for loot-box content + achievements — see "AI content integration design" section above; remaining implementation-level TBDs (tier formula, stat ranges, model choice, timeout) listed there
- [ ] Start Ollama and pick/pull a local model to use for this experiment
- [x] Implement the "curator" LLM pass described above — twice-per-floor cadence, `CuratorGenerator` validation, `OllamaClient.get_curator_update()`, `floor.gd` wiring (mid-floor + floor-end, race-guarded), and threading the profile into loot/achievement prompts are all in place. Not yet playtested for output quality/coherence over a real run.
- [ ] Read further into the books for more concrete material (floor themes, specific enemies/items) to draw from

## Reference

- Plot research notes (Book 1): World Dungeon is an 18-level structure; protagonist Carl (Coast Guard vet) and Princess Donut (his ex's cat, becomes sapient via an enchanted biscuit); tutorial guide Mordecai; floors 1–2 covered in book 1 along with early audience/interview beats (host Odette) and a set-up quest for Donut (hunting Blood Sultanate royalty by floor nine).
