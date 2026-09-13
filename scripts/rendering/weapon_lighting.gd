class_name WeaponLighting
extends Node

## Mirrors world lighting into the existing isolated viewmodel. No new viewport,
## no exposure floor, no additional studio fill. Up to four nearby practical lights.
var player: PlayerController
var host: PhotorealEnvironment
var sun: DirectionalLight3D
var _sources: Array[Light3D] = []
var _mirrors: Dictionary = {}
var _sun_visibility: float = 1.0
var _filtered_sun_visibility: float = 1.0
var _timer: float = 0.0
var _world_probes: Array[ReflectionProbe] = []
var _weapon_probe: ReflectionProbe = null

func configure(owner_player: PlayerController, environment: PhotorealEnvironment, world_sun: DirectionalLight3D) -> void:
	player = owner_player
	host = environment
	sun = world_sun
	player.weapon_environment.environment = player.weapon_environment.environment.duplicate() as Environment
	for node: Node in host.get_parent().find_children("*", "Light3D", true, false):
		if node.get_viewport() == player.get_viewport() and (node is OmniLight3D or node is SpotLight3D):
			_sources.append(node as Light3D)
	for node: Node in host.get_parent().find_children("*", "ReflectionProbe", true, false):
		if node.get_viewport() == player.get_viewport():
			_world_probes.append(node as ReflectionProbe)

func _physics_process(delta: float) -> void:
	if player == null or host == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.2
	var eye := player.camera.global_position
	var space := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye, eye + Vector3.UP)
	query.exclude = [player.get_rid()]
	if sun != null and sun.shadow_enabled:
		query.to = eye + sun.global_basis.z.normalized() * 100.0
		_sun_visibility = 1.0 if space.intersect_ray(query).is_empty() else 0.0
	else:
		_sun_visibility = 1.0
	var selected: Array[Light3D] = []
	for light: Light3D in _sources:
		if not is_instance_valid(light) or not light.is_visible_in_tree() or light.light_energy <= 0.0:
			continue
		var radius: float = (light as OmniLight3D).omni_range if light is OmniLight3D else (light as SpotLight3D).spot_range
		if eye.distance_to(light.global_position) > radius:
			continue
		selected.append(light)
	selected.sort_custom(func(a: Light3D, b: Light3D) -> bool:
		return eye.distance_squared_to(a.global_position) < eye.distance_squared_to(b.global_position))
	if selected.size() > 4:
		selected.resize(4)
	for source: Light3D in _mirrors.keys():
		if not selected.has(source):
			(_mirrors[source] as Light3D).queue_free()
			_mirrors.erase(source)
	for source: Light3D in selected:
		if not _mirrors.has(source):
			var mirror: Light3D = SpotLight3D.new() if source is SpotLight3D else OmniLight3D.new()
			mirror.name = "WorldPractical"
			player.weapon_camera.get_viewport().add_child(mirror)
			_mirrors[source] = mirror
		query.to = source.global_position
		# End before the lamp's own housing. This rejects light through walls, but
		# cannot reproduce per-pixel world shadows inside a separate World3D.
		query.to = query.to.move_toward(eye, 0.12)
		(_mirrors[source] as Light3D).visible = space.intersect_ray(query).is_empty()

func _process(delta: float) -> void:
	if player == null or host == null:
		return
	_filtered_sun_visibility = lerpf(_filtered_sun_visibility, _sun_visibility, 1.0 - exp(-maxf(delta, 0.0) * 18.0))
	var world := host.environment
	var view := player.weapon_environment.environment
	view.tonemap_mode = world.tonemap_mode
	view.tonemap_exposure = world.tonemap_exposure
	view.adjustment_enabled = false
	view.glow_enabled = world.glow_enabled
	# One photographic response: no extra studio fill or separate bloom on the gun.
	view.glow_blend_mode = world.glow_blend_mode
	view.glow_intensity = world.glow_intensity
	view.glow_strength = world.glow_strength
	view.glow_bloom = world.glow_bloom
	view.glow_hdr_threshold = world.glow_hdr_threshold
	view.glow_hdr_scale = world.glow_hdr_scale
	view.background_energy_multiplier = world.background_energy_multiplier
	view.sky = world.sky
	view.ambient_light_source = world.ambient_light_source
	view.ambient_light_color = world.ambient_light_color
	view.ambient_light_energy = world.ambient_light_energy
	view.ambient_light_sky_contribution = world.ambient_light_sky_contribution
	view.reflected_light_source = world.reflected_light_source
	var camera := player.weapon_camera.get_viewport().get_camera_3d()
	if camera == null:
		return
	var mapping := camera.global_transform * player.camera.global_transform.affine_inverse()
	view.sky_rotation = (mapping.basis.orthonormalized() * Basis.from_euler(world.sky_rotation)).get_euler()
	var high := host.resolved_quality >= PhotorealEnvironment.QualityPreset.HIGH
	var viewport := camera.get_viewport()
	# MSAA on the isolated gun avoids TAA trails on fast recoil and transparent edges.
	viewport.use_taa = false
	viewport.msaa_3d = Viewport.MSAA_4X if high else Viewport.MSAA_2X
	if sun != null and player.weapon_key_light != null:
		var key := player.weapon_key_light
		key.global_basis = mapping.basis.orthonormalized() * sun.global_basis.orthonormalized()
		key.light_color = sun.light_color
		# Sun visibility: 0 when occluded (indoors), 1 when in direct sun.
		# Smooth the transition to avoid a hard cut when crossing a doorway.
		key.light_energy = sun.light_energy * _filtered_sun_visibility
		key.light_angular_distance = sun.light_angular_distance
		key.shadow_enabled = high
		key.directional_shadow_max_distance = 4.0
	for source: Light3D in _mirrors:
		var mirror := _mirrors[source] as Light3D
		mirror.global_transform = mapping * source.global_transform
		mirror.light_color = source.light_color
		mirror.light_energy = source.light_energy
		mirror.light_specular = source.light_specular
		mirror.shadow_enabled = high and source.shadow_enabled
		if mirror is OmniLight3D:
			mirror.omni_range = (source as OmniLight3D).omni_range
			mirror.omni_attenuation = (source as OmniLight3D).omni_attenuation
		else:
			mirror.spot_range = (source as SpotLight3D).spot_range
			mirror.spot_angle = (source as SpotLight3D).spot_angle
			mirror.spot_attenuation = (source as SpotLight3D).spot_attenuation
			mirror.spot_angle_attenuation = (source as SpotLight3D).spot_angle_attenuation

	# Relay the nearest world reflection probe into the weapon viewport so metallic
	# surfaces (AK-74M receiver, barrel) reflect the surrounding room instead of void.
	if _world_probes.size() > 0:
		var nearest: ReflectionProbe = null
		var best_dist := INF
		var eye := player.camera.global_position
		for probe: ReflectionProbe in _world_probes:
			if not is_instance_valid(probe) or not probe.is_visible_in_tree():
				continue
			var d := eye.distance_squared_to(probe.global_position)
			if d < best_dist:
				best_dist = d
				nearest = probe
		if nearest != null:
			if _weapon_probe == null:
				_weapon_probe = ReflectionProbe.new()
				_weapon_probe.name = "WeaponReflectionProbe"
				_weapon_probe.interior = true
				_weapon_probe.box_projection = true
				_weapon_probe.enable_shadows = false
				player.weapon_camera.get_viewport().add_child(_weapon_probe)
			_weapon_probe.global_transform = mapping * nearest.global_transform
			_weapon_probe.size = nearest.size
			_weapon_probe.max_distance = nearest.max_distance

func _exit_tree() -> void:
	for mirror: Light3D in _mirrors.values():
		if is_instance_valid(mirror):
			mirror.queue_free()
	if is_instance_valid(_weapon_probe):
		_weapon_probe.queue_free()
