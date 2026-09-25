"""Copy the chosen sprites into the game and write assets/sprites/roster.json (explicit frame lists).

Source packs (both CC0) are expected unzipped under DCC_ART_SRC (default: %TEMP%/dcc-art):
  0x72/0x72_DungeonTilesetII_v1.7/...          https://0x72.itch.io/dungeontileset-ii
  dcssfull/Dungeon Crawl Stone Soup Full/...   https://opengameart.org/content/dungeon-crawl-32x32-tiles

The roster below was drafted by the local model (tools/local_llm.py at the repo root: qwen2.5 picked
Stone Soup candidates per floor, llava described every candidate sprite, qwen2.5 cast the floors and
named the monsters), then theme-checked by hand. See docs/art.md.
"""
import json
import os
import re
import shutil
import tempfile
from pathlib import Path

from PIL import Image

SRC = Path(os.environ.get("DCC_ART_SRC", Path(tempfile.gettempdir()) / "dcc-art"))
X = SRC / "0x72" / "0x72_DungeonTilesetII_v1.7" / "frames"
D = SRC / "dcssfull" / "Dungeon Crawl Stone Soup Full" / "monster"
P = SRC / "dcssfull" / "Dungeon Crawl Stone Soup Full" / "player"
OUT = Path(__file__).resolve().parent.parent / "assets" / "sprites"

# Stone Soup paper-doll layers: Carl in his boxers and leather jacket, barefoot. Donut: white Persian.
CARL_LAYERS = ["base/human_male.png", "legs/pj.png", "body/leather_jacket.png", "hair/brown_1.png"]
DONUT = "felids/cat_6.png"

# Per floor: three common enemies + a boss, as (sprite id, display name).
# 0x72__<name> = animated 0x72 character; dcss__<dir>__<name> = static Stone Soup monster.
FLOORS = [
    ([("0x72__goblin", "Grinny Goblin"), ("dcss__animals__rat", "Tutorial Rat"), ("dcss__animals__giant_cockroach_new", "Cockroach Intern")], ("0x72__ogre", "The Hall Monitor")),
    ([("0x72__swampy", "Swampy Snob"), ("0x72__muddy", "Sewer Mud Guy"), ("dcss__amorphous__acid_blob", "Acid Reflux")], ("0x72__big_zombie", "Zomby McZombinator")),
    ([("0x72__orc_warrior", "Orcy Oaf"), ("0x72__masked_orc", "Masked Muncher"), ("dcss__deep_dwarf_berserker", "Dwarf on Overtime")], ("dcss__iron_troll_monk_ghost", "Greedy Grotto")),
    ([("dcss__fungi_plants__wandering_mushroom_new", "Fun Guy"), ("dcss__fungi_plants__deathcap", "Deathcap Dave"), ("0x72__slug", "Squishy Squirt")], ("dcss__fungi_plants__hyperactive_ballistomycete", "Hyperactive Ballistomycete")),
    ([("0x72__chort", "Chortle Chuckle"), ("0x72__imp", "Bottle-Service Imp"), ("dcss__demons__quasit_new", "Quasit Promoter")], ("0x72__big_demon", "Demon Decadence")),
    ([("dcss__salamander_firebrand", "Flame Fin"), ("dcss__animals__hell_hound_new", "Flame Fuzz"), ("dcss__lava_worm", "Lava Lamp Worm")], ("dcss__fire_giant_new", "Flame Fart")),
    ([("dcss__undead__vampire_knight_new", "Overdraft Knight"), ("dcss__animals__bat", "Late-Fee Bat"), ("dcss__undead__vampire_mage_new", "Vampy Vixen")], ("0x72__big_demon", "The Loan Officer")),
    ([("0x72__ice_zombie", "Cold Clod"), ("dcss__ice_beast", "Icicle Jester"), ("dcss__demons__blizzard_demon", "Brain Freeze")], ("dcss__frost_giant_new", "Frosty Frotto")),
    ([("0x72__skelet", "Skeletal Intern"), ("dcss__undead__skeletal_warrior_new", "Bone Middle Manager"), ("dcss__undead__phantom_new", "Phantom Puff")], ("0x72__big_zombie", "The Orchard Keeper")),
    ([("0x72__angel", "Compliance Angel"), ("0x72__necromancer", "Chief Necromancy Officer"), ("0x72__wizzard_f", "Wizzy Whisp")], ("dcss__unique__tiamat_green", "Tiamat, VP of Sales")),
]


def frame_num(p: Path) -> int:
    return int(re.search(r"f(\d+)\.png$", p.name).group(1))


def res(path: Path) -> str:
    return "res://assets/sprites/" + path.relative_to(OUT).as_posix()


def install(sprite_id: str) -> dict:
    """Copy one sprite's frames into the game; return {"idle": [res paths], "run": [res paths]}."""
    pack, name = sprite_id.split("__", 1)
    if pack == "0x72":
        dst = OUT / "0x72" / name
        dst.mkdir(parents=True, exist_ok=True)
        anims = {}
        for anim in ("idle", "run"):
            frames = sorted(X.glob(f"{name}_{anim}_anim_f*.png"), key=frame_num) \
                or sorted(X.glob(f"{name}_anim_f*.png"), key=frame_num)
            anims[anim] = []
            for i, f in enumerate(frames):
                shutil.copy(f, dst / f"{anim}_{i}.png")
                anims[anim].append(res(dst / f"{anim}_{i}.png"))
        return anims
    dst = OUT / "dcss" / f"{name}.png"
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(D / (name.replace("__", "/") + ".png"), dst)
    return {"idle": [res(dst)], "run": [res(dst)]}  # static: SpriteBank bobs it in code


def install_carl_and_donut() -> tuple[dict, dict]:
    dst = OUT / "dcss"
    dst.mkdir(parents=True, exist_ok=True)
    carl = Image.new("RGBA", (32, 32))
    for layer in CARL_LAYERS:
        carl.alpha_composite(Image.open(P / layer).convert("RGBA"))
    carl.save(dst / "carl.png")
    shutil.copy(P / DONUT, dst / "donut.png")
    return (
        {"id": "carl", "idle": [res(dst / "carl.png")], "run": [res(dst / "carl.png")]},
        {"id": "donut", "idle": [res(dst / "donut.png")], "run": [res(dst / "donut.png")]},
    )


def main():
    if not X.exists() or not D.exists():
        raise SystemExit(f"source packs not found under {SRC} (set DCC_ART_SRC)")
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    carl, donut = install_carl_and_donut()
    roster = {"player": carl, "donut": donut, "floors": []}
    for enemies, (boss_id, boss_name) in FLOORS:
        roster["floors"].append({
            "enemies": [{"id": s, "name": n, **install(s)} for s, n in enemies],
            "boss": {"id": boss_id, "name": boss_name, **install(boss_id)},
        })
    (OUT / "roster.json").write_text(json.dumps(roster, indent=1), encoding="utf-8")
    (OUT / "0x72" / "LICENSE.txt").write_text(
        "16x16 DungeonTileset II v1.7 by 0x72 - https://0x72.itch.io/dungeontileset-ii - CC0 1.0 (public domain).\n")
    (OUT / "dcss" / "LICENSE.txt").write_text(
        "Dungeon Crawl Stone Soup tiles - https://opengameart.org/content/dungeon-crawl-32x32-tiles - CC0 1.0 (public domain).\n"
        "carl.png is composed from its paper-doll layers by tools/build_sprite_assets.py.\n")
    pngs = list(OUT.rglob("*.png"))
    print(f"{len(pngs)} png files, {sum(p.stat().st_size for p in pngs) // 1024} KB -> {OUT}")


if __name__ == "__main__":
    main()
