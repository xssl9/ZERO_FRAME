class_name WeaponBase
extends Node3D

var weapon_name: String = "WEAPON"
var magazine_size: int = 30
var ammo: int = 30
var reserve: int = 90
var rounds_per_minute: float = 600.0
var damage: float = 30.0
var automatic: bool = false
var model_path: String = ""
var idle_animation: String = ""
var reload_animation: String = ""
var last_shot_msec: int = 0
var trigger_released: bool = true
var reloading: bool = false
var aiming: bool = false
var model_root: Node3D
var muzzle: Marker3D
var muzzle_light: OmniLight3D
var shot_audio: AudioStreamPlayer3D
var authored_camera: Camera3D
var authored_camera_fov: float = 96.0
var authored_camera_keep_aspect: Camera3D.KeepAspect = Camera3D.KEEP_HEIGHT

func configure(p_name: String, p_magazine: int, p_ammo: int, p_rpm: float, p_damage: float, p_automatic: bool, p_model: String, p_idle: String, p_reload: String) -> void:
	weapon_name = p_name
	magazine_size = p_magazine
	ammo = p_ammo
	reserve = p_magazine * 3
	rounds_per_minute = p_rpm
	damage = p_damage
	automatic = p_automatic
	model_path = p_model
	idle_animation = p_idle
	reload_animation = p_reload

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
			# This exact authored camera renders the weapon viewport. Reparenting it
			# outside WeaponManager preserves the saved editor framing while allowing
			# the weapon/model to sway and push back independently beneath it.
			tuning_camera.near = 0.01
			tuning_camera.far = 20.0
			tuning_camera.current = false
			call_deferred("_detach_authored_camera")
		model_root.name = "%sRuntimeRoot" % weapon_name
		_play_animation(idle_animation)
	else:
		_build_fallback_mesh()
	muzzle = Marker3D.new()
	muzzle.position = Vector3(0.17, -0.12, -1.35 if weapon_name == "AK-74M" else -0.85)
	add_child(muzzle)
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color("ffb45b")
	muzzle_light.light_energy = 0.0
	muzzle_light.omni_range = 4.0
	muzzle.add_child(muzzle_light)
	shot_audio = AudioStreamPlayer3D.new()
	shot_audio.stream = load("res://assets/audio/weapons/firearm_compact_space_user.mp3") as AudioStream
	shot_audio.max_distance = 75.0
	shot_audio.volume_db = -1.5
	shot_audio.pitch_scale = 0.92 if weapon_name == "AK-74M" else 1.12
	muzzle.add_child(shot_audio)

func set_authored_camera_active(enabled: bool) -> void:
	if authored_camera != null:
		authored_camera.current = enabled

func _detach_authored_camera() -> void:
	if authored_camera == null or not is_instance_valid(authored_camera):
		return
	var weapon_viewport := get_viewport()
	if weapon_viewport == null or authored_camera.get_parent() == weapon_viewport:
		return
	authored_camera.reparent(weapon_viewport, true)
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

func try_fire() -> void:
	var pressed_now := Input.is_action_pressed("fire")
	if not pressed_now:
		trigger_released = true
		return
	if not automatic and not trigger_released:
		return
	var interval := int(60000.0 / rounds_per_minute)
	var now := Time.get_ticks_msec()
	if now - last_shot_msec < interval or reloading:
		return
	trigger_released = false
	last_shot_msec = now
	if ammo <= 0:
		return
	ammo -= 1
	_fire_hitscan()
	_muzzle_flash()
	shot_audio.play()
	_play_animation("Rig|AK_Shot" if weapon_name == "AK-74M" else "Armature|FPS_Pistol_Fire")

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
	var spread := 0.001 if aiming else (0.008 if weapon_name == "AK-74M" else 0.005)
	direction = (direction + Vector3(randf_range(-spread, spread), randf_range(-spread, spread), randf_range(-spread, spread))).normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 120.0)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider: Object = hit["collider"]
		if collider.has_method("apply_damage"):
			collider.call("apply_damage", damage, String(hit.get("shape", "torso")))
		_spawn_impact(hit["position"], hit["normal"])
	player.add_camera_impulse(-2.6 if weapon_name == "AK-74M" else -1.45, randf_range(-0.42, 0.42), randf_range(-0.16, 0.16))

func _spawn_impact(point: Vector3, normal: Vector3) -> void:
	var impact_root := Node3D.new()
	impact_root.name = "BulletImpact"
	get_tree().current_scene.add_child(impact_root)
	impact_root.global_position = point + normal * 0.012
	impact_root.quaternion = Quaternion(Vector3.UP, normal.normalized())
	_create_bullet_decal(impact_root)
	_create_impact_particles(impact_root)
	var timer := get_tree().create_timer(45.0)
	timer.timeout.connect(impact_root.queue_free)

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
	muzzle_light.light_energy = 9.0
	var tween := create_tween()
	tween.tween_property(muzzle_light, "light_energy", 0.0, 0.055)
	var recoil_distance: float = 0.12 if weapon_name == "AK-74M" else 0.075
	model_root.position.z += recoil_distance
	tween.parallel().tween_property(model_root, "position:z", model_root.position.z - recoil_distance, 0.16)

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
	var players := model_root.find_children("*", "AnimationPlayer", true, false)
	for node: Node in players:
		var player := node as AnimationPlayer
		if player.has_animation(animation_name):
			player.play(animation_name)
			return

func set_aiming(value: bool) -> void:
	aiming = value
	var target := Vector3(-0.07, 0.07, -0.08) if aiming else Vector3.ZERO
	position = position.lerp(target, 0.14)
