@tool
class_name RainSystem
extends Node3D

## Rain that travels with the shooter. The drop volume is a box that keeps itself centred
## above the player, so a few thousand particles cover the whole visible downpour instead
## of trying to fill a 48 x 48 m arena. Splashes are a second, flat emitter at foot level.
##
## The drops are unshaded and fogged, so distant rain dissolves into the volumetric fog
## rather than staying crisp all the way to the wall.

@export_category("Downpour")
@export_range(0.0, 3.0, 0.05) var intensity: float = 1.0:
	set(value):
		intensity = value
		_apply_intensity()
@export var drop_count: int = 3200
@export var volume_size: Vector3 = Vector3(30.0, 14.0, 30.0)
@export var fall_speed: float = 17.0
# Rain is never vertical. This is the horizontal drift the wind puts on every drop.
@export var wind: Vector3 = Vector3(2.2, 0.0, -1.1)
@export var drop_length: float = 0.8
@export var drop_width: float = 0.014
@export var drop_color: Color = Color(0.66, 0.71, 0.78, 0.42)

@export_category("Splashes")
@export var splash_count: int = 320
@export var splash_size: float = 0.055

@export_category("Ambience")
# 28.5 s loop, crossfaded so the join sits inside steady noise. Non-positional: rain is
# all around the listener, not coming from a point in the level.
@export var ambience_stream_path: String = "res://assets/audio/environment/rain_loop.ogg"
@export_range(-40.0, 6.0, 0.5) var ambience_volume_db: float = -12.0

var _drops: GPUParticles3D
var _splashes: GPUParticles3D
var _ambience: AudioStreamPlayer
var _player: Node3D

func _ready() -> void:
	_build_drops()
	_build_splashes()
	_build_ambience()
	# Deferred: PhotorealEnvironment sets the real intensity from the chosen weather in a
	# deferred pass of its own, and its call is registered first. Applying immediately here
	# would start the downpour for one frame even when the player picked clear weather.
	call_deferred("_apply_intensity")

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	# Only the volume follows the player; the drops themselves are in world coordinates,
	# so nothing teleports sideways when the shooter moves.
	var feet := _player.global_position
	global_position = Vector3(feet.x, feet.y, feet.z)

func _apply_intensity() -> void:
	var scale := clampf(intensity, 0.0, 1.0)
	if _drops != null:
		_drops.amount_ratio = scale
		_drops.emitting = intensity > 0.0
	if _splashes != null:
		_splashes.amount_ratio = scale
		_splashes.emitting = intensity > 0.0
	if _ambience == null:
		return
	if intensity <= 0.0:
		_ambience.stop()
		return
	# A lighter drizzle is quieter as well as thinner, so the bed follows the same knob.
	_ambience.volume_db = ambience_volume_db + linear_to_db(maxf(scale, 0.05))
	if not _ambience.playing and not Engine.is_editor_hint():
		_ambience.play()

func _build_ambience() -> void:
	if ambience_stream_path.is_empty():
		return
	var stream := load(ambience_stream_path) as AudioStream
	if stream == null:
		push_warning("RainSystem: no usable ambience_stream_path")
		return
	# The import keeps loop off by default; a 28.5 s bed has to repeat for the whole match.
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_ambience = AudioStreamPlayer.new()
	_ambience.name = "RainAmbience"
	_ambience.stream = stream
	_ambience.volume_db = ambience_volume_db
	add_child(_ambience)

func _build_drops() -> void:
	_drops = GPUParticles3D.new()
	_drops.name = "Drops"
	_drops.amount = drop_count
	# One pass through the box: spawn at the top, die at the bottom.
	_drops.lifetime = volume_size.y / maxf(fall_speed, 1.0)
	_drops.preprocess = _drops.lifetime
	_drops.local_coords = false
	_drops.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	_drops.position = Vector3(0.0, volume_size.y * 0.5, 0.0)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(volume_size.x * 0.5, volume_size.y * 0.5, volume_size.z * 0.5)
	process.direction = Vector3(0.0, -1.0, 0.0)
	process.spread = 0.0
	process.initial_velocity_min = fall_speed * 0.86
	process.initial_velocity_max = fall_speed * 1.12
	process.gravity = Vector3(wind.x, -3.0, wind.z)
	process.scale_min = 0.7
	process.scale_max = 1.25
	_drops.process_material = process
	var drop := QuadMesh.new()
	drop.size = Vector2(drop_width, drop_length)
	drop.material = _build_drop_material(drop_color)
	_drops.draw_pass_1 = drop
	add_child(_drops)

func _build_splashes() -> void:
	_splashes = GPUParticles3D.new()
	_splashes.name = "Splashes"
	_splashes.amount = splash_count
	_splashes.lifetime = 0.3
	_splashes.local_coords = false
	_splashes.randomness = 0.7
	_splashes.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# A flat slab at foot height: every splash lands on the floor plane the player is on.
	process.emission_box_extents = Vector3(volume_size.x * 0.42, 0.02, volume_size.z * 0.42)
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 26.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 1.9
	process.gravity = Vector3(0.0, -7.5, 0.0)
	process.scale_min = 0.5
	process.scale_max = 1.15
	_splashes.process_material = process
	var splash := QuadMesh.new()
	splash.size = Vector2(splash_size, splash_size * 1.6)
	splash.material = _build_drop_material(Color(drop_color.r, drop_color.g, drop_color.b, 0.5))
	_splashes.draw_pass_1 = splash
	add_child(_splashes)

func _build_drop_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Fixed-Y billboard: the streak always faces the camera but stays upright, which is
	# what makes falling rain read as streaks instead of confetti.
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.billboard_keep_scale = true
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	return material
