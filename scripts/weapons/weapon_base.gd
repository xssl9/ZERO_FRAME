class_name WeaponBase
extends Node3D

enum FireMode {AUTO, SEMI}

const FIRE_MODE_LABELS: Dictionary = {FireMode.AUTO: "АВТО", FireMode.SEMI: "ОД"}
# One AudioStreamPlayer can only voice one shot at a time, so at 650 RPM a single
# player would restart the sample every 92 ms and cut its own tail off. A small
# round-robin pool lets the reports overlap the way real automatic fire does.
const SHOT_VOICE_COUNT: int = 8
# One flash has to be over well before the next round at 650 RPM (92 ms), otherwise
# automatic fire reads as one continuous glow instead of a string of shots.
const MUZZLE_FLASH_SECONDS: float = 0.045

var weapon_name: String = "WEAPON"
var magazine_size: int = 30
var ammo: int = 30
var reserve: int = 90
var rounds_per_minute: float = 600.0
var damage: float = 30.0
var fire_modes: Array[int] = [FireMode.SEMI]
var fire_mode_index: int = 0
var model_path: String = ""
var idle_animation: String = ""
var reload_animation: String = ""
var shot_animation: String = ""
var trigger_released: bool = true
var reloading: bool = false
var aiming: bool = false
var model_root: Node3D
var muzzle: Marker3D
var muzzle_light: OmniLight3D
var authored_camera: Camera3D
var authored_camera_fov: float = 96.0
var authored_camera_keep_aspect: Camera3D.KeepAspect = Camera3D.KEEP_HEIGHT

@export_category("Recoil profile")
# Per-shot view kick. The pitch figure is what the shooter has to pull back down:
# it is added to the real aim, not just to the visual camera shake. An uncompensated
# 30-round magazine walks the aim roughly 44 degrees up and 10 degrees right, which
# is most of a screen height at this FOV.
@export var recoil_pitch_degrees: float = 0.88
@export var recoil_pitch_climb_degrees: float = 1.1
@export var recoil_yaw_bias_degrees: float = 0.32
@export var recoil_yaw_spread_degrees: float = 0.62
# Viewmodel kick: how far the gun slams back into the shoulder and how far the
# muzzle flips up. Purely cosmetic, but it is what sells the weight.
@export var recoil_kick_speed: float = 1.85
@export var recoil_pitch_speed: float = 2.7
@export var recoil_spring_stiffness: float = 380.0
@export var recoil_spring_damping: float = 26.0
# Burst heat: sustained fire climbs harder and scatters wider than the first round.
@export var recoil_heat_per_shot: float = 0.2
@export var recoil_heat_decay: float = 1.7

@export_category("Muzzle flash")
# Metres across for the crossed flame petals. Scaled per weapon because the pistol
# muzzle sits about half as far from the camera as the rifle's.
@export var muzzle_flash_size: float = 0.34
@export var muzzle_flash_energy: float = 26.0

var _fire_cooldown: float = 0.0
var _recoil_heat: float = 0.0
var _kick_offset: float = 0.0
var _kick_velocity: float = 0.0
var _kick_pitch: float = 0.0
var _kick_pitch_velocity: float = 0.0
var _shot_voices: Array[AudioStreamPlayer] = []
var _shot_voice_index: int = 0
var _animation_player: AnimationPlayer
var _shot_animation_length: float = 0.0
var _shot_animation_timer: float = 0.0
var _flash_root: Node3D
var _flash_petals: Node3D
var _flash_material: ShaderMaterial
var _flash_timer: float = 0.0
var _authored_camera_rest: Transform3D = Transform3D.IDENTITY

func configure(p_name: String, p_magazine: int, p_ammo: int, p_rpm: float, p_damage: float, p_modes: Array[int], p_model: String, p_idle: String, p_reload: String, p_shot: String) -> void:
	weapon_name = p_name
	magazine_size = p_magazine
	ammo = p_ammo
	reserve = p_magazine * 3
	rounds_per_minute = p_rpm
	damage = p_damage
	fire_modes = p_modes
	fire_mode_index = 0
	model_path = p_model
	idle_animation = p_idle
	reload_animation = p_reload
	shot_animation = p_shot

func fire_mode() -> FireMode:
	return fire_modes[fire_mode_index] as FireMode

func is_automatic() -> bool:
	return fire_mode() == FireMode.AUTO

func fire_mode_label() -> String:
	return FIRE_MODE_LABELS[fire_mode()] as String

func has_selector() -> bool:
	return fire_modes.size() > 1

# Returns true when the selector actually moved, so the caller can react.
func cycle_fire_mode() -> bool:
	if not has_selector():
		return false
	fire_mode_index = (fire_mode_index + 1) % fire_modes.size()
	# Flipping the selector while the trigger is held must not release a round:
	# semi-auto requires a fresh press, so consume the current one.
	trigger_released = false
	return true

func reset_recoil() -> void:
	_recoil_heat = 0.0
	_kick_offset = 0.0
	_kick_velocity = 0.0
	_kick_pitch = 0.0
	_kick_pitch_velocity = 0.0
	_fire_cooldown = 0.0
	_shot_animation_timer = 0.0
	_end_muzzle_flash()
	if model_root != null:
		model_root.position.z = 0.0
		model_root.rotation.x = 0.0
	# A holstered weapon still runs its AnimationPlayer, so without this it would be
	# frozen on the last frame of a compressed shot cycle when it is drawn again.
	_play_animation(idle_animation)

func _ready() -> void:
	_build_model()

func _build_model() -> void:
	model_root = Node3D.new()
	model_root.top_level = false
	add_child(model_root)
	# Ignore the editor resource cache: every Play run must use the transform that
	# was actually saved in the editable weapon scene.
	var resource := ResourceLoader.load(model_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if resource is PackedScene:
		var imported := (resource as PackedScene).instantiate()
		model_root.add_child(imported)
		var tuning_camera := imported.find_child("WeaponTuningCamera", true, false) as Camera3D
		if tuning_camera != null:
			authored_camera = tuning_camera
			authored_camera_fov = tuning_camera.fov
			authored_camera_keep_aspect = tuning_camera.keep_aspect
			# Captured here rather than inside the deferred reparent below so the
			# framing can never pick up a frame of sway or recoil: nothing has moved
			# yet at _ready() time, so this is the authored rest pose by definition.
			# near/far are deliberately NOT overwritten - they are authored too.
			_authored_camera_rest = tuning_camera.global_transform
			# This exact authored camera renders the weapon viewport. Reparenting it
			# outside WeaponManager preserves the saved editor framing while allowing
			# the weapon/model to sway and push back independently beneath it.
			tuning_camera.current = false
			call_deferred("_detach_authored_camera")
		model_root.name = "%sRuntimeRoot" % weapon_name
		# MuzzlePoint is authored in the weapon scene next to the camera, so the flash
		# origin is draggable in the editor instead of being a magic number in here.
		muzzle = imported.find_child("MuzzlePoint", true, false) as Marker3D
		_bind_animation_player(imported)
		_play_animation(idle_animation)
	else:
		_build_fallback_mesh()
	if muzzle == null:
		muzzle = Marker3D.new()
		muzzle.name = "MuzzleFallback"
		muzzle.position = Vector3(0.21, 0.02, -0.8 if weapon_name == "AK-74M" else -0.47)
		model_root.add_child(muzzle)
	muzzle_light = OmniLight3D.new()
	muzzle_light.name = "MuzzleLight"
	muzzle_light.light_color = Color("ffc182")
	muzzle_light.light_energy = 0.0
	muzzle_light.omni_range = 6.5
	muzzle_light.omni_attenuation = 1.4
	muzzle_light.shadow_enabled = false
	muzzle.add_child(muzzle_light)
	_build_muzzle_flash()
	_build_shot_audio()

func _bind_animation_player(imported: Node) -> void:
	for node: Node in imported.find_children("*", "AnimationPlayer", true, false):
		var candidate := node as AnimationPlayer
		if candidate.has_animation(idle_animation) or candidate.has_animation(shot_animation):
			_animation_player = candidate
			break
	if _animation_player == null:
		return
	# Every clip imports with looping off, so idle used to freeze on its final frame
	# and the gun stayed stuck in whatever pose the last shot left behind.
	if _animation_player.has_animation(idle_animation):
		_animation_player.get_animation(idle_animation).loop_mode = Animation.LOOP_LINEAR
	if _animation_player.has_animation(shot_animation):
		var shot := _animation_player.get_animation(shot_animation)
		shot.loop_mode = Animation.LOOP_NONE
		_shot_animation_length = shot.length

func _build_muzzle_flash() -> void:
	var shader := load("res://shaders/muzzle_flash.gdshader") as Shader
	if shader == null or muzzle == null:
		return
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = shader
	_flash_material.set_shader_parameter("progress", 1.0)
	_flash_root = Node3D.new()
	_flash_root.name = "MuzzleFlash"
	_flash_root.visible = false
	muzzle.add_child(_flash_root)
	# A flat billboard reads as a sticker from the side, so the flame is built from
	# two quads crossed along the barrel axis plus one disc facing the shooter.
	_flash_petals = Node3D.new()
	_flash_petals.name = "Petals"
	_flash_petals.position = Vector3(0.0, 0.0, -muzzle_flash_size * 0.5)
	_flash_root.add_child(_flash_petals)
	_flash_petals.add_child(_build_flash_quad("PetalVertical", Vector2(muzzle_flash_size, muzzle_flash_size * 0.78), Vector3(0.0, PI * 0.5, 0.0)))
	_flash_petals.add_child(_build_flash_quad("PetalHorizontal", Vector2(muzzle_flash_size, muzzle_flash_size * 0.78), Vector3(-PI * 0.5, 0.0, 0.0)))
	var bloom := _build_flash_quad("Bloom", Vector2(muzzle_flash_size * 0.9, muzzle_flash_size * 0.9), Vector3.ZERO)
	bloom.position = Vector3(0.0, 0.0, -0.015)
	_flash_root.add_child(bloom)

func _build_flash_quad(quad_name: String, size: Vector2, quad_rotation: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = quad_name
	var quad := QuadMesh.new()
	quad.size = size
	instance.mesh = quad
	instance.rotation = quad_rotation
	instance.material_override = _flash_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 1.0
	return instance

func _build_shot_audio() -> void:
	# Deliberately NOT AudioStreamPlayer3D: the viewmodel is rendered inside a
	# SubViewport with own_world_3d, and that viewport has no 3D audio listener,
	# so positional players parented under it output complete silence. The
	# shooter's own gun sits at the listener anyway, so it needs no attenuation.
	var stream_path := "res://assets/audio/weapons/ak_fire_real.ogg" if weapon_name == "AK-74M" else "res://assets/audio/weapons/pistol_fire_real.ogg"
	var stream := load(stream_path) as AudioStream
	for index: int in SHOT_VOICE_COUNT:
		var voice := AudioStreamPlayer.new()
		voice.name = "ShotVoice%d" % index
		voice.stream = stream
		# Both source recordings peak around -6 dBFS, so this stays under clipping
		# even when several tails overlap during a burst.
		voice.volume_db = 4.0
		add_child(voice)
		_shot_voices.append(voice)

func _play_shot_audio() -> void:
	if _shot_voices.is_empty():
		return
	var voice := _shot_voices[_shot_voice_index]
	_shot_voice_index = (_shot_voice_index + 1) % _shot_voices.size()
	voice.pitch_scale = randf_range(0.97, 1.04)
	voice.play()

func set_authored_camera_active(enabled: bool) -> void:
	if authored_camera != null:
		authored_camera.current = enabled

func _detach_authored_camera() -> void:
	if authored_camera == null or not is_instance_valid(authored_camera):
		return
	var weapon_viewport := get_viewport()
	if weapon_viewport == null or authored_camera.get_parent() == weapon_viewport:
		return
	authored_camera.reparent(weapon_viewport, false)
	# The rest transform was captured before anything could sway, so the framing the
	# player sees is exactly the framing saved in the weapon scene.
	authored_camera.transform = _authored_camera_rest
	authored_camera.name = "%s_WeaponCamera" % weapon_name.replace("-", "_")
	# _select() may have run before this deferred tree operation. Restore the
	# authoritative state after reparenting because a viewport owns one camera.
	var manager := get_parent() as WeaponManager
	if manager != null:
		authored_camera.current = manager.weapons.find(self) == manager.current_index

func _build_fallback_mesh() -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.16, 0.75)
	mesh_instance.mesh = box
	mesh_instance.position = Vector3(0.22, -0.2, -0.65)
	model_root.add_child(mesh_instance)

func try_fire(delta: float) -> void:
	# Carrying the remainder over instead of stamping a new deadline every shot
	# keeps the average rate honest even though _process quantises to frames.
	_fire_cooldown = maxf(_fire_cooldown - minf(delta, 0.25), 0.0)
	if not Input.is_action_pressed("fire"):
		trigger_released = true
		return
	if reloading or _fire_cooldown > 0.0:
		return
	if not is_automatic() and not trigger_released:
		return
	trigger_released = false
	_fire_cooldown += 60.0 / maxf(rounds_per_minute, 1.0)
	if ammo <= 0:
		return
	ammo -= 1
	_fire_hitscan()
	_muzzle_flash()
	_apply_recoil()
	_play_shot_audio()
	_play_shot_animation()

func _play_shot_animation() -> void:
	if _animation_player == null or not _animation_player.has_animation(shot_animation):
		return
	var interval: float = 60.0 / maxf(rounds_per_minute, 1.0)
	_shot_animation_timer = interval
	# One complete bolt cycle per round. Rig|AK_Shot runs 0.317 s while the interval
	# at 650 RPM is 0.092 s, so at normal speed the bolt finished roughly once every
	# three or four rounds and the cycling visibly lagged behind the shots.
	var speed: float = 1.0
	if _shot_animation_length > 0.0:
		speed = clampf(_shot_animation_length / interval, 1.0, 8.0)
	_animation_player.speed_scale = speed
	_animation_player.play(shot_animation)
	# play() on the clip that is already running is a no-op, and during automatic fire
	# the previous stroke is always still running, so this seek is what actually
	# restarts the cycle for every single shot.
	_animation_player.seek(0.0, true)

func _apply_recoil() -> void:
	_recoil_heat = minf(_recoil_heat + recoil_heat_per_shot, 1.0)
	var control: float = 0.72 if aiming else 1.0
	var heat_scale: float = 0.78 + 0.55 * _recoil_heat
	# Viewmodel: a velocity impulse into the spring integrated in _process. The
	# gun travels back along +Z (away from the muzzle) and the barrel flips up.
	_kick_velocity += recoil_kick_speed * heat_scale * control
	_kick_pitch_velocity += recoil_pitch_speed * heat_scale * control
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player == null:
		return
	# The AK walks up and to the right; the random term keeps the pattern from
	# being a memorisable straight line.
	var pitch_kick: float = (recoil_pitch_degrees + recoil_pitch_climb_degrees * _recoil_heat) * control
	var yaw_kick: float = (recoil_yaw_bias_degrees + randf_range(-recoil_yaw_spread_degrees, recoil_yaw_spread_degrees)) * control
	player.apply_weapon_recoil(pitch_kick, yaw_kick)

func _process(delta: float) -> void:
	_recoil_heat = maxf(_recoil_heat - recoil_heat_decay * delta, 0.0)
	_update_muzzle_flash(delta)
	if _shot_animation_timer > 0.0:
		_shot_animation_timer = maxf(_shot_animation_timer - delta, 0.0)
		# The cycle finished and no new round followed, so drop back to the looping
		# idle instead of leaving the gun parked on the last frame of the shot.
		if _shot_animation_timer <= 0.0 and not reloading:
			_play_animation(idle_animation)
	if model_root == null:
		return
	var step: float = minf(delta, 1.0 / 30.0)
	var kick_acceleration: float = -_kick_offset * recoil_spring_stiffness - _kick_velocity * recoil_spring_damping
	_kick_velocity += kick_acceleration * step
	_kick_offset += _kick_velocity * step
	var pitch_acceleration: float = -_kick_pitch * recoil_spring_stiffness - _kick_pitch_velocity * recoil_spring_damping
	_kick_pitch_velocity += pitch_acceleration * step
	_kick_pitch += _kick_pitch_velocity * step
	model_root.position.z = _kick_offset
	model_root.rotation.x = _kick_pitch

func _update_muzzle_flash(delta: float) -> void:
	if _flash_timer <= 0.0:
		return
	_flash_timer = maxf(_flash_timer - delta, 0.0)
	var progress: float = 1.0 - _flash_timer / MUZZLE_FLASH_SECONDS
	if _flash_material != null:
		_flash_material.set_shader_parameter("progress", progress)
	if muzzle_light != null:
		var falloff: float = 1.0 - progress
		muzzle_light.light_energy = muzzle_flash_energy * falloff * falloff
	if _flash_timer <= 0.0:
		_end_muzzle_flash()

func _end_muzzle_flash() -> void:
	_flash_timer = 0.0
	if _flash_material != null:
		_flash_material.set_shader_parameter("progress", 1.0)
	if _flash_root != null:
		_flash_root.visible = false
	if muzzle_light != null:
		muzzle_light.light_energy = 0.0

func _fire_hitscan() -> void:
	# The viewmodel now lives in its own SubViewport/World3D, so aim and the shot
	# ray must come from the player's MAIN camera and world, not get_viewport().
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player == null or player.camera == null:
		return
	var camera := player.camera
	var center := camera.get_viewport().get_visible_rect().size * 0.5
	var origin := camera.project_ray_origin(center)
	var direction := camera.project_ray_normal(center)
	# Cone spread built from the camera's own right/up axes, so the deviation is
	# always perpendicular to the shot instead of also shortening the ray.
	var base_spread: float = 0.0009 if aiming else (0.0055 if weapon_name == "AK-74M" else 0.004)
	var spread: float = base_spread * (1.0 + 2.6 * _recoil_heat)
	var basis := camera.global_transform.basis
	direction = (direction
		+ basis.x * randf_range(-spread, spread)
		+ basis.y * randf_range(-spread, spread)).normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 120.0)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider: Object = hit["collider"]
		if collider.has_method("apply_damage"):
			collider.call("apply_damage", damage, String(hit.get("shape", "torso")))
		_spawn_impact(hit["position"], hit["normal"])

func _spawn_impact(point: Vector3, normal: Vector3) -> void:
	# The decal must land in the LEVEL's world, never under the weapon viewport.
	# current_scene is null when a tool script drives the tree directly, so fall
	# back to the node the player is parented under.
	var host: Node = get_tree().current_scene
	if host == null:
		var player := get_tree().get_first_node_in_group("player") as Node
		host = player.get_parent() if player != null else null
	if host == null:
		return
	var impact_root := Node3D.new()
	impact_root.name = "BulletImpact"
	host.add_child(impact_root)
	impact_root.global_position = point + normal * 0.012
	impact_root.quaternion = Quaternion(Vector3.UP, normal.normalized())
	_create_bullet_decal(impact_root)
	_create_impact_particles(impact_root)
	_create_impact_audio(impact_root)
	var timer := get_tree().create_timer(45.0)
	timer.timeout.connect(impact_root.queue_free)

func _create_impact_audio(impact_root: Node3D) -> void:
	# This one IS positional: the impact lives in the level's own World3D, which
	# does have the player camera as its 3D listener, so distance cues work.
	var stream := load("res://assets/audio/impacts/metal.ogg") as AudioStream
	if stream == null:
		return
	var strike := AudioStreamPlayer3D.new()
	strike.name = "ImpactAudio"
	strike.stream = stream
	# The source peaks at -0.9 dBFS, so it needs pulling down rather than up.
	strike.volume_db = -9.0
	strike.unit_size = 6.0
	strike.max_distance = 45.0
	strike.pitch_scale = randf_range(0.88, 1.12)
	impact_root.add_child(strike)
	strike.play()

func _create_bullet_decal(impact_root: Node3D) -> void:
	var albedo := load("res://assets/textures/decals/bullet_hole/bullet_hole_albedo.png") as Texture2D
	var normal_map := load("res://assets/textures/decals/bullet_hole/bullet_hole_normal.png") as Texture2D
	var roughness_map := load("res://assets/textures/decals/bullet_hole/bullet_hole_roughness.png") as Texture2D
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		var decal := Decal.new()
		decal.name = "ProjectedBulletHole"
		decal.size = Vector3(0.24, 0.09, 0.24)
		decal.texture_albedo = albedo
		decal.texture_normal = normal_map
		decal.texture_orm = load("res://assets/textures/decals/bullet_hole/bullet_hole_orm.png") as Texture2D
		decal.upper_fade = 0.12
		decal.lower_fade = 0.12
		impact_root.add_child(decal)
		return
	# Compatibility renderer fallback: a surface-aligned PBR quad remains visible.
	var mark := MeshInstance3D.new()
	mark.name = "BulletHoleQuad"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.24, 0.24)
	quad.orientation = PlaneMesh.FACE_Y
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = albedo
	material.normal_enabled = true
	material.normal_texture = normal_map
	material.roughness_texture = roughness_map
	material.roughness = 0.82
	material.metallic = 0.0
	material.render_priority = 1
	quad.material = material
	mark.mesh = quad
	impact_root.add_child(mark)

func _create_impact_particles(impact_root: Node3D) -> void:
	var debris := GPUParticles3D.new()
	debris.name = "ConcreteDebris"
	debris.amount = 22
	debris.lifetime = 0.72
	debris.one_shot = true
	debris.local_coords = false
	debris.explosiveness = 0.92
	debris.randomness = 0.42
	var debris_process := ParticleProcessMaterial.new()
	debris_process.direction = impact_root.global_transform.basis.y.normalized()
	debris_process.spread = 48.0
	debris_process.initial_velocity_min = 1.2
	debris_process.initial_velocity_max = 3.8
	debris_process.gravity = Vector3(0.0, -7.5, 0.0)
	debris_process.scale_min = 0.45
	debris_process.scale_max = 1.25
	debris_process.color = Color("8a8174")
	debris.process_material = debris_process
	var chip := BoxMesh.new()
	chip.size = Vector3(0.018, 0.012, 0.024)
	var chip_material := StandardMaterial3D.new()
	chip_material.albedo_color = Color("8a8174")
	chip_material.roughness = 0.94
	chip.material = chip_material
	debris.draw_pass_1 = chip
	impact_root.add_child(debris)
	debris.emitting = true

	var dust := GPUParticles3D.new()
	dust.name = "ConcreteDust"
	dust.amount = 14
	dust.lifetime = 1.25
	dust.one_shot = true
	dust.local_coords = false
	dust.explosiveness = 0.78
	dust.randomness = 0.55
	var dust_process := ParticleProcessMaterial.new()
	dust_process.direction = impact_root.global_transform.basis.y.normalized()
	dust_process.spread = 62.0
	dust_process.initial_velocity_min = 0.35
	dust_process.initial_velocity_max = 1.4
	dust_process.gravity = Vector3(0.0, -0.32, 0.0)
	dust_process.scale_min = 0.35
	dust_process.scale_max = 1.0
	dust_process.color = Color(0.48, 0.45, 0.4, 0.34)
	dust.process_material = dust_process
	var dust_quad := QuadMesh.new()
	dust_quad.size = Vector2(0.13, 0.13)
	var dust_material := StandardMaterial3D.new()
	dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dust_material.vertex_color_use_as_albedo = true
	dust_material.albedo_color = Color(0.55, 0.51, 0.45, 0.34)
	dust_quad.material = dust_material
	dust.draw_pass_1 = dust_quad
	impact_root.add_child(dust)
	dust.emitting = true

func _muzzle_flash() -> void:
	# No tween here: at 650 RPM overlapping tweens fought each other over
	# model_root.position.z and left the gun drifting. The flash is a plain timer
	# feeding the shader, and the kick is integrated as a spring in _process.
	_flash_timer = MUZZLE_FLASH_SECONDS
	if _flash_material != null:
		_flash_material.set_shader_parameter("progress", 0.0)
		_flash_material.set_shader_parameter("seed", randf() * TAU)
	if _flash_petals != null:
		# Spin the crossed petals around the barrel axis so no two rounds burn the
		# same shape and the flame does not read as a repeating sprite.
		_flash_petals.rotation.z = randf() * TAU
	if _flash_root != null:
		_flash_root.visible = true
	if muzzle_light != null:
		muzzle_light.light_energy = muzzle_flash_energy

func reload() -> void:
	if reloading or ammo >= magazine_size or reserve <= 0:
		return
	reloading = true
	_play_animation(reload_animation)
	var duration := 2.65 if weapon_name == "AK-74M" else 1.32
	var timer := get_tree().create_timer(duration)
	timer.timeout.connect(_finish_reload)

func _finish_reload() -> void:
	var needed := magazine_size - ammo
	var loaded := mini(needed, reserve)
	ammo += loaded
	reserve -= loaded
	reloading = false
	_play_animation(idle_animation)

func _play_animation(animation_name: String) -> void:
	if _animation_player == null or animation_name.is_empty():
		return
	if not _animation_player.has_animation(animation_name):
		return
	# Idle and reload always run at authored speed; only the shot cycle is compressed.
	_shot_animation_timer = 0.0
	_animation_player.speed_scale = 1.0
	_animation_player.play(animation_name, 0.12)

func set_aiming(value: bool) -> void:
	aiming = value
	var target := Vector3(-0.07, 0.07, -0.08) if aiming else Vector3.ZERO
	position = position.lerp(target, 0.14)
