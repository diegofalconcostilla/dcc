extends Node2D
class_name Bomb

## Left-click ability prop: lands instantly at the impact point (thrown), then
## sits for FUSE_DURATION before exploding for AOE damage — this delay is what
## replaces the old instant-explosion bomb, specifically so it can be dodged.
## The moment it lands, every enemy within blast range + a small margin gets
## one dodge roll (see Enemy.try_dodge_point), using the System AI's
## bomb_dodge_chance (see floor.gd's character_profile). The dodge is told to
## last the full fuse, not Enemy's default short window — otherwise an enemy
## that successfully flees resumes chasing the player well before the bomb
## actually goes off, and often walks straight back into the blast.

const FUSE_DURATION := 0.9
const DANGER_RADIUS_MARGIN := 20.0  # enemies just outside the blast can still flinch away

var damage := 20.0
var radius := 60.0
var dodge_chance := 0.0

var _fuse := FUSE_DURATION
var _age := 0.0  # presentation only: drives the blink/flicker

func _ready() -> void:
	add_to_group("bombs")
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to(enemy.global_position) <= radius + DANGER_RADIUS_MARGIN and enemy.has_method("try_dodge_point"):
			enemy.try_dodge_point(global_position, dodge_chance, FUSE_DURATION)

func _process(delta: float) -> void:
	_fuse -= delta
	_age += delta
	queue_redraw()
	if _fuse <= 0.0:
		_explode()

func _explode() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to(enemy.global_position) <= radius and enemy.has_method("take_damage"):
			enemy.take_damage(damage)
	var fx := FxLayer.of(self)
	if fx:
		fx.flash(global_position, Color(1.0, 0.85, 0.5), radius * 0.9, 0.2)
		fx.ring(global_position, UIStyle.AMBER, radius * 0.4, radius * 1.15, 0.35, 5.0)
		fx.sparks(global_position, Color(1.0, 0.7, 0.25), 14, 300.0, 16.0, 0.35)
		fx.burst(global_position, Color(0.4, 0.3, 0.25), 8, 120.0, 4.0, 0.6)
		fx.shake(3.0)
	queue_free()

func _draw() -> void:
	# The blast zone is the telegraph (it's what enemies dodge, and what the
	# player must judge): a fixed outer rim, plus an inner fill that grows to
	# meet it exactly when the fuse hits zero, blinking faster as it does.
	var t: float = 1.0 - clampf(_fuse / FUSE_DURATION, 0.0, 1.0)  # 0 just landed -> 1 about to blow
	var blink := 0.5 + 0.5 * sin(_age * (12.0 + 34.0 * t))
	var hot := Color(1.0, 0.32 + 0.4 * t, 0.1)  # orange -> yellow-white as it nears zero
	draw_circle(Vector2.ZERO, radius, Color(hot, 0.05 + 0.08 * t))
	draw_circle(Vector2.ZERO, radius * t, Color(hot, 0.10 + 0.22 * t))
	draw_arc(Vector2.ZERO, radius * t, 0.0, TAU, 40, Color(hot, 0.35 + 0.4 * t), 1.5)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(hot, 0.45 + 0.55 * t * blink), 2.0 + 2.0 * t)
	# Hazard ticks around the rim.
	for i in 12:
		var a := TAU * float(i) / 12.0 + _age * 0.6
		draw_line(Vector2.from_angle(a) * (radius - 2.0), Vector2.from_angle(a) * (radius + 5.0), Color(hot, 0.5 + 0.4 * blink), 2.0)

	# The bomb itself: dark shell, sheen, and a fuse that burns down.
	draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 8.0, Color(0, 0, 0, 0.4))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(Vector2.ZERO, 8.0, Color(0.05, 0.05, 0.07))
	draw_circle(Vector2.ZERO, 6.5, Color(0.2, 0.2, 0.26))
	draw_circle(Vector2(-2.2, -2.4), 2.2, Color(0.55, 0.55, 0.65))
	var fuse_len := 12.0 * (1.0 - t)
	var fuse_tip := Vector2(4.0, -8.0) + Vector2(3.0, -6.0).normalized() * fuse_len
	draw_line(Vector2(3.0, -6.5), fuse_tip, Color(0.7, 0.55, 0.3), 2.0)
	draw_circle(fuse_tip, 2.5 + 1.5 * blink, Color(1.0, 0.9, 0.4))
	draw_circle(fuse_tip, 5.0 + 2.0 * blink, Color(1.0, 0.6, 0.1, 0.35))
