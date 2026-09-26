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

**Trigger (revised 2026-09-09): achievement-gated.** A loot box is only opened when that floor's achievement call (see below) actually earns one — no achievement, no loot. This runs achievements *before* loot at floor-end now (previously the reverse, and independent of each other), specifically so the loot call can be handed the achievement's title/description and told to make the item thematically tied to it, rather than the two being generated as unrelated flavor. Tier is still *not* LLM-decided — it's computed deterministically client-side. The LLM only fills in the box's contents within that tier's constraints, now steered by the achievement's theme.

**Tier is floor-relative, not a flat point scale (revised 2026-09-11).** A Monte Carlo simulation of the actual spawn/attack math (auto-attack only, no bomb/laser, zero damage taken — an optimistic floor, not a ceiling) showed raw `floor_points` grows sharply across a run purely from the player's own level/damage scaling: median floor 1 ~570, climbing to ~1400 by floor 10 as attack cooldown bottoms out. The original flat thresholds (50/150/350/700) made "legendary" the default outcome by the mid-run regardless of how well that floor was actually played. `LootGenerator.compute_tier()` now takes `floor_num` and compares `score = points - damage_taken*2.0` against a per-floor baseline (`FLOOR_BASELINE_SCORE`, the simulation's median per floor) as a *ratio* — `<0.5` common, `<0.85` uncommon, `<1.15` rare, `<1.5` epic, else legendary — so a ratio of 1.0 ("an average floor for where you are in the run") always lands on "rare," at any floor number.

**The System AI can shift the bar itself — `loot_generosity_multiplier` (2026-09-11).** Per Diego's explicit direction, this isn't just a static curve: the curator profile gained `loot_generosity_multiplier` (0.7–1.4, 1.0 = neutral), which multiplies the per-floor baseline before the ratio is computed. Below 1.0 lowers the bar (a generous mood, easier to hit a high tier); above 1.0 raises it (a stingy mood). Same discipline as every other System AI tactical number (see "Combat abilities" below): the LLM picks the value in-character each cycle, `CuratorGenerator.validate_and_clamp()` only clamps it into its safety range, never derives it from a formula.

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
`achievement` is `null` when `earned` is `false`. Achievements are pure bonus/flavor (no mechanical effect for now).

**Death never awards an achievement (revised 2026-09-11).** This call is now only ever made for outcome `"cleared"` — `floor.gd`'s `_end_floor()` branches on outcome before deciding what to do at all: death (`"collapsed"`) skips achievements/loot entirely and instead calls `OllamaClient.get_game_over_message()`, a small separate LLM call that just narrates the run's end in-character (schema: `{"message": string (<=160 chars)}`), with `AchievementGenerator.generate_game_over_message()` as its local fallback. `AchievementGenerator`'s old "Buried in Rubble" collapsed-outcome rule was removed since it's now unreachable.

**The "no achievement" toast is now LLM-authored too.** `get_achievement()` always returns `{"earned": bool, "achievement": dict|null, "message": string}` — when nothing was earned, `message` is the model's own in-character line about why (replacing the old hardcoded "No achievement this time — no loot." toast), with `AchievementGenerator.generate_no_award_message()` as the local fallback if the call fails or the model leaves it blank.

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

**Second dodge bug found and fixed (2026-09-11), this time on the laser side.** The line above about lasers not needing special handling turned out to be wrong in a different way than the bomb bug: at `Laser.SPEED` (900px/s) with `HIT_RADIUS` (14px), an enemy starting right on the beam's line only has enough time to physically sidestep clear of that radius if it's more than ~130px along the beam's path when fired (`DODGE_SPEED_MULTIPLIER`-boosted dodge speed × transit time > 14px, worked out from the actual constants). Real engagements happen well inside that range — auto-attack range is 140px, contact damage triggers at ~28px — so a "successful" `missile_dodge_chance` roll on a close enemy was frequently a geometrically wasted roll: the RNG said dodge, but the beam physically outran the sidestep before it moved far enough. This quietly undermined the stat and the `counter_laser` tactic for exactly the enemies most likely to matter. Fix: a successful `try_dodge_line` now also grants `LASER_DODGE_IFRAME` (0.3s, comfortably covers any laser's full possible flight time at `max_range`/`SPEED`) of laser-damage immunity, checked by `Laser` before applying damage — a "you dodged" roll now reliably means "you don't get hit," regardless of how little physical space there was to react in. (The beam passes through a dodging enemy rather than fizzling, so it can still hit whoever's behind them.)

**Laser (`scripts/laser.gd`, new; replaces the old instant missile hitscan):** right-click now spawns a `Laser` prop that travels in a straight line at `SPEED` (900px/s placeholder) and damages the first enemy it touches, or fades out past `max_range`. The instant it's fired, every enemy near its path gets one dodge roll. (Internally this ability is still tracked as "missile" — `floor_missiles_cast`, `dominant_ability: "missile"`, etc. — only the projectile behavior and its presentation as a laser bolt changed, to avoid an unrelated rename across the LLM prompt/schema plumbing.)

**Dodge mechanic (`scripts/enemy.gd`):** `Enemy.try_dodge_point(from, chance)` (bombs) and `Enemy.try_dodge_line(origin, dir, max_range, chance)` (lasers) each roll `chance`, and on success set a `_dodge_timer`/`_dodge_dir` that `_physics_process` uses to override normal player-chasing movement for `DODGE_DURATION` (0.35s) at `DODGE_SPEED_MULTIPLIER` (1.4x) speed — fleeing radially from a bomb, sidestepping perpendicular to a laser's path. A successful line-dodge also sets `_laser_iframe_timer` (see the second dodge bug fix below) so the physical sidestep isn't the only thing standing between the enemy and the beam. `Boss extends Enemy` and inherits this unchanged, so bosses dodge too. This part is pure mechanics with no adaptive logic of its own — `chance` is just a number handed in from outside; see below for where that number actually comes from.

**The System AI (`scripts/curator_generator.gd` + `scripts/ollama_client.gd` + `scripts/enemy_spawner.gd`, revised):** the existing twice-per-floor "curator" LLM call (see "Long-term direction" below) was extended rather than duplicated — the same call that maintains the narrative character profile now also outputs a live **tactic** against the player, in-character as the System AI. `CuratorGenerator`'s schema gained:
- `tactic`: enum `none | ambush | swarm | counter_bomb | counter_laser | aggression | early_boss` — mostly for flavor/toast selection and making the model commit to one coherent idea per cycle rather than nudging every number at once.
- `bomb_dodge_chance` / `missile_dodge_chance` (0.0–0.6), `spawn_interval_multiplier` / `spawn_radius_multiplier` / `boss_threshold_multiplier` (0.3–1.0, lower = more aggressive), `aggression_multiplier` (1.0–1.6) — **the LLM sets each of these numbers itself**; `CuratorGenerator.validate_and_clamp()` only clamps them into their safety range (same discipline as `LootGenerator`'s power budget) and defaults any missing/invalid one to its neutral no-op value. There is no code path anywhere that derives these from a formula over usage counts — the prompt (`OllamaClient._build_curator_prompt`) hands the model this window's bomb/laser counts plus the previous profile (which already carries its own last-chosen numbers forward) and lets it decide what to do with that, in character, each cycle.
- `ai_commentary` (<=140 chars) — an in-character taunt, shown to the player as a "System AI: ..." toast whenever it says something (`floor.gd._apply_curator_profile`), so the adaptation is visible, not just felt.

`EnemySpawner.apply_profile()` applies whatever the System AI decided to the live spawner (spawn interval/radius, aggression, boss threshold — normalizing the boss threshold against the *previous* multiplier so repeated calls with an unchanged tactic don't compound); `Player._get_character_profile()` reads `bomb_dodge_chance`/`missile_dodge_chance` straight off `floor.gd`'s `character_profile` when spawning a `Bomb`/`Laser`. Because the profile already persists across floors unmodified except by the curator's own replace-in-place updates, "learning across the whole run" (Diego's earlier explicit choice) falls out of the existing curator persistence for free — no separate lifetime counters were needed, and the ones added for the earlier formula-based attempt were removed.

**Not yet tuned/tested:** fuse duration, laser speed, dodge duration/speed, and the individual System AI safety ranges themselves (`DODGE_CHANCE_RANGE`, `SPAWN_INTERVAL_MULT_RANGE`, etc.) are still first-guess placeholders, same status as the floor speed step — unlike the loot tier work, there was no tractable simulation to ground these in, so they're genuinely waiting on hands-on play. Whether a 3B local model reliably commits to a coherent, *noticeably* aggressive tactic (per the prompt's "don't be shy" instruction) rather than playing it safe near the neutral defaults is an open question — not yet played by hand.

**Joint threat-budget safety net added (2026-09-11).** Each per-field range was already clamped independently, but nothing stopped every lever maxing out simultaneously if the model ignores the prompt's "push only the one or two numbers relevant to your tactic" instruction — a real risk given the local 3B model has already been observed doing exactly this once. `CuratorGenerator.validate_and_clamp()` now scores each of the six combat-difficulty fields (both dodge chances, spawn interval/radius, aggression, boss threshold — everything except `loot_generosity_multiplier`, which isn't a difficulty lever) as a normalized 0-1 "threat" (0 = neutral, 1 = at its extreme), sums them, and if the total exceeds `THREAT_BUDGET` (2.0 — chosen to exactly match "one or two fields maxed, rest neutral," so compliant responses are never touched), scales every field's deviation from neutral down proportionally. Same discipline as `LootGenerator` scaling down an over-budget item's effects rather than rejecting the response outright.

## Live director: the System AI steers the fight every second (2026-09-20)

The curator (twice per floor) sets the System AI's narrative profile, `ai_approach`, `loot_generosity_multiplier` and a *standing* tactic. That cadence was too coarse — the AI could only react at the half-floor mark — so a second, much smaller LLM loop now lets it adjust the fight **every second**.

**Why a plan, not a call per second:** measured on the dev machine (RTX 4070 laptop, `llama3.2`), a compact 6-beat response takes ~2-4s (cold first call ~4s). A call per second is impossible, so the model writes a **plan of per-second beats** and the game plays one beat per second, requesting the next plan *before* the current one ends (prefetch when <=3 beats remain) so plans chain without gaps. Every beat is still the LLM's own decision — code only schedules, smooths and clamps.

**Pieces:**
- `scripts/system_director.gd` (`SystemDirector`, child of the floor): plays the plan (`BEAT_SEC`=1s), eases the live numbers toward each beat (`SMOOTH_RATE`, exponential — smoothing only, no decisions), prefetches the next plan, holds the last beat `HOLD_LAST_BEAT_SEC` if the next plan is late, then falls back to the curator's standing numbers (also the behavior whenever Ollama is down). Backs off exponentially on failed calls. Pauses its requests while the curator call is in flight so the two don't queue on Ollama. `reset()` at each new floor drops the old plan.
- `scripts/director_generator.gd` (`DirectorGenerator`): validates/clamps a plan (`BEAT_COUNT`=6). Beats carry a tactic label + five numbers (both dodge chances, spawn interval/radius, aggression). `boss_threshold_multiplier` is *not* a beat field (it counts kills; stays with the curator). Missing fields = neutral; short plans are accepted (last beat is held, and a re-request fires immediately).
- `CuratorGenerator.clamp_tactics()` — the six-field clamp + joint `THREAT_BUDGET`, extracted so curator and director beats get identical safety.
- `OllamaClient.get_director_plan()` / `_build_director_prompt()` — compact prompt (standing `ai_approach`, live state, deltas since the last look, the last beat played); `DIRECTOR_TIMEOUT_SEC`=5, `DIRECTOR_MAX_TOKENS`=500 via the new `options` arg on `_request_json`. Logged to `ContentLogger` as `kind: "director"` (context + raw response + result; prompt omitted since it's templated).
- `floor.gd`: `get_effective_profile()` = curator profile with `director.live` merged over it; the player (dodge chances) and spawner (`apply_profile` every frame, idempotent) read that instead of `character_profile`.
- **Aggression is now live.** It used to be baked into each enemy at spawn, so a beat would only reach newly spawned enemies. `Enemy` now reads `spawner.get_aggression()` every physics frame for both speed and contact damage.
- HUD shows the current beat's tactic ("System AI: swarm") so the per-second moves are visible.

**Verified (headless only):** the director fired against the real model, produced valid 6-beat plans, and chained a second plan after the first. **Not hand-played yet.**

**Open / expected to need tuning:** in the first real output the model ignores "1-2 numbers per beat" and swings hard (e.g. spawn multiplier 1.0 -> 0.3 -> 0.9 between consecutive seconds) — the threat budget catches the worst of it, but the *feel* of per-second swings (and `SMOOTH_RATE`) needs playtesting. Whether a 3B model produces a coherent pacing arc, rather than noise, is unproven. Beat/prefetch/hold constants are first guesses.

## UI & art pass (2026-09-20)

Still no image assets — everything is code-drawn — but the look is now cohesive and readable. **Visual/UI only: no gameplay numbers or AI/LLM logic changed.**

**Where things live**
- `scripts/ui_style.gd` (`UIStyle`) — the single source of the look: palette constants (gold = Carl, pink = Donut, hot red = System AI, amber = bombs, cyan = laser, mint = XP, purple = boss), tier/tactic colors and labels, `FLOOR_LOOKS` (name + ground color + accent for floors 1-10), the shared `Theme` (`build_theme()`), fonts (`SystemFont`: Bahnschrift -> Segoe UI -> Arial -> Godot default, so it degrades gracefully off Windows). (Camera-shake strength used to be a `SHAKE_SCALE` constant here; it is now the `shake_scale` setting in `GameSettings`, see "Esc menu, SFX & restart fix".)
- `scripts/hud.gd` — rebuilt: floor/name/score panel (top-left), timer + progress bar (top-center, amber/red under 30s/10s) with a boss health bar, a **System AI panel** (top-right: blinking rec dot, the live tactic in the tactic's color with a flash + glitch-scramble whenever it changes, and an aggression meter fed by `spawner.get_aggression()`), bottom-center ability slots with cooldown wipes (`scripts/ability_slot.gd`), HP bar with a lagging damage trail and low-HP throb, XP bar + level. Transient messages: `show_toast(text, kind, duration, accent, title)` -> `scripts/toast_panel.gd` cards (System AI taunts hang under the System AI panel with a typewriter reveal; achievement/loot/boss/death cards low-center, loot tinted by tier), `show_banner()` big center callouts (floor start, boss, level-up, floor cleared/crawler down), and `show_run_over()` a final card with floor/points/level. **R restarts** (reloads the scene) once the run-over card is up — this closes the old "no restart" gap.
- `scripts/fx_layer.gd` (`FxLayer`) — one pooled node drawing all short-lived world FX (death bursts, sparks, rings, floating damage numbers, "DODGED" callouts) plus camera shake; capped at 480 live effects. Call via `FxLayer.of(node)`.
- `scripts/screen_overlay.gd` (`ScreenOverlay`) — a tiny canvas shader: constant vignette, red heartbeat edges as HP drops below 35%, and a hit flash.
- `scripts/background_grid.gd` — chunked (culled) tiled floor with hash-based flagstone variation, cracks and pebbles, retinted per floor via `set_floor_theme(n)` (also sets the clear color).
- Actor art: `player.gd` (aura, shadow, eyes tracking the cursor, orbiting Donut, faint auto-attack range ring, bomb landing reticle), `enemy.gd` (spiky googly-eyed blobs, hit flash, damage numbers, health pip, eyes glow hotter with System AI aggression, cyan ring while mid-dodge), `boss.gd` (horned, burning eyes, aura, clockwise HP ring), `bomb.gd` (blast zone with an inner fill that grows to meet the rim exactly at detonation, blink speeding up, burning fuse, explosion FX), `laser.gd` (glow + white core + tapering tail, trail motes, muzzle/impact sparks), `xp_orb.gd` (pulsing glow; golden for boss-sized drops).

**Gameplay-code plumbing added (behavior identical):** `Player.get_bomb_cooldown_fraction()` / `get_laser_cooldown_fraction()` getters; `Enemy.take_damage(amount, crit := false)` gained an optional `crit` flag (only colors the damage number); `Enemy._facing`/`_hit_flash` visual state; `floor.gd` now owns a `BackgroundGrid`/`FxLayer`/`ScreenOverlay`, feeds the HUD each frame, and passes toast `kind`s (replaces the old floor-start toast with a banner). `HUD.update_system_tactic()` takes an optional aggression arg.

**Testing hook:** `scripts/debug_capture.gd` (`DebugCapture`) is only added by `floor.gd` when env `DCC_CAPTURE_DIR` is set; it plays a scripted timeline (`DCC_CAPTURE_PLAN="3:close:12;6:shot:fight;..."`, actions listed in the file header) and saves viewport PNGs. Run windowed with `--audio-driver Dummy` to keep the soundtrack quiet.

**Verified:** headless run error-free; screenshots reviewed for early/fight/boss/bomb/laser/level-up/low-HP/floor-cleared/run-over states, a System AI toast, and floors 2/4/7/10 tints; restart-on-R exercised. **Not verified:** how any of it *feels* in real play (shake strength, flash intensity, how busy the FX get in a big crowd, HUD scale on other resolutions), the SystemFont fallback on a machine without Bahnschrift, and pressing R while an Ollama request is still in flight (the freed `OllamaClient` logs script errors from `_request_json`; normally requests have finished by the time the run-over card appears, but a force-restart mid-request will do it).

## Music & window (2026-09-20)

**Layout note:** the project now lives in `floor-survivors/` inside the `dcc/` repo, so more DCC games can sit beside it (the git repo root is `dcc/`; `.gitignore` stays at the root and its patterns match at any depth).

**Fullscreen.** `project.godot` starts fullscreen (`display/window/size/mode=3`, borderless) and pins the logical viewport to 1152x648 with `canvas_items` stretch + `keep` aspect. The pin matters for gameplay, not just looks: the camera is a fixed 1.5x zoom and enemies spawn 500px away, so an un-stretched 1080p window would show ~1280x720 world pixels and enemies would visibly pop in on screen. `scripts/window_controls.gd` (autoload) toggles fullscreen/windowed on `F11`. Other aspect ratios are letterboxed, not tested.

**Music: procedural 8-bit, original and license-free.** `tools/make_chiptune.py` (numpy, run from the game folder: `python tools/make_chiptune.py`, then reimport in Godot) synthesizes everything into `assets/audio/`:
- Five loop stems, all 16 bars / 132 BPM / A minor, cut to loop seamlessly: `pad`, `bass`, `drums`, `lead` (hook in bars 1-8, arpeggios in bars 9-16), `menace` (beating minor-2nd drone, lub-dub heartbeat, tritone stabs, riser).
- Four stingers: `sting_level_up`, `sting_floor_clear`, `sting_boss`, `sting_game_over` (sad trombone).

`scripts/audio_manager.gd` (autoload) plays the stems through one `AudioStreamSynchronized` (sample-locked) and fades each layer by polling the floor: **lead** and **menace** follow the System AI's live threat (sum of the director's per-second numbers' distance from neutral, same scoring as `THREAT_BUDGET`), **drums** follow enemy count, **menace** also rises on a boss and as HP drops (the heartbeat), floor end drops everything to a thin pad. Stingers fire on level-up, boss appearing, and floor end (clear vs. death); music ducks ~7 dB under them. `M` mutes. It only observes the floor and touches no gameplay files.

**Design note:** which stems play is a fixed presentation mapping over numbers the AI already chose — deliberately *not* an AI decision. If the AI should "conduct" the music, the cheap route is one extra `music_mood` field in the director's plan.

**Not done / untested:** verified headless only (music starts, stingers fire, no errors) — **nobody has listened to it yet**: mix balance, layer thresholds, fade speed and whether the synthesis sounds good are all first guesses. SFX and achievement/loot stingers were added 2026-09-21 (see "Esc menu, SFX & restart fix"); still no per-floor-band variations, boss stem set, or menu music.

## ai_approach investigation (2026-09-21)

**Symptom (Diego's playtests):** `ai_approach` was meant to be the System AI's stable, self-chosen strategy for the whole run, but it drifted every cycle.

**Evidence** (`logs/`, every logged curator cycle, plus a harness that plays a synthetic 5-floor run through the real `get_curator_update` path — `scripts/llm_approach_test.gd`, run with `godot --headless --path . --script res://scripts/llm_approach_test.gd`): on the old prompt the approach changed on **8 of 9** cycles after the first, with 9 distinct strings in 10 cycles. Real playtest logs showed the same, and three concrete causes:
1. **The model copied the prompt's example strings verbatim.** "Grind them down slowly through attrition and stinginess rather than flashy kills" (an *example* in the prompt) appeared as the model's "own" approach in four separate sessions.
2. **The prompt contradicted itself.** "KEEP IT STABLE and reuse it near-verbatim" sat a few lines above "produce an UPDATED profile ... refine it, don't just repeat it verbatim" — and the previous approach was buried inside a JSON blob that the model regenerated whole, so paraphrasing it was the path of least resistance.
3. **Approach was welded to the tactic.** The texts named the current tactic/ability ("exploit their aggression and bomb-happy tendencies"), so whenever the tactic changed the approach followed.

**Fix (the LLM still decides; code only honors the decision):** (`OllamaClient._approach_instructions`, `CuratorGenerator.resolve_approach`)
- The standing approach is quoted in its own block and *removed* from the JSON blob the model sees (`_profile_without_approach`).
- New output field **`revise_approach`** (boolean). The model must explicitly choose whether to change its approach; with an approach already set, the old text is kept unless the model said `true` AND wrote a replacement. On the first cycle (nothing set) it takes whatever the model wrote. This honors the model's own stated decision; it is not a formula over play data.
- All example approaches removed; the prompt describes what an approach *is* (the long game: pacing, cruelty vs. kindness, what it builds toward) and says not to name a tactic/ability/number in it.
- The contradictory "refine it" line now explicitly excludes `ai_approach`.

**Result** (same harness, real `llama3.2`, 5 floors / 10 cycles, three runs): changes after the first read dropped from 8/9 to **2/9** and **0/9** (the 2 landed on the scripted near-death floor, the kind of turning point it was told to react to), and an end-to-end game run kept one approach across all 6 real cycles, with the model itself answering `revise_approach: false`. No verbatim copies of the old examples. **Not yet judged by feel:** the approaches are stable and original but fairly generic ("toy with them..."); whether they visibly steer the run is a playtest question. A next lever if wanted: have the director's beats weigh the approach more prominently.

**Also noticed, not fixed:** the curator's 6s timeout occasionally trips (`fallback_no_response`, e.g. mid-floor 2 in a real run) when a director request is still in flight on the same Ollama at the moment the curator fires. The director only *stops starting* new requests while the curator is busy; it doesn't wait for one already running. Raising the curator's timeout, or holding the curator until the director's request lands, would cure it.

## Esc menu, SFX & restart fix (2026-09-21)

**Esc menu** (`scripts/pause_menu.gd`, `PauseMenu`, a CanvasLayer added by `floor.gd`): Resume / Restart run / Settings / Quit game; a settings page with music + SFX volume, mute, fullscreen, screen shake, and a "System AI language model" ON/OFF switch. Themed with `UIStyle` (its shared theme gained Button/HSlider styles); keyboard (arrows, left/right, Enter, Esc = back) and mouse both work, and hovering focuses.
- **One source of truth: `GameSettings`** (`scripts/game_settings.gd`, a static class — no autoload, so it also works in headless `--script` harnesses). The menu, `AudioManager` (M key, bus volumes), `WindowControls` (F11), `FxLayer` (shake) and `OllamaClient` all read/write it; persisted to `user://settings.cfg` (`ConfigFile`) and applied at startup. Setters apply immediately and mark the file dirty; `flush()` runs on slider release, page change, menu close and hotkeys.
- **LLM off** = `OllamaClient._request_json` returns null immediately, so every AI feature takes its existing local fallback; the director stops requesting plans and the curator's standing numbers apply.
- **Pause semantics:** opening pauses the tree; closing sets `paused = not floor_active` (so Resume never unpauses the floor-end sequence, which pauses on purpose); while open it re-asserts the pause each frame (a floor can start under the menu when the end-of-floor sequence finishes). Verified in a windowed run driven by `DebugCapture`: Esc / Esc / Esc cycle, Esc during the floor-end sequence then Resume stays paused, a new floor starting under the open menu stays frozen until Resume, and menu Restart doesn't leave a stuck pause.
- **Timeouts across a pause:** `PauseMenu.menu_open` (static) makes `OllamaClient._request_json` push its deadline out while the menu is up, so a long pause doesn't turn an arriving curator reply into a timeout. HUD ignores R while the menu is open. The menu resets that static in `_ready`/`_exit_tree`.

**Restart bug fixed** (pressing R / Restart while an Ollama request was in flight logged "Resumed function after await, but class instance is gone"): `floor.gd` now counts its LLM-awaiting coroutines (`_flows`: the mid-floor curator and the floor-end sequence), sleeps with an abortable `_wait()` instead of `create_timer`, and `restart_run()` sets `_quitting`, calls `OllamaClient.cancel()` (every in-flight/future request resolves to null on the next frame; ContentLogger is silenced so forced fallbacks aren't logged), waits for all coroutines and the director's request to unwind, and only then reloads. HUD's R and the menu's Restart both go through it. Verified: restart mid-request and from the menu, repeated reloads, no script errors.

**SFX + stingers:** `tools/make_chiptune.py sfx` renders `sfx_hit/kill/hurt/pickup/bomb_throw/bomb_boom/laser/dodge/ui_move/ui_click` and `sting_achievement`/`sting_loot` (same synth, no external assets). `AudioManager.play_sfx(name, pitch, jitter)` plays them from a 10-voice pool with per-effect trim, a per-effect minimum gap (a bomb killing ten enemies is one thud) and random pitch jitter; `play_sting(name, pitch)` ducks the music. They are called directly from the gameplay scripts (`player`, `bomb`, `enemy`, `xp_orb`); `floor.gd` fires the achievement/loot stingers (the loot chime rises in pitch with tier). Everything is on the `SFX` bus, so the menu's SFX slider covers it. **Nobody has listened to any of it** — levels and trims are first guesses, same as the music.

## First full playtest — log analysis (2026-09-21)

Diego played a full 10-floor clear with real Ollama calls (`logs/session_1790052606.jsonl`, 169 AI events, ~18 min, no deaths). Confirmed working: the `ai_approach` fix held for real (see previous section) — the same approach string survived 8 straight successful curator cycles with the model correctly answering `revise_approach: false` each time. Everything else below is a finding from that log, most-severe first.

**1. Zero achievements earned across all 10 floors -> zero loot boxes the entire run.** Since loot is achievement-gated, the game's core AI content feature never fired once in a full clear. Floor 1 was cleared with **0 damage taken** — exactly the kind of run the achievement prompt calls out as notable — and still declined. Two causes read off the actual decline messages: the "be selective, most runs should NOT get one" instruction is landing too hard on this model (10/10 declines observed), and the model's reasoning about the numbers it's given is often just wrong — it called a floor with ~13,700px of movement "barely moving," and one with ~11,500px "barely left your starting spot." Raw pixel counts apparently don't mean anything to it, so it free-associates a dismissive line regardless of the real stats. **NEXT SESSION:** loosen the achievement prompt's selectivity language and/or give it a normalized/comparative stat instead of raw px, and add a client-side circuit breaker (guarantee an achievement if none has fired in N floors) so the feature can't go fully dark for a whole run again.

**2. Mid-floor curator calls fail ~50% of the time (5/10) from Ollama contention with the director; floor-end calls are 10/10.** Every mid-floor timeout in the log lines up with a `SystemDirector` plan request still in flight on the same local Ollama instance, eating the curator's 6s budget while queued. The director already waits on `floor_node._curator_busy` before firing, but nothing stops the curator from firing while a director request is mid-flight — floor-end calls always land only because the director has already stopped issuing requests by then (`floor_active` is false). **NEXT SESSION:** make it mutual — have `_run_mid_floor_curator` wait for `director.is_request_in_flight()` to clear before firing, same pattern as the existing one-directional check.

**3. `ai_commentary` (the "System AI: ..." toast) repeats verbatim for long streaks** — the exact same sentence, word for word, for floors 6 through 9 (8 consecutive cycles). Same root cause as the `ai_approach` drift fixed earlier this session: the previous cycle's commentary is still embedded in the JSON blob echoed back to the model (`_profile_without_approach` only stripped `ai_approach`), so the model just copies it forward — except unlike `ai_approach`, commentary isn't supposed to persist at all; it's meant to be a fresh one-off line every cycle. **NEXT SESSION:** also strip `ai_commentary` from what's echoed back, with an explicit "never repeat a previous line" instruction.

**Smaller findings, lower priority:**
- `dominant_ability` stayed `"bomb"` for all 10 floors even as bomb usage collapsed from 46 uses (floor 1) to 1 (floor 10) — likely the same stale-field pattern as #3, just on a field with less player-visible impact.
- The standing `tactic` field only used 2 of its 7 options all run (`ambush` floors 1-3, then `swarm` floors 4-10 without a single switch back), and `early_boss` was never chosen once across 20 curator decisions — more evidence for the already-flagged "does the model commit to varied tactics or lock on and coast" open question.
- Ability usage (bombs + lasers combined) collapsed hard in the back half of the run while points kept climbing — a gameplay-balance/tuning observation for Diego's own read, not an AI-logic bug, so not something to "fix" with a coded formula.



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
  "loot_generosity_multiplier": 1.0,
  "ai_approach": "Grind them down slowly through attrition rather than flashy kills.",
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
- `loot_generosity_multiplier`: 0.7-1.4 (lower = more generous), multiplies the per-floor baseline score in `LootGenerator.compute_tier()` before the tier ratio is computed — see "Loot-box generation" above.
- `ai_approach`: <=160 chars, free text — the System AI's own self-chosen long-term strategy for the whole run (2026-09-11), distinct from `tactic` (the specific tool reached for *this* cycle). The model is prompted to establish it once (when the previous value is empty) and then keep it stable across cycles, only deliberately evolving it at a real turning point rather than rewriting it for variety — a bet on whether a small local model can maintain a consistent multi-cycle "identity" the same way it's already asked to commit to one tactic per cycle (see "Not yet tuned/tested" below and plan.md's existing note on the model playing tactics safe near neutral defaults — this is a harder version of that same open question). No safety clamp beyond a length cap is possible for free text the way the numeric fields get one.
- `revise_approach`: boolean, output-only (not stored in the profile) — the model's explicit decision whether to change `ai_approach` this cycle; see "ai_approach investigation".
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
- [ ] Known gaps: no "stairs" mechanic (floor-clear = survive the timer, not reach an exit, per the earlier VS-style decision); no restart/game-over UI after a full run ends (reload the scene manually); the 0.15-per-floor speed step, individual combat-feel numbers (bomb fuse/radius, laser speed, dodge duration/speed, cooldowns, boss multipliers), and the individual System AI safety range magnitudes (the ranges themselves, not the new joint threat-budget cap) are all still untuned placeholders pending real playtesting.
- [x] Loot tier is now floor-relative (2026-09-11), not a flat point scale — see "Loot-box generation" above (`LootGenerator.FLOOR_BASELINE_SCORE`, simulation-informed, still pending real playtesting to confirm the baseline curve and ratio bands feel right) plus the System AI's own `loot_generosity_multiplier` lever.
- [x] XP curve tuning (2026-09-11) — a Monte Carlo simulation of the actual combat/level math (same harness as the loot baseline work) showed level-ups collapsing from 5/floor on floor 1 to exactly 1/floor (sometimes 0) by floor 4 onward under the original `xp_to_next = xp_to_next * 1.25 + 5.0` curve: the multiplicative threshold growth compounded faster than the player's kill throughput could keep up with, stalling the only non-loot source of player power growth for most of a 10-floor run while enemies kept scaling up regardless. Retuned to `Player.XP_GROWTH_MULT` (1.12) / `XP_GROWTH_ADD` (4.0), which keeps at least ~1 level-up every floor throughout a full run in simulation (median final level ~24-25 instead of ~16-17). Because loot tier and level-up pacing are coupled — a gentler XP curve means higher damage/lower cooldown earlier, which raises achievable points per floor — `LootGenerator.FLOOR_BASELINE_SCORE` was re-simulated against the new curve rather than left stale (see "Loot-box generation" above). Level-up itself is decided and implemented — automatic flat stat bonus on every level, no choice screen (`Player.apply_level_up_bonus`) — replacing the earlier "VS-style choice screen" idea.
- [x] Companion pet / party-model question — resolved by superseding the switch-attacker plan entirely: Carl and Donut now act as one combatant with two aimed abilities plus auto-attack (see "Combat abilities"), so there's no separate "Donut as active attacker" state to design for anymore.
- [x] Godot install/setup on this machine — installed via winget, v4.7.2 standard build confirmed working
- [x] Reality-show meta layer — deprioritized, out of scope for now
- [x] AI content-generation request/response shape for loot-box content + achievements — see "AI content integration design" section above; remaining implementation-level TBDs (tier formula, stat ranges, model choice, timeout) listed there
- [x] Implement the "curator" LLM pass described above — twice-per-floor cadence, `CuratorGenerator` validation, `OllamaClient.get_curator_update()`, `floor.gd` wiring (mid-floor + floor-end, race-guarded), and threading the profile into loot/achievement prompts are all in place. Not yet playtested for output quality/coherence over a real run.
- [x] System AI gained `ai_approach` — its own self-chosen long-term strategy for the run, prompted to stay stable across cycles rather than being re-picked each time (2026-09-11) — plus a joint threat-budget safety net (`CuratorGenerator.THREAT_BUDGET`) so it can't max every tactical lever at once if it ignores the "push 1-2 numbers" instruction. See "Long-term direction" and "Combat abilities" sections. Whether the local 3B model can actually hold a consistent multi-cycle identity is unproven — not yet played by hand.
- [x] Death no longer awards achievements (2026-09-11) — `floor.gd` branches on outcome before deciding anything; a collapsed run gets a dedicated LLM-narrated game-over message (`OllamaClient.get_game_over_message`) instead of the achievement/loot flow, and the "no achievement" toast on a cleared floor is now LLM-authored too, not a hardcoded string. See "AI content integration design" section.
- [x] Laser dodge bug found and fixed (2026-09-11) — a laser travels too fast for a close-range enemy to physically sidestep clear of its hit radius in time, so a successful `missile_dodge_chance` roll was often wasted at exactly the ranges combat happens in; fixed with a brief damage-immunity window on a successful dodge instead of relying purely on repositioning. See "Combat abilities" section.
- [x] Live director (2026-09-20) — the System AI now steers the fight every second via a prefetched 6-beat LLM plan (`SystemDirector`), on top of the curator's twice-per-floor standing profile. See "Live director" section. Verified headless only; not hand-played.
- [x] UI & art pass (2026-09-20) — cohesive code-drawn look: shared `UIStyle` palette/theme, styled HUD with a System AI banner, toasts/banners/run-over card (R to restart), FX layer (death bursts, damage numbers, shake), telegraphed bomb/laser art, per-floor ground tints. Screenshot-verified only; not hand-played. See "UI & art pass" section.
- [ ] Tune the look by feel once played: FX density/shake strength, HUD scale at other resolutions, whether the checkerboard-ish floor tiles or the bomb/laser telegraphs need to be louder or quieter.
- [x] Fullscreen start + F11 toggle, procedural 8-bit adaptive music + stingers (2026-09-20) — see "Music & window". Headless-verified only; not listened to.
- [ ] Music follow-ups still open: per-floor-band variations, boss stem set, menu music, optional AI-chosen `music_mood`. (SFX + achievement/loot stingers done 2026-09-21.)
- [x] **Esc menu (pause + settings + quit)** — done 2026-09-21, see "Esc menu, SFX & restart fix". Remaining ideas: confirm-on-quit, key rebinding, a model-name field (only on/off exists), a main menu.
- [x] R-during-an-Ollama-request script errors fixed 2026-09-21 (`restart_run` drains in-flight coroutines first).
- [x] `ai_approach` drift investigated and fixed 2026-09-21 — see "ai_approach investigation". Judge by feel next playtest.
- [x] First full playtest (2026-09-21, no deaths, all 10 floors) — see "First full playtest — log analysis" for the full breakdown; `ai_approach` fix confirmed holding in real play.
- [ ] **NEXT SESSION, in priority order (all from the 2026-09-21 playtest log — see "First full playtest — log analysis" for full evidence):**
  1. Achievement generator awarded 0/10 floors, including a 0-damage floor-1 clear -> loot never fired all run. Loosen the "be selective" prompt language and/or give it normalized stats instead of raw px (it called ~13,700px "barely moving"); add a circuit breaker guaranteeing an achievement after N achievement-less floors.
  2. Mid-floor curator calls fail ~50% of the time from Ollama contention with an in-flight director request. Make `_run_mid_floor_curator` wait for `director.is_request_in_flight()` to clear, mirroring the director's existing wait on `_curator_busy`.
  3. `ai_commentary` (the System AI toast) repeated verbatim for 8 straight cycles (floors 6-9) — same root cause as the `ai_approach` drift bug, just on a field that was never fixed. Strip `ai_commentary` from the JSON blob echoed back to the model too, with an explicit "don't repeat a previous line" instruction.
  - Lower priority if time allows: `dominant_ability` went stale at "bomb" all run despite usage collapsing to near-zero; standing `tactic` only used 2 of 7 options and never picked `early_boss` once.
- [ ] Read further into the books for more concrete material (floor themes, specific enemies/items) to draw from

## Reference

- Plot research notes (Book 1): World Dungeon is an 18-level structure; protagonist Carl (Coast Guard vet) and Princess Donut (his ex's cat, becomes sapient via an enchanted biscuit); tutorial guide Mordecai; floors 1–2 covered in book 1 along with early audience/interview beats (host Odette) and a set-up quest for Donut (hunting Blood Sultanate royalty by floor nine).

## Sprite art pass (2026-09-25)

Actors are CC0 pixel-art sprites (0x72 DungeonTileset II + Dungeon Crawl Stone Soup) instead of circles: a per-floor roster of 3 enemies + a boss, Carl in boxers and leather jacket, Donut as a white Persian. `SpriteBank` (static) draws them; the code-drawn look is kept behind `GameSettings.sprite_art = false`. Gameplay unchanged. Roster drafted by the local model via `../tools/local_llm.py`, reviewed by hand. Details, roster table and next-step proposals: `docs/art.md`.

**Verified:** headless import and parse clean; screenshots of floors 1/4/5/7/10 with crowds and bosses. **Not verified:** feel in real play (crowd readability, flash/tint strength), other resolutions, export (`roster.json` needs `*.json` in the export include filter).

## Playtest fixes (2026-09-25)

The three open findings from the 2026-09-21 full playtest, fixed ahead of the next one:

1. **Zero achievements -> zero loot.** Two layers. (a) `OllamaClient._achievement_standouts` spots standout stats in code: HP lost <=10% or >=70%, no ability used, bombs >=10/min or lasers >=20/min, moving <15% or >90% of the time. A floor with a standout has earned an achievement, and the model is only asked to *write* it, from those facts. Even when told "that qualifies", llama3.2 declined 8/8 such floors in two verification runs. Floors with no standout stay the model's call. The prompt now shows movement as % of the time, damage as % of max HP and abilities per minute, never raw px. (b) Circuit breaker in `floor.gd`: after `ACHIEVEMENT_DROUGHT_MAX` (2) floors without one, `AchievementGenerator.drought_breaker` guarantees a local achievement.
2. **Mid-floor curator timeouts.** `_run_mid_floor_curator` now sets `_curator_busy` (the director stops starting requests), then waits up to `CURATOR_WAIT_MAX` (5.5s) for an in-flight director request before calling.
3. **Repeated `ai_commentary`.** Stripped from the profile echoed back to the model (`_profile_without_approach`); `_commentary_instructions` quotes the previous line as "already aired" and asks for a new one.

Also: Esc menu > Settings gains a "Pixel-art sprites" toggle (`GameSettings.set_sprite_art`).

**Verified** (25s floors, god mode, real `llama3.2`): curator 13/13 calls answered by the LLM, including every mid-floor call; commentary different every cycle; standout floors 2/2 got LLM-written achievements ("Threadbare Survivor", "Thy Unyielding Stasis") and LLM loot; no script errors. **Not verified:** achievement frequency in real play. A player who kites nonstop may hit the >90% moving standout every floor, so loot every floor; if it feels too generous, raise that threshold first. The capture harness's `bomb:`/`laser:` actions don't count toward Carl's ability stats, so ability standouts were only exercised as "none used".

## No passive attack + Android build (2026-09-25)

**Passive auto-attack removed** (Diego: "I want the player to do the attacks"). Every hit is now fired by the player: the laser is the main weapon (right-click, hold to keep firing; base cooldown 0.5 s -> 0.35 s to keep total damage output roughly the same), bombs as before. Level-up and loot bonuses that fed the auto-attack now feed the laser: `attack_damage` above its starting 8 adds to laser damage, `_cooldown_multiplier` scales the laser cooldown, `_range_bonus` adds to laser range, `crit_chance` doubles a laser's damage. The range ring and gold beam are gone. The "no ability used" achievement became "Conscientious Objector" (outlasting a timed floor without firing). Balance is untested in real play; loot `effects` still name the old stats, which is fine since they map onto the laser. `curator_generator`'s `auto_attack` dominant-ability value is now meaningless but harmless.

**Android build**, see `docs/android.md`: `tools/build_android.py [--send]` exports `build/floor-survivors.apk` (arm64, landscape, 30 MB) with the `C:\Android` toolchain, and can send it through the Telegram bot. `TouchControls` (added by `floor.gd` on touchscreens, or with `DCC_TOUCH=1`) gives twin-stick controls: left thumb joystick, right thumb drag = aimed laser, tap = bomb at that spot, plus a pause button. `OllamaClient.url()` reads `res://ollama_host.txt`, which the build writes with the PC's LAN IP, so the phone can use the PC's Ollama at home. `project.godot` gained `window/handheld/orientation=4` (sensor landscape) and `import_etc2_astc=true` (Android refused to export without it). **Not verified on a real phone.**

**Touch aiming v2 (2026-09-25):** the drag-to-aim laser stick was hard to use on a phone (Diego). Now: press and hold a spot on the right side and the laser keeps firing from Carl toward the finger (re-aimed every frame, slide to follow); double-tap a spot for a bomb there. Still no auto-aim. The capture harness gained `tdown`/`tup`/`tdtap:x,y` (simulated touches in viewport coords) and `stats`; verified: holding for 1.8 s fired 5 lasers at the finger, a double-tap threw 1 bomb.

**Touch v3 (2026-09-25):** the joystick lived only on the left half, so the left thumb blocked shooting to the left (Diego). Now either thumb does anything, decided by gesture: drag >= 20 px = floating joystick at the touch point; held still >= 0.12 s = laser aim at the finger; double-tap = bomb (quick taps never fire the laser). A second dragging thumb while one already steers becomes an aim. Verified with the harness (new `tdrag` and `x,y,finger` args): hold on the left fired lasers left without moving; a second finger dragged on the right moved Carl while the laser kept firing; a double-tap on the left threw a bomb.
