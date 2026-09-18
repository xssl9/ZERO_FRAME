extends Node

## Global input handler for actions that must work everywhere:
## main menu, in-game, pause, lobby.

## The DevPanel is created once and lives here so it survives scene changes.
var _dev_panel: DevPanel = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_spawn_dev_panel()

func _spawn_dev_panel() -> void:
	_dev_panel = DevPanel.new()
	_dev_panel.name = "DevPanel"
	# PROCESS_MODE_ALWAYS so it works while the game is paused / in menus.
	_dev_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_dev_panel)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		var window := get_window()
		if window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN or window.mode == Window.MODE_FULLSCREEN:
			window.mode = Window.MODE_WINDOWED
		else:
			window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		get_viewport().set_input_as_handled()
