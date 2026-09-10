# DCC

A 2D dungeon crawler prototype drawing on the setting/tone of Matt Dinniman's *Dungeon Crawler Carl*: survivors ("crawlers") fight down through a multi-level "World Dungeon," broadcast as an intergalactic reality show.

Built in [Godot 4](https://godotengine.org/) (GDScript). Combat/movement is real-time and free-roam, Vampire Survivors-style: passive auto-attack on the nearest enemy, plus two aimed abilities, level up, survive the floor's clock.

The core experiment of this project is **LLM-generated content and decisions at runtime**, via a local [Ollama](https://ollama.com/) model — not hand-authored, and never trusted without a client-side validation/clamping layer:
- Loot-box items and achievements, generated live at floor-end.
- A "System AI" antagonist that watches your playstyle and actively picks (and commits real numbers to) a tactic meant to counter it — more dodge-savvy enemies against whichever attack you favor, faster/closer spawns, tougher enemies, or an early boss — plus an in-character taunt about what it's doing.

See [`plan.md`](plan.md) for the full design notes and decision log.

## Current state

- Free movement (WASD/arrows), passive auto-attack on the nearest enemy in range.
- Two aimed abilities: **left-click** throws a bomb that lands instantly but explodes after a short fuse (dodgeable); **right-click** fires a laser bolt that travels as a real projectile (also dodgeable), rather than an instant hit.
- Enemies can dodge both, at a chance the System AI sets — see below. Boss enemies spawn periodically after a run of regular kills, tougher and worth far more.
- Automatic level-up: XP grants a flat bump to all four core stats — no pause-and-choose screen currently.
- 10 sequential floors, 90 seconds each — clear a floor by surviving the timer; monster speed ramps up each floor and within it.
- **Loot is achievement-gated:** at floor-end, an LLM call decides whether the run earned an achievement (deliberately selective — most floors won't). Only if one is earned does a loot box open, and its contents are generated to thematically tie into that achievement — no achievement, no loot.
- **The System AI:** twice per floor (halfway through the timer, and at floor-end), an LLM call updates a running character profile of your playstyle *and* picks a live tactic against you — enemy dodge chance per ability, spawn rate/distance, aggression, or boss timing are all numbers it sets itself, clamped into safe ranges but never computed by a formula. It'll sometimes leave a gloating one-liner as a toast.
- A local hand-written fallback covers loot/achievements if Ollama is slow or unavailable — gameplay never blocks waiting on the model.

## Running it

1. Install [Godot 4.7+](https://godotengine.org/download) (standard build, no Mono/.NET needed).
2. (Optional, for LLM-generated content) Install [Ollama](https://ollama.com/download) and pull a model, e.g. `ollama pull llama3.2`. Without Ollama running, the game falls back to local hand-written loot/achievement content automatically, and the System AI's tactic stays neutral.
3. Open the project in Godot, or run it directly:
   ```
   godot --path .
   ```

On Windows, if Godot was installed via `winget` (not on `PATH` by default) and you want Ollama started for you automatically, use `run_game.bat` in the repo root instead — it boots `ollama serve` if it isn't already running, refreshes Godot's script class cache, then launches the game.

For fast iteration on the floor-end/System AI flow, override the floor timer with an environment variable so floors clear in seconds instead of minutes:

```
# cmd.exe
set DCC_FLOOR_DURATION=3 && godot --path .

# PowerShell
$env:DCC_FLOOR_DURATION = "3"; godot --path .
```

`run_batch_test.bat` runs `scripts/llm_batch_test.gd` headlessly, exercising the Ollama-backed content pipeline directly (without a full playthrough) across a matrix of synthetic contexts — useful for judging content quality across many samples quickly.

Every loot/achievement/System AI decision (including the exact prompt sent and whether it came from the LLM or a fallback) is logged as JSONL under `logs/` (gitignored), one file per run.
