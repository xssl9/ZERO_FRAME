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
const MUZZLE_FLASH_SECONDS: float = 0.042
# The gas cloud keeps glowing slightly longer than the visible flame, so the lights
# outlive the quads. Still well inside one round at 650 RPM.
const MUZZLE_LIGHT_SECONDS: float = 0.075
# Restarting the smoke puff on every round would delete the previous puff and leave a
# single popping cloud. Firing it every fourth round instead builds a real haze.
const MUZZLE_SMOKE_INTERVAL: float = 0.22


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
# muzzle flips up. Purely cosmetic, but it is what sells the weight. The spring is
# deliberately underdamped (ratio about 0.43), so the rifle snaps and then visibly
# jerks back through its rest pose instead of easing home.
@export var recoil_kick_speed: float = 4.2
@export var recoil_pitch_speed: float = 6.0
@export var recoil_spring_stiffness: float = 300.0
@export var recoil_spring_damping: float = 15.0
# Burst heat: sustained fire climbs harder and scatters wider than the first round.
@export var recoil_heat_per_shot: float = 0.2
@export var recoil_heat_decay: float = 1.7
# How much of WeaponManager's free-aim envelope this weapon gets. A rifle carried at the shoulder
# has room to wander; a pistol held out in front in two hands has much less, which is why a
# sidearm nudges the view on every shot while a rifle absorbs its first few rounds.
@export_range(0.1, 2.0, 0.05) var free_aim_envelope_scale: float = 1.0

@export_category("Muzzle flash")
# Metres across for the crossed flame petals. Scaled per weapon because the pistol
# muzzle sits about half as far from the camera as the rifle's.
@export var muzzle_flash_size: float = 0.34
# Energy of the light inside the weapon viewport: this is what lights the hands and
# the receiver from the muzzle.
@export var muzzle_flash_energy: float = 13.0
# Energy of the twin light placed in the LEVEL's world, which is what actually makes
# walls, floor and props flash. The viewport light cannot reach them: the viewmodel
# lives in its own World3D.
@export var muzzle_flash_world_energy: float = 16.0
@export var muzzle_flash_world_range: float = 9.0
# Strength of the flash the SURFACE shaders draw themselves (the wet-ground smear and the
# reflection in puddles, shaders/muzzle_flash_light.gdshaderinc). Separate from the light
# above because that one is in Godot light units and this one is a shader term.
@export var muzzle_flash_surface_energy: float = 1.8
# How ragged the flame edge is. A muzzle brake with side ports throws more, wider
# tongues than a bare barrel.
@export var muzzle_flash_tongues: float = 9.0
@export var muzzle_sparks_amount: int = 14
@export var muzzle_smoke_amount: int = 10

@export_category("Audio")
# Set by WeaponManager before the weapon enters the tree, because _build_shot_audio
# runs from _ready.
@export var shot_stream_path: String = ""
# The samples are mastered to -1 dBFS, so the voices sit near unity and the hard
# limiter on the Weapons bus catches the overlapping tails of a long burst.
@export var shot_volume_db: float = -1.0
# Everything loud goes through the limited bus rather than straight to Master.
@export var audio_bus: StringName = &"Weapons"
# Magazine change. When this is set, the recording defines how long the reload takes and
# the reload animation is stretched to cover it, so the magazine seats and the bolt is
# released exactly when you hear it happen.
@export var reload_stream_path: String = ""
@export var reload_volume_db: float = -5.0

var _fire_cooldown: float = 0.0
var _recoil_heat: float = 0.0
var _kick_offset: float = 0.0
var _kick_velocity: float = 0.0
var _kick_pitch: float = 0.0
var _kick_pitch_velocity: float = 0.0
# Recoil is not a straight line: the rifle also twists and walks sideways in the hands.
var _kick_roll: float = 0.0
var _kick_roll_velocity: float = 0.0
var _kick_side: float = 0.0
var _kick_side_velocity: float = 0.0
var _aim_pose: Vector3 = Vector3.ZERO
var _shot_voices: Array[AudioStreamPlayer] = []
var _shot_voice_index: int = 0
var _reload_voice: AudioStreamPlayer
var _reload_audio_length: float = 0.0
var _animation_player: AnimationPlayer
var _shot_animation_length: float = 0.0
var _shot_animation_timer: float = 0.0
var _flash_root: Node3D
var _flash_petals: Node3D
var _flash_materials: Array[ShaderMaterial] = []
var _flash_timer: float = 0.0
var _light_timer: float = 0.0
var _flash_gain: float = 1.0
var _sparks: GPUParticles3D
var _smoke: GPUParticles3D
var _smoke_cooldown: float = 0.0
var _world_flash_light: OmniLight3D
var _flash_surface_bus: PhotorealEnvironment
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
	_kick_roll = 0.0
	_kick_roll_velocity = 0.0
	_kick_side = 0.0
	_kick_side_velocity = 0.0
	_fire_cooldown = 0.0
	_shot_animation_timer = 0.0
	_end_muzzle_flash()
	if _reload_voice != null and _reload_voice.playing:
		# Holstering the weapon has to take its reload noise with it, or a switched-away
		# rifle keeps rattling its magazine off screen.
		_reload_voice.stop()
	if model_root != null:
		model_root.position.z = 0.0
		model_root.position.x = 0.0
		model_root.rotation.x = 0.0
		model_root.rotation.z = 0.0
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
	_build_reload_audio()

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
	# Brightness is deliberately modest: the weapon viewport tonemaps with AgX and adds
	# bloom above 1.35, so anything much hotter than this stops being a flame and turns
	# into one white ball with no shape left in it.
	var tongue_material := _build_flash_material(shader, 0.0, muzzle_flash_tongues, 1.0, 13.0)
	var core_material := _build_flash_material(shader, 1.0, 4.0, 0.0, 6.0)
	var glow_material := _build_flash_material(shader, 1.0, 4.0, 0.0, 2.6)
	_flash_root = Node3D.new()
	_flash_root.name = "MuzzleFlash"
	_flash_root.visible = false
	muzzle.add_child(_flash_root)
	# A flat billboard reads as a sticker from the side, so the flame is three quads
	# crossed at 60 degrees around the barrel axis: from any head angle at least one of
	# them is close to face-on, and the pattern still has volume in between.
	_flash_petals = Node3D.new()
	_flash_petals.name = "Petals"
	_flash_petals.position = Vector3(0.0, 0.0, -muzzle_flash_size * 0.52)
	_flash_root.add_child(_flash_petals)
	# Longer than it is tall: powder gas leaves the muzzle as a cone, not a circle.
	var petal_size := Vector2(muzzle_flash_size * 1.3, muzzle_flash_size * 0.72)
	for index: int in 3:
		var spin := Basis(Vector3(0.0, 0.0, 1.0), PI / 3.0 * float(index))
		var petal_basis := spin * Basis(Vector3(0.0, 1.0, 0.0), PI * 0.5)
		_flash_petals.add_child(_build_flash_quad("Petal%d" % index, petal_size, petal_basis, tongue_material))
	# Looking down the barrel the axial petals are edge-on and contribute almost nothing,
	# and that is exactly the shooter's own view. This face-on quad carries the same
	# ragged tongues, so from behind the gun the flash reads as a star and not a ball. It
	# hangs under the petals node so it inherits the per-shot spin and size jitter.
	var star := _build_flash_quad("Star", Vector2(muzzle_flash_size * 0.95, muzzle_flash_size * 0.95), Basis.IDENTITY, tongue_material)
	star.position = Vector3(0.0, 0.0, muzzle_flash_size * 0.17)
	_flash_petals.add_child(star)
	# The white-hot gas ball welded to the muzzle, then a wider dim halo that gives the
	# flash its bloom footprint instead of ending at a hard quad edge.
	var core := _build_flash_quad("Core", Vector2(muzzle_flash_size * 0.3, muzzle_flash_size * 0.3), Basis.IDENTITY, core_material)
	core.position = Vector3(0.0, 0.0, -muzzle_flash_size * 0.14)
	_flash_root.add_child(core)
	var glow := _build_flash_quad("OuterGlow", Vector2(muzzle_flash_size * 0.85, muzzle_flash_size * 0.85), Basis.IDENTITY, glow_material)
	glow.position = Vector3(0.0, 0.0, -0.015)
	_flash_root.add_child(glow)
	_build_muzzle_sparks()
	_build_muzzle_smoke()

func _build_flash_material(shader: Shader, soft_ball: float, tongues: float, turbulence: float, brightness: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("progress", 1.0)
	material.set_shader_parameter("soft_ball", soft_ball)
	material.set_shader_parameter("tongue_count", tongues)
	material.set_shader_parameter("turbulence", turbulence)
	material.set_shader_parameter("brightness", brightness)
	_flash_materials.append(material)
	return material

func _build_flash_quad(quad_name: String, size: Vector2, quad_basis: Basis, material: ShaderMaterial) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = quad_name
	var quad := QuadMesh.new()
	quad.size = size
	instance.mesh = quad
	instance.basis = quad_basis
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 1.0
	return instance

func _build_muzzle_sparks() -> void:
	if muzzle_sparks_amount <= 0:
		return
	_sparks = GPUParticles3D.new()
	_sparks.name = "MuzzleSparks"
	_sparks.amount = muzzle_sparks_amount
	_sparks.lifetime = 0.28
	_sparks.one_shot = true
	_sparks.explosiveness = 1.0
	_sparks.randomness = 0.6
	# World coordinates: an ember keeps its own trajectory while the gun kicks back
	# underneath it, instead of being dragged along by the recoil like a decal.
	_sparks.local_coords = false
	_sparks.emitting = false
	_sparks.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 0.0, -1.0)
	process.spread = 24.0
	process.initial_velocity_min = 2.2
	process.initial_velocity_max = 7.8
	process.gravity = Vector3(0.0, -5.2, 0.0)
	process.damping_min = 3.0
	process.damping_max = 8.0
	process.scale_min = 0.35
	process.scale_max = 1.0
	process.color_ramp = _build_fade_ramp(Color(1.0, 0.86, 0.55), Color(1.0, 0.32, 0.06))
	_sparks.process_material = process
	var ember := QuadMesh.new()
	ember.size = Vector2(muzzle_flash_size * 0.05, muzzle_flash_size * 0.05)
	# HDR albedo on an unshaded material: unshaded ignores emission, so the over-1.0
	# colour is what makes the ember read as a glowing particle and trip the bloom.
	ember.material = _build_particle_material(Color(4.0, 2.1, 0.7), null)
	_sparks.draw_pass_1 = ember
	muzzle.add_child(_sparks)

func _build_muzzle_smoke() -> void:
	if muzzle_smoke_amount <= 0:
		return
	_smoke = GPUParticles3D.new()
	_smoke.name = "MuzzleSmoke"
	_smoke.amount = muzzle_smoke_amount
	_smoke.lifetime = 0.7
	_smoke.one_shot = true
	_smoke.explosiveness = 0.85
	_smoke.randomness = 0.7
	_smoke.local_coords = false
	_smoke.emitting = false
	_smoke.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 0.0, -1.0)
	process.spread = 34.0
	process.initial_velocity_min = 0.45
	process.initial_velocity_max = 1.7
	# Burnt gas is hot, so the puff drifts upwards instead of falling.
	process.gravity = Vector3(0.0, 0.42, 0.0)
	process.damping_min = 1.8
	process.damping_max = 4.2
	process.scale_min = 0.5
	process.scale_max = 1.3
	process.scale_curve = _build_growth_curve()
	process.color_ramp = _build_fade_ramp(Color(0.72, 0.7, 0.68), Color(0.4, 0.39, 0.38))
	_smoke.process_material = process
	var puff := QuadMesh.new()
	puff.size = Vector2(muzzle_flash_size * 0.62, muzzle_flash_size * 0.62)
	puff.material = _build_particle_material(Color(0.62, 0.61, 0.6, 0.5), _build_soft_disc())
	_smoke.draw_pass_1 = puff
	muzzle.add_child(_smoke)

func _build_particle_material(albedo: Color, texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.albedo_color = albedo
	material.albedo_texture = texture
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	return material

# Soft round falloff so a smoke puff is a puff and not a visible square.
func _build_soft_disc() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.45, Color(1.0, 1.0, 1.0, 0.85))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture

func _build_fade_ramp(start_color: Color, end_color: Color) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, start_color)
	gradient.set_color(1, Color(end_color.r, end_color.g, end_color.b, 0.0))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture

# Powder smoke expands quickly and then coasts, so the curve is steep early and flat late.
func _build_growth_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.35, 0.85))
	curve.add_point(Vector2(1.0, 1.0))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture

func _build_shot_audio() -> void:
	# Deliberately NOT AudioStreamPlayer3D: the viewmodel is rendered inside a
	# SubViewport with own_world_3d, and that viewport has no 3D audio listener,
	# so positional players parented under it output complete silence. The
	# shooter's own gun sits at the listener anyway, so it needs no attenuation.
	var stream: AudioStream = null
	if not shot_stream_path.is_empty():
		stream = load(shot_stream_path) as AudioStream
	if stream == null:
		push_warning("%s has no usable shot_stream_path, the report will be silent" % weapon_name)
		return
	for index: int in SHOT_VOICE_COUNT:
		var voice := AudioStreamPlayer.new()
		voice.name = "ShotVoice%d" % index
		voice.stream = stream
		voice.volume_db = shot_volume_db
		voice.bus = _resolved_audio_bus()
		add_child(voice)
		_shot_voices.append(voice)

# Falls back to Master if the layout is missing, otherwise every voice would warn and
# go silent on a machine where default_bus_layout.tres failed to load.
func _resolved_audio_bus() -> StringName:
	if AudioServer.get_bus_index(audio_bus) < 0:
		return &"Master"
	return audio_bus

func _build_reload_audio() -> void:
	if reload_stream_path.is_empty():
		return
	var stream := load(reload_stream_path) as AudioStream
	if stream == null:
		push_warning("%s has no usable reload_stream_path" % weapon_name)
		return
	# One voice, not a pool: a reload cannot overlap itself.
	_reload_voice = AudioStreamPlayer.new()
	_reload_voice.name = "ReloadVoice"
	_reload_voice.stream = stream
	_reload_voice.volume_db = reload_volume_db
	_reload_voice.bus = _resolved_audio_bus()
	add_child(_reload_voice)
	_reload_audio_length = stream.get_length()

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
	_fire_round()

# Fires one round immediately, bypassing input, cooldown and fire mode. Used by the
# capture/diagnostic tools so a shot can be staged without a keyboard.
func fire_once() -> void:
	if ammo <= 0 or reloading:
		return
	_fire_round()

func _fire_round() -> void:
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
	var control: float = 0.86 if aiming else 1.0
	var heat_scale: float = 0.78 + 0.55 * _recoil_heat
	# Viewmodel: a velocity impulse into the spring integrated in _process. The
	# gun travels back along +Z (away from the muzzle) and the barrel flips up.
	_kick_velocity += recoil_kick_speed * heat_scale * control
	_kick_pitch_velocity += recoil_pitch_speed * heat_scale * control
	# Twist and sideways walk, signed randomly per round, so a burst never repeats the same
	# shape and the rifle looks like it is being fought rather than animated.
	_kick_roll_velocity += randf_range(-1.0, 1.0) * recoil_pitch_speed * 0.7 * heat_scale * control
	_kick_side_velocity += randf_range(-1.0, 1.0) * recoil_kick_speed * 0.3 * heat_scale * control
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player == null:
		return
	# Random per round rather than a memorisable pattern: the climb grows with heat, the
	# sideways component is signed noise around a small per-weapon bias.
	var pitch_kick: float = (recoil_pitch_degrees + recoil_pitch_climb_degrees * _recoil_heat) * control * randf_range(0.85, 1.2)
	var yaw_bias: float = recoil_yaw_bias_degrees * control
	var yaw_scatter: float = randf_range(-recoil_yaw_spread_degrees, recoil_yaw_spread_degrees) * control
	# Free aim first. The muzzle wanders inside its envelope while it has room, and only the
	# part that no longer fits reaches the camera and the real aim. The brake's constant
	# sideways push is deliberately left out of that: wrists absorb a random jolt, they do not
	# absorb a force that pulls the same way thirty times in a row, so the burst still walks.
	var yaw_kick: float = yaw_bias
	var manager := get_parent() as WeaponManager
	if manager != null:
		var spill := manager.add_free_aim(deg_to_rad(pitch_kick), deg_to_rad(-yaw_scatter),
			free_aim_envelope_scale)
		pitch_kick = rad_to_deg(spill.y)
		yaw_kick = yaw_bias - rad_to_deg(spill.x)
	else:
		yaw_kick = yaw_bias + yaw_scatter
	if is_zero_approx(pitch_kick) and is_zero_approx(yaw_kick):
		return
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
	# Roll and lateral springs are softer and less damped, so they settle a beat after the
	# main kick has already gone.
	var roll_acceleration: float = -_kick_roll * recoil_spring_stiffness * 0.65 - _kick_roll_velocity * recoil_spring_damping * 0.8
	_kick_roll_velocity += roll_acceleration * step
	_kick_roll += _kick_roll_velocity * step
	var side_acceleration: float = -_kick_side * recoil_spring_stiffness * 0.7 - _kick_side_velocity * recoil_spring_damping * 0.85
	_kick_side_velocity += side_acceleration * step
	_kick_side += _kick_side_velocity * step
	_kick_offset = clampf(_kick_offset, -0.03, 0.13)
	_kick_pitch = clampf(_kick_pitch, -0.07, 0.27)
	model_root.position.z = _kick_offset
	model_root.position.x = _kick_side * 0.12
	model_root.rotation.x = _kick_pitch
	model_root.rotation.z = _kick_roll * 0.7
	# Frame-rate independent sights: the old fixed 0.14 lerp made aiming faster at 144 Hz
	# than at 60.
	position = position.lerp(_aim_pose, 1.0 - exp(-delta * 13.0))

func _update_muzzle_flash(delta: float) -> void:
	if _smoke_cooldown > 0.0:
		_smoke_cooldown = maxf(_smoke_cooldown - delta, 0.0)
	if _light_timer > 0.0:
		_light_timer = maxf(_light_timer - delta, 0.0)
		var light_life: float = _light_timer / MUZZLE_LIGHT_SECONDS
		# Cubed rather than linear: the gas stops radiating far faster than it lit up,
		# so a linear fade reads as a lamp being switched off instead of a flash.
		var falloff: float = light_life * light_life * light_life
		if muzzle_light != null:
			muzzle_light.light_energy = muzzle_flash_energy * _flash_gain * falloff
		if _world_flash_light != null and is_instance_valid(_world_flash_light):
			_world_flash_light.light_energy = muzzle_flash_world_energy * _flash_gain * falloff
		_push_surface_flash(falloff)
	if _flash_timer <= 0.0:
		return
	_flash_timer = maxf(_flash_timer - delta, 0.0)
	var progress: float = 1.0 - _flash_timer / MUZZLE_FLASH_SECONDS
	for material: ShaderMaterial in _flash_materials:
		material.set_shader_parameter("progress", progress)
	if _flash_timer <= 0.0:
		_hide_flash_quads()

func _hide_flash_quads() -> void:
	_flash_timer = 0.0
	for material: ShaderMaterial in _flash_materials:
		material.set_shader_parameter("progress", 1.0)
	if _flash_root != null:
		_flash_root.visible = false

func _end_muzzle_flash() -> void:
	_hide_flash_quads()
	_light_timer = 0.0
	_smoke_cooldown = 0.0
	if muzzle_light != null:
		muzzle_light.light_energy = 0.0
	if _world_flash_light != null and is_instance_valid(_world_flash_light):
		_world_flash_light.light_energy = 0.0
	_push_surface_flash(0.0)
	if _sparks != null:
		_sparks.emitting = false
	if _smoke != null:
		_smoke.emitting = false

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
	# Free aim means the bullet goes where the muzzle is pointing, not where the middle of
	# the screen is: the wander has to move the ray as well as the viewmodel.
	var manager := get_parent() as WeaponManager
	if manager != null:
		var free_aim := manager.free_aim()
		direction = direction.rotated(basis.x.normalized(), free_aim.y).rotated(Vector3.UP, free_aim.x)
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
	strike.bus = _resolved_audio_bus()
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
	_light_timer = MUZZLE_LIGHT_SECONDS
	# Real flashes vary round to round. Size, brightness and shape all jitter, and
	# roughly every sixth round throws a noticeably bigger flame the way an unevenly
	# burning powder charge does.
	_flash_gain = randf_range(0.82, 1.16)
	if randf() < 0.16:
		_flash_gain *= 1.45
	for material: ShaderMaterial in _flash_materials:
		material.set_shader_parameter("progress", 0.0)
		material.set_shader_parameter("seed", randf() * 64.0)
	if _flash_petals != null:
		# Spin the crossed petals around the barrel axis so no two rounds burn the same
		# shape and the flame does not read as a repeating sprite.
		_flash_petals.rotation.z = randf() * TAU
		_flash_petals.scale = Vector3.ONE * _flash_gain
	if _flash_root != null:
		_flash_root.visible = true
	if muzzle_light != null:
		muzzle_light.light_energy = muzzle_flash_energy * _flash_gain
	_flash_world_light()
	if _sparks != null:
		_sparks.restart()
	# restart() wipes the previous puff, so gating keeps a burst leaving one drifting
	# cloud instead of a single popping puff that resets every 92 ms.
	if _smoke != null and _smoke_cooldown <= 0.0:
		_smoke_cooldown = MUZZLE_SMOKE_INTERVAL
		_smoke.restart()

# The viewmodel light only ever reaches the hands and the receiver, because the
# viewmodel lives in its own World3D. This twin light is the one that makes the level
# flash, and it is placed by mapping the muzzle out of weapon-camera space.
func _flash_world_light() -> void:
	if muzzle == null:
		return
	if _world_flash_light == null or not is_instance_valid(_world_flash_light):
		_create_world_flash_light()
	if _world_flash_light == null:
		return
	var view_camera: Camera3D = authored_camera
	var weapon_viewport := get_viewport()
	if weapon_viewport != null and weapon_viewport.get_camera_3d() != null:
		view_camera = weapon_viewport.get_camera_3d()
	if view_camera != null:
		# The muzzle taken relative to the weapon camera is exactly where the muzzle
		# sits relative to the player camera out in the level, so the same offset can
		# be reused verbatim as a local transform under the world camera.
		_world_flash_light.transform = view_camera.global_transform.affine_inverse() * muzzle.global_transform
	_world_flash_light.light_energy = muzzle_flash_world_energy * _flash_gain
	_push_surface_flash(1.0)

# The level's own surfaces draw the flash through a shader include, which is how the wet
# ground gets a smeared highlight and the puddles get a reflection the SSR pass can never
# find: the flame itself is in the weapon viewport, not on screen.
func _push_surface_flash(falloff: float) -> void:
	if _flash_surface_bus == null or not is_instance_valid(_flash_surface_bus):
		_flash_surface_bus = get_tree().get_first_node_in_group("photoreal_environment") as PhotorealEnvironment
		if _flash_surface_bus == null:
			return
	if _world_flash_light == null or not is_instance_valid(_world_flash_light):
		return
	_flash_surface_bus.push_muzzle_flash(
		_world_flash_light.global_position,
		_world_flash_light.light_color,
		muzzle_flash_surface_energy * _flash_gain * falloff,
		muzzle_flash_world_range)

func _create_world_flash_light() -> void:
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player == null or player.camera == null:
		return
	_world_flash_light = OmniLight3D.new()
	_world_flash_light.name = "%s_MuzzleFlashWorld" % weapon_name.replace("-", "_")
	_world_flash_light.light_color = Color("ffcb96")
	_world_flash_light.light_energy = 0.0
	_world_flash_light.omni_range = muzzle_flash_world_range
	_world_flash_light.omni_attenuation = 1.6
	# The flash has to light the volumetric fog too, so every round puts a visible pulse
	# into the air and the light shafts around the shooter, not just on the walls.
	_world_flash_light.light_volumetric_fog_energy = 2.4
	# Shadows stay off deliberately: a 75 ms light would force a full shadow map update
	# every round, and the flash is far too short for anyone to resolve its shadows.
	_world_flash_light.shadow_enabled = false
	player.camera.add_child(_world_flash_light)

func reload() -> void:
	if reloading or ammo >= magazine_size or reserve <= 0:
		return
	reloading = true
	# The recording is the authority on how long a magazine change takes: 4.2 s of real
	# mag-out, mag-in and bolt-release for the AK. The animation is then stretched to
	# cover exactly that, so the hands are not finished a second and a half early.
	var duration := 2.65 if weapon_name == "AK-74M" else 1.32
	if _reload_audio_length > 0.0:
		duration = _reload_audio_length
		_reload_voice.play()
	var animation_speed := 1.0
	if _animation_player != null and _animation_player.has_animation(reload_animation):
		var clip_length := _animation_player.get_animation(reload_animation).length
		if clip_length > 0.0 and duration > 0.0:
			animation_speed = clampf(clip_length / duration, 0.35, 3.0)
	_play_animation(reload_animation, animation_speed)
	var timer := get_tree().create_timer(duration)
	timer.timeout.connect(_finish_reload)

func _finish_reload() -> void:
	var needed := magazine_size - ammo
	var loaded := mini(needed, reserve)
	ammo += loaded
	reserve -= loaded
	reloading = false
	_play_animation(idle_animation)

func _play_animation(animation_name: String, speed: float = 1.0) -> void:
	if _animation_player == null or animation_name.is_empty():
		return
	if not _animation_player.has_animation(animation_name):
		return
	# Idle runs at authored speed; the shot cycle is compressed to the fire interval and
	# the reload is stretched to the length of its recording.
	_shot_animation_timer = 0.0
	_animation_player.speed_scale = speed
	_animation_player.play(animation_name, 0.12)

func set_aiming(value: bool) -> void:
	aiming = value
	# Only the target moves here; _process walks the weapon towards it with delta, so the
	# sights come up at the same speed on any monitor.
	_aim_pose = Vector3(-0.07, 0.07, -0.08) if aiming else Vector3.ZERO
