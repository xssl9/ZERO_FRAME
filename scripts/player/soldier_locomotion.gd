class_name SoldierLocomotion
extends Node

## Builds and drives the 8-way locomotion tree for a soldier avatar.
##
## Shape: a BlendTree whose root is a StateMachine feeding a TimeScale node.
## Every moving state is an AnimationNodeBlendSpace2D carrying all eight compass
## directions of its gait, so strafing and backpedalling are real animations -
## nothing here plays a clip in reverse or yaws the torso to fake a direction.
##
## The blend position is the convention from the asset spec:
##     Vector2(local_velocity.x, -local_velocity.z).normalized() * (speed / max)
## +Y is forward because Godot's forward is -Z.
##
## The TimeScale node is what actually keeps the feet planted: each gait declares
## the ground speed its clips were authored for, and playback is scaled by the
## ratio to the real speed. At the walk/run/sprint/crouch reference speeds the
## ratio is 1.0, so the clips run untouched and only the acceleration ramps and
## the analogue in-between speeds get stretched.

const STATE_IDLE := "idle"
const STATE_IDLE_AIM := "idle_aiming"
const STATE_CROUCH_IDLE := "idle_crouching"
const STATE_CROUCH_IDLE_AIM := "idle_crouching_aiming"
const STATE_WALK := "walk"
const STATE_RUN := "run"
const STATE_SPRINT := "sprint"
const STATE_CROUCH := "crouch"
const STATE_JUMP_UP := "jump_up"
const STATE_JUMP := "jump"
const STATE_JUMP_DOWN := "jump_down"
const STATE_DEATH := "death"

const BLEND_WALK := "Walk_BlendSpace2D"
const BLEND_RUN := "Run_BlendSpace2D"
const BLEND_SPRINT := "Sprint_BlendSpace2D"
const BLEND_CROUCH := "Crouch_BlendSpace2D"

## Ground speed each gait was authored at. Walk is the only estimate: the player
## controller has no dedicated walk speed, so the walk states only ever show up
## on the acceleration ramp between standing and running.
const WALK_REFERENCE := 1.9
const RUN_REFERENCE := 4.2
const SPRINT_REFERENCE := 7.0
const CROUCH_REFERENCE := 2.2

## Below this the soldier is standing still, above RUN_THRESHOLD it is running.
const MOVING_THRESHOLD := 0.18
const RUN_THRESHOLD := 2.8

const DEATH_CLIPS: PackedStringArray = [
	"death_from_the_front",
	"death_from_the_back",
	"death_from_right",
	"death_from_front_headshot",
	"death_from_back_headshot",
]
const DEATH_CROUCHING := "death_crouching_headshot_front"

const _DIAGONAL := 0.70710678

## Suffix -> blend-space coordinate. Shared by all four gaits because the clips
## follow the same naming everywhere.
const DIRECTIONS := {
	"forward": Vector2(0.0, 1.0),
	"backward": Vector2(0.0, -1.0),
	"left": Vector2(-1.0, 0.0),
	"right": Vector2(1.0, 0.0),
	"forward_left": Vector2(-_DIAGONAL, _DIAGONAL),
	"forward_right": Vector2(_DIAGONAL, _DIAGONAL),
	"backward_left": Vector2(-_DIAGONAL, -_DIAGONAL),
	"backward_right": Vector2(_DIAGONAL, -_DIAGONAL),
}

var tree: AnimationTree = null

var _playback: AnimationNodeStateMachinePlayback = null
var _death_node: AnimationNodeAnimation = null
var _state: String = STATE_IDLE
var _blend: Vector2 = Vector2.ZERO
var _scale: float = 1.0
var _was_airborne := false
var _landing_time := 0.0

func build(animation_tree: AnimationTree, animation_player: AnimationPlayer) -> bool:
	if animation_tree == null or animation_player == null:
		return false
	tree = animation_tree
	_force_looping(animation_player)

	var machine := AnimationNodeStateMachine.new()
	_add_state(machine, STATE_IDLE, _clip("idle"), Vector2(0.0, 0.0))
	_add_state(machine, STATE_IDLE_AIM, _clip("idle_aiming"), Vector2(220.0, 0.0))
	_add_state(machine, STATE_CROUCH_IDLE, _clip("idle_crouching"), Vector2(0.0, 90.0))
	_add_state(machine, STATE_CROUCH_IDLE_AIM, _clip("idle_crouching_aiming"), Vector2(220.0, 90.0))
	_add_state(machine, STATE_WALK, _build_blend_space(animation_player, "walk", "idle"), Vector2(0.0, 180.0))
	_add_state(machine, STATE_RUN, _build_blend_space(animation_player, "run", "idle"), Vector2(220.0, 180.0))
	_add_state(machine, STATE_SPRINT, _build_blend_space(animation_player, "sprint", "idle"), Vector2(440.0, 180.0))
	_add_state(machine, STATE_CROUCH, _build_blend_space(animation_player, "walk_crouching", "idle_crouching"), Vector2(660.0, 180.0))
	_add_state(machine, STATE_JUMP_UP, _clip("jump_up"), Vector2(0.0, 280.0))
	_add_state(machine, STATE_JUMP, _clip("jump_loop"), Vector2(220.0, 280.0))
	_add_state(machine, STATE_JUMP_DOWN, _clip("jump_down"), Vector2(440.0, 280.0))

	# One death state whose clip is swapped just before travelling into it, so the
	# six authored deaths stay distinct without six near-identical states.
	_death_node = _clip(DEATH_CLIPS[0])
	_death_node.loop_mode = Animation.LOOP_NONE
	_add_state(machine, STATE_DEATH, _death_node, Vector2(660.0, 280.0))

	_connect_all(machine)
	var start_transition := AnimationNodeStateMachineTransition.new()
	start_transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	machine.add_transition(&"Start", STATE_IDLE, start_transition)

	# The state machine is wrapped rather than used as the root so playback speed
	# can be scaled downstream of it.
	var root := AnimationNodeBlendTree.new()
	root.add_node("Locomotion", machine, Vector2(0.0, 0.0))
	root.add_node("Speed", AnimationNodeTimeScale.new(), Vector2(260.0, 0.0))
	root.connect_node("Speed", 0, "Locomotion")
	root.connect_node("output", 0, "Speed")

	tree.tree_root = root
	tree.anim_player = tree.get_path_to(animation_player)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	tree.active = true
	_playback = tree.get("parameters/Locomotion/playback") as AnimationNodeStateMachinePlayback
	if _playback != null:
		_playback.start(STATE_IDLE)
	return _playback != null

## The GLB import leaves every clip non-looping, which would freeze a gait on its
## last frame. Flipping the shared Animation resources is idempotent and applies
## to every avatar instance at once.
func _force_looping(animation_player: AnimationPlayer) -> void:
	for animation_name: String in animation_player.get_animation_list():
		if animation_name.begins_with("death") or animation_name.begins_with("jump") or animation_name == "t_pose":
			continue
		var animation := animation_player.get_animation(animation_name)
		if animation != null and animation.loop_mode == Animation.LOOP_NONE:
			animation.loop_mode = Animation.LOOP_LINEAR

func _clip(animation_name: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = animation_name
	return node

func _add_state(machine: AnimationNodeStateMachine, state: String, node: AnimationRootNode, position: Vector2) -> void:
	machine.add_node(state, node, position)

## `prefix` is the clip family ("walk", "run", "sprint", "walk_crouching") and
## `centre_clip` fills the origin so a blend position passing through zero during
## a cross-fade lands on a real pose instead of a triangulation hole.
func _build_blend_space(animation_player: AnimationPlayer, prefix: String, centre_clip: String) -> AnimationNodeBlendSpace2D:
	var space := AnimationNodeBlendSpace2D.new()
	space.min_space = Vector2(-1.0, -1.0)
	space.max_space = Vector2(1.0, 1.0)
	space.snap = Vector2(0.05, 0.05)
	space.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	space.auto_triangles = true
	space.add_blend_point(_clip(centre_clip), Vector2.ZERO, -1, centre_clip)
	for suffix: String in DIRECTIONS:
		var clip_name := "%s_%s" % [prefix, suffix]
		if not animation_player.has_animation(clip_name):
			push_warning("SOLDIER_LOCOMOTION: нет клипа %s" % clip_name)
			continue
		space.add_blend_point(_clip(clip_name), DIRECTIONS[suffix], -1, suffix)
	return space

## Every state reaches every other one directly. `travel()` could path through
## intermediates, but explicit edges keep the cross-fade length under control and
## make an interrupted transition (crouch cancelled mid-blend) behave.
func _connect_all(machine: AnimationNodeStateMachine) -> void:
	var states: PackedStringArray = [
		STATE_IDLE, STATE_IDLE_AIM, STATE_CROUCH_IDLE, STATE_CROUCH_IDLE_AIM,
		STATE_WALK, STATE_RUN, STATE_SPRINT, STATE_CROUCH,
		STATE_JUMP_UP, STATE_JUMP, STATE_JUMP_DOWN, STATE_DEATH,
	]
	for from: String in states:
		for to: String in states:
			if from == to:
				continue
			var transition := AnimationNodeStateMachineTransition.new()
			transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
			if to == STATE_DEATH:
				# Dying must read as an interruption, not as a blend.
				transition.xfade_time = 0.05
				transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			else:
				transition.xfade_time = 0.14
				# SYNC carries the gait phase across, so changing direction or
				# stance never resets the stride and never stutters the feet.
				transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC
			machine.add_transition(from, to, transition)

# --- Driving --------------------------------------------------------------

## `local_velocity` is the avatar-local planar velocity; `crouching`, `aiming`,
## `sprinting`, `airborne` and `dead` are the replicated state flags.
func update(local_velocity: Vector3, crouching: bool, aiming: bool, sprinting: bool, airborne: bool, dead: bool, delta: float) -> void:
	if tree == null or _playback == null:
		return

	var planar := Vector2(local_velocity.x, -local_velocity.z)
	var speed := planar.length()
	var wanted_state := _select_state(speed, crouching, aiming, sprinting, airborne, dead)
	if airborne and not dead:
		wanted_state = STATE_JUMP_UP if local_velocity.y > 0.5 else STATE_JUMP
	elif _was_airborne and not dead:
		_landing_time = 0.18
	_was_airborne = airborne
	if _landing_time > 0.0 and not airborne and not dead:
		_landing_time = maxf(0.0, _landing_time - delta)
		wanted_state = STATE_JUMP_DOWN
	var reference := _reference_speed(wanted_state)

	var target_blend := Vector2.ZERO
	if speed > MOVING_THRESHOLD:
		target_blend = planar.normalized() * clampf(speed / reference, 0.0, 1.0)
	# Easing the blend position rather than snapping it is what stops the feet
	# from skating when the player taps a strafe key.
	_blend = _blend.lerp(target_blend, clampf(delta * 12.0, 0.0, 1.0))

	var target_scale := 1.0
	if speed > MOVING_THRESHOLD and wanted_state in [STATE_WALK, STATE_RUN, STATE_SPRINT, STATE_CROUCH]:
		target_scale = clampf(speed / reference, 0.65, 1.6)
	_scale = lerpf(_scale, target_scale, clampf(delta * 10.0, 0.0, 1.0))

	for blend_space: String in [BLEND_WALK, BLEND_RUN, BLEND_SPRINT, BLEND_CROUCH]:
		tree.set("parameters/Locomotion/%s/blend_position" % _state_for_blend(blend_space), _blend)
	tree.set("parameters/Speed/scale", _scale)

	if wanted_state != _state:
		_state = wanted_state
		_playback.travel(wanted_state)

func _state_for_blend(blend_space: String) -> String:
	match blend_space:
		BLEND_WALK:
			return STATE_WALK
		BLEND_RUN:
			return STATE_RUN
		BLEND_SPRINT:
			return STATE_SPRINT
		_:
			return STATE_CROUCH

func _select_state(speed: float, crouching: bool, aiming: bool, sprinting: bool, airborne: bool, dead: bool) -> String:
	if dead:
		return STATE_DEATH
	if airborne:
		return STATE_JUMP
	if crouching:
		if speed <= MOVING_THRESHOLD:
			return STATE_CROUCH_IDLE_AIM if aiming else STATE_CROUCH_IDLE
		return STATE_CROUCH
	if speed <= MOVING_THRESHOLD:
		return STATE_IDLE_AIM if aiming else STATE_IDLE
	if sprinting and speed > RUN_THRESHOLD:
		return STATE_SPRINT
	if speed >= RUN_THRESHOLD:
		return STATE_RUN
	return STATE_WALK

func _reference_speed(state: String) -> float:
	match state:
		STATE_SPRINT:
			return SPRINT_REFERENCE
		STATE_CROUCH, STATE_CROUCH_IDLE, STATE_CROUCH_IDLE_AIM:
			return CROUCH_REFERENCE
		STATE_WALK:
			return WALK_REFERENCE
		_:
			return RUN_REFERENCE

## Picks the death clip from the zone that killed and the direction the shot came
## from, so a headshot from behind does not play a forward collapse.
func play_death(zone: String, crouching: bool, from_behind: bool) -> void:
	if _death_node == null or _playback == null:
		return
	var clip := "death_from_the_back" if from_behind else "death_from_the_front"
	if zone == "head":
		if crouching:
			clip = DEATH_CROUCHING
		else:
			clip = "death_from_back_headshot" if from_behind else "death_from_front_headshot"
	_death_node.animation = clip
	_state = STATE_DEATH
	_playback.travel(STATE_DEATH)
