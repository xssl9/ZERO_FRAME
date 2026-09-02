class_name WeaponManager
extends Node3D

var weapons: Array[WeaponBase] = []
var current_index: int = 0
var sway: Vector2 = Vector2.ZERO
var sway_velocity: Vector2 = Vector2.ZERO
var base_position: Vector3 = Vector3(0.0, -0.18, -0.35)
var collision_camera: Camera3D
var collision_player: CharacterBody3D
var wall_pushback: float = 0.0
var wall_blocked: bool = false
# Positional trail. The rifle has mass: it lags behind a fast turn and swings back, which is
# what separates a carried weapon from one bolted to the camera.
var _drag: Vector2 = Vector2.ZERO
var _drag_velocity: Vector2 = Vector2.ZERO
var _breath_time: float = 0.0
var _walk_phase: float = 0.0
var _sprint_blend: float = 0.0
var _lean: float = 0.0
# Free aim. The muzzle has this much room to wander inside the frame before recoil starts
# dragging the actual view: the first rounds move the gun, not the world.
@export_range(0.0, 12.0, 0.1) var free_aim_limit_degrees: float = 3.6
@export_range(0.5, 20.0, 0.1) var free_aim_recentre: float = 5.5
var _free_aim: Vector2 = Vector2.ZERO

# Takes a kick in radians, keeps what fits inside the envelope and hands back the spill for
# the camera and the real aim to deal with.
func add_free_aim(pitch: float, yaw: float) -> Vector2:
	var limit := deg_to_rad(free_aim_limit_degrees)
	var wanted := _free_aim + Vector2(yaw, pitch)
	var clamped := Vector2(clampf(wanted.x, -limit, limit), clampf(wanted.y, -limit, limit))
	_free_aim = clamped
	return wanted - clamped

func free_aim() -> Vector2:
	return _free_aim

func set_lean(value: float) -> void:
	_lean = clampf(value, -1.0, 1.0)

func configure_weapon_collision(player: CharacterBody3D, player_camera: Camera3D) -> void:
	collision_player = player
	collision_camera = player_camera

func _ready() -> void:
	top_level = false
	position = base_position
	var ak := WeaponBase.new()
	# AUTO first: the AK spawns on full auto and V flips it to single shots.
	var ak_modes: Array[int] = [WeaponBase.FireMode.AUTO, WeaponBase.FireMode.SEMI]
	# Rig|AK_Reload_full rather than Rig|AK_Reload: the reload recording ends on a
	# charging-handle pull, which is what the empty-magazine animation actually does, and
	# at 3.5 s it also needs the least stretching to cover the 4.2 s of audio.
	ak.configure("AK-74M", 30, 30, 650.0, 34.0, ak_modes, "res://scenes/weapons/ak_viewmodel.tscn", "Rig|AK_Idle", "Rig|AK_Reload_full", "Rig|AK_Shot")
	ak.shot_stream_path = "res://assets/audio/weapons/ak_shot.ogg"
	ak.reload_stream_path = "res://assets/audio/weapons/ak_reload.ogg"
	add_child(ak)
	weapons.append(ak)
	var pistol := WeaponBase.new()
	var pistol_modes: Array[int] = [WeaponBase.FireMode.SEMI]
	pistol.configure("PISTOL", 15, 15, 330.0, 25.0, pistol_modes, "res://scenes/weapons/pistol_viewmodel.tscn", "Armature|FPS_Pistol_Idle", "Armature|FPS_Pistol_Reload_easy", "Armature|FPS_Pistol_Fire")
	# The test grid is a walled courtyard open to the sky, so the outdoor report is the
	# right one. `pistol_shot_room.ogg` is the same shot recorded in a closed room and
	# is a drop-in swap for interior maps.
	pistol.shot_stream_path = "res://assets/audio/weapons/pistol_shot.ogg"
	# The 9 mm sample is already resampled down so it does not read as a cap gun, and it
	# sits about 3 dB under the rifle: one round never stacks the way a burst does.
	pistol.shot_volume_db = -4.0
	# A 9 mm sidearm snaps rather than climbs, so it gets a lighter profile than
	# the rifle defaults declared on WeaponBase.
	pistol.recoil_pitch_degrees = 0.72
	pistol.recoil_pitch_climb_degrees = 0.45
	pistol.recoil_yaw_bias_degrees = 0.12
	pistol.recoil_yaw_spread_degrees = 0.4
	pistol.recoil_kick_speed = 1.85
	pistol.recoil_pitch_speed = 2.7
	pistol.recoil_heat_per_shot = 0.14
	pistol.recoil_heat_decay = 2.4
	# Its muzzle sits about half as far from the camera as the rifle's, so an
	# identically sized flame would swallow the whole screen.
	pistol.muzzle_flash_size = 0.19
	pistol.muzzle_flash_energy = 9.0
	# A pistol without a muzzle brake throws a smaller, tighter flash than the AK's
	# four-port brake, and correspondingly less unburnt powder and smoke.
	pistol.muzzle_flash_world_energy = 11.0
	pistol.muzzle_flash_world_range = 7.0
	pistol.muzzle_flash_tongues = 6.0
	pistol.muzzle_sparks_amount = 9
	pistol.muzzle_smoke_amount = 6
	add_child(pistol)
	weapons.append(pistol)
	_select(1 if "--pistol" in OS.get_cmdline_user_args() else 0)

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("weapon_1"):
		_select(0)
	if Input.is_action_just_pressed("weapon_2"):
		_select(1)
	if Input.is_action_just_pressed("fire_mode"):
		weapons[current_index].cycle_fire_mode()
	if Input.is_action_just_pressed("reload"):
		weapons[current_index].reload()
	if not wall_blocked:
		weapons[current_index].try_fire(delta)
	weapons[current_index].set_aiming(Input.is_action_pressed("aim"))
	var movement := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var aiming: bool = Input.is_action_pressed("aim")
	# Rotational sway: where the muzzle trails to when the view turns.
	sway_velocity += (-sway * 54.0 - sway_velocity * 13.0) * delta
	sway += sway_velocity * delta
	# Positional trail on the same impulse, but slower and softer, so the gun visibly swings
	# through the frame on a fast turn instead of only tilting.
	_drag_velocity += (-_drag * 38.0 - _drag_velocity * 10.0) * delta
	_drag += _drag_velocity * delta

	var horizontal_speed := 0.0
	var sprinting := false
	if collision_player != null:
		horizontal_speed = Vector2(collision_player.velocity.x, collision_player.velocity.z).length()
		sprinting = Input.is_action_pressed("sprint") and horizontal_speed > 5.0
	# Sprinting drops the muzzle and rolls the rifle in towards the chest.
	_sprint_blend = move_toward(_sprint_blend, 1.0 if sprinting else 0.0, delta * (5.0 if sprinting else 3.2))
	# Weapon gait, driven by real speed rather than by a timer, so it stops when you stop.
	_walk_phase = fmod(_walk_phase + delta * (2.2 + 1.4 * clampf(horizontal_speed / 7.0, 0.0, 1.0)) * TAU * 0.5, TAU)
	var gait := clampf(horizontal_speed / 4.2, 0.0, 1.4) * (0.35 if aiming else 1.0)
	# Breathing never stops, it only gets quieter when the sights are up.
	_breath_time += delta
	var breath_scale := 0.4 if aiming else 1.0

	# The shooter is always pulling the gun back onto the target, so the envelope drains
	# whether or not the trigger is held.
	_free_aim = _free_aim.lerp(Vector2.ZERO, 1.0 - exp(-free_aim_recentre * delta))

	var sway_scale := 0.4 if aiming else 1.0
	rotation = Vector3(
		_free_aim.y + (sway.y * 0.018 + sin(_breath_time * 1.7) * 0.0045 * breath_scale) * sway_scale - wall_pushback * 0.46 + _sprint_blend * 0.26,
		_free_aim.x + (sway.x * 0.025 + sin(_breath_time * 1.15) * 0.0055 * breath_scale) * sway_scale,
		lerpf(rotation.z, -movement.x * 0.018 + wall_pushback * 0.08 + _lean * 0.12 - _sprint_blend * 0.12 + sin(_walk_phase) * 0.012 * gait, 1.0 - exp(-delta * 9.0))
	)
	var collision_offset := Vector3(0.0, wall_pushback * 0.16, wall_pushback)
	var sprint_offset := Vector3(0.03, -0.075, 0.05) * _sprint_blend
	var lean_offset := Vector3(-_lean * 0.03, 0.0, 0.0)
	var gait_offset := Vector3(sin(_walk_phase) * 0.006, -absf(cos(_walk_phase)) * 0.008, 0.0) * gait
	var drag_offset := Vector3(_drag.x, _drag.y, 0.0) * 0.0022 * sway_scale
	var target := base_position + collision_offset + sprint_offset + lean_offset + gait_offset + drag_offset
	position = position.lerp(target, 1.0 - exp(-delta * 18.0))

func _physics_process(delta: float) -> void:
	if collision_camera == null or collision_player == null or weapons.is_empty():
		return
	var weapon_length: float = 1.18 if weapons[current_index].weapon_name == "AK-74M" else 0.72
	var origin: Vector3 = collision_camera.global_position
	var forward: Vector3 = -collision_camera.global_transform.basis.z.normalized()
	var query := PhysicsRayQueryParameters3D.create(origin + forward * 0.08, origin + forward * weapon_length)
	query.exclude = [collision_player.get_rid()]
	query.collide_with_areas = false
	var hit := collision_player.get_world_3d().direct_space_state.intersect_ray(query)
	var target_pushback: float = 0.0
	if not hit.is_empty():
		var distance: float = origin.distance_to(hit["position"] as Vector3)
		target_pushback = clampf(weapon_length - distance + 0.12, 0.0, 0.62)
	wall_blocked = target_pushback > (0.2 if weapons[current_index].weapon_name == "AK-74M" else 0.13)
	var speed: float = 8.0 if target_pushback > wall_pushback else 13.0
	wall_pushback = move_toward(wall_pushback, target_pushback, speed * delta)

func add_look_impulse(relative: Vector2) -> void:
	sway_velocity += Vector2(clampf(-relative.x, -35.0, 35.0), clampf(-relative.y, -35.0, 35.0)) * 0.35
	# The same impulse feeds the heavier positional spring, clamped harder so a flick of the
	# mouse cannot throw the rifle out of frame.
	_drag_velocity += Vector2(clampf(-relative.x, -24.0, 24.0), clampf(relative.y, -24.0, 24.0)) * 0.5

func _select(index: int) -> void:
	current_index = clampi(index, 0, weapons.size() - 1)
	for i: int in weapons.size():
		var weapon := weapons[i]
		var active: bool = i == current_index
		weapon.visible = active
		# The holstered weapon stops processing, so its recoil springs would freeze
		# mid-kick and reappear bent when it is drawn again.
		weapon.reset_recoil()
		weapon.set_process(active)
		weapon.set_authored_camera_active(active)

func get_hud_text() -> String:
	if weapons.is_empty():
		return ""
	var weapon := weapons[current_index]
	var mode: String = "  %s" % weapon.fire_mode_label() if weapon.has_selector() else ""
	return "%s%s   %02d / %02d" % [weapon.weapon_name, mode, weapon.ammo, weapon.reserve]

func get_status_text() -> String:
	if weapons.is_empty():
		return ""
	var weapon := weapons[current_index]
	if weapon.reloading:
		return "ПЕРЕЗАРЯДКА"
	if weapon.ammo == 0:
		return "R — ПЕРЕЗАРЯДИТЬ"
	return ""

func get_active_camera_fov() -> float:
	if weapons.is_empty():
		return 96.0
	return weapons[current_index].authored_camera_fov

func get_active_camera_keep_aspect() -> Camera3D.KeepAspect:
	if weapons.is_empty():
		return Camera3D.KEEP_HEIGHT
	return weapons[current_index].authored_camera_keep_aspect

func get_active_authored_camera() -> Camera3D:
	if weapons.is_empty():
		return null
	return weapons[current_index].authored_camera
