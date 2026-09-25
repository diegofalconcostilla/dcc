extends RefCounted
class_name SpriteBank

## Pixel-art sprites for Carl, enemies and bosses (CC0 packs, see
## assets/sprites/*/LICENSE.txt). roster.json is written by
## tools/build_sprite_assets.py: per floor, three enemy sprites and a boss, each
## with explicit idle/run frame lists (Stone Soup sprites are single static
## frames, so they get a squash-and-stretch bob instead of animation).
##
## Static like GameSettings, so actors keep drawing themselves in _draw() and
## GameSettings.sprite_art = false brings back the original code-drawn look.

const ROSTER_PATH := "res://assets/sprites/roster.json"
const FPS := 8.0

static var _roster: Dictionary = {}
static var _textures: Dictionary = {}  # res path -> Texture2D

static func enabled() -> bool:
	return GameSettings.sprite_art and not _get_roster().is_empty()

static func _get_roster() -> Dictionary:
	if _roster.is_empty() and FileAccess.file_exists(ROSTER_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(ROSTER_PATH))
		if parsed is Dictionary:
			_roster = parsed
	return _roster

static func _floor_entry(floor_num: int) -> Dictionary:
	var floors: Array = _get_roster().get("floors", [])
	if floors.is_empty():
		return {}
	return floors[clampi(floor_num - 1, 0, floors.size() - 1)]

static func player_entry() -> Dictionary:
	return _get_roster().get("player", {})

## A random one of the floor's enemy sprites.
static func enemy_entry(floor_num: int) -> Dictionary:
	var enemies: Array = _floor_entry(floor_num).get("enemies", [])
	return enemies.pick_random() if not enemies.is_empty() else {}

static func boss_entry(floor_num: int) -> Dictionary:
	return _floor_entry(floor_num).get("boss", {})

static func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path)
	return _textures[path]

static func donut_entry() -> Dictionary:
	return _get_roster().get("donut", {})

## Draws `entry` standing with its feet at `feet`, `height` px tall (the
## camera's 1.5x zoom already rules out whole-pixel scaling, so none is
## forced). `phase` de-syncs a crowd; `modulate` above 1.0 washes toward
## white (hit flash).
static func draw_actor(ci: CanvasItem, entry: Dictionary, feet: Vector2, height: float,
		moving: bool, face_left: bool, modulate: Color = Color.WHITE, phase: float = 0.0) -> void:
	var frames: Array = entry.get("run" if moving else "idle", [])
	if frames.is_empty():
		return
	var time := Time.get_ticks_msec() / 1000.0 + phase
	var tex := _texture(frames[int(time * FPS) % frames.size()])
	if tex == null:
		return
	var px_scale := height / tex.get_height()
	var size := tex.get_size() * px_scale
	var squash := Vector2.ONE
	if frames.size() == 1:  # static (Stone Soup) sprite: breathe while idle, hop while moving
		feet.y += size.y * 0.1  # its 32x32 tile leaves empty rows under the feet
		var s := sin(time * (11.0 if moving else 3.0))
		var amount := 0.07 if moving else 0.035
		squash = Vector2(1.0 - amount * s, 1.0 + amount * s)
	ci.draw_set_transform(feet, 0.0, Vector2(-squash.x if face_left else squash.x, squash.y))
	ci.draw_texture_rect(tex, Rect2(Vector2(-size.x * 0.5, -size.y), size), false, modulate)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
