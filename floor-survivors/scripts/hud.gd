extends CanvasLayer
class_name GameHud

## The whole on-screen UI, built in code and styled through UIStyle's shared
## Theme. Layout: floor + score top-left, collapse timer (and boss bar) top-
## center, the System AI's live banner top-right, abilities/HP/XP bottom-
## center. Transient messages come in three flavors: ToastPanel cards (the
## System AI's taunts up top, everything else low), big center banners (floor
## start, level-up, floor end) and a full-screen run-over card.
##
## Runs with PROCESS_MODE_ALWAYS so animations (and the "R to restart"
## prompt) keep working while the end-of-floor sequence has the tree paused.

const BAR_WIDTH := 400.0
const GLITCH_SEC := 0.35
const GLITCH_CHARS := "#@%&*/<>=+01"
const HP_TRAIL_DELAY := 0.4

var hp_bar: ProgressBar
var hp_trail: ProgressBar
var hp_text: Label
var xp_bar: ProgressBar
var timer_label: Label
var timer_bar: ProgressBar
var floor_label: Label
var floor_name_label: Label
var points_label: Label
var system_label: Label
var level_label: Label

var _system_panel: PanelContainer
var _system_style: StyleBoxFlat
var _system_dot: Panel
var _system_bar: ProgressBar
var _system_mult: Label
var _boss_panel: PanelContainer
var _boss_bar: ProgressBar
var _slot_bomb: AbilitySlot
var _slot_laser: AbilitySlot
var _toast_system: ToastPanel
var _toast_main: ToastPanel
var _banner_box: VBoxContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_tween: Tween
var _run_over: Control
var _run_over_title: Label
var _run_over_text: Label
var _run_over_stats: HBoxContainer
var _run_over_prompt: Label
var _points_tween: Tween

var _hp_fill: StyleBoxFlat
var _hp_fraction := 1.0
var _trail_delay := 0.0
var _timer_max := 0.0
var _timer_color := UIStyle.TEXT
var _timer_secs := -1
var _aggression_text := ""
var _time := 0.0
var _tactic := "none"
var _tactic_color := UIStyle.TEXT_DIM
var _glitch_time := 0.0
var _flash := 0.0

func _ready() -> void:
	layer = 2  # above ScreenOverlay (1)
	process_mode = Node.PROCESS_MODE_ALWAYS

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIStyle.build_theme()
	add_child(root)

	_build_top_left(root)
	_build_top_center(root)
	_build_system_panel(root)
	_build_bottom(root)
	_build_toasts(root)
	_build_banner(root)
	_build_run_over(root)

# --- Construction ------------------------------------------------------------

func _label(text: String, font_size: int, color: Color = UIStyle.TEXT, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if bold:
		label.add_theme_font_override("font", UIStyle.font(true))
	return label

func _bar(size: Vector2, fill: Color, back: Color = Color(0.09, 0.10, 0.15, 0.9)) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = size
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.add_theme_stylebox_override("background", UIStyle.bar_style(back, 4))
	bar.add_theme_stylebox_override("fill", UIStyle.bar_style(fill, 4))
	return bar

func _build_top_left(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	floor_label = _label("FLOOR 1 / 10", 18, UIStyle.TEXT, true)
	box.add_child(floor_label)
	floor_name_label = _label("", 12, UIStyle.TEXT_DIM)
	box.add_child(floor_name_label)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	box.add_child(gap)
	points_label = _label("0 PTS", 22, UIStyle.GOLD, true)
	box.add_child(points_label)

func _build_top_center(root: Control) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.offset_top = 12
	box.add_theme_constant_override("separation", 2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(box)

	var caption := _label("FLOOR COLLAPSES IN", 11, UIStyle.TEXT_DIM, true)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption)
	timer_label = _label("00:00", 38, UIStyle.TEXT, true)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(timer_label)
	timer_bar = _bar(Vector2(220, 5), UIStyle.CYAN)
	timer_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	timer_bar.value = 1.0
	box.add_child(timer_bar)

	# Boss health: only visible while a boss is alive.
	_boss_panel = PanelContainer.new()
	_boss_panel.visible = false
	_boss_panel.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.08, 0.03, 0.12, 0.88), Color(UIStyle.BOSS_PURPLE, 0.8), 6, 8, 1))
	_boss_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var boss_box := VBoxContainer.new()
	boss_box.add_theme_constant_override("separation", 2)
	_boss_panel.add_child(boss_box)
	var boss_caption := _label("BOSS", 11, UIStyle.BOSS_PURPLE.lightened(0.3), true)
	boss_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_caption)
	_boss_bar = _bar(Vector2(320, 10), UIStyle.BOSS_PURPLE)
	boss_box.add_child(_boss_bar)
	var boss_gap := Control.new()
	boss_gap.custom_minimum_size.y = 6
	box.add_child(boss_gap)
	box.add_child(_boss_panel)

func _build_system_panel(root: Control) -> void:
	_system_panel = PanelContainer.new()
	_system_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_system_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_system_panel.offset_right = -16
	_system_panel.offset_top = 16
	_system_style = UIStyle.panel_style(Color(0.11, 0.02, 0.05, 0.9), Color(UIStyle.SYSTEM, 0.75), 6, 10, 1)
	_system_style.shadow_color = Color(UIStyle.SYSTEM, 0.25)
	_system_style.shadow_size = 10
	_system_panel.add_theme_stylebox_override("panel", _system_style)
	root.add_child(_system_panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 236
	box.add_theme_constant_override("separation", 3)
	_system_panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	box.add_child(header)
	# Blinking "recording" dot — the AI is always watching.
	_system_dot = Panel.new()
	_system_dot.custom_minimum_size = Vector2(9, 9)
	_system_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_system_dot.add_theme_stylebox_override("panel", UIStyle.bar_style(UIStyle.SYSTEM, 5))
	header.add_child(_system_dot)
	header.add_child(_label("SYSTEM AI", 12, UIStyle.SYSTEM, true))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(_label("LIVE", 11, UIStyle.TEXT_DIM, true))

	system_label = _label("OBSERVING", 24, UIStyle.TEXT_DIM, true)
	box.add_child(system_label)

	var agg := HBoxContainer.new()
	agg.add_theme_constant_override("separation", 6)
	box.add_child(agg)
	agg.add_child(_label("AGGRESSION", 10, UIStyle.TEXT_DIM, true))
	_system_bar = _bar(Vector2(86, 6), UIStyle.SYSTEM)
	_system_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	agg.add_child(_system_bar)
	_system_mult = _label("x1.00", 12, UIStyle.TEXT, true)
	agg.add_child(_system_mult)

func _build_bottom(root: Control) -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.offset_bottom = -16
	col.add_theme_constant_override("separation", 6)
	root.add_child(col)

	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override("separation", 8)
	col.add_child(slots)
	_slot_bomb = AbilitySlot.new()
	_slot_bomb.kind = "bomb"
	_slot_bomb.key_text = "LMB"
	_slot_bomb.accent = UIStyle.AMBER
	slots.add_child(_slot_bomb)
	_slot_laser = AbilitySlot.new()
	_slot_laser.kind = "laser"
	_slot_laser.key_text = "RMB"
	_slot_laser.accent = UIStyle.CYAN
	slots.add_child(_slot_laser)

	# HP: a pale "trail" bar sits behind the live bar and drains slowly, so
	# recent damage stays visible for a moment.
	var hp_stack := Control.new()
	hp_stack.custom_minimum_size = Vector2(BAR_WIDTH, 26)
	col.add_child(hp_stack)
	hp_trail = _bar(Vector2(BAR_WIDTH, 26), Color(1.0, 0.72, 0.4, 0.9))
	hp_trail.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_stack.add_child(hp_trail)
	hp_bar = _bar(Vector2(BAR_WIDTH, 26), UIStyle.HP_RED, Color(0, 0, 0, 0))
	hp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_bar.value = 100
	hp_bar.max_value = 100
	_hp_fill = UIStyle.bar_style(UIStyle.HP_RED, 4)
	hp_bar.add_theme_stylebox_override("fill", _hp_fill)
	hp_stack.add_child(hp_bar)
	hp_text = _label("100 / 100", 15, UIStyle.TEXT, true)
	hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_stack.add_child(hp_text)

	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 8)
	col.add_child(xp_row)
	level_label = _label("LV 1", 14, UIStyle.MINT, true)
	level_label.custom_minimum_size.x = 44
	xp_row.add_child(level_label)
	xp_bar = _bar(Vector2(BAR_WIDTH - 52, 8), UIStyle.MINT)
	xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp_row.add_child(xp_bar)

func _build_toasts(root: Control) -> void:
	# System AI taunts: hang directly under the System AI panel, as if the
	# panel itself were speaking.
	_toast_system = ToastPanel.new()
	_toast_system.set_card_width(330.0)
	_toast_system.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toast_system.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toast_system.offset_right = -16
	_toast_system.offset_top = 104
	root.add_child(_toast_system)
	# Everything else (achievements, loot, misc): low, above the bottom bars.
	_toast_main = ToastPanel.new()
	_toast_main.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast_main.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_main.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast_main.offset_bottom = -150
	root.add_child(_toast_main)

func _build_banner(root: Control) -> void:
	_banner_box = VBoxContainer.new()
	_banner_box.visible = false
	_banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner_box.anchor_top = 0.24
	_banner_box.anchor_bottom = 0.24
	_banner_box.add_theme_constant_override("separation", 0)
	root.add_child(_banner_box)
	_banner_title = _label("", 54, UIStyle.TEXT, true)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.add_theme_constant_override("outline_size", 8)
	_banner_box.add_child(_banner_title)
	_banner_sub = _label("", 18, UIStyle.TEXT_DIM)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_box.add_child(_banner_sub)

func _build_run_over(root: Control) -> void:
	_run_over = Control.new()
	_run_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_run_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_run_over.visible = false
	root.add_child(_run_over)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.04, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_run_over.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_run_over.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.04, 0.05, 0.08, 0.95), UIStyle.PANEL_BORDER, 10, 28, 2))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 520
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_run_over_title = _label("", 44, UIStyle.TEXT, true)
	_run_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_run_over_title.add_theme_constant_override("outline_size", 6)
	box.add_child(_run_over_title)
	_run_over_text = _label("", 16, UIStyle.TEXT_DIM)
	_run_over_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_run_over_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_run_over_text)
	_run_over_stats = HBoxContainer.new()
	_run_over_stats.alignment = BoxContainer.ALIGNMENT_CENTER
	_run_over_stats.add_theme_constant_override("separation", 40)
	box.add_child(_run_over_stats)
	_run_over_prompt = _label("PRESS R TO TRY AGAIN", 14, UIStyle.TEXT, true)
	_run_over_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_run_over_prompt)

# --- Per-frame animation -----------------------------------------------------

func _process(delta: float) -> void:
	_time += delta

	# HP trail: waits a beat after a hit, then drains toward the live value.
	if _trail_delay > 0.0:
		_trail_delay -= delta
	elif hp_trail.value > hp_bar.value:
		hp_trail.value = move_toward(hp_trail.value, hp_bar.value, hp_trail.max_value * 0.4 * delta)
	# Low-HP: the bar itself throbs.
	if _hp_fraction < ScreenOverlay.LOW_HP_THRESHOLD:
		var throb := 0.5 + 0.5 * sin(_time * 9.0)
		_hp_fill.bg_color = UIStyle.HP_RED.lerp(Color(1.0, 0.3, 0.35), throb)
	elif _hp_fill.bg_color != UIStyle.HP_RED:
		_hp_fill.bg_color = UIStyle.HP_RED

	# System AI banner: recording dot blink, change flash, glitch-in text.
	_system_dot.modulate.a = 0.35 + 0.65 * (0.5 + 0.5 * sin(_time * 5.0))
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.5)
		_system_panel.self_modulate = Color(1.0 + _flash * 0.9, 1.0 + _flash * 0.35, 1.0 + _flash * 0.35)
	if _glitch_time > 0.0:
		_glitch_time -= delta
		if _glitch_time <= 0.0:
			system_label.text = UIStyle.tactic_label(_tactic)
			system_label.add_theme_color_override("font_color", _tactic_color)
		else:
			system_label.text = _scramble(UIStyle.tactic_label(_tactic), _glitch_time / GLITCH_SEC)
			system_label.add_theme_color_override("font_color", _tactic_color.lerp(Color.WHITE, 0.6 * randf()))

	# "Press R" prompt blinks while the run-over card is up.
	if _run_over.visible:
		_run_over_prompt.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_time * 3.5))

func _scramble(text: String, amount: float) -> String:
	var out := ""
	for i in text.length():
		var ch := text[i]
		out += GLITCH_CHARS[randi() % GLITCH_CHARS.length()] if ch != " " and randf() < amount else ch
	return out

func _unhandled_input(event: InputEvent) -> void:
	if _run_over.visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		get_tree().paused = false
		get_tree().reload_current_scene()

# --- Updates pushed by floor.gd / player -----------------------------------

func update_floor(current_floor: int, max_floor: int) -> void:
	floor_label.text = "FLOOR %d / %d" % [current_floor, max_floor]
	var look := UIStyle.floor_look(current_floor)
	floor_name_label.text = look["name"]
	floor_name_label.add_theme_color_override("font_color", look["accent"].lightened(0.2))
	_timer_max = 0.0

func update_timer(time_remaining: float) -> void:
	_timer_max = maxf(_timer_max, time_remaining)
	var secs := int(ceilf(time_remaining))
	if secs != _timer_secs:  # text only changes once a second; skip the relayout otherwise
		_timer_secs = secs
		timer_label.text = "%02d:%02d" % [secs / 60, secs % 60]
	timer_bar.value = time_remaining / maxf(_timer_max, 0.001)
	var color := UIStyle.TEXT
	if time_remaining <= 10.0:
		color = UIStyle.SYSTEM.lerp(Color.WHITE, 0.5 * (0.5 + 0.5 * sin(_time * 10.0)))
	elif time_remaining <= 30.0:
		color = UIStyle.AMBER
	if color != _timer_color:  # only touch theme overrides on change (they trigger a relayout)
		_timer_color = color
		timer_label.add_theme_color_override("font_color", color)
		(timer_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = color if time_remaining <= 30.0 else UIStyle.CYAN

## Shows the System AI's current live tactic (changes every ~second when the
## director is running) so its per-second moves are visible, not just felt. A
## change triggers a flash and a short glitch-in so the player notices it.
func update_system_tactic(tactic: String, aggression: float = 1.0) -> void:
	if tactic != _tactic:
		_tactic = tactic
		_tactic_color = UIStyle.tactic_color(tactic)
		_glitch_time = GLITCH_SEC
		_flash = 1.0
		_system_style.border_color = Color(_tactic_color, 0.85)
		_system_style.shadow_color = Color(_tactic_color, 0.28)
	# Aggression 1.0 (neutral) .. 1.6 (max) fills the bar.
	_system_bar.value = clampf((aggression - 1.0) / 0.6, 0.0, 1.0)
	var mult_text := "x%.2f" % aggression
	if mult_text != _aggression_text:
		_aggression_text = mult_text
		_system_mult.text = mult_text

func update_points(points: int) -> void:
	points_label.text = "%d PTS" % points
	# Tiny punch so score gains register in the corner of the eye.
	if _points_tween:
		_points_tween.kill()
	points_label.pivot_offset = Vector2(0, points_label.size.y * 0.5)
	points_label.scale = Vector2(1.12, 1.12)
	_points_tween = create_tween()
	_points_tween.tween_property(points_label, "scale", Vector2.ONE, 0.18)

func update_level(level: int) -> void:
	level_label.text = "LV %d" % level

func update_hp(current: float, max_hp: float) -> void:
	hp_bar.max_value = max_hp
	hp_trail.max_value = max_hp
	if current < hp_bar.value:
		_trail_delay = HP_TRAIL_DELAY
	hp_bar.value = maxf(current, 0.0)
	if hp_bar.value >= hp_trail.value:
		hp_trail.value = hp_bar.value  # healing / max-HP gain: no trail
	hp_text.text = "%d / %d" % [ceili(maxf(current, 0.0)), ceili(max_hp)]
	_hp_fraction = clampf(current / maxf(max_hp, 1.0), 0.0, 1.0)

func update_xp(current: float, needed: float) -> void:
	xp_bar.max_value = needed
	xp_bar.value = current

## Cooldown fractions from Player: 0 = ready, 1 = just used.
func update_abilities(bomb_cooldown: float, laser_cooldown: float) -> void:
	_slot_bomb.set_cooldown(bomb_cooldown)
	_slot_laser.set_cooldown(laser_cooldown)

## fraction < 0 hides the bar (no boss alive).
func update_boss(hp_fraction: float) -> void:
	_boss_panel.visible = hp_fraction >= 0.0
	if hp_fraction >= 0.0:
		_boss_bar.value = clampf(hp_fraction, 0.0, 1.0)

# --- Transient messages ------------------------------------------------------

## kind: "info" | "system" | "achievement" | "loot" | "boss" | "death". `title`
## is an optional bold line above the body; `accent` overrides the kind's color
## (used for loot tiers).
func show_toast(text: String, kind: String = "info", duration: float = 4.5, accent: Color = Color.TRANSPARENT, title: String = "") -> void:
	var header := ""
	var color := UIStyle.CYAN
	match kind:
		"system":
			header = "SYSTEM AI TRANSMISSION"
			color = UIStyle.SYSTEM
		"achievement":
			header = "ACHIEVEMENT UNLOCKED"
			color = UIStyle.GOLD
		"loot":
			header = "LOOT"
			color = UIStyle.TIER_COLORS["rare"]
		"boss":
			header = "BOSS"
			color = UIStyle.BOSS_PURPLE
		"death":
			header = "THE SYSTEM HAS NOTED YOUR DEMISE"
			color = UIStyle.SYSTEM
	if accent.a > 0.0:
		color = accent
	if kind == "system":
		_toast_system.pop(header, title, text, color, duration, true)
	else:
		_toast_main.pop(header, title, text, color, duration, false)

## Big center-screen callout (floor start, boss, level-up, floor end).
func show_banner(title: String, subtitle: String = "", color: Color = UIStyle.TEXT, duration: float = 2.2) -> void:
	if _banner_tween:
		_banner_tween.kill()
	_banner_title.text = title
	_banner_title.add_theme_color_override("font_color", color.lightened(0.15))
	_banner_sub.text = subtitle
	_banner_sub.visible = subtitle != ""
	_banner_box.pivot_offset = _banner_box.get_combined_minimum_size() * 0.5
	_banner_box.visible = true
	_banner_box.modulate.a = 0.0
	_banner_box.scale = Vector2(1.25, 1.25)
	_banner_tween = create_tween().set_parallel(true)
	_banner_tween.tween_property(_banner_box, "modulate:a", 1.0, 0.18)
	_banner_tween.tween_property(_banner_box, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.set_parallel(false)
	_banner_tween.tween_interval(maxf(0.1, duration - 0.6))
	_banner_tween.tween_property(_banner_box, "modulate:a", 0.0, 0.4)
	_banner_tween.tween_callback(func() -> void: _banner_box.visible = false)

func show_floor_banner(current_floor: int, max_floor: int) -> void:
	var look := UIStyle.floor_look(current_floor)
	show_banner("FLOOR %d" % current_floor, "%s   -   %d of %d" % [look["name"], current_floor, max_floor], look["accent"], 2.6)

func show_level_up(level: int) -> void:
	show_banner("LEVEL UP", "Level %d   -   more damage, range, speed and HP" % level, UIStyle.MINT, 1.6)

## outcome: "cleared" | "collapsed" (same strings floor.gd's _end_floor uses).
func show_floor_end(outcome: String) -> void:
	if outcome == "cleared":
		show_banner("FLOOR CLEARED", "", UIStyle.MINT, 3.0)
	else:
		show_banner("CRAWLER DOWN", "", UIStyle.SYSTEM, 4.0)

## The final card. stats: {"floor": int, "points": int, "level": int}.
func show_run_over(outcome: String, text: String, stats: Dictionary) -> void:
	var won := outcome == "cleared"
	_run_over_title.text = "RUN COMPLETE" if won else "RUN OVER"
	_run_over_title.add_theme_color_override("font_color", UIStyle.GOLD if won else UIStyle.SYSTEM)
	_run_over_text.text = text
	for child in _run_over_stats.get_children():
		child.queue_free()
	_add_stat("FLOOR", str(stats.get("floor", 1)))
	_add_stat("POINTS", str(stats.get("points", 0)))
	_add_stat("LEVEL", str(stats.get("level", 1)))
	_run_over.modulate.a = 0.0
	_run_over.visible = true
	create_tween().tween_property(_run_over, "modulate:a", 1.0, 0.6)

func _add_stat(caption: String, value: String) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	var number := _label(value, 32, UIStyle.TEXT, true)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(number)
	var small := _label(caption, 11, UIStyle.TEXT_DIM, true)
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(small)
	_run_over_stats.add_child(col)
