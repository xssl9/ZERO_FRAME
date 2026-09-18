class_name HitFeedback
extends Node

## Hit Feedback / Game Feel
##
## Provides:
##   - Instant hit reaction on the target avatar (locomotion death-like flinch)
##   - Hit-stop: brief Engine.time_scale freeze (10–50 ms)
##   - Camera kick + shake via PlayerController.add_camera_impulse
##   - Impact sound (reuses assets/audio/impacts/metal.ogg as flesh hit fallback)
##   - 3D debug marker at the hit point (visible when dev panel "Debug Hit Info" is on)
##
## Usage: call HitFeedback.on_hit(hit_dict, zone, player) from weapon_base after
## a confirmed hitbox hit. The singleton is added to the scene tree by DevPanel.

const HIT_STOP_SECONDS := 0.022          # 22 ms — perceptible but not jarring
const HIT_STOP_TIME_SCALE := 0.0         # full freeze during hit-stop
const CAMERA_KICK_PITCH := 0.18          # degrees of upward kick
const CAMERA_KICK_YAW := 0.06
const CAMERA_KICK_ROLL := 0.04
const MARKER_LIFETIME := 4.0
const MARKER_RADIUS := 0.045

## Set by DevPanel; when false the 3D markers are not spawned.
var debug_hit_info: bool = false

var _hit_stop_timer: float = 0.0
var _original_time_scale: float = 1.0
var _impact_stream: AudioStream = null
var _impact_voice: AudioStreamPlayer = null

func _ready() -> void:
	_impact_stream = load("res://assets/audio/impacts/metal.ogg") as AudioStream
	if _impact_stream != null:
		_impact_voice = AudioStreamPlayer.new()
		_impact_voice.name = "HitImpactVoice"
		_impact_voice.stream = _impact_stream
		# Flesh hit is softer than a metal ricochet.
		_impact_voice.volume_db = -14.0
		_impact_voice.bus = &"Master"
		add_child(_impact_voice)

func _process(delta: float) -> void:
	if _hit_stop_timer > 0.0:
		_hit_stop_timer = maxf(_hit_stop_timer - delta, 0.0)
		if _hit_stop_timer <= 0.0:
			Engine.time_scale = _original_time_scale

## Called by weapon_base._fire_hitscan() after a hitbox is confirmed.
## `hit`  — the Dictionary returned by ShotBallistics.trace()
## `zone` — "head" / "torso" / "limbs"
## `avatar` — the SoldierAvatar (or any Node3D) that was hit; may be null
func on_hit(hit: Dictionary, zone: String, avatar: Node3D) -> void:
	_do_hit_stop()
	_do_camera_kick(zone)
	_do_impact_sound()
	if debug_hit_info and not hit.is_empty():
		_spawn_debug_marker(hit.get("position", Vector3.ZERO), zone)

func _do_hit_stop() -> void:
	if _hit_stop_timer > 0.0:
		return  # already in a stop; don't stack
	_original_time_scale = Engine.time_scale
	Engine.time_scale = HIT_STOP_TIME_SCALE
	_hit_stop_timer = HIT_STOP_SECONDS

func _do_camera_kick(zone: String) -> void:
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player == null:
		return
	var pitch := CAMERA_KICK_PITCH * (1.5 if zone == "head" else 1.0)
	var yaw   := randf_range(-CAMERA_KICK_YAW, CAMERA_KICK_YAW)
	var roll  := randf_range(-CAMERA_KICK_ROLL, CAMERA_KICK_ROLL)
	player.add_camera_impulse(pitch, yaw, roll)

func _do_impact_sound() -> void:
	if _impact_voice == null:
		return
	_impact_voice.pitch_scale = randf_range(0.82, 1.18)
	_impact_voice.play()

func _spawn_debug_marker(world_pos: Vector3, zone: String) -> void:
	var host: Node = get_tree().current_scene
	if host == null:
		return
	var marker := MeshInstance3D.new()
	marker.name = "HitDebugMarker"
	var sphere := SphereMesh.new()
	sphere.radius = MARKER_RADIUS
	sphere.height = MARKER_RADIUS * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	marker.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _zone_color(zone)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.85
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(marker)
	marker.global_position = world_pos
	# Fade and free after lifetime.
	var tween := create_tween()
	tween.tween_interval(MARKER_LIFETIME * 0.6)
	tween.tween_property(mat, "albedo_color:a", 0.0, MARKER_LIFETIME * 0.4)
	tween.tween_callback(marker.queue_free)

func _zone_color(zone: String) -> Color:
	match zone:
		"head":
			return Color(1.0, 0.15, 0.1)   # red
		"torso":
			return Color(1.0, 0.65, 0.0)   # orange
		_:
			return Color(0.2, 0.8, 1.0)    # cyan for limbs
