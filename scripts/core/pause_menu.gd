class_name PauseMenu
extends CanvasLayer

var player: PlayerController
var opened := false
var _shade: ColorRect
var _resume: Button
var _status: Label
var _confirm: ConfirmationDialog

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 200
	_shade = ColorRect.new()
	_shade.color = Color(0.025, 0.04, 0.055, 0.93)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.add_child(center)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 600)
	center.add_child(scroll)
	var list := VBoxContainer.new()
	list.custom_minimum_size.x = 460
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var title := Label.new()
	title.text = "ПАУЗА / ZERO FRAME"
	title.add_theme_font_size_override("font_size", 30)
	list.add_child(title)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 460
	list.add_child(_status)
	_resume = _button(list, "ПРОДОЛЖИТЬ · ESC", func() -> void: set_open(false))
	var graphics := OptionButton.new()
	for label: String in ["ГРАФИКА: AUTO", "ГРАФИКА: PERFORMANCE", "ГРАФИКА: HIGH", "ГРАФИКА: ULTRA"]:
		graphics.add_item(label)
	graphics.select(clampi(int(ProjectSettings.get_setting("zero_frame/graphics_quality", 0)), 0, 3))
	graphics.item_selected.connect(set_graphics)
	list.add_child(graphics)
	_slider(list, "Угол обзора", 70, 110, 1, player.camera.fov, set_fov)
	_slider(list, "Чувствительность мыши", 0.5, 10, 0.1, (player.camera as BodycamPhysics).mouse_sensitivity * 1000.0, set_sensitivity)
	_slider(list, "Громкость, %", 0, 100, 1, AudioServer.get_bus_volume_linear(0) * 100.0, set_volume)
	_button(list, "ПОЛНЫЙ ЭКРАН · F11", func() -> void:
		var window := get_window()
		window.mode = Window.MODE_WINDOWED if window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN] else Window.MODE_EXCLUSIVE_FULLSCREEN)
	_button(list, "В ГЛАВНОЕ МЕНЮ…", _request_leave)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Выйти из игры?"
	_confirm.ok_button_text = "ВЫЙТИ В МЕНЮ"
	_confirm.cancel_button_text = "ОСТАТЬСЯ"
	_confirm.confirmed.connect(_leave)
	add_child(_confirm)
	_shade.hide()

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _slider(parent: Node, text: String, low: float, high: float, step: float, value: float, action: Callable) -> void:
	var label := Label.new()
	label.text = "%s: %.1f" % [text, value]
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.y = 24
	slider.value_changed.connect(func(next: float) -> void:
		label.text = "%s: %.1f" % [text, next]
		action.call(next))
	parent.add_child(slider)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		if _confirm.visible:
			_confirm.hide()
		else:
			set_open(not opened)
		get_viewport().set_input_as_handled()

func set_open(value: bool) -> void:
	opened = value
	player.menu_open = value
	_shade.visible = value
	# Never pause SceneTree in multiplayer, including on the listening host.
	# Physics, replication, damage and respawn keep running for every peer.
	get_tree().paused = value and not get_node("/root/NetworkGame").active
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED
	player.weapon_manager.require_trigger_release = true
	if value:
		_status.text = "ОНЛАЙН НЕ ОСТАНОВЛЕН. Вы остаётесь уязвимы." if get_node("/root/NetworkGame").active else "Одиночная игра приостановлена."
		_resume.grab_focus()
	else:
		_confirm.hide()

func set_graphics(index: int) -> void:
	ProjectSettings.set_setting("zero_frame/graphics_quality", index)
	for host: PhotorealEnvironment in get_tree().get_nodes_in_group("photoreal_environment"):
		if host.get_viewport() == player.get_viewport():
			host.quality_preset = index as PhotorealEnvironment.QualityPreset
			host.apply_preset()

func set_fov(value: float) -> void:
	ProjectSettings.set_setting("zero_frame/fov", value)
	player.camera.fov = value

func set_sensitivity(value: float) -> void:
	ProjectSettings.set_setting("zero_frame/mouse_sensitivity", value / 1000.0)
	(player.camera as BodycamPhysics).mouse_sensitivity = value / 1000.0

func set_volume(value: float) -> void:
	AudioServer.set_bus_volume_linear(0, value / 100.0)

func _request_leave() -> void:
	var network := get_node("/root/NetworkGame")
	_confirm.dialog_text = "Выход хоста завершит матч для остальных игроков." if network.is_server() else "Покинуть текущую игру и открыть главное меню?"
	_confirm.popup_centered()

func _leave() -> void:
	get_tree().paused = false
	get_node("/root/NetworkGame").leave_match()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _exit_tree() -> void:
	if opened:
		get_tree().paused = false
