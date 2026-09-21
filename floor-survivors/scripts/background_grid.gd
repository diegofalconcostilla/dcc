extends Node2D
class_name BackgroundGrid

const EXTENT := 3000
const SPACING := 100

func _draw() -> void:
	var color := Color(0.15, 0.15, 0.18)
	var x := -EXTENT
	while x <= EXTENT:
		draw_line(Vector2(x, -EXTENT), Vector2(x, EXTENT), color, 1.0)
		x += SPACING
	var y := -EXTENT
	while y <= EXTENT:
		draw_line(Vector2(-EXTENT, y), Vector2(EXTENT, y), color, 1.0)
		y += SPACING
