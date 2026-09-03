class_name BodycamPhysics
extends Camera3D

@export_category("References")
@export var character_body: CharacterBody3D
@export var weapon_aim_pivot: Node3D

@export_category("Body-mounted gait")
@export_range(0.0, 2.0, 0.01) var idle_rotation_degrees: float = 0.16
@export_range(0.0, 0.04, 0.001) var idle_position_meters: float = 0.003
@export_range(0.0, 8.0, 0.1) var walk_rotation_degrees: float = 3.3
@export_range(0.0, 0.08, 0.001) var walk_position_meters: float = 0.036
@export_range(0.2, 3.0, 0.05) var walk_frequency: float = 1.05
@export_range(1.0, 40.0, 0.1) var response_speed: float = 18.0
@export_range(0.0, 8.0, 0.1) var strafe_roll_degrees: float = 2.1
@export_range(0.0, 8.0, 0.1) var acceleration_pitch_degrees: float = 1.7
@export_range(0.0, 0.08, 0.001) var acceleration_lag_meters: float = 0.018
@export_range(1.0, 2.0, 0.05) var sprint_motion_multiplier: float = 1.58

@export_category("Responsive view and weapon lag")
@export_range(0.0001, 0.02, 0.0001) var mouse_sensitivity: float = 0.0046
@export_range(20.0, 89.0, 1.0) var pitch_limit_degrees: float = 78.0
# The rifle is carried, not bolted to the view: it trails a turn by up to this much and, because
# the spring below is deliberately underdamped, swings past its rest pose and settles back.
@export_range(0.0, 1.5, 0.01) var weapon_lag_multiplier: float = 0.66
@export_range(0.1, 12.0, 0.1) var maximum_weapon_lag_degrees: float = 6.8
@export_range(1.0, 240.0, 1.0) var weapon_lag_stiffness: float = 64.0
@export_range(1.0, 40.0, 0.5) var weapon_lag_damping: float = 9.5
@export_range(0.0, 1.0, 0.01) var look_inertia_strength: float = 0.2
@export_range(0.0, 4.0, 0.1) var maximum_look_inertia_degrees: float = 1.5
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
@export_range(0.0, 40.0, 0.5) var recoil_visual_gain: float = 15.0
# Sustained fire must not recover between rounds, or the burst would never climb.
@export_range(0.0, 1.0, 0.01) var recoil_recovery_delay: float = 0.16
@export_range(0.0, 120.0, 1.0) var recoil_recovery_degrees_per_second: float = 34.0
@export_range(0.0, 60.0, 0.5) var maximum_recoil_debt_degrees: float = 30.0
# A chest-mounted camera does not only rotate when the rifle goes off: the whole housing is
# shoved. This is the positional half of the kick, plus the tremble that builds during a
# burst and decays a few tenths of a second after it stops.
@export_range(0.0, 0.2, 0.001) var recoil_camera_kick_meters: float = 0.034
@export_range(1.0, 400.0, 1.0) var recoil_position_stiffness: float = 165.0
@export_range(1.0, 40.0, 0.5) var recoil_position_damping: float = 12.5
@export_range(0.0, 3.0, 0.05) var shake_per_shot: float = 0.85
@export_range(0.1, 12.0, 0.1) var shake_decay: float = 3.4
@export_range(0.0, 6.0, 0.05) var shake_rotation_degrees: float = 2.3
@export_range(0.0, 0.06, 0.001) var shake_position_meters: float = 0.019

@export_category("Lean")
# Q/E lean. The camera rolls, shifts sideways and drops a little, the way a shoulder does
# when you actually put your head past a corner.
@export_range(0.0, 30.0, 0.5) var lean_roll_degrees: float = 14.0
@export_range(0.0, 0.8, 0.01) var lean_offset_meters: float = 0.34
@export_range(0.0, 0.3, 0.01) var lean_drop_meters: float = 0.06
@export_range(0.5, 12.0, 0.1) var lean_speed: float = 5.0

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
var _impact_position: Vector3 = Vector3.ZERO
var _impact_position_velocity: Vector3 = Vector3.ZERO
var _shake: float = 0.0
# The smoothed gait position is kept apart from what is written to the node: the recoil
# shove is added afterwards, and feeding it back into the smoothing would let it accumulate
# frame after frame until the camera drifted a third of a metre out of the head.
var _smoothed_position: Vector3 = Vector3.ZERO
# Aim displacement the weapon owes back, in view space. Positive pitch debt means
# the muzzle was pushed up; yaw debt is stored exactly as it was fed to rotate_y.
var _recoil_pitch_debt: float = 0.0
var _recoil_yaw_debt: float = 0.0
var _recoil_recovery_timer: float = 0.0
# Lean amount in [-1, 1]; the target is set by PlayerController, which is also what checks
# there is room to lean into before asking for it.
var _lean: float = 0.0
var _lean_target: float = 0.0

func set_lean_target(value: float) -> void:
	_lean_target = clampf(value, -1.0, 1.0)

func lean_amount() -> float:
	return _lean

func _ready() -> void:
	# This camera owns a render-frame procedural spring. Interpolating that result
	# a second time produces the warning and the visible micro-teleports/jitter.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_base_position = position
	_smoothed_position = position
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
	_lean = move_toward(_lean, _lean_target, lean_speed * visual_delta)
	# Tremble builds while the trigger is held and dies a few tenths after it is released.
	_shake = maxf(_shake - shake_decay * visual_delta, 0.0)
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
	var trauma_limit: float = deg_to_rad(maxf(trauma_pitch_degrees, 1.0))
	_impact_velocity = _impact_velocity.limit_length(trauma_limit * 14.0)
	_impact_rotation = _impact_rotation.limit_length(trauma_limit * 0.6)

	# The housing itself is shoved, not just tilted: this is the part that reads as a camera
	# strapped to a chest rather than a floating eye.
	var position_acceleration: Vector3 = -_impact_position * recoil_position_stiffness - _impact_position_velocity * recoil_position_damping
	_impact_position_velocity += position_acceleration * delta
	_impact_position += _impact_position_velocity * delta
	var kick_limit: float = recoil_camera_kick_meters * 2.5
	_impact_position_velocity = _impact_position_velocity.limit_length(kick_limit * 12.0)
	_impact_position = _impact_position.limit_length(kick_limit)

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
	# Lean is applied last and in the rig's own axes, so it stacks on top of the gait
	# instead of fighting it: shoulder out, head over, camera rolled.
	var lean_position := Vector3(_lean * lean_offset_meters, -absf(_lean) * lean_drop_meters, 0.0)
	# High-frequency tremble, sampled from the same noise as the idle sway but ninety times
	# faster, so it reads as vibration rather than as drift.
	var tremble := clampf(_shake, 0.0, 2.5)
	var shake_offset := Vector3(
		_idle_noise.get_noise_2d(_time * 90.0, 11.0),
		_idle_noise.get_noise_2d(_time * 90.0, 47.0),
		_idle_noise.get_noise_2d(_time * 90.0, 83.0)) * shake_position_meters * tremble
	var shake_rotation := Vector3(
		_idle_noise.get_noise_2d(_time * 78.0, 131.0),
		_idle_noise.get_noise_2d(_time * 78.0, 167.0),
		_idle_noise.get_noise_2d(_time * 78.0, 199.0)) * deg_to_rad(shake_rotation_degrees) * tremble
	var lean_rotation := Vector3(0.0, 0.0, -_lean * deg_to_rad(lean_roll_degrees))
	var target_rotation: Vector3 = _base_rotation + gait_rotation + movement_rotation + idle_rotation + _look_inertia + _impact_rotation + lean_rotation + shake_rotation
	var weight: float = 1.0 - exp(-response_speed * delta)
	# The recoil shove and the tremble are applied outside the smoothing, or the lerp would
	# swallow exactly the frames that make a shot feel like a shot.
	_smoothed_position = _smoothed_position.lerp(target_position + lean_position, weight)
	position = _smoothed_position + _impact_position + shake_offset
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
	# Shove the housing back, up and slightly sideways, and add to the tremble.
	_impact_position_velocity += Vector3(randf_range(-0.45, 0.45), 0.5, 1.0) * recoil_camera_kick_meters * 14.0
	_shake = minf(_shake + shake_per_shot, 2.5)
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
