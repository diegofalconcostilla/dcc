extends CharacterBody2D
class_name Enemy

signal died(point_value: int, death_position: Vector2)

const RADIUS := 12.0

var speed := 70.0
var hp := 20.0
var max_hp := 20.0
var contact_damage := 8.0
var xp_value := 3.0
var point_value := 10

var _contact_cooldown := 0.0

func _ready() -> void:
	add_to_group("enemies")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)

func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var dir: Vector2 = (player.global_position - global_position).normalized()
		velocity = dir * speed
		move_and_slide()
		if _contact_cooldown > 0.0:
			_contact_cooldown -= delta
		elif global_position.distance_to(player.global_position) <= RADIUS + 16.0:
			if player.has_method("take_damage"):
				player.take_damage(contact_damage)
				_contact_cooldown = 0.5
				var floor_node := get_tree().get_first_node_in_group("floor_controller")
				if floor_node and floor_node.has_method("register_damage_taken"):
					floor_node.register_damage_taken(contact_damage)
	queue_redraw()

func _draw() -> void:
	var t: float = hp / max_hp
	draw_circle(Vector2.ZERO, RADIUS, Color(0.8, 0.2 + 0.4 * (1.0 - t), 0.2))

func take_damage(amount: float) -> void:
	hp -= amount
	if hp <= 0.0:
		died.emit(point_value, global_position)
		queue_free()

func scale_difficulty(factor: float) -> void:
	hp *= factor
	max_hp = hp
	speed *= min(factor, 1.3)
	contact_damage *= factor
