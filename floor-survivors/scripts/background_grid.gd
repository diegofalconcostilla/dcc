extends Node2D
class_name BackgroundGrid

## The dungeon floor: a large tiled area tinted per floor (see
## UIStyle.FLOOR_LOOKS). Drawn as chunks so the renderer culls everything off
## screen, and every "random" detail comes from a coordinate hash, so the
## ground is stable (no flicker) and identical each time you revisit a spot.

const EXTENT := 3000
const SPACING := 100
const CHUNK_TILES := 5  # tiles per chunk edge

var _base := Color(0.06, 0.07, 0.1)
var _accent := Color(0.42, 0.52, 0.78)
var _chunks: Array[Node2D] = []

## A chunk is just a canvas item that asks its owner to paint its tile range.
class Chunk extends Node2D:
	var grid: BackgroundGrid
	var tile_x := 0
	var tile_y := 0

	func _draw() -> void:
		grid.paint_chunk(self, tile_x, tile_y)

func _ready() -> void:
	z_index = -10
	var tiles := int(EXTENT * 2 / SPACING)
	var start := -EXTENT / SPACING
	var cx := start
	while cx < start + tiles:
		var cy := start
		while cy < start + tiles:
			var chunk := Chunk.new()
			chunk.grid = self
			chunk.tile_x = cx
			chunk.tile_y = cy
			add_child(chunk)
			_chunks.append(chunk)
			cy += CHUNK_TILES
		cx += CHUNK_TILES
	set_floor_theme(1)

## Retints the ground for a new floor (and the engine's clear color, so the
## void beyond the tiled area matches).
func set_floor_theme(floor_num: int) -> void:
	var look := UIStyle.floor_look(floor_num)
	_base = look["base"]
	_accent = look["accent"]
	RenderingServer.set_default_clear_color(_base)
	for chunk in _chunks:
		chunk.queue_redraw()

func _hash01(x: int, y: int, salt: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0

func paint_chunk(canvas: Node2D, tile_x: int, tile_y: int) -> void:
	var seam := Color(_accent.r, _accent.g, _accent.b, 0.11)
	var seam_major := Color(_accent.r, _accent.g, _accent.b, 0.22)
	var tick := Color(_accent.r, _accent.g, _accent.b, 0.34)
	var crack := Color(_base.r * 0.35, _base.g * 0.35, _base.b * 0.35, 0.85)
	var lighter := _base.lightened(0.035)
	var darker := _base.darkened(0.14)
	for tx in range(tile_x, tile_x + CHUNK_TILES):
		for ty in range(tile_y, tile_y + CHUNK_TILES):
			var origin := Vector2(tx * SPACING, ty * SPACING)
			var r := _hash01(tx, ty, 1)
			# Slightly uneven flagstones.
			if r > 0.62:
				canvas.draw_rect(Rect2(origin, Vector2(SPACING, SPACING)), lighter)
			elif r < 0.18:
				canvas.draw_rect(Rect2(origin, Vector2(SPACING, SPACING)), darker)
			# Seams (top and left edge of each tile; every 5th is a heavier "room" line).
			canvas.draw_line(origin, origin + Vector2(SPACING, 0), seam_major if ty % 5 == 0 else seam, 1.0)
			canvas.draw_line(origin, origin + Vector2(0, SPACING), seam_major if tx % 5 == 0 else seam, 1.0)
			# Corner plus-marks where seams cross.
			canvas.draw_line(origin + Vector2(-4, 0), origin + Vector2(4, 0), tick, 1.0)
			canvas.draw_line(origin + Vector2(0, -4), origin + Vector2(0, 4), tick, 1.0)
			# Occasional crack and pebbles.
			var c := _hash01(tx, ty, 2)
			if c > 0.86:
				var p0 := origin + Vector2(_hash01(tx, ty, 3), _hash01(tx, ty, 4)) * (SPACING - 20.0) + Vector2(10, 10)
				var p1 := p0 + Vector2(_hash01(tx, ty, 5) - 0.3, _hash01(tx, ty, 6) - 0.5) * 34.0
				var p2 := p1 + Vector2(_hash01(tx, ty, 7) - 0.5, _hash01(tx, ty, 8) - 0.5) * 30.0
				canvas.draw_polyline(PackedVector2Array([p0, p1, p2]), crack, 1.5)
			elif c < 0.10:
				var p := origin + Vector2(_hash01(tx, ty, 9), _hash01(tx, ty, 10)) * (SPACING - 20.0) + Vector2(10, 10)
				canvas.draw_circle(p, 2.0 + _hash01(tx, ty, 11) * 2.0, crack)
