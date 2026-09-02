extends SceneTree

## Stages a single round in the dev test grid and saves the frame while the muzzle flash
## is still burning, so the flash, its lights and the volumetric shafts can be reviewed
## without playing the game.
##
## Needs a real GPU context, so run it WITHOUT --headless:
##   godot --script res://scripts/tools/muzzle_flash_capture.gd -- \
##       --output=/tmp/flash.png --weapon=0 --delay-frames=1 --yaw=0

const SCENE_PATH := "res://scenes/levels/dev_test_grid.tscn"

func _initialize() -> void:
	call_deferred("_run")

func _apply_lighting_overrides(level: Node, sun_energy: float, ambient_energy: float, exposure: float, shafts: float, sky_yaw: float) -> void:
	var environment_node := level.get_node_or_null("PhotorealEnvironment")
	var sun := level.get_node_or_null("PhysicalSun") as DirectionalLight3D
	if sun != null and sun_energy > 0.0:
		sun.light_energy = sun_energy
	if environment_node == null:
		return
	if ambient_energy >= 0.0:
		environment_node.set("ambient_energy", ambient_energy)
	if exposure > 0.0:
		environment_node.set("exposure_multiplier", exposure)
	if shafts >= 0.0:
		environment_node.set("shaft_density", shafts)
	if not is_zero_approx(sky_yaw):
		environment_node.set("sky_rotation_degrees", sky_yaw)
		if sun != null:
			sun.basis = Basis(Vector3.UP, deg_to_rad(sky_yaw)) * sun.basis
	environment_node.call("apply_preset")
	print("LIGHTING sun=", sun.light_energy if sun != null else -1.0,
		" ambient=", environment_node.get("ambient_energy"),
		" exposure=", environment_node.get("exposure_multiplier"),
		" shafts=", environment_node.get("shaft_density"),
		" sky_yaw=", sky_yaw)

func _run() -> void:
	var scene_path := SCENE_PATH
	var output_path := "/tmp/zero_frame_flash.png"
	var weapon_index := 0
	var delay_frames := 1
	var settle_frames := 150
	var yaw_degrees := 0.0
	var pitch_degrees := 0.0
	var idle_only := false
	var override_position := Vector3.INF
	# Lighting overrides, so exposure and sun/sky placement can be bracketed without
	# editing the level between runs. Negative means "leave the authored value alone".
	var sun_energy := -1.0
	var ambient_energy := -1.0
	var exposure := -1.0
	var shafts := -1.0
	# Rotates the sky AND the sun by the same angle, so the alignment between the visible
	# solar disc and the shadows survives a composition change.
	var sky_yaw := 0.0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="):
			scene_path = argument.trim_prefix("--scene=")
		elif argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--weapon="):
			weapon_index = argument.trim_prefix("--weapon=").to_int()
		elif argument.begins_with("--delay-frames="):
			delay_frames = argument.trim_prefix("--delay-frames=").to_int()
		elif argument.begins_with("--settle-frames="):
			settle_frames = argument.trim_prefix("--settle-frames=").to_int()
		elif argument.begins_with("--yaw="):
			yaw_degrees = argument.trim_prefix("--yaw=").to_float()
		elif argument.begins_with("--pitch="):
			pitch_degrees = argument.trim_prefix("--pitch=").to_float()
		elif argument.begins_with("--position="):
			var parts := argument.trim_prefix("--position=").split(",")
			if parts.size() == 3:
				override_position = Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
		elif argument == "--no-shot":
			idle_only = true
		elif argument.begins_with("--sun="):
			sun_energy = argument.trim_prefix("--sun=").to_float()
		elif argument.begins_with("--ambient="):
			ambient_energy = argument.trim_prefix("--ambient=").to_float()
		elif argument.begins_with("--exposure="):
			exposure = argument.trim_prefix("--exposure=").to_float()
		elif argument.begins_with("--shafts="):
			shafts = argument.trim_prefix("--shafts=").to_float()
		elif argument.begins_with("--sky-yaw="):
			sky_yaw = argument.trim_prefix("--sky-yaw=").to_float()
		elif argument.begins_with("--preset="):
			var names := {"auto": 0, "performance": 1, "high": 2, "ultra": 3}
			var wanted: String = argument.trim_prefix("--preset=")
			if names.has(wanted):
				ProjectSettings.set_setting("zero_frame/graphics_quality", names[wanted])
		elif argument == "--weather=clear":
			ProjectSettings.set_setting("zero_frame/weather", 0)
		elif argument == "--weather=rain":
			ProjectSettings.set_setting("zero_frame/weather", 1)
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("FLASH_CAPTURE_LOAD_FAILED " + scene_path)
		quit(1)
		return
	root.content_scale_size = Vector2i(1280, 720)
	var level := packed.instantiate()
	root.add_child(level)
	_apply_lighting_overrides(level, sun_energy, ambient_energy, exposure, shafts, sky_yaw)
	# The player grabs the mouse in _ready; a capture run must not hijack the pointer.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player := get_first_node_in_group("player") as PlayerController
	if player == null:
		push_error("FLASH_CAPTURE_NO_PLAYER")
		quit(1)
		return
	player.rotation.y = deg_to_rad(yaw_degrees)
	if override_position != Vector3.INF:
		player.global_position = override_position
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
	var pitch_pivot := player.get_node_or_null("BodycamRig") as Node3D
	if pitch_pivot != null:
		pitch_pivot.rotation.x = deg_to_rad(pitch_degrees)
	# Volumetric fog, SDFGI and the sky radiance all need a few frames to converge, and
	# the first frames also compile shaders.
	for frame: int in settle_frames:
		await process_frame
	var weapon: WeaponBase = null
	if player.weapon_manager != null and weapon_index < player.weapon_manager.weapons.size():
		weapon = player.weapon_manager.weapons[weapon_index]
	var ammo_before: int = weapon.ammo if weapon != null else -1
	if weapon != null and not idle_only:
		player.weapon_manager._select(weapon_index)
		await process_frame
		weapon.fire_once()
	for frame: int in maxi(delay_frames, 0):
		await process_frame
	var image := root.get_texture().get_image()
	var error := image.save_png(output_path)
	var flash_state := "none"
	if weapon != null:
		flash_state = "flash_timer=%.4f light_timer=%.4f ammo=%d/%d" % [weapon._flash_timer, weapon._light_timer, ammo_before, weapon.ammo]
	print("FLASH_CAPTURE path=", output_path, " size=", image.get_size(), " ", flash_state, " error=", error_string(error))
	level.free()
	for frame: int in 4:
		await process_frame
	quit(0 if error == OK else 1)
