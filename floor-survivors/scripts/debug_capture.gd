extends Node
class_name DebugCapture

## Testing hook, inert unless env var DCC_CAPTURE_DIR is set (floor.gd only adds
## this node then). Runs a scripted timeline against the live game and saves
## viewport screenshots, so UI/art changes can be checked without playing.
##
##   DCC_CAPTURE_DIR   folder for the PNGs (created if missing)
##   DCC_CAPTURE_PLAN  "seconds:action[:arg]" steps separated by ";", e.g.
##                     "3:shot:early;6:close:14;8:shot:fight;9:quit"
##
## Actions: shot:name | close:N (spawn N enemies near the player) | boss |
## bomb:dx,dy | laser:dx,dy | hp:N | xp:N | end (expire the floor) | die | quit
## | floor:N (jump to floor N) | god:N (keep HP >= N) | tactic:name | toast:kind | runover | pressr (simulate the restart key) | fx (dump a sample of every effect type) | esc (simulate the Esc key) | settings (open the menu's settings page) | restart (floor.restart_run(), e.g. mid-request) | menurestart (the menu's Restart button) | state (print paused/floor_active/menu) | llm:on/off | tdown:x,y / tup:x,y / tdtap:x,y (simulated touch, viewport coords; needs DCC_TOUCH=1) | stats (print Carl's bomb/laser counts). Timings are wall-clock seconds
## since the floor started; the node ignores pause so it can shoot the
## end-of-floor screens too.

var _steps: Array = []
var _elapsed := 0.0
var _dir := ""
var _god_min_hp := 0.0  # while > 0, keeps the player alive so long timelines aren't cut short by dying

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dir = OS.get_environment("DCC_CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(_dir)
	for raw in OS.get_environment("DCC_CAPTURE_PLAN").split(";", false):
		var parts := raw.split(":")
		if parts.size() >= 2:
			_steps.append({"t": float(parts[0]), "action": parts[1], "arg": parts[2] if parts.size() > 2 else ""})
	_steps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["t"] < b["t"])

func _process(delta: float) -> void:
	_elapsed += delta
	if _god_min_hp > 0.0 and get_parent().floor_active and get_parent().player.hp < _god_min_hp:
		get_parent().player.hp = _god_min_hp
	while not _steps.is_empty() and _steps[0]["t"] <= _elapsed:
		var step: Dictionary = _steps.pop_front()
		await _run(step["action"], step["arg"])

func _run(action: String, arg: String) -> void:
	var floor_node := get_parent()
	var player: Player = floor_node.player
	match action:
		"shot":
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			image.save_png("%s/%s.png" % [_dir, arg])
			print("[capture] saved %s.png" % arg)
		"close":
			var spawner: EnemySpawner = floor_node.spawner
			var saved: float = spawner._spawn_radius_mult
			spawner._spawn_radius_mult = 0.42
			for i in int(arg):
				spawner._spawn_enemy()
			spawner._spawn_radius_mult = saved
		"boss":
			floor_node.spawner._spawn_boss()
			var boss := get_tree().get_first_node_in_group("bosses") as Node2D
			if boss:
				boss.global_position = player.global_position + Vector2(170, -90)
		"tdown", "tup", "tdtap":
			# Simulated touches (viewport coords "x,y", finger 1), for TouchControls.
			# parse_input_event wants window coords; the plan speaks viewport coords.
			var at := get_viewport().get_final_transform() * _vec(arg)
			var presses: Array = [true] if action == "tdown" else ([false] if action == "tup" else [true, false, true, false])
			for pressed in presses:
				var touch := InputEventScreenTouch.new()
				touch.index = 1
				touch.position = at
				touch.pressed = pressed
				Input.parse_input_event(touch)
		"stats":
			print("[capture] stats: bombs=%d lasers=%d" % [player.floor_bombs_thrown, player.floor_missiles_cast])
		"bomb":
			var offset := _vec(arg)
			var bomb := Bomb.new()
			bomb.global_position = player.global_position + offset
			bomb.damage = Player.BOMB_DAMAGE
			bomb.radius = Player.BOMB_RADIUS
			floor_node.add_child(bomb)
		"laser":
			var laser := Laser.new()
			laser.global_position = player.global_position
			laser.direction = _vec(arg).normalized()
			laser.damage = Player.MISSILE_DAMAGE
			laser.max_range = Player.MISSILE_RANGE
			floor_node.add_child(laser)
		"god":
			_god_min_hp = float(arg)
		"hp":
			_god_min_hp = 0.0
			player.hp = float(arg)
			player.hp_changed.emit(player.hp, player.max_hp)
		"xp":
			player.gain_xp(float(arg))
		"end":
			floor_node.time_remaining = 0.05
		"die":
			player.take_damage(1.0e9)
		"fx":
			var fx := FxLayer.of(self)
			var p := player.global_position + Vector2(0, -120)
			fx.burst(p, UIStyle.HP_RED, 14, 200.0)
			fx.sparks(p + Vector2(60, 0), UIStyle.CYAN, 10, 250.0)
			fx.ring(p + Vector2(-60, 0), UIStyle.AMBER, 10.0, 60.0, 1.5)
			fx.float_text(p + Vector2(0, -30), "128", Color(1, 0.82, 0.25), 20.0, 1.5)
		"tactic":
			var beat := {"tactic": arg, "bomb_dodge_chance": 0.0, "missile_dodge_chance": 0.0, "spawn_interval_multiplier": 1.0, "spawn_radius_multiplier": 1.0, "aggression_multiplier": 1.45}
			floor_node.director._plan = [beat, beat, beat, beat, beat, beat]
			floor_node.director._plan_age = 0.0
		"toast":
			match arg:
				"system": floor_node.hud.show_toast("You throw bombs like they are free. Let us see how well you dodge what dodges you back.", "system", 6.0)
				"achievement": floor_node.hud.show_toast("Survived a whole floor without once looking at the map.", "achievement", 6.0, Color.TRANSPARENT, "Directionally Challenged")
				"loot": floor_node.hud.show_toast("It smells faintly of cat. Nobody asked it to.", "loot", 6.0, UIStyle.tier_color("epic"), "Donut's Second-Favorite Sock  [EPIC]")
				"boss": floor_node.hud.show_toast("+500 points", "boss", 5.0, Color.TRANSPARENT, "Boss defeated")
		"floor":
			floor_node.current_floor = int(arg) - 1
			floor_node._start_next_floor()
		"pressr":
			var key := InputEventKey.new()
			key.keycode = KEY_R
			key.pressed = true
			Input.parse_input_event(key)
		"runover":
			floor_node.hud.show_run_over("collapsed", "The System regrets nothing. Carl regrets everything.", {"floor": 4, "points": 1820, "level": 9})
		"esc":
			var esc := InputEventKey.new()
			esc.keycode = KEY_ESCAPE
			esc.physical_keycode = KEY_ESCAPE
			esc.pressed = true
			Input.parse_input_event(esc)
		"settings":
			var menu := get_tree().get_first_node_in_group("pause_menu")
			if not menu.is_open():
				menu.open()
			menu._show_page(true)
		"restart":
			floor_node.restart_run()
		"menurestart":
			get_tree().get_first_node_in_group("pause_menu")._on_restart()
		"state":
			print("[capture] state: paused=%s floor_active=%s menu_open=%s floor=%d" % [get_tree().paused, floor_node.floor_active, PauseMenu.menu_open, floor_node.current_floor])
		"llm":
			GameSettings.set_llm_enabled(arg == "on")
		"quit":
			get_tree().quit()

func _vec(arg: String) -> Vector2:
	var xy := arg.split(",")
	return Vector2(float(xy[0]), float(xy[1])) if xy.size() == 2 else Vector2.RIGHT * 100.0
