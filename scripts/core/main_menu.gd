extends Control

const MAPS: Array[Array] = [
	["DEV TEST GRID", "res://scenes/levels/dev_test_grid.tscn"],
	["PVP — LINSE", "res://scenes/levels/pvp_linse.tscn"],
	["ПАРКИНГ", "res://scenes/levels/parking_garage.tscn"]
]

const GRAPHICS_NAMES: PackedStringArray = ["AUTO", "PERFORMANCE", "HIGH", "ULTRA"]
# Plain 0/1 is what PhotorealEnvironment reads back out of the setting: 0 clear, 1 rain, and
# clear is what the game starts on - rain is the heavier grade and the one that costs a
# fullscreen water pass, so it is opted into rather than out of.
const WEATHER_NAMES: PackedStringArray = ["ЯСНО", "ДОЖДЬ"]
const WEATHER_SETTING := "zero_frame/weather"
# The menu shows the PvP map behind the buttons: a camera standing in the middle of it,
# turning slowly, that the player can grab and look around with.
const PANORAMA_SCENE := "res://scenes/levels/pvp_linse.tscn"
const PANORAMA_EYE := Vector3(0.0, 2.35, -1.6)
const PANORAMA_DRIFT_DEGREES_PER_SECOND := 3.2
const PANORAMA_SENSITIVITY := 0.16

var graphics_button: Button
var weather_button: Button
var _panorama_camera: Camera3D
var _panorama_yaw: float = 0.0
var _panorama_pitch: float = -3.0
var _dragging: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_panorama()
	var background := ColorRect.new()
	# Semi-transparent: the panorama behind it has to stay visible, the text on it readable.
	background.color = Color("071015")
	background.color.a = 0.3
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var title := Label.new()
	title.text = "ZERO FRAME"
	title.add_theme_font_size_override("font_size", 54)
	title.position = Vector2(80.0, 48.0)
	background.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "BODYCAM   •   ВЫБОР КАРТЫ"
	subtitle.modulate = Color("7f9ba5")
	subtitle.position = Vector2(84.0, 118.0)
	background.add_child(subtitle)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(80.0, 175.0)
	scroll.size = Vector2(460.0, 455.0)
	background.add_child(scroll)
	var buttons := VBoxContainer.new()
	buttons.custom_minimum_size = Vector2(430.0, 0.0)
	buttons.add_theme_constant_override("separation", 8)
	scroll.add_child(buttons)
	for map_data: Array in MAPS:
		_add_button(buttons, map_data[0] as String, _start_map.bind(map_data[1] as String))
	graphics_button = _add_button(buttons, "", _cycle_graphics)
	_refresh_graphics_button()
	weather_button = _add_button(buttons, "", _cycle_weather)
	_refresh_weather_button()
	_add_button(buttons, "ВЫХОД", _quit)
	var hint := Label.new()
	hint.text = "ЛКМ — осмотреться"
	hint.modulate = Color(0.65, 0.72, 0.74, 0.6)
	hint.position = Vector2(84.0, 648.0)
	background.add_child(hint)

# The map itself is the menu background, rendered by its own camera in a SubViewport. The
# Player node is dropped before the level enters the tree, so it never grabs the mouse or
# makes its own camera current.
func _build_panorama() -> void:
	var packed := load(PANORAMA_SCENE) as PackedScene
	if packed == null:
		return
	var container := SubViewportContainer.new()
	container.name = "PanoramaContainer"
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	var viewport := SubViewport.new()
	viewport.name = "Panorama"
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(viewport)
	var level := packed.instantiate()
	var player := level.get_node_or_null("Player")
	if player != null:
		level.remove_child(player)
		player.free()
	var scan := level.get_node_or_null("Scan")
	if scan != null:
		scan.set("build_collision", false)
	viewport.add_child(level)
	_panorama_camera = Camera3D.new()
	_panorama_camera.name = "PanoramaCamera"
	_panorama_camera.fov = 74.0
	_panorama_camera.near = 0.05
	_panorama_camera.far = 200.0
	_panorama_camera.position = PANORAMA_EYE
	_panorama_camera.current = true
	viewport.add_child(_panorama_camera)
	_apply_panorama_rotation()
	# After the level's own _ready has graded itself, lift the menu copy: the interior is
	# darker than a menu wants, and gameplay exposure must not be touched for it.
	call_deferred("_brighten_panorama", level)

func _brighten_panorama(level: Node) -> void:
	var world_environment := level.get_node_or_null("PhotorealEnvironment") as WorldEnvironment
	if world_environment == null or world_environment.environment == null:
		return
	world_environment.environment.tonemap_exposure *= 1.4

func _unhandled_input(event: InputEvent) -> void:
	if _panorama_camera == null:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_panorama_yaw -= motion.relative.x * PANORAMA_SENSITIVITY
		_panorama_pitch = clampf(_panorama_pitch - motion.relative.y * PANORAMA_SENSITIVITY, -70.0, 70.0)
		_apply_panorama_rotation()

func _process(delta: float) -> void:
	if _panorama_camera == null or _dragging:
		return
	# Slow drift when nobody is holding it, so the menu is never a still frame.
	_panorama_yaw = fmod(_panorama_yaw + PANORAMA_DRIFT_DEGREES_PER_SECOND * delta, 360.0)
	_apply_panorama_rotation()

func _apply_panorama_rotation() -> void:
	_panorama_camera.rotation_degrees = Vector3(_panorama_pitch, _panorama_yaw, 0.0)

func _add_button(parent: VBoxContainer, label_text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(420.0, 48.0)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _cycle_graphics() -> void:
	var current := int(ProjectSettings.get_setting("zero_frame/graphics_quality", 0))
	ProjectSettings.set_setting("zero_frame/graphics_quality", (current + 1) % GRAPHICS_NAMES.size())
	_refresh_graphics_button()

func _refresh_graphics_button() -> void:
	var current := clampi(int(ProjectSettings.get_setting("zero_frame/graphics_quality", 0)), 0, GRAPHICS_NAMES.size() - 1)
	graphics_button.text = "ГРАФИКА: %s" % GRAPHICS_NAMES[current]

func _cycle_weather() -> void:
	var current := int(ProjectSettings.get_setting(WEATHER_SETTING, 0))
	ProjectSettings.set_setting(WEATHER_SETTING, (current + 1) % WEATHER_NAMES.size())
	_refresh_weather_button()

func _refresh_weather_button() -> void:
	var current := clampi(int(ProjectSettings.get_setting(WEATHER_SETTING, 0)), 0, WEATHER_NAMES.size() - 1)
	weather_button.text = "ПОГОДА: %s" % WEATHER_NAMES[current]

func _start_map(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func _quit() -> void:
	get_tree().quit()
