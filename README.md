# DCC

A collection of games drawing on the setting and tone of Matt Dinniman's *Dungeon Crawler Carl*. Each game is a self-contained project in its own folder, so they can share this repo without sharing code.

| Game | Folder | What it is |
|---|---|---|
| Floor Survivors | [`floor-survivors/`](floor-survivors/) | Godot 4 real-time survivor: 10 timed floors, a live LLM-driven "System AI" antagonist, LLM-generated loot and achievements, adaptive 8-bit music. |

New game: make a new folder beside the existing ones with its own project, README and design doc. `.gitignore` at this level covers every game (Godot's `.godot/` cache, generated `logs/`).

## Shared tools

- `tools/local_llm.py`: offloads bulk text and vision work to the local Ollama models (`qwen2.5:7b`, `llava`), so a cloud model only plans and reviews. `text` = prompt + context files -> text/JSON; `vision` = describe images -> JSONL (resumable). Used to cast Floor Survivors' sprite roster, see `floor-survivors/docs/art.md`.
