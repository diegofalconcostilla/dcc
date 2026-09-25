extends CanvasLayer
class_name PauseMenu

## The Esc menu: Resume / Restart run / Settings / Quit game, plus a settings
## page (music + SFX volume, mute, fullscreen, screen shake, and a switch that
## turns the System AI's language model off). Values live in GameSettings, which
## persists them to user://settings.cfg; this node is only the UI over it.
##
## Pausing: opening the menu pauses the tree; closing puts the pause back to
## whatever the floor wants (`not floor_active`, because the floor-end sequence
## runs with the tree paused on purpose — Resume must not unpause *that*). While
## open it re-asserts the pause every frame, so a floor starting underneath it
## (the end-of-floor sequence can finish while the menu is up) can't let the
## game run behind it. Mouse and keyboard both work (arrows/Enter, Esc = back).
##
## The node is PROCESS_MODE_ALWAYS on a CanvasLayer above the HUD, and its
## full-screen root swallows mouse input, so clicks never reach the player's
## _unhandled_input.

## True while the menu is up. Read by OllamaClient (time spent in the menu
## doesn't count against a request's timeout) and HUD (R is ignored under it).
static var menu_open := false

const PANEL_WIDTH := 480.0

var _root: Control
var _subtitle: Label
var _main_page: VBoxContainer
var _settings_page: VBoxContainer
var _resume_button: Button
var _back_button: Button
var _music_slider: HSlider
var _sfx_slider: HSlider
var _shake_slider: HSlider
var _music_value: Label
var _sfx_value: Label
var _shake_value: Label
var _mute_toggle: Button
var _fullscreen_toggle: Button
var _llm_toggle: Button
var _art_toggle: Button
var _in_settings := false
var _quiet := false  # suppresses the focus tick while we move focus ourselves

func _ready() -> void:
	layer = 20  # above the HUD (2) and everything else
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pause_menu")
	menu_open = false  # a static: don't inherit "open" from a scene that was freed with the menu up
	_build()
	_root.visible = false

func _exit_tree() -> void:
	menu_open = false

func is_open() -> bool:
	return _root.visible

# --- Construction ----------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = UIStyle.build_theme()
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.04, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.04, 0.05, 0.08, 0.96), UIStyle.PANEL_BORDER, 10, 28, 2))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = PANEL_WIDTH
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := _label("PAUSED", 40, UIStyle.TEXT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 6)
	box.add_child(title)
	_subtitle = _label("", 14, UIStyle.TEXT_DIM)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_subtitle)

	_main_page = VBoxContainer.new()
	_main_page.add_theme_constant_override("separation", 10)
	box.add_child(_main_page)
	_resume_button = _button("Resume", close)
	_main_page.add_child(_resume_button)
	_main_page.add_child(_button("Restart run", _on_restart))
	_main_page.add_child(_button("Settings", func(): _show_page(true)))
	_main_page.add_child(_button("Quit game", func(): get_tree().quit()))

	_settings_page = VBoxContainer.new()
	_settings_page.add_theme_constant_override("separation", 12)
	box.add_child(_settings_page)
	_music_slider = _slider(0.0, 100.0, 5.0)
	_music_value = _label("", 15, UIStyle.TEXT_DIM)
	_settings_page.add_child(_slider_row("Music volume", _music_slider, _music_value))
	_sfx_slider = _slider(0.0, 100.0, 5.0)
	_sfx_value = _label("", 15, UIStyle.TEXT_DIM)
	_settings_page.add_child(_slider_row("SFX volume", _sfx_slider, _sfx_value))
	_mute_toggle = _toggle()
	_settings_page.add_child(_row("Mute all  [M]", _mute_toggle))
	_fullscreen_toggle = _toggle()
	_settings_page.add_child(_row("Fullscreen  [F11]", _fullscreen_toggle))
	_shake_slider = _slider(0.0, GameSettings.SHAKE_MAX * 100.0, 10.0)
	_shake_value = _label("", 15, UIStyle.TEXT_DIM)
	_settings_page.add_child(_slider_row("Screen shake", _shake_slider, _shake_value))
	_art_toggle = _toggle()
	_settings_page.add_child(_row("Pixel-art sprites", _art_toggle))
	_llm_toggle = _toggle()
	_settings_page.add_child(_row("System AI language model", _llm_toggle))
	var llm_note := _label("Off = no Ollama calls; the System AI, achievements and loot use their built-in fallbacks.", 12, UIStyle.TEXT_DIM)
	llm_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settings_page.add_child(llm_note)
	_back_button = _button("Back", func(): _show_page(false))
	_settings_page.add_child(_back_button)

	var hint := _label("Esc back   ·   ↑ ↓ move   ·   ← → adjust   ·   Enter select", 12, UIStyle.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	_music_slider.value_changed.connect(func(v: float):
		GameSettings.set_music_volume(v / 100.0)
		_music_value.text = "%d%%" % int(v))
	_sfx_slider.value_changed.connect(func(v: float):
		GameSettings.set_sfx_volume(v / 100.0)
		_sfx_value.text = "%d%%" % int(v)
		AudioManager.play_sfx("kill"))  # audible preview of the new level
	_shake_slider.value_changed.connect(func(v: float):
		GameSettings.set_shake_scale(v / 100.0)
		_shake_value.text = "%d%%" % int(v)
		var fx := FxLayer.of(self)
		if fx:
			fx.shake(4.0))  # visible preview
	_mute_toggle.toggled.connect(func(on: bool):
		GameSettings.set_muted(on)
		_set_toggle_text(_mute_toggle, on))
	_fullscreen_toggle.toggled.connect(func(on: bool):
		GameSettings.set_fullscreen(on)
		_set_toggle_text(_fullscreen_toggle, on))
	_llm_toggle.toggled.connect(func(on: bool):
		GameSettings.set_llm_enabled(on)
		_set_toggle_text(_llm_toggle, on))
	_art_toggle.toggled.connect(func(on: bool):  # off = the original code-drawn actors
		GameSettings.set_sprite_art(on)
		_set_toggle_text(_art_toggle, on))
	for slider in [_music_slider, _sfx_slider, _shake_slider]:
		slider.drag_ended.connect(func(_changed: bool): GameSettings.flush())

func _label(text: String, font_size: int, color: Color = UIStyle.TEXT, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if bold:
		label.add_theme_font_override("font", UIStyle.font(true))
	return label

func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		AudioManager.play_sfx("ui_click")
		on_press.call())
	b.focus_entered.connect(_focus_tick)
	b.mouse_entered.connect(b.grab_focus)  # hover and keyboard focus stay one and the same
	return b

func _toggle() -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size.x = 96
	b.focus_entered.connect(_focus_tick)
	b.mouse_entered.connect(b.grab_focus)
	b.toggled.connect(func(_on: bool): AudioManager.play_sfx("ui_click"))
	return b

func _slider(min_value: float, max_value: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_value
	s.max_value = max_value
	s.step = step
	s.custom_minimum_size = Vector2(190, 26)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_entered.connect(_focus_tick)
	s.mouse_entered.connect(s.grab_focus)
	return s

func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := _label(text, 16)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(control)
	return row

func _slider_row(text: String, slider: HSlider, value_label: Label) -> HBoxContainer:
	value_label.custom_minimum_size.x = 46
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.add_child(slider)
	right.add_child(value_label)
	return _row(text, right)

func _focus_tick() -> void:
	if not _quiet:
		AudioManager.play_sfx("ui_move")

# --- Behavior ----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if not is_open():
		open()
	elif _in_settings:
		_show_page(false)
	else:
		close()

func open() -> void:
	if is_open():
		return
	menu_open = true
	_root.visible = true
	get_tree().paused = true
	var floor_node := get_tree().get_first_node_in_group("floor_controller")
	if floor_node:
		_subtitle.text = "Floor %d / %d  ·  %s" % [floor_node.current_floor, floor_node.MAX_FLOOR, UIStyle.floor_look(floor_node.current_floor)["name"]]
	_show_page(false)
	AudioManager.play_sfx("ui_click")

## Closes the menu and puts the pause back to what the floor itself wants —
## paused only during the floor-end sequence (see the class comment).
func close() -> void:
	if not is_open():
		return
	_hide()
	var floor_node := get_tree().get_first_node_in_group("floor_controller")
	get_tree().paused = floor_node != null and not floor_node.floor_active

func _hide() -> void:
	menu_open = false
	_root.visible = false
	GameSettings.flush()

func _on_restart() -> void:
	var floor_node := get_tree().get_first_node_in_group("floor_controller")
	if floor_node == null:
		return
	# Hide without touching the pause state: restart_run() lifts it itself right
	# before the reload (so the fresh scene never inherits a paused tree).
	_hide()
	floor_node.restart_run()

func _show_page(settings: bool) -> void:
	_in_settings = settings
	_main_page.visible = not settings
	_settings_page.visible = settings
	if settings:
		_sync_settings(true)
	_quiet = true
	(_back_button if settings else _resume_button).grab_focus()
	_quiet = false
	if not settings:
		GameSettings.flush()

func _process(_delta: float) -> void:
	if not is_open():
		return
	get_tree().paused = true  # keep the game frozen even if something tries to unpause it
	if _in_settings:
		_sync_settings(false)  # M / F11 pressed while the menu is up

## Pushes GameSettings' values into the widgets. `all` also resets the sliders
## (on entering the page); the toggles are always re-synced since hotkeys change them.
func _sync_settings(all: bool) -> void:
	if all:
		_music_slider.set_value_no_signal(GameSettings.music_volume * 100.0)
		_music_value.text = "%d%%" % int(_music_slider.value)
		_sfx_slider.set_value_no_signal(GameSettings.sfx_volume * 100.0)
		_sfx_value.text = "%d%%" % int(_sfx_slider.value)
		_shake_slider.set_value_no_signal(GameSettings.shake_scale * 100.0)
		_shake_value.text = "%d%%" % int(_shake_slider.value)
	_set_toggle(_mute_toggle, GameSettings.muted)
	_set_toggle(_fullscreen_toggle, GameSettings.is_fullscreen())
	_set_toggle(_llm_toggle, GameSettings.llm_enabled)
	_set_toggle(_art_toggle, GameSettings.sprite_art)

func _set_toggle(button: Button, on: bool) -> void:
	if button.button_pressed != on:
		button.set_pressed_no_signal(on)
	_set_toggle_text(button, on)

func _set_toggle_text(button: Button, on: bool) -> void:
	button.text = "ON" if on else "OFF"
