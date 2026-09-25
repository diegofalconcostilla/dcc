extends RefCounted
class_name GameSettings

## The single source of truth for player settings — the Esc menu, AudioManager,
## WindowControls (F11), the M key, FxLayer's shake and OllamaClient all read and
## write these values, and they persist to user://settings.cfg. Static (no
## autoload node) so it also works in the headless --script harnesses.
##
## Setters apply their effect immediately and only mark the file dirty; call
## flush() at natural moments (slider released, menu closed, a hotkey) so
## dragging a slider doesn't rewrite the file every frame.

const PATH := "user://settings.cfg"
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
# Bus levels at 100% volume (AudioManager creates the buses with these).
const BUS_BASE_DB := {"Music": -4.0, "SFX": -2.0}
const SHAKE_MAX := 1.5

static var music_volume := 1.0   # 0..1
static var sfx_volume := 1.0     # 0..1
static var muted := false
static var fullscreen := true    # the project starts fullscreen (project.godot)
static var shake_scale := 1.0    # 0..SHAKE_MAX, multiplies FxLayer's camera shake
static var llm_enabled := true   # false = never call Ollama; every AI feature uses its local fallback
static var sprite_art := true    # false = the original code-drawn actors (SpriteBank)

static var _loaded := false
static var _dirty := false

static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return  # first run: defaults
	music_volume = clampf(float(cfg.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	muted = bool(cfg.get_value("audio", "muted", muted))
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	shake_scale = clampf(float(cfg.get_value("video", "shake_scale", shake_scale)), 0.0, SHAKE_MAX)
	llm_enabled = bool(cfg.get_value("ai", "llm_enabled", llm_enabled))
	sprite_art = bool(cfg.get_value("video", "sprite_art", sprite_art))

static func flush() -> void:
	if not _dirty:
		return
	_dirty = false
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "muted", muted)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "shake_scale", shake_scale)
	cfg.set_value("ai", "llm_enabled", llm_enabled)
	cfg.set_value("video", "sprite_art", sprite_art)
	if cfg.save(PATH) != OK:
		push_warning("[GameSettings] could not save %s" % PATH)

## Pushes the audio settings onto the buses (which AudioManager must have created).
static func apply_audio() -> void:
	_apply_bus(MUSIC_BUS, music_volume)
	_apply_bus(SFX_BUS, sfx_volume)

static func _apply_bus(bus_name: String, volume: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var db := -80.0 if volume <= 0.001 else float(BUS_BASE_DB[bus_name]) + linear_to_db(volume)
	AudioServer.set_bus_volume_db(idx, db)
	AudioServer.set_bus_mute(idx, muted)

static func apply_window() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

## The window's real state (the OS can change it behind our back), for the menu.
static func is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN

static func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_dirty = true
	apply_audio()

static func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_dirty = true
	apply_audio()

static func set_muted(value: bool) -> void:
	muted = value
	_dirty = true
	apply_audio()

static func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_dirty = true
	apply_window()

static func set_shake_scale(v: float) -> void:
	shake_scale = clampf(v, 0.0, SHAKE_MAX)
	_dirty = true

static func set_llm_enabled(value: bool) -> void:
	llm_enabled = value
	_dirty = true
