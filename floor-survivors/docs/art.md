# Art: sprites instead of circles

_2026-09-25._ Carl, Donut, every enemy and every boss are now pixel-art sprites from two **CC0** packs
(public domain: free for commercial use, credit optional). The original code-drawn look is still there:
set `GameSettings.sprite_art = false` (`[video] sprite_art` in `user://settings.cfg`).

| Pack | Used for | License |
|---|---|---|
| [0x72 16x16 DungeonTileset II v1.7](https://0x72.itch.io/dungeontileset-ii) | Animated enemies and bosses (idle + run, 4 frames) | CC0 |
| [Dungeon Crawl Stone Soup tiles](https://opengameart.org/content/dungeon-crawl-32x32-tiles) | Themed monsters, Carl (paper-doll composite), Donut (white Persian) | CC0 |

## What changed

- `scripts/sprite_bank.gd` (`SpriteBank`, static): loads `assets/sprites/roster.json`, picks sprites per floor, draws an actor standing on its shadow. It animates 0x72 frames, and gives static Stone Soup sprites a squash-and-stretch bob.
- `enemy.gd` / `boss.gd` / `player.gd`: a sprite branch in `_draw()`. The old drawing moved to `_draw_blob()` / an `else`, unchanged.
  - Kept: shadows, health pips and ring, dodge ring, aura, reticles, aim tick and attack beam.
  - Hit flash now washes the sprite white. System AI aggression tints enemies red, standing in for the blob's hot eyes.
- `enemy_spawner.gd`: new `floor_number`, set by `floor.gd`. Each enemy gets a random sprite from its floor's roster.
- `floor.gd`: the boss banner names the boss ("Tiamat, VP of Sales has noticed you.").
- `game_settings.gd`: `sprite_art` setting, default on.
- `tools/build_sprite_assets.py`: rebuilds `assets/sprites/` from the unzipped packs. The roster lives here; edit it and re-run.

Collision radii, speeds and all gameplay numbers are unchanged. Sprites are sized from the collision radius
(enemies 2.7×, Carl 2.8×), so hitboxes still match what you see.

## Roster (floor → enemies · boss)

| Floor | Enemies | Boss |
|---|---|---|
| 1 The Welcome Mat | Grinny Goblin, Tutorial Rat, Cockroach Intern | The Hall Monitor (ogre) |
| 2 Sewer Sublevel | Swampy Snob, Sewer Mud Guy, Acid Reflux | Zomby McZombinator |
| 3 Rust Belt | Orcy Oaf, Masked Muncher, Dwarf on Overtime | Greedy Grotto (iron troll) |
| 4 Fungal Annex | Fun Guy, Deathcap Dave, Squishy Squirt | Hyperactive Ballistomycete |
| 5 The Velvet Pit | Chortle Chuckle, Bottle-Service Imp, Quasit Promoter | Demon Decadence |
| 6 Sulfur Springs | Flame Fin, Flame Fuzz, Lava Lamp Worm | Flame Fart (fire giant) |
| 7 Blood Bank | Overdraft Knight, Late-Fee Bat, Vampy Vixen | The Loan Officer |
| 8 Cold Storage | Cold Clod, Icicle Jester, Brain Freeze | Frosty Frotto (frost giant) |
| 9 The Bone Orchard | Skeletal Intern, Bone Middle Manager, Phantom Puff | The Orchard Keeper |
| 10 Syndicate Penthouse | Compliance Angel, Chief Necromancy Officer, Wizzy Whisp | Tiamat, VP of Sales |

## How the local model was used (low cloud-token workflow)

The bulk work ran on this PC's Ollama (RTX 4070, `qwen2.5:7b` + `llava`) through `../tools/local_llm.py`. Claude only
planned, fixed and wired the code.

1. **Candidate picking (qwen2.5, 48 s):** 833 Stone Soup monster names plus the 10 floor themes produced 6 picks per floor.
   About 40% were hallucinated names; a fuzzy match snapped most of them to real files.
2. **Sprite catalog (llava, 6.5 min):** all 84 candidates were upscaled 8× and each described in one sentence (creature, colors, minion or boss).
3. **Casting and names (qwen2.5, 32 s):** from the catalog, 3 enemies and 1 boss per floor, each with a DCC-style name.
4. **Review (Claude):** fixed theme mistakes (frost giants on the fire floor, vampires missing from the Blood Bank), two invalid IDs,
   and swapped unreadable sprites after checking one contact sheet of screenshots.

Lesson: a 7B model is a good *drafter* for creative lists and names, and a bad *validator*. Always check its IDs against the real list in code.

## Proposals (next steps, by value/effort)

| # | Proposal | Effort | Local LLM role |
|---|---|---|---|
| 1 | **Loot icons**: match each LLM-generated loot item to one of Stone Soup's ~1,000 `item/` icons and show it on the loot card | S | qwen2.5 picks the icon from the item name + icon list (at generation time, or pre-baked per tier) |
| 2 | **Floor tiles**: replace the grid background with 0x72 floor/wall tiles tinted by `FLOOR_LOOKS` | S | none |
| 3 | **Monster names in play**: kill toasts for elites; feed the floor's roster names into the System AI director prompt so its taunts name what's hunting you | S | qwen2.5 already runs the director |
| 4 | **Settings toggle** for sprite vs classic art in the Esc menu's settings page | XS | none |
| 5 | **Elites**: 1 in 20 enemies uses the boss sprite at 0.6× with a gold outline, extra HP and a name tag | M | qwen2.5 names elites per run ("Brenda, Rat of the Month") |
| 6 | **Carl walk cycle**: 2–4 frames made by shifting paper-doll leg layers; Donut gets a sit/hop pair | M | none |
| 7 | **Death variety**: per-monster death puffs colored from the sprite's dominant color | S | none |
| 8 | **Asset search tool**: `local_llm.py vision` over all 6,000 Stone Soup tiles once, producing a searchable catalog for future floors and games | M, runs unattended | llava, ~6 s/tile, overnight |

Not verified yet: how the sprites *feel* in a real run (readability in big crowds, the hit-flash strength, the red aggression tint),
and fullscreen at resolutions other than 2560×1440. Export note: `roster.json` is read with `FileAccess`, so add `*.json` to the export
preset's non-resource include filter when you first export.
