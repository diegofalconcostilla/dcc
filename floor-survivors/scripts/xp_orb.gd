extends Node2D
class_name XPOrb

const RADIUS := 5.0
const MAGNET_RADIUS := 90.0
const PICKUP_RADIUS := 18.0
const SPEED := 260.0

var value := 3.0

func _ready() -> void:
	add_to_group("pickups")

func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var dist: float = global_position.distance_to(player.global_position)
	if dist <= MAGNET_RADIUS:
		global_position = global_position.move_toward(player.global_position, SPEED * delta)
	if dist <= PICKUP_RADIUS:
		if player.has_method("gain_xp"):
			player.gain_xp(value)
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, Color(0.3, 0.9, 1.0))
