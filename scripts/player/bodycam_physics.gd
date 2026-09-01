class_name BodycamPhysics
extends Camera3D

@export_category("References")
@export var character_body: CharacterBody3D
@export var weapon_aim_pivot: Node3D

@export_category("Body-mounted gait")
@export_range(0.0, 2.0, 0.01) var idle_rotation_degrees: float = 0.16
@export_range(0.0, 0.04, 0.001) var idle_position_meters: float = 0.003
@export_range(0.0, 8.0, 0.1) var walk_rotation_degrees: float = 2.65
@export_range(0.0, 0.08, 0.001) var walk_position_meters: float = 0.027
@export_range(0.2, 3.0, 0.05) var walk_frequency: float = 1.05
@export_range(1.0, 40.0, 0.1) var response_speed: float = 18.0
@export_range(0.0, 8.0, 0.1) var strafe_roll_degrees: float = 2.1
@export_range(0.0, 8.0, 0.1) var acceleration_pitch_degrees: float = 1.7
@export_range(0.0, 0.08, 0.001) var acceleration_lag_meters: float = 0.018
@export_range(1.0, 2.0, 0.05) var sprint_motion_multiplier: float = 1.42

@export_category("Responsive view and weapon lag")
@export_range(0.0001, 0.02, 0.0001) var mouse_sensitivity: float = 0.0046
@export_range(20.0, 89.0, 1.0) var pitch_limit_degrees: float = 78.0
@export_range(0.0, 1.5, 0.01) var weapon_lag_multiplier: float = 0.48
@export_range(0.1, 12.0, 0.1) var maximum_weapon_lag_degrees: float = 4.2
@export_range(1.0, 240.0, 1.0) var weapon_lag_stiffness: float = 92.0
@export_range(1.0, 40.0, 0.5) var weapon_lag_damping: float = 18.0
@export_range(0.0, 1.0, 0.01) var look_inertia_strength: float = 0.14
@export_range(0.0, 4.0, 0.1) var maximum_look_inertia_degrees: float = 0.85
@export_range(1.0, 240.0, 1.0) var look_inertia_stiffness: float = 105.0
@export_range(1.0, 40.0, 0.5) var look_inertia_damping: float = 19.0

@export_category("Recoil and impacts")
@export_range(1.0, 240.0, 1.0) var impact_spring_stiffness: float = 62.0
@export_range(1.0, 40.0, 0.5) var impact_spring_damping: float = 10.5
@export_range(0.0, 24.0, 0.1) var trauma_pitch_degrees: float = 14.5
@export_range(0.0, 18.0, 0.1) var trauma_yaw_degrees: float = 7.0
@export_range(0.0, 18.0, 0.1) var trauma_roll_degrees: float = 6.0
# How hard the shot punches the view on top of the permanent aim kick. Kept modest
# because the per-shot aim kick below is now large and the two add up.
@export_range(0.0, 40.0, 0.5) var recoil_visual_gain: float = 11.0
# Sustained fire must not recover between rounds, or the burst would never climb.
@export_range(0.0, 1.0, 0.01) var recoil_recovery_delay: float = 0.16
@export_range(0.0, 120.0, 1.0) var recoil_recovery_degrees_per_second: float = 34.0
@export_range(0.0, 60.0, 0.5) var maximum_recoil_debt_degrees: float = 30.0

var _base_position: Vector3
var _base_rotation: Vector3
var _idle_noise: FastNoiseLite = FastNoiseLite.new()
var _time: float = 0.0
var _walk_phase: float = 0.0
var _smoothed_speed: float = 0.0
var _previous_local_velocity: Vector3 = Vector3.ZERO
var _smoothed_acceleration: Vector3 = Vector3.ZERO
var _weapon_lag: Vector2 = Vector2.ZERO
var _weapon_lag_velocity: Vector2 = Vector2.ZERO
var _look_inertia: Vector3 = Vector3.ZERO
var _look_inertia_velocity: Vector3 = Vector3.ZERO
var _impact_rotation: Vector3 = Vector3.ZERO
var _impact_velocity: Vector3 = Vector3.ZERO
# Aim displacement the weapon owes back, in view space. Positive pitch debt means
# the muzzle was pushed up; yaw debt is stored exactly as it was fed to rotate_y.
var _recoil_pitch_debt: float = 0.0
var _recoil_yaw_debt: float = 0.0
var _recoil_recovery_timer: float = 0.0

func _ready() -> void:
	# This camera owns a render-frame procedural spring. Interpolating that result
	# a second time produces the warning and the visible micro-teleports/jitter.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_base_position = position
	_base_rotation = rotation
	_idle_noise.seed = 14891
	_idle_noise.frequency = 0.24
	_idle_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

func configure(body: CharacterBody3D, aim_pivot: Node3D) -> void:
	character_body = body
	weapon_aim_pivot = aim_pivot

func _unhandled_input(event: InputEvent) -> void:
	if character_body == null or event is not InputEventMouseMotion:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion := event as InputEventMouseMotion
	var look_delta := Vector2(
		-motion.relative.x * mouse_sensitivity,
		-motion.relative.y * mouse_sensitivity
	)
	# The player's view rotates in the input event itself. No interpolation or
	# physics-frame wait is allowed here: only the gun and vest retain inertia.
	_apply_view_rotation(look_delta)
	var maximum_weapon_lag := deg_to_rad(maximum_weapon_lag_degrees)
	_weapon_lag -= look_delta * weapon_lag_multiplier
	_weapon_lag.x = clampf(_weapon_lag.x, -maximum_weapon_lag, maximum_weapon_lag)
	_weapon_lag.y = clampf(_weapon_lag.y, -maximum_weapon_lag, maximum_weapon_lag)
	_look_inertia += Vector3(
		-look_delta.y,
		-look_delta.x * 0.55,
		-look_delta.x * 0.9
	) * look_inertia_strength
	_look_inertia = _look_inertia.limit_length(deg_to_rad(maximum_look_inertia_degrees))

func _physics_process(delta: float) -> void:
	if character_body == null:
		return
	var local_velocity: Vector3 = character_body.global_transform.basis.inverse() * character_body.velocity
	var frame_acceleration: Vector3 = (local_velocity - _previous_local_velocity) / maxf(delta, 0.001)
	_previous_local_velocity = local_velocity
	frame_acceleration = frame_acceleration.limit_length(18.0)
	_smoothed_acceleration = _smoothed_acceleration.lerp(frame_acceleration, 1.0 - exp(-7.0 * delta))
	var horizontal_speed: float = Vector2(local_velocity.x, local_velocity.z).length()
	_smoothed_speed = move_toward(_smoothed_speed, horizontal_speed, 24.0 * delta)

func _process(delta: float) -> void:
	if character_body == null:
		return
	# Preserve real-time response during an occasional slow frame. Springs are
	# sub-stepped below instead of slowing the camera clock with a delta clamp.
	var visual_delta: float = minf(delta, 0.1)
	_time += visual_delta
	_update_visual_springs_substepped(visual_delta)
	_recover_recoil(visual_delta)
	var local_velocity: Vector3 = character_body.global_transform.basis.inverse() * character_body.velocity
	var speed_ratio: float = clampf(_smoothed_speed / 7.0, 0.0, 1.0)
	var cycle_frequency: float = walk_frequency * lerpf(0.88, 1.32, speed_ratio)
	_walk_phase = fmod(_walk_phase + TAU * cycle_frequency * speed_ratio * visual_delta, TAU)
	_apply_body_transform(speed_ratio, local_velocity, _smoothed_acceleration, visual_delta)

func _apply_view_rotation(angular_step: Vector2) -> void:
	# Pulling the muzzle back down has to retire the recoil debt, otherwise the
	# automatic recovery below would drag the view back up past the player's aim
	# and every burst would end pointing at the sky.
	if angular_step.y < 0.0 and _recoil_pitch_debt > 0.0:
		_recoil_pitch_debt = maxf(_recoil_pitch_debt + angular_step.y, 0.0)
	if not is_zero_approx(_recoil_yaw_debt) and signf(angular_step.x) != signf(_recoil_yaw_debt):
		_recoil_yaw_debt = move_toward(_recoil_yaw_debt, 0.0, absf(angular_step.x))
	character_body.rotate_y(angular_step.x)
	var pitch_pivot := get_parent() as Node3D
	if pitch_pivot == null:
		return
	var pitch_limit: float = deg_to_rad(pitch_limit_degrees)
	pitch_pivot.rotation.x = clampf(pitch_pivot.rotation.x + angular_step.y, -pitch_limit, pitch_limit)

func _update_visual_springs_substepped(delta: float) -> void:
	var remaining: float = delta
	while remaining > 0.00001:
		var step: float = minf(remaining, 1.0 / 120.0)
		_integrate_visual_springs(step)
		remaining -= step

func _integrate_visual_springs(delta: float) -> void:
	var weapon_acceleration: Vector2 = -_weapon_lag * weapon_lag_stiffness - _weapon_lag_velocity * weapon_lag_damping
	_weapon_lag_velocity += weapon_acceleration * delta
	_weapon_lag += _weapon_lag_velocity * delta
	if weapon_aim_pivot != null:
		weapon_aim_pivot.rotation = Vector3(_weapon_lag.y, _weapon_lag.x, -_weapon_lag.x * 0.16)

	var inertia_acceleration: Vector3 = -_look_inertia * look_inertia_stiffness - _look_inertia_velocity * look_inertia_damping
	_look_inertia_velocity += inertia_acceleration * delta
	_look_inertia += _look_inertia_velocity * delta

	var impact_acceleration: Vector3 = -_impact_rotation * impact_spring_stiffness - _impact_velocity * impact_spring_damping
	_impact_velocity += impact_acceleration * delta
	_impact_rotation += _impact_velocity * delta

func _apply_body_transform(speed_ratio: float, local_velocity: Vector3, local_acceleration: Vector3, delta: float) -> void:
	var idle_x: float = _idle_noise.get_noise_1d(_time)
	var idle_y: float = _idle_noise.get_noise_1d(_time + 41.3)
	var gait: float = smoothstep(0.04, 0.72, speed_ratio)
	var sprint_blend: float = smoothstep(0.66, 1.0, speed_ratio)
	var motion_multiplier: float = lerpf(1.0, sprint_motion_multiplier, sprint_blend)
	var side_wave: float = sin(_walk_phase)
	var forward_wave: float = cos(_walk_phase)
	# Two soft chest drops per left/right gait cycle; no high-frequency jitter.
	var step_drop: float = (cos(_walk_phase * 2.0) - 1.0) * 0.5
	var strafe_ratio: float = clampf(local_velocity.x / 7.0, -1.0, 1.0)
	var acceleration_forward: float = clampf(local_acceleration.z / 18.0, -1.0, 1.0)
	var acceleration_side: float = clampf(local_acceleration.x / 18.0, -1.0, 1.0)
	var target_position := _base_position + Vector3(
		side_wave * walk_position_meters * 0.62 * gait * motion_multiplier - acceleration_side * acceleration_lag_meters,
		step_drop * walk_position_meters * gait * motion_multiplier + idle_y * idle_position_meters,
		-acceleration_forward * acceleration_lag_meters
	)
	var gait_rotation := Vector3(
		forward_wave * deg_to_rad(walk_rotation_degrees * 0.36) * gait * motion_multiplier,
		side_wave * deg_to_rad(walk_rotation_degrees * 0.20) * gait,
		-side_wave * deg_to_rad(walk_rotation_degrees) * gait * motion_multiplier
	)
	var movement_rotation := Vector3(
		acceleration_forward * deg_to_rad(acceleration_pitch_degrees),
		0.0,
		-strafe_ratio * deg_to_rad(strafe_roll_degrees)
	)
	var idle_rotation := Vector3(idle_y, idle_x * 0.35, idle_x) * deg_to_rad(idle_rotation_degrees)
	var target_rotation: Vector3 = _base_rotation + gait_rotation + movement_rotation + idle_rotation + _look_inertia + _impact_rotation
	var weight: float = 1.0 - exp(-response_speed * delta)
	position = position.lerp(target_position, weight)
	rotation = Vector3(
		lerp_angle(rotation.x, target_rotation.x, weight),
		lerp_angle(rotation.y, target_rotation.y, weight),
		lerp_angle(rotation.z, target_rotation.z, weight)
	)

func add_trauma(direction: Vector3, strength: float) -> void:
	var impulse_strength: float = clampf(strength, 0.0, 1.0)
	# Direction values come from each weapon, while the spring turns the short
	# velocity impulse into one strong kick and a controlled return.
	_impact_velocity += Vector3(
		direction.y * deg_to_rad(trauma_pitch_degrees),
		direction.x * deg_to_rad(trauma_yaw_degrees),
		direction.z * deg_to_rad(trauma_roll_degrees)
	) * impulse_strength * 4.5

# Real recoil, not just a shake: the aim itself is displaced and stays displaced
# until the player fights it down or the recovery below walks it back.
func add_recoil(pitch_degrees: float, yaw_degrees: float) -> void:
	if character_body == null:
		return
	var pitch_step: float = deg_to_rad(pitch_degrees)
	var yaw_step: float = -deg_to_rad(yaw_degrees)
	var debt_limit: float = deg_to_rad(maximum_recoil_debt_degrees)
	# The full kick always reaches the aim - an uncompensated magazine is supposed to
	# walk off target. Only the automatic recovery is capped, so the game never hands
	# back more than maximum_recoil_debt_degrees for free.
	character_body.rotate_y(yaw_step)
	var pitch_pivot := get_parent() as Node3D
	if pitch_pivot != null:
		var pitch_limit: float = deg_to_rad(pitch_limit_degrees)
		pitch_pivot.rotation.x = clampf(pitch_pivot.rotation.x + pitch_step, -pitch_limit, pitch_limit)
	_recoil_pitch_debt = minf(_recoil_pitch_debt + pitch_step, debt_limit)
	_recoil_yaw_debt = clampf(_recoil_yaw_debt + yaw_step, -debt_limit, debt_limit)
	_recoil_recovery_timer = recoil_recovery_delay
	# The visual punch rides on top so a single shot still snaps hard even when the
	# permanent aim kick is deliberately small.
	_impact_velocity += Vector3(
		deg_to_rad(pitch_degrees),
		-deg_to_rad(yaw_degrees),
		deg_to_rad(pitch_degrees) * randf_range(-0.45, 0.45)
	) * recoil_visual_gain

func _recover_recoil(delta: float) -> void:
	if _recoil_recovery_timer > 0.0:
		_recoil_recovery_timer = maxf(_recoil_recovery_timer - delta, 0.0)
		return
	if _recoil_pitch_debt <= 0.0 and is_zero_approx(_recoil_yaw_debt):
		return
	var rate: float = deg_to_rad(recoil_recovery_degrees_per_second) * delta
	var yaw_returned: float = _recoil_yaw_debt - move_toward(_recoil_yaw_debt, 0.0, rate)
	if not is_zero_approx(yaw_returned):
		_recoil_yaw_debt -= yaw_returned
		character_body.rotate_y(-yaw_returned)
	var pitch_returned: float = minf(_recoil_pitch_debt, rate)
	if pitch_returned <= 0.0:
		return
	_recoil_pitch_debt -= pitch_returned
	var pitch_pivot := get_parent() as Node3D
	if pitch_pivot != null:
		var pitch_limit: float = deg_to_rad(pitch_limit_degrees)
		pitch_pivot.rotation.x = clampf(pitch_pivot.rotation.x - pitch_returned, -pitch_limit, pitch_limit)
