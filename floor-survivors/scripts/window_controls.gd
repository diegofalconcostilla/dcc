extends Node

## Autoload. The game starts fullscreen (project.godot's display/window/size/mode)
## and F11 toggles back to a normal window and again. The project also pins the
## logical viewport to 1152x648 with canvas_items stretching, so fullscreen shows
## the same slice of the world as the windowed game, just scaled up — otherwise
## a bigger window would reveal more of the map and enemies (which spawn ~500px
## away) would visibly pop in on-screen.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep working while the floor-end pause is active

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()
