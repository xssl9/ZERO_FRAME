class_name PlayerController
extends CharacterBody3D

const WALK_SPEED: float = 4.2
const SPRINT_SPEED: float = 7.0
const CROUCH_SPEED: float = 2.2
const GRAVITY: float = 20.0
# Strides overlap at a run, so one player would clip its own tail every step.
const FOOTSTEP_VOICE_COUNT: int = 4
# Six strides cut out of one recorded run cycle. Picking one at random per step is what
# keeps a sprint from turning into the same slap repeated twice a second.
const FOOTSTEP_VARIANT_COUNT: int = 6
# Six seconds of unbroken sprinting before the player audibly starts breathing hard, and
# it happens while still running rather than after stopping.
const BREATH_SPRINT_SECONDS: float = 6.0
const BREATH_EXERTION_CAP: float = 26.0
const BREATH_VARIANT_COUNT: int = 5
# Leaning out from cover. The head only goes as far as there is room for it, checked against
# the world every physics tick, so you cannot lean through a wall to see round it.
const LEAN_CLEARANCE: float = 0.62

var camera: Camera3D
var weapon_camera: Camera3D
var weapon_environment: WorldEnvironment
var weapon_key_light: DirectionalLight3D
var bodycam: Node3D
var weapon_manager: WeaponManager
var viewmodel_pivot: Node3D
var weapon_aim_pivot: Node3D
var hud_ammo: Label
var hud_status: Label
var hud_stamp: Label
var hud_rec: Label
var health: float = 100.0
var flashlight: SpotLight3D
var base_bodycam_position: Vector3 = Vector3(0.16, 1.5, 0.02)
var spawn_position: Vector3 = Vector3.ZERO
var spawn_transform: Transform3D = Transform3D.IDENTITY

var _footstep_voices: Array[AudioStreamPlayer] = []
var _footstep_streams: Array[AudioStream] = []
var _footstep_voice_index: int = 0
var _last_footstep_variant: int = -1
var _land_audio: AudioStreamPlayer
var _breath_audio: AudioStreamPlayer
var _breath_streams: Array[AudioStream] = []
var _last_breath_variant: int = -1
var _sprint_exertion: float = 0.0
var _breath_timer: float = 0.0
var _level_environment: PhotorealEnvironment
var _level_sun: DirectionalLight3D
var _viewmodel_rain: GPUParticles3D
var _overlay_clock: float = 0.0
var _stamp_updated: float = -1.0
var _stride_distance: float = 0.0
var _was_on_floor: bool = true

func _ready() -> void:
	add_to_group("player")
	_apply_authored_spawn_point()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if get_node_or_null("BodycamRig/WorldCamera") != null:
		_bind_scene_body()
	else:
		_build_body()
	_configure_runtime_body()
	# Built here rather than in _build_body so the authored player.tscn gets the
	# movement audio too: the scene file has no audio nodes at all.
	_build_movement_audio()
	# Deferred: the level's environment resolves its weather in a deferred pass of its own,
	# and the viewmodel grade is copied from the result.
	call_deferred("_bind_level_lighting")

func _build_movement_audio() -> void:
	# Non-positional on purpose. The shooter's own boots are at the listener, and a
	# positional player would be at the mercy of whichever camera is current.
	for index: int in FOOTSTEP_VARIANT_COUNT:
		var step_stream := load("res://assets/audio/footsteps/run_0%d.ogg" % (index + 1)) as AudioStream
		if step_stream != null:
			_footstep_streams.append(step_stream)
	if _footstep_streams.is_empty():
		# The old single concrete sample is still a valid fallback if the run cycle
		# assets are ever missing.
		var fallback := load("res://assets/audio/footsteps/concrete.ogg") as AudioStream
		if fallback != null:
			_footstep_streams.append(fallback)
	if not _footstep_streams.is_empty():
		for index: int in FOOTSTEP_VOICE_COUNT:
			var voice := AudioStreamPlayer.new()
			voice.name = "FootstepVoice%d" % index
			voice.stream = _footstep_streams[0]
			add_child(voice)
			_footstep_voices.append(voice)
	# land.ogg averages -36 dBFS, so it is inaudible without a large lift.
	var land_stream := load("res://assets/audio/land.ogg") as AudioStream
	if land_stream != null:
		_land_audio = AudioStreamPlayer.new()
		_land_audio.name = "LandAudio"
		_land_audio.stream = land_stream
		_land_audio.volume_db = 16.0
		add_child(_land_audio)
	# Breathing while sprinting. Five separate breaths cut out of the one recording, so a
	# long run does not turn into the same sample looping.
	for index: int in BREATH_VARIANT_COUNT:
		var breath_stream := load("res://assets/audio/player/breath_0%d.ogg" % (index + 1)) as AudioStream
		if breath_stream != null:
			_breath_streams.append(breath_stream)
	if not _breath_streams.is_empty():
		_breath_audio = AudioStreamPlayer.new()
		_breath_audio.name = "BreathAudio"
		_breath_audio.stream = _breath_streams[0]
		add_child(_breath_audio)

func _apply_authored_spawn_point() -> void:
	var spawn_point := get_parent().get_node_or_null("SpawnPoint3D") as Marker3D
	if spawn_point == null:
		spawn_point = get_parent().get_node_or_null("PlayerSpawn") as Marker3D
	if spawn_point == null:
		spawn_point = get_tree().get_first_node_in_group("player_spawn_point") as Marker3D
	if spawn_point != null:
		# Position and yaw only. A spawn marker that was tilted or scaled while dragging it
		# around the editor must not tilt the character body or resize its collider.
		global_transform = Transform3D(Basis(Vector3.UP, spawn_point.global_rotation.y), spawn_point.global_position)
		reset_physics_interpolation()
	spawn_transform = global_transform
	spawn_position = spawn_transform.origin

func _bind_scene_body() -> void:
	bodycam = get_node("BodycamRig") as Node3D
	camera = get_node("BodycamRig/WorldCamera") as Camera3D
	flashlight = get_node("BodycamRig/WorldCamera/Flashlight") as SpotLight3D
	weapon_camera = get_node("WeaponLayer/WeaponViewportContainer/WeaponViewport/WeaponCamera") as Camera3D
	weapon_environment = get_node_or_null("WeaponLayer/WeaponViewportContainer/WeaponViewport/WeaponEnvironment") as WorldEnvironment
	weapon_key_light = get_node_or_null("WeaponLayer/WeaponViewportContainer/WeaponViewport/WeaponKeyLight") as DirectionalLight3D
	weapon_aim_pivot = weapon_camera.get_node("WeaponAimPivot") as Node3D
	viewmodel_pivot = weapon_aim_pivot.get_node("ViewModelPivot") as Node3D
	weapon_manager = viewmodel_pivot.get_node("WeaponManager") as WeaponManager
	hud_ammo = get_node("HUD/Ammo") as Label
	hud_status = get_node("HUD/Status") as Label
	hud_stamp = get_node_or_null("HUD/StampTime") as Label
	hud_rec = get_node_or_null("HUD/Rec") as Label

func _configure_runtime_body() -> void:
	weapon_manager.configure_weapon_collision(self, camera)
	var physics_camera := camera as BodycamPhysics
	physics_camera.configure(self, weapon_aim_pivot)
	_sync_weapon_camera_profile()

func _build_body() -> void:
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.75
	collider.shape = capsule
	collider.position.y = 0.9
	add_child(collider)
	bodycam = Node3D.new()
	bodycam.name = "BodycamRig"
	bodycam.position = Vector3(0.18, 1.58, 0.0)
	add_child(bodycam)
	camera = Camera3D.new()
	camera.set_script(load("res://scripts/player/bodycam_physics.gd"))
	camera.fov = float(ProjectSettings.get_setting("zero_frame/fov", 96.0))
	camera.current = true
	bodycam.add_child(camera)
	flashlight = SpotLight3D.new()
	flashlight.light_energy = 7.0
	# The beam itself has to show up in the volumetric fog, not just the pool of light
	# it throws on a wall.
	flashlight.light_volumetric_fog_energy = 2.6
	flashlight.spot_range = 24.0
	flashlight.spot_angle = 30.0
	flashlight.visible = false
	camera.add_child(flashlight)
	_build_weapon_viewport()
	_build_hud()
	_build_bodycam_overlay()

func _build_weapon_viewport() -> void:
	# The viewmodel is rendered by its OWN camera in a SubViewport with an isolated
	# World3D, then composited over the world view. This is why the gun no longer
	# renders from the player camera: it has a dedicated weapon camera. Isolation
	# also means the weapon can never clip into level geometry.
	var weapon_layer := CanvasLayer.new()
	weapon_layer.name = "WeaponLayer"
	weapon_layer.layer = 1
	add_child(weapon_layer)
	var container := SubViewportContainer.new()
	container.name = "WeaponViewportContainer"
	container.stretch = true
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_layer.add_child(container)
	var weapon_viewport := SubViewport.new()
	weapon_viewport.name = "WeaponViewport"
	weapon_viewport.own_world_3d = true
	weapon_viewport.transparent_bg = true
	weapon_viewport.handle_input_locally = false
	weapon_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	weapon_viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(weapon_viewport)
	weapon_camera = Camera3D.new()
	weapon_camera.name = "WeaponCamera"
	# Match the world camera FOV so the authored viewmodel framing is preserved.
	weapon_camera.fov = camera.fov
	weapon_camera.near = 0.01
	weapon_camera.far = 20.0
	weapon_camera.current = true
	weapon_viewport.add_child(weapon_camera)
	# Dedicated lighting + AgX so the gun reads consistently over any background.
	var weapon_world_env := WorldEnvironment.new()
	var weapon_env := Environment.new()
	weapon_env.background_mode = Environment.BG_CLEAR_COLOR
	weapon_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	weapon_env.ambient_light_color = Color(0.74, 0.76, 0.8)
	weapon_env.ambient_light_energy = 1.1
	weapon_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	weapon_env.tonemap_exposure = 0.9
	# Glow only above the tonemapper's white point, so the muzzle flash blooms while the
	# gun itself stays clean.
	weapon_env.glow_enabled = true
	weapon_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	weapon_env.glow_intensity = 0.45
	weapon_env.glow_bloom = 0.04
	weapon_env.glow_hdr_threshold = 1.35
	weapon_world_env.environment = weapon_env
	weapon_viewport.add_child(weapon_world_env)
	var weapon_key := DirectionalLight3D.new()
	weapon_key.name = "WeaponKeyLight"
	weapon_key.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	weapon_key.light_energy = 1.5
	weapon_key.light_color = Color("fff2df")
	weapon_viewport.add_child(weapon_key)
	weapon_aim_pivot = Node3D.new()
	weapon_aim_pivot.name = "WeaponAimPivot"
	weapon_camera.add_child(weapon_aim_pivot)
	viewmodel_pivot = Node3D.new()
	viewmodel_pivot.name = "ViewModelPivot"
	weapon_aim_pivot.add_child(viewmodel_pivot)
	weapon_manager = WeaponManager.new()
	weapon_manager.top_level = false
	viewmodel_pivot.add_child(weapon_manager)

func _process(delta: float) -> void:
	_sync_weapon_camera_profile()
	_update_viewmodel_lighting()
	_update_overlay(delta)

# The burnt-in camera stamp. Nothing here is a game HUD element: a real body camera writes a
# wordmark, a record indicator, a battery readout and a wall-clock timestamp, and that is all
# it writes.
func _update_overlay(delta: float) -> void:
	_overlay_clock += delta
	if hud_rec != null:
		# Units blink the record dot about once a second.
		hud_rec.modulate.a = 0.85 if fmod(_overlay_clock, 1.2) < 0.75 else 0.22
	if hud_stamp == null or _overlay_clock - _stamp_updated < 0.5:
		return
	_stamp_updated = _overlay_clock
	var now := Time.get_datetime_dict_from_system()
	var bias: int = int(Time.get_time_zone_from_system()["bias"])
	hud_stamp.text = "%04d-%02d-%02d %02d:%02d:%02d %s%02d%02d" % [
		int(now["year"]), int(now["month"]), int(now["day"]),
		int(now["hour"]), int(now["minute"]), int(now["second"]),
		"+" if bias >= 0 else "-", absi(bias) / 60, absi(bias) % 60]

# The viewmodel is rendered by its own camera in its own World3D, so nothing about the
# level reaches it on its own: no sun, no sky, no weather. Everything the hands and the
# gun know about the world outside is copied across here.
func _bind_level_lighting() -> void:
	_level_environment = get_tree().get_first_node_in_group("photoreal_environment") as PhotorealEnvironment
	var host := get_parent()
	if host != null:
		_level_sun = host.get_node_or_null("PhysicalSun") as DirectionalLight3D
	_apply_viewmodel_grade()
	_build_viewmodel_rain()

func _apply_viewmodel_grade() -> void:
	if weapon_environment == null or weapon_environment.environment == null or _level_environment == null:
		return
	var raining := _level_environment.is_raining()
	var environment := weapon_environment.environment
	# Scaled up because the level's ambient is a sky multiplier while this one is a flat
	# colour, and clamped so a dark level never leaves the hands as a silhouette.
	environment.ambient_light_energy = clampf(_level_environment.ambient_energy_in_effect() * 1.5, 0.7, 2.4)
	environment.ambient_light_color = Color(0.7, 0.76, 0.9) if raining else Color(0.82, 0.83, 0.86)
	environment.tonemap_exposure = clampf(_level_environment.exposure_in_effect() * 1.35, 0.4, 1.6)

func _update_viewmodel_lighting() -> void:
	if weapon_key_light == null or _level_sun == null or camera == null:
		return
	# Camera space: the sun has to be re-expressed relative to where the player is looking,
	# otherwise the gun stays lit from one fixed side no matter which way you turn.
	var relative := camera.global_transform.basis.inverse() * _level_sun.global_transform.basis
	weapon_key_light.transform = Transform3D(relative, Vector3.ZERO)
	weapon_key_light.light_color = _level_sun.light_color
	weapon_key_light.light_energy = clampf(_level_sun.light_energy * 0.45, 0.15, 2.2)
	if _viewmodel_rain != null:
		var down: Vector3 = camera.global_transform.basis.inverse() * Vector3.DOWN
		var process := _viewmodel_rain.process_material as ParticleProcessMaterial
		process.direction = down
		process.gravity = down * 6.0

# A thin curtain of drops inside the weapon viewport, so rain falls past the hands instead
# of stopping at an invisible line in front of the camera.
func _build_viewmodel_rain() -> void:
	if _level_environment == null or not _level_environment.is_raining() or weapon_camera == null:
		return
	_viewmodel_rain = GPUParticles3D.new()
	_viewmodel_rain.name = "ViewmodelRain"
	_viewmodel_rain.amount = 90
	_viewmodel_rain.lifetime = 0.55
	_viewmodel_rain.preprocess = 0.55
	_viewmodel_rain.local_coords = true
	_viewmodel_rain.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	_viewmodel_rain.position = Vector3(0.0, 0.35, -0.9)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.9, 0.35, 0.7)
	process.direction = Vector3(0.0, -1.0, 0.0)
	process.spread = 0.0
	process.initial_velocity_min = 5.0
	process.initial_velocity_max = 7.5
	process.gravity = Vector3(0.0, -6.0, 0.0)
	process.scale_min = 0.7
	process.scale_max = 1.2
	_viewmodel_rain.process_material = process
	var drop := QuadMesh.new()
	drop.size = Vector2(0.004, 0.11)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.billboard_keep_scale = true
	material.albedo_color = Color(0.7, 0.76, 0.84, 0.5)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	drop.material = material
	_viewmodel_rain.draw_pass_1 = drop
	weapon_camera.add_child(_viewmodel_rain)

func _sync_weapon_camera_profile() -> void:
	if weapon_camera == null or weapon_manager == null:
		return
	var authored_camera := weapon_manager.get_active_authored_camera()
	# WeaponTuningCamera from the active weapon scene is the authoritative
	# renderer. The old player camera remains only as a safe import fallback.
	weapon_camera.current = authored_camera == null
	if authored_camera != null:
		authored_camera.current = true

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	# Above the bodycam lens at 90: the lens distorts everything drawn under it, which is
	# what used to eat the ammo counter at the edge of the frame.
	layer.layer = 100
	add_child(layer)
	hud_stamp = _build_hud_label(layer, Control.PRESET_TOP_RIGHT, Vector2(-330.0, 16.0), Vector2(-26.0, 38.0))
	hud_stamp.add_theme_font_size_override("font_size", 14)
	hud_stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud_stamp.modulate = Color(1.0, 1.0, 1.0, 0.78)
	var serial := _build_hud_label(layer, Control.PRESET_TOP_RIGHT, Vector2(-330.0, 39.0), Vector2(-26.0, 58.0))
	serial.text = "AXON BODY 3 X07108B133"
	serial.add_theme_font_size_override("font_size", 12)
	serial.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	serial.modulate = Color(1.0, 1.0, 1.0, 0.6)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/textures/hud/axon_logo.png") as Texture2D
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.modulate = Color(1.0, 1.0, 1.0, 0.85)
	layer.add_child(logo)
	logo.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	logo.offset_left = -204.0
	logo.offset_top = 40.0
	logo.offset_right = -186.0
	logo.offset_bottom = 57.0
	hud_rec = _build_hud_label(layer, Control.PRESET_TOP_LEFT, Vector2(26.0, 16.0), Vector2(160.0, 40.0))
	hud_rec.text = "● REC"
	hud_rec.add_theme_font_size_override("font_size", 15)
	hud_rec.modulate = Color(0.88, 0.24, 0.2, 0.85)
	hud_ammo = _build_hud_label(layer, Control.PRESET_BOTTOM_RIGHT, Vector2(-320.0, -40.0), Vector2(-26.0, -16.0))
	hud_ammo.add_theme_font_size_override("font_size", 15)
	hud_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud_ammo.modulate = Color(1.0, 1.0, 1.0, 0.66)
	hud_status = _build_hud_label(layer, Control.PRESET_BOTTOM_RIGHT, Vector2(-320.0, -62.0), Vector2(-26.0, -40.0))
	hud_status.add_theme_font_size_override("font_size", 12)
	hud_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud_status.modulate = Color(1.0, 0.92, 0.78, 0.5)

# Anchored, not placed: the overlay has to land inside the window at any resolution.
func _build_hud_label(layer: CanvasLayer, preset: Control.LayoutPreset, top_left: Vector2, bottom_right: Vector2) -> Label:
	var label := Label.new()
	layer.add_child(label)
	label.set_anchors_preset(preset)
	label.offset_left = top_left.x
	label.offset_top = top_left.y
	label.offset_right = bottom_right.x
	label.offset_bottom = bottom_right.y
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _build_bodycam_overlay() -> void:
	var overlay_layer := CanvasLayer.new()
	overlay_layer.layer = 90
	add_child(overlay_layer)
	var overlay := ColorRect.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/bodycam.gdshader") as Shader
	overlay.material = material
	overlay_layer.add_child(overlay)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		weapon_manager.add_look_impulse(motion.relative)
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	if event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := WALK_SPEED
	if Input.is_action_pressed("sprint") and input.y < 0.0:
		speed = SPRINT_SPEED
	elif Input.is_action_pressed("crouch"):
		speed = CROUCH_SPEED
	velocity.x = move_toward(velocity.x, direction.x * speed, 24.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 24.0 * delta)
	move_and_slide()
	_update_lean(delta)
	_update_movement_audio(delta, speed)
	_update_bodycam(delta)
	hud_ammo.text = weapon_manager.get_hud_text()
	hud_status.text = weapon_manager.get_status_text()

func _update_lean(_delta: float) -> void:
	var physics_camera := camera as BodycamPhysics
	if physics_camera == null:
		return
	var wanted := 0.0
	if Input.is_action_pressed("lean_left"):
		wanted -= 1.0
	if Input.is_action_pressed("lean_right"):
		wanted += 1.0
	# Sprinting with the rifle up and your head out of cover is not a thing.
	if Input.is_action_pressed("sprint") and Vector2(velocity.x, velocity.z).length() > SPRINT_SPEED * 0.6:
		wanted = 0.0
	if not is_zero_approx(wanted):
		var head := camera.global_position
		var side := camera.global_transform.basis.x * signf(wanted)
		var query := PhysicsRayQueryParameters3D.create(head, head + side * LEAN_CLEARANCE)
		query.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			wanted = 0.0
	physics_camera.set_lean_target(wanted)
	if weapon_manager != null:
		weapon_manager.set_lean(physics_camera.lean_amount())

func _update_movement_audio(delta: float, speed: float) -> void:
	var grounded := is_on_floor()
	if grounded and not _was_on_floor and _land_audio != null:
		_land_audio.pitch_scale = randf_range(0.94, 1.06)
		_land_audio.play()
	_was_on_floor = grounded
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var sprinting: bool = is_equal_approx(speed, SPRINT_SPEED) and horizontal_speed > SPRINT_SPEED * 0.6
	# Breathing is tracked even in the air, so a sprint that ends in a fall still pays
	# its debt when the player lands.
	_update_breathing(delta, sprinting)
	if not grounded or _footstep_voices.is_empty():
		return
	if horizontal_speed < 0.45:
		# Standing still must not keep a partial stride banked, or the next step
		# would fire the instant the player twitches.
		_stride_distance = 0.0
		return
	# Distance-based instead of time-based: the cadence then follows the actual
	# speed, and crouch-walking does not sound like a sprint in slow motion.
	_stride_distance += horizontal_speed * delta
	var stride_length: float = 1.62
	var volume: float = -5.0
	# One recorded run cycle covers every gait: sprint plays it flat out, walking is
	# pitched down and softened, crouching is barely there.
	var pitch_low: float = 0.95
	var pitch_high: float = 1.05
	if sprinting:
		stride_length = 2.05
		volume = 0.0
	elif is_equal_approx(speed, CROUCH_SPEED):
		stride_length = 1.05
		volume = -16.0
		pitch_low = 0.82
		pitch_high = 0.92
	else:
		pitch_low = 0.88
		pitch_high = 0.98
	if _stride_distance < stride_length:
		return
	_stride_distance -= stride_length
	var voice := _footstep_voices[_footstep_voice_index]
	_footstep_voice_index = (_footstep_voice_index + 1) % _footstep_voices.size()
	voice.stream = _next_footstep_stream()
	voice.volume_db = volume
	voice.pitch_scale = randf_range(pitch_low, pitch_high)
	voice.play()

# Never the same stride twice in a row: a repeat is the one thing the ear catches.
func _next_footstep_stream() -> AudioStream:
	if _footstep_streams.size() == 1:
		return _footstep_streams[0]
	var variant: int = randi() % _footstep_streams.size()
	if variant == _last_footstep_variant:
		variant = (variant + 1) % _footstep_streams.size()
	_last_footstep_variant = variant
	return _footstep_streams[variant]

func _update_breathing(delta: float, sprinting: bool) -> void:
	if _breath_audio == null:
		return
	if not sprinting:
		# The exertion clock drains as soon as the player slows down, so ten seconds of
		# running has to be earned again instead of banked. A breath already playing is
		# left alone to finish on its own.
		_sprint_exertion = maxf(_sprint_exertion - delta * 1.5, 0.0)
		return
	_sprint_exertion = minf(_sprint_exertion + delta, BREATH_EXERTION_CAP)
	if _sprint_exertion < BREATH_SPRINT_SECONDS:
		return
	_breath_timer = maxf(_breath_timer - delta, 0.0)
	if _breath_timer > 0.0:
		return
	_breath_audio.stream = _next_breath_stream()
	# The gap is measured from the end of the clip rather than from AudioStreamPlayer.playing,
	# so the cadence is the same whatever the audio driver reports.
	_breath_timer = _breath_audio.stream.get_length() + randf_range(0.9, 2.1)
	# Deliberately at the floor of the mix: this is the shooter's own breathing behind
	# the footsteps and the gun, not a foreground effect.
	_breath_audio.volume_db = randf_range(-25.0, -21.0)
	_breath_audio.pitch_scale = randf_range(0.93, 1.09)
	_breath_audio.play()

func _next_breath_stream() -> AudioStream:
	if _breath_streams.size() == 1:
		return _breath_streams[0]
	var variant: int = randi() % _breath_streams.size()
	if variant == _last_breath_variant:
		variant = (variant + 1) % _breath_streams.size()
	_last_breath_variant = variant
	return _breath_streams[variant]

func _update_bodycam(delta: float) -> void:
	bodycam.position = base_bodycam_position
	# Pitch lives on this rig; all gait/strafe roll is owned by BodycamPhysics so
	# two independent roll layers cannot fight and create high-frequency shake.
	bodycam.rotation.z = lerpf(bodycam.rotation.z, 0.0, 1.0 - exp(-delta * 16.0))

func add_camera_impulse(pitch_impulse: float, yaw_impulse: float, roll_impulse: float = 0.0) -> void:
	var physics_camera := camera as BodycamPhysics
	physics_camera.add_trauma(Vector3(yaw_impulse, pitch_impulse, roll_impulse), clampf(absf(pitch_impulse) + absf(yaw_impulse) + absf(roll_impulse), 0.0, 1.0))

# Weapons call this instead of add_camera_impulse: recoil moves the real aim, not
# only the visual camera, so the burst has to be pulled back down by hand.
func apply_weapon_recoil(pitch_degrees: float, yaw_degrees: float) -> void:
	var physics_camera := camera as BodycamPhysics
	if physics_camera == null:
		return
	physics_camera.add_recoil(pitch_degrees, yaw_degrees)

func apply_damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		global_transform = spawn_transform
		reset_physics_interpolation()
		velocity = Vector3.ZERO
		health = 100.0
