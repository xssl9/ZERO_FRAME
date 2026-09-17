extends Control

const MAPS: Array[Array] = [
	["DEV TEST GRID", "res://scenes/levels/dev_test_grid.tscn"],
	["PVP — LINSE", "res://scenes/levels/pvp_linse.tscn"],
	["ПАРКИНГ", "res://scenes/levels/parking_garage_rework.tscn"]
]

const GRAPHICS_NAMES: PackedStringArray = ["AUTO", "PERFORMANCE", "HIGH", "ULTRA"]
# Plain 0/1 is what PhotorealEnvironment reads back out of the setting: 0 clear, 1 rain, and
# clear is what the game starts on - rain is the heavier grade and the one that costs a
# fullscreen water pass, so it is opted into rather than out of.
const WEATHER_NAMES: PackedStringArray = ["ЯСНО", "ДОЖДЬ", "ПАСМУРНО", "ЛИВЕНЬ"]
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

# Lobby state
var _main_panel: VBoxContainer
var _lobby_panel: VBoxContainer
var _member_list: VBoxContainer
var _steam_status: Label
var _lobby_map_button: Button
var _lobby_ready_button: Button
var _lobby_start_button: Button
var _create_lobby_button: Button
var _lobby_map_index: int = 0
var _in_lobby: bool = false
var _is_ready: bool = false
var _member_avatars: Dictionary = {}
var _friends_dialog: AcceptDialog

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
	# --- Main button list (single-player maps + settings) ---
	_main_panel = VBoxContainer.new()
	_main_panel.custom_minimum_size = Vector2(430.0, 0.0)
	_main_panel.add_theme_constant_override("separation", 8)
	scroll.add_child(_main_panel)
	for map_data: Array in MAPS:
		_add_button(_main_panel, map_data[0] as String, _start_map.bind(map_data[1] as String))
	graphics_button = _add_button(_main_panel, "", _cycle_graphics)
	_refresh_graphics_button()
	weather_button = _add_button(_main_panel, "", _cycle_weather)
	_refresh_weather_button()
	_create_lobby_button = _add_button(_main_panel, "СОЗДАТЬ ЛОББИ", _create_lobby)
	_add_button(_main_panel, "ВЫХОД", _quit)
	# --- Lobby panel (hidden until a lobby is entered) ---
	_build_lobby_panel(scroll)
	# --- Steam status ---
	_steam_status = Label.new()
	_steam_status.modulate = Color(0.55, 0.7, 0.72, 0.7)
	_steam_status.position = Vector2(84.0, 648.0)
	background.add_child(_steam_status)
	_update_steam_status()
	# Connect to SteamManager signals if available.
	if _steam_available():
		SteamManager.lobby_entered.connect(_on_lobby_entered)
		SteamManager.lobby_exited.connect(_on_lobby_exited)
		SteamManager.lobby_members_changed.connect(_on_lobby_members_changed)
		SteamManager.avatar_ready.connect(_on_avatar_ready)
		SteamManager.status_changed.connect(func(_t: String) -> void: _update_steam_status())
		# If we already have an active lobby (returned from a match), show the panel.
		if SteamManager.lobby_id != 0:
			call_deferred("_on_lobby_entered", SteamManager.lobby_id)
	else:
		_create_lobby_button.disabled = true
		_create_lobby_button.text = "ЛОББИ (STEAM НЕ ДОСТУПЕН)"

# --- Lobby panel ----------------------------------------------------------

func _build_lobby_panel(scroll: ScrollContainer) -> void:
	_lobby_panel = VBoxContainer.new()
	_lobby_panel.custom_minimum_size = Vector2(430.0, 0.0)
	_lobby_panel.add_theme_constant_override("separation", 8)
	_lobby_panel.visible = false
	scroll.add_child(_lobby_panel)
	var header := Label.new()
	header.text = "ЛОББИ"
	header.add_theme_font_size_override("font_size", 24)
	header.modulate = Color(0.82, 0.92, 1.0)
	_lobby_panel.add_child(header)
	_member_list = VBoxContainer.new()
	_member_list.name = "MemberList"
	_member_list.add_theme_constant_override("separation", 4)
	_lobby_panel.add_child(_member_list)
	var sep := HSeparator.new()
	sep.modulate = Color(0.4, 0.5, 0.55, 0.5)
	_lobby_panel.add_child(sep)
	_lobby_map_button = _add_button(_lobby_panel, "", _cycle_lobby_map)
	_refresh_lobby_map_button()
	_add_button(_lobby_panel, "ПРИГЛАСИТЬ ДРУГА", _invite_friend)
	_add_button(_lobby_panel, "ДРУЗЬЯ (БЕЗ ОВЕРЛЕЯ)", _show_friends)
	_lobby_ready_button = _add_button(_lobby_panel, "ГОТОВ", _toggle_ready)
	_lobby_start_button = _add_button(_lobby_panel, "НАЧАТЬ МАТЧ", _start_match)
	_add_button(_lobby_panel, "ПОКИНУТЬ ЛОББИ", _leave_lobby)

func _steam_available() -> bool:
	return SteamManager != null and SteamManager.available

func _update_steam_status() -> void:
	if _steam_status == null:
		return
	if SteamManager != null:
		_steam_status.text = SteamManager.status_text
	else:
		_steam_status.text = "STEAM: НЕ ЗАГРУЖЕН"

func _create_lobby() -> void:
	if not _steam_available():
		return
	SteamManager.create_lobby()

func _on_lobby_entered(_lobby_id: int) -> void:
	_in_lobby = true
	_main_panel.visible = false
	_lobby_panel.visible = true
	_update_member_list()
	_update_lobby_buttons()

func _on_lobby_exited() -> void:
	_in_lobby = false
	_is_ready = false
	_main_panel.visible = true
	_lobby_panel.visible = false
	if is_instance_valid(_friends_dialog):
		_friends_dialog.hide()

func _on_lobby_members_changed() -> void:
	_update_member_list()
	_update_lobby_buttons()

func _on_avatar_ready(member: int, texture: ImageTexture) -> void:
	var icon := _member_avatars.get(member) as TextureRect
	if is_instance_valid(icon):
		icon.texture = texture

func _update_member_list() -> void:
	_member_avatars.clear()
	for child: Node in _member_list.get_children():
		child.queue_free()
	if not _steam_available() or SteamManager.lobby_id == 0:
		return
	var member_ids := SteamManager.members()
	for member_id: int in member_ids:
		var mname := SteamManager.member_name(member_id)
		var ready := SteamManager.is_member_ready(member_id)
		var is_host_member := member_id == SteamManager.host_steam_id()
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(420.0, 36.0)
		_member_list.add_child(row)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		_member_avatars[member_id] = icon
		icon.texture = SteamManager.request_avatar(member_id)
		var name_label := Label.new()
		var prefix := "★ " if is_host_member else "  "
		name_label.text = "%s%s" % [prefix, mname]
		name_label.custom_minimum_size = Vector2(300.0, 32.0)
		row.add_child(name_label)
		var status_label := Label.new()
		status_label.text = "ГОТОВ" if ready else "—"
		status_label.modulate = Color(0.3, 1.0, 0.4) if ready else Color(0.55, 0.55, 0.55)
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		status_label.custom_minimum_size = Vector2(100.0, 32.0)
		row.add_child(status_label)

func _update_lobby_buttons() -> void:
	if not _steam_available():
		return
	var host := SteamManager.is_host()
	_is_ready = SteamManager.is_member_ready(SteamManager.steam_id)
	_lobby_start_button.visible = host
	_lobby_map_button.visible = host
	if host:
		_lobby_start_button.disabled = not SteamManager.everyone_ready()
	_lobby_ready_button.text = "НЕ ГОТОВ" if _is_ready else "ГОТОВ"

func _invite_friend() -> void:
	if _steam_available() and not SteamManager.invite_friend():
		_show_friends()

func _show_friends() -> void:
	if not _steam_available() or SteamManager.lobby_id == 0:
		return
	if is_instance_valid(_friends_dialog):
		_friends_dialog.queue_free()
	_friends_dialog = AcceptDialog.new()
	_friends_dialog.title = "ПРИГЛАСИТЬ ДРУГА"
	_friends_dialog.ok_button_text = "ЗАКРЫТЬ"
	add_child(_friends_dialog)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 320)
	_friends_dialog.add_child(scroll)
	var list := VBoxContainer.new()
	scroll.add_child(list)
	var friends := SteamManager.friends()
	if friends.is_empty():
		var empty := Label.new()
		empty.text = "Список друзей Steam пуст"
		list.add_child(empty)
	for friend_id: int in friends:
		var button := _add_button(list, SteamManager.member_name(friend_id), func() -> void:
			SteamManager.invite_user(friend_id))
		button.tooltip_text = "Отправить приглашение Steam"
	_friends_dialog.popup_centered()

func _toggle_ready() -> void:
	if not _steam_available():
		return
	_is_ready = not _is_ready
	SteamManager.set_ready(_is_ready)
	_lobby_ready_button.text = "НЕ ГОТОВ" if _is_ready else "ГОТОВ"

func _cycle_lobby_map() -> void:
	_lobby_map_index = (_lobby_map_index + 1) % MAPS.size()
	_refresh_lobby_map_button()

func _refresh_lobby_map_button() -> void:
	if _lobby_map_button != null:
		_lobby_map_button.text = "КАРТА: %s" % (MAPS[_lobby_map_index][0] as String)

func _start_match() -> void:
	if not _steam_available() or not SteamManager.is_host():
		return
	if not SteamManager.everyone_ready():
		return
	var selected_map: String = MAPS[_lobby_map_index][1] as String
	NetworkGame.host_match(selected_map)

func _leave_lobby() -> void:
	if _steam_available():
		SteamManager.leave_lobby()
	_on_lobby_exited()

# --- Panorama background --------------------------------------------------

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
	var preview_environment := level.get_node_or_null("PhotorealEnvironment") as PhotorealEnvironment
	if preview_environment != null:
		preview_environment.enable_auto_exposure = false
	var scan := level.get_node_or_null("Scan")
	if scan != null:
		scan.set("build_collision", false)
	viewport.add_child(level)
	_panorama_camera = Camera3D.new()
	_panorama_camera.name = "PanoramaCamera"
	_panorama_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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

# --- Input ----------------------------------------------------------------

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

# --- Shared button factory ------------------------------------------------

func _add_button(parent: VBoxContainer, label_text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(420.0, 48.0)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

# --- Graphics and weather cycling -----------------------------------------

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
