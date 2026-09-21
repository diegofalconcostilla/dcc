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

func _ready() -> void:
	add_to_group("bombs")
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to(enemy.global_position) <= radius + DANGER_RADIUS_MARGIN and enemy.has_method("try_dodge_point"):
			enemy.try_dodge_point(global_position, dodge_chance, FUSE_DURATION)

func _process(delta: float) -> void:
	_fuse -= delta
	queue_redraw()
	if _fuse <= 0.0:
		_explode()

func _explode() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to(enemy.global_position) <= radius and enemy.has_method("take_damage"):
			enemy.take_damage(damage)
	queue_free()

func _draw() -> void:
	var t: float = 1.0 - clampf(_fuse / FUSE_DURATION, 0.0, 1.0)  # 0 just landed -> 1 about to blow
	draw_circle(Vector2.ZERO, 6.0, Color(0.15, 0.15, 0.15))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(1, 0.4, 0.1, 0.15 + 0.35 * t), 2.0 + 2.0 * t)
