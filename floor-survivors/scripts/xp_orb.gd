extends Node2D
class_name XPOrb

const RADIUS := 5.0
const MAGNET_RADIUS := 90.0
const PICKUP_RADIUS := 18.0
const SPEED := 260.0

var value := 3.0
var _phase := randf() * TAU  # presentation only: desyncs the pulse between orbs

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
		var fx := FxLayer.of(self)
		if fx:
			fx.burst(global_position, UIStyle.MINT, 4, 90.0, 2.2, 0.3)
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	# Bigger, golden orbs for boss-sized XP drops; regular ones glow mint.
	var big := value >= 20.0
	var base := UIStyle.GOLD if big else UIStyle.MINT
	var r := RADIUS * (1.8 if big else 1.0)
	var time := Time.get_ticks_msec() / 1000.0
	var pulse := 0.5 + 0.5 * sin(time * 4.0 + _phase)
	draw_circle(Vector2.ZERO, r + 7.0 + 2.5 * pulse, Color(base, 0.07))
	draw_circle(Vector2.ZERO, r + 3.5 + 1.5 * pulse, Color(base, 0.16))
	draw_circle(Vector2.ZERO, r, base)
	draw_circle(Vector2(-r * 0.3, -r * 0.3), r * 0.45, Color(1, 1, 1, 0.85))
