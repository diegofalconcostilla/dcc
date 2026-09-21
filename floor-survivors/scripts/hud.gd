extends CanvasLayer
class_name GameHud

var hp_bar: ProgressBar
var xp_bar: ProgressBar
var timer_label: Label
var floor_label: Label
var points_label: Label
var level_label: Label
var toast_label: Label
var _toast_timer := 0.0

func _ready() -> void:
	layer = 1

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	add_child(margin)

	var top_bar := VBoxContainer.new()
	margin.add_child(top_bar)

	floor_label = Label.new()
	floor_label.add_theme_font_size_override("font_size", 20)
	top_bar.add_child(floor_label)

	timer_label = Label.new()
	timer_label.add_theme_font_size_override("font_size", 28)
	top_bar.add_child(timer_label)

	points_label = Label.new()
	top_bar.add_child(points_label)

	level_label = Label.new()
	top_bar.add_child(level_label)

	hp_bar = ProgressBar.new()
	hp_bar.max_value = 100
	hp_bar.value = 100
	hp_bar.custom_minimum_size = Vector2(220, 20)
	top_bar.add_child(hp_bar)

	xp_bar = ProgressBar.new()
	xp_bar.max_value = 10
	xp_bar.value = 0
	xp_bar.custom_minimum_size = Vector2(220, 10)
	top_bar.add_child(xp_bar)

	toast_label = Label.new()
	toast_label.add_theme_font_size_override("font_size", 20)
	toast_label.visible = false
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.position = Vector2(-200, 60)
	toast_label.custom_minimum_size = Vector2(400, 80)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(toast_label)

func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			toast_label.visible = false

func update_floor(current_floor: int, max_floor: int) -> void:
	floor_label.text = "Floor %d / %d" % [current_floor, max_floor]

func update_timer(time_remaining: float) -> void:
	timer_label.text = "Floor collapses in: %02d:%02d" % [int(time_remaining) / 60, int(time_remaining) % 60]

func update_points(points: int) -> void:
	points_label.text = "Points: %d" % points

func update_level(level: int) -> void:
	level_label.text = "Level %d" % level

func update_hp(current: float, max_hp: float) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = current

func update_xp(current: float, needed: float) -> void:
	xp_bar.max_value = needed
	xp_bar.value = current

func show_toast(text: String) -> void:
	toast_label.text = text
	toast_label.visible = true
	_toast_timer = 4.0
