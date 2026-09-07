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

var quality_scale: float = 1.0:
	set(value):
		quality_scale = clampf(value, 0.1, 1.0)
		_apply_intensity()
var shelter: float = 0.0
var _heightfield: GPUParticlesCollisionHeightField3D
var _splash_points: ImageTexture
var _valid_splashes: int = 0
var _rng := RandomNumberGenerator.new()
var _shelter_timer: float = 0.0
var _far_drops: GPUParticles3D
var _drops: GPUParticles3D
var _splashes: GPUParticles3D
var _ambience: AudioStreamPlayer
var _player: Node3D

func _ready() -> void:
	_rng.seed = 7031
	_build_drops()
	_build_far_drops()
	_build_splashes()
	_build_heightfield()
	_build_ambience()
	# Deferred: PhotorealEnvironment sets the real intensity from the chosen weather in a
	# deferred pass of its own, and its call is registered first. Applying immediately here
	# would start the downpour for one frame even when the player picked clear weather.
	call_deferred("_apply_intensity")

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not is_instance_valid(_player):
		for candidate: Node in get_tree().get_nodes_in_group("player"):
			if candidate.get_viewport() == get_viewport():
				_player = candidate as Node3D
				break
		if _player == null:
			return
	# World-space particles retain their trajectory when the emitter moves.
	global_position = _player.global_position
	_shelter_timer -= delta
	if _shelter_timer <= 0.0:
		_shelter_timer = 0.3
		_update_surface_samples()
		_apply_intensity()

func _update_surface_samples() -> void:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if _player is CollisionObject3D:
		exclude.append((_player as CollisionObject3D).get_rid())
	var eye := global_position + Vector3.UP * 1.5
	var overhead := PhysicsRayQueryParameters3D.create(eye, eye + Vector3.UP * 40.0)
	overhead.exclude = exclude
	shelter = 0.0 if space.intersect_ray(overhead).is_empty() else 1.0
	if intensity <= 0.0:
		return
	# Sparse real collision samples, not a horizontal splash plane floating across stairs.
	var points: Array[Vector3] = []
	for sample: int in 24:
		var start := eye + Vector3(_rng.randf_range(-9.0, 9.0), 0.0, _rng.randf_range(-9.0, 9.0))
		var query := PhysicsRayQueryParameters3D.create(start, start + Vector3.DOWN * 5.0)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty() or (hit.normal as Vector3).y < 0.55:
			continue
		var point: Vector3 = hit.position + hit.normal * 0.015
		query.from = point + Vector3.UP * 0.03
		query.to = point + Vector3.UP * 40.0
		if space.intersect_ray(query).is_empty():
			points.append(to_local(point))
	_valid_splashes = points.size()
	if points.is_empty():
		return
	var image := Image.create(24, 1, false, Image.FORMAT_RGBF)
	for index: int in 24:
		var point := points[index % points.size()]
		image.set_pixel(index, 0, Color(point.x, point.y, point.z))
	if _splash_points == null:
		_splash_points = ImageTexture.create_from_image(image)
	else:
		_splash_points.update(image)
	var process := _splashes.process_material as ParticleProcessMaterial
	process.emission_point_texture = _splash_points
	process.emission_point_count = points.size()

func _apply_intensity() -> void:
	var scale := clampf(intensity, 0.0, 1.0)
	for emitter: GPUParticles3D in [_drops, _far_drops]:
		if emitter == null:
			continue
		emitter.amount_ratio = scale * quality_scale
		emitter.emitting = intensity > 0.0
		(emitter.process_material as ParticleProcessMaterial).gravity = Vector3(wind.x, -3.0, wind.z)
	if _heightfield != null:
		_heightfield.visible = intensity > 0.0
	if _splashes != null:
		_splashes.amount_ratio = scale * quality_scale
		_splashes.emitting = intensity > 0.0 and _valid_splashes > 0
	if _ambience == null:
		return
	if intensity <= 0.0:
		_ambience.stop()
		return
	# A lighter drizzle is quieter as well as thinner, so the bed follows the same knob.
	_ambience.volume_db = ambience_volume_db + linear_to_db(maxf(scale, 0.05)) - shelter * 9.0
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
	# Spawn ABOVE roofs rather than throughout the volume (which spawned indoors).
	process.emission_box_extents = Vector3(volume_size.x * 0.5, 0.1, volume_size.z * 0.5)
	process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_drops.visibility_aabb = AABB(-volume_size, volume_size * 2.0)
	_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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

func _build_far_drops() -> void:
	_far_drops = _drops.duplicate() as GPUParticles3D
	_far_drops.name = "FarDrops"
	_far_drops.amount = maxi(256, drop_count / 2)
	var process := _drops.process_material.duplicate() as ParticleProcessMaterial
	process.emission_box_extents = Vector3(volume_size.x, 0.1, volume_size.z)
	_far_drops.process_material = process
	var drop := QuadMesh.new()
	drop.size = Vector2(drop_width * 0.6, drop_length * 0.45)
	drop.material = _build_drop_material(Color(drop_color.r, drop_color.g, drop_color.b, 0.16))
	_far_drops.draw_pass_1 = drop
	_far_drops.visibility_aabb = AABB(-volume_size, volume_size * 2.0)
	add_child(_far_drops)

func _build_heightfield() -> void:
	# Top-down depth capture kills drops at roofs/ground, including non-collidable
	# pergola meshes. WHEN_MOVED avoids rendering this map while standing still.
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return
	_heightfield = GPUParticlesCollisionHeightField3D.new()
	_heightfield.name = "RainSurfaceCollision"
	_heightfield.size = volume_size * Vector3(2.0, 2.0, 2.0)
	_heightfield.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	_heightfield.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	add_child(_heightfield)

func _build_splashes() -> void:
	_splashes = GPUParticles3D.new()
	_splashes.name = "Splashes"
	_splashes.amount = splash_count
	_splashes.lifetime = 0.3
	_splashes.local_coords = false
	_splashes.randomness = 0.7
	_splashes.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	_splashes.emitting = false
	_splashes.visibility_aabb = AABB(Vector3(-12.0, -6.0, -12.0), Vector3(24.0, 14.0, 24.0))
	_splashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
