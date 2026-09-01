class_name PlayerController
extends CharacterBody3D

const WALK_SPEED: float = 4.2
const SPRINT_SPEED: float = 7.0
const CROUCH_SPEED: float = 2.2
const GRAVITY: float = 20.0

var camera: Camera3D
var weapon_camera: Camera3D
var bodycam: Node3D
var weapon_manager: WeaponManager
var viewmodel_pivot: Node3D
var weapon_aim_pivot: Node3D
var hud_ammo: Label
var hud_status: Label
var health: float = 100.0
var flashlight: SpotLight3D
var base_bodycam_position: Vector3 = Vector3(0.16, 1.5, 0.02)
var spawn_position: Vector3 = Vector3.ZERO
var spawn_transform: Transform3D = Transform3D.IDENTITY

func _ready() -> void:
	add_to_group("player")
	_apply_authored_spawn_point()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if get_node_or_null("BodycamRig/WorldCamera") != null:
		_bind_scene_body()
	else:
		_build_body()
	_configure_runtime_body()

func _apply_authored_spawn_point() -> void:
	var spawn_point := get_parent().get_node_or_null("SpawnPoint3D") as Marker3D
	if spawn_point == null:
		spawn_point = get_parent().get_node_or_null("PlayerSpawn") as Marker3D
	if spawn_point == null:
		spawn_point = get_tree().get_first_node_in_group("player_spawn_point") as Marker3D
	if spawn_point != null:
		global_transform = spawn_point.global_transform
		reset_physics_interpolation()
	spawn_transform = global_transform
	spawn_position = spawn_transform.origin

func _bind_scene_body() -> void:
	bodycam = get_node("BodycamRig") as Node3D
	camera = get_node("BodycamRig/WorldCamera") as Camera3D
	flashlight = get_node("BodycamRig/WorldCamera/Flashlight") as SpotLight3D
	weapon_camera = get_node("WeaponLayer/WeaponViewportContainer/WeaponViewport/WeaponCamera") as Camera3D
	weapon_aim_pivot = weapon_camera.get_node("WeaponAimPivot") as Node3D
	viewmodel_pivot = weapon_aim_pivot.get_node("ViewModelPivot") as Node3D
	weapon_manager = viewmodel_pivot.get_node("WeaponManager") as WeaponManager
	hud_ammo = get_node("HUD/Ammo") as Label
	hud_status = get_node("HUD/Status") as Label
	var rec := get_node_or_null("BodycamOverlay/REC") as Label
	if rec != null:
		var time := Time.get_time_dict_from_system()
		rec.text = "● REC   ZERO FRAME   %02d:%02d" % [int(time["hour"]), int(time["minute"])]

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

func _process(_delta: float) -> void:
	_sync_weapon_camera_profile()

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
	add_child(layer)
	hud_ammo = Label.new()
	hud_ammo.position = Vector2(1040.0, 635.0)
	hud_ammo.add_theme_font_size_override("font_size", 25)
	layer.add_child(hud_ammo)
	hud_status = Label.new()
	hud_status.position = Vector2(520.0, 610.0)
	hud_status.modulate = Color("d6b875")
	layer.add_child(hud_status)
	var controls := Label.new()
	controls.text = "WASD движение  •  Shift бег  •  ПКМ прицел  •  R перезарядка  •  1/2 оружие  •  F фонарь  •  Esc меню"
	controls.position = Vector2(22.0, 685.0)
	controls.modulate = Color(0.65, 0.72, 0.74, 0.75)
	layer.add_child(controls)

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
	var rec := Label.new()
	var time := Time.get_time_dict_from_system()
	rec.text = "● REC   ZERO FRAME   %02d:%02d" % [int(time["hour"]), int(time["minute"])]
	rec.position = Vector2(28.0, 22.0)
	rec.modulate = Color(0.85, 0.22, 0.18, 0.78)
	overlay_layer.add_child(rec)

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
	_update_bodycam(delta)
	hud_ammo.text = weapon_manager.get_hud_text()
	hud_status.text = weapon_manager.get_status_text()

func _update_bodycam(delta: float) -> void:
	bodycam.position = base_bodycam_position
	# Pitch lives on this rig; all gait/strafe roll is owned by BodycamPhysics so
	# two independent roll layers cannot fight and create high-frequency shake.
	bodycam.rotation.z = lerpf(bodycam.rotation.z, 0.0, 1.0 - exp(-delta * 16.0))

func add_camera_impulse(pitch_impulse: float, yaw_impulse: float, roll_impulse: float = 0.0) -> void:
	var physics_camera := camera as BodycamPhysics
	physics_camera.add_trauma(Vector3(yaw_impulse, pitch_impulse, roll_impulse), clampf(absf(pitch_impulse) + absf(yaw_impulse) + absf(roll_impulse), 0.0, 1.0))

func apply_damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		global_transform = spawn_transform
		reset_physics_interpolation()
		velocity = Vector3.ZERO
		health = 100.0
