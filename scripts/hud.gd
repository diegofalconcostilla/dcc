extends CanvasLayer
class_name GameHud

signal upgrade_chosen(upgrade_id: String)

const UPGRADE_CHOICES := [
	{"id": "damage", "label": "+25% Damage"},
	{"id": "speed", "label": "+15% Attack Speed"},
	{"id": "range", "label": "+20% Range"},
	{"id": "max_hp", "label": "+20 Max HP"},
]

var hp_bar: ProgressBar
var xp_bar: ProgressBar
var timer_label: Label
var floor_label: Label
var points_label: Label
var level_label: Label
var choice_panel: Control
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

	_build_choice_panel()

func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			toast_label.visible = false

func _build_choice_panel() -> void:
	choice_panel = PanelContainer.new()
	choice_panel.set_anchors_preset(Control.PRESET_CENTER)
	choice_panel.visible = false
	add_child(choice_panel)

	var vbox := VBoxContainer.new()
	choice_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Level Up! Choose an upgrade:"
	vbox.add_child(title)

	for choice in UPGRADE_CHOICES:
		var button := Button.new()
		button.text = choice["label"]
		button.pressed.connect(_on_choice_pressed.bind(choice["id"]))
		vbox.add_child(button)

func _on_choice_pressed(upgrade_id: String) -> void:
	choice_panel.visible = false
	get_tree().paused = false
	upgrade_chosen.emit(upgrade_id)

func show_level_up_choice() -> void:
	get_tree().paused = true
	choice_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	choice_panel.visible = true

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
