class_name BloodEffects
extends Node3D

## One bounded cosmetic pool per level. No particle positions travel over RPC.
const MAX_BURSTS := 24
const MAX_STAINS := 96
const MAX_WOUND_MARKS := 64
const MAX_RAYS_PER_FRAME := 12
const STAIN_LIFETIME := 90.0
var bursts: Array[GPUParticles3D] = []
var stains: Array[Decal] = []
var _burst_times: Array[float] = []
var _clock := 0.0
var _ray_frame := -1
var _ray_count := 0
var _texture: ImageTexture
var _orm: ImageTexture
var _dry_orm: ImageTexture
var _drop_mesh: QuadMesh
var _stain_clock := 0.0

static func for_node(node: Node) -> BloodEffects:
	# Scope to the owning level, including test levels not set as current_scene.
	var level := node
	while level.get_parent() != null and level.get_parent() != node.get_tree().root:
		level = level.get_parent()
	var existing := level.get_node_or_null("BloodEffects") as BloodEffects
	if existing != null:
		return existing
	var pool := BloodEffects.new()
	pool.name = "BloodEffects"
	level.add_child(pool)
	return pool

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	# Shared organic coverage: a broken rim and satellite droplets, no opaque quad.
	var pixels := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 71031
	var satellites: Array[Vector3] = []
	for i: int in 28:
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(0.48, 0.9)
		satellites.append(Vector3(cos(angle) * radius, sin(angle) * radius, rng.randf_range(0.012, 0.05)))
	for y: int in 128:
		for x: int in 128:
			var p := (Vector2(x, y) + Vector2.ONE * 0.5) / 64.0 - Vector2.ONE
			var angle := p.angle()
			var edge := 0.51 + 0.065 * sin(angle * 7.0) + 0.03 * sin(angle * 17.0 + 0.7)
			var alpha := 1.0 - smoothstep(edge - 0.02, edge + 0.01, p.length())
			for drop: Vector3 in satellites:
				alpha = maxf(alpha, 1.0 - smoothstep(drop.z * 0.65, drop.z, p.distance_to(Vector2(drop.x, drop.y))))
			var thickness := clampf(1.0 - p.length() / 0.6, 0.0, 1.0)
			pixels.set_pixel(x, y, Color(lerpf(0.24, 0.075, thickness), 0.006, 0.009, alpha))
	pixels.generate_mipmaps()
	_texture = ImageTexture.create_from_image(pixels)
	var orm_image := Image.create(4, 4, false, Image.FORMAT_RGB8)
	orm_image.fill(Color(1.0, 0.23, 0.0))
	_orm = ImageTexture.create_from_image(orm_image)
	orm_image.fill(Color(1.0, 0.75, 0.0))
	_dry_orm = ImageTexture.create_from_image(orm_image)
	_drop_mesh = QuadMesh.new()
	_drop_mesh.size = Vector2(0.012, 0.025)
	var material := StandardMaterial3D.new()
	material.albedo_texture = _texture
	material.albedo_color = Color(0.7, 0.4, 0.4)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.25
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.roughness = 0.3
	_drop_mesh.material = material

func splash(point: Vector3, direction: Vector3, strength: float = 1.0) -> void:
	var slot := -1
	for i: int in bursts.size():
		if _clock >= _burst_times[i]:
			slot = i
			break
	if slot < 0:
		if bursts.size() >= MAX_BURSTS:
			return
		slot = bursts.size()
		var emitter := GPUParticles3D.new()
		emitter.emitting = false
		emitter.one_shot = true
		emitter.explosiveness = 0.95
		emitter.amount = 24
		emitter.lifetime = 0.48
		emitter.local_coords = false
		emitter.draw_pass_1 = _drop_mesh
		emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		emitter.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
		var process := ParticleProcessMaterial.new()
		process.gravity = Vector3(0, -9.8, 0)
		process.spread = 32.0
		process.scale_min = 0.35
		process.scale_max = 1.0
		emitter.process_material = process
		add_child(emitter)
		bursts.append(emitter)
		_burst_times.append(0.0)
	var emitter := bursts[slot]
	emitter.global_position = point
	var process := emitter.process_material as ParticleProcessMaterial
	process.direction = direction.normalized()
	process.initial_velocity_min = 0.4 * strength
	process.initial_velocity_max = 2.8 * strength
	emitter.restart()
	emitter.emitting = true
	_burst_times[slot] = _clock + 0.6

func trace(from: Vector3, to: Vector3) -> Dictionary:
	var frame := Engine.get_physics_frames()
	if frame != _ray_frame:
		_ray_frame = frame
		_ray_count = 0
	if _ray_count >= MAX_RAYS_PER_FRAME:
		return {}
	_ray_count += 1
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	# World only: bodies and character capsules must not receive floor deposits.
	var excluded: Array[RID] = []
	for player: Node in get_tree().get_nodes_in_group("player"):
		if player is CollisionObject3D:
			excluded.append((player as CollisionObject3D).get_rid())
	query.exclude = excluded
	return get_world_3d().direct_space_state.intersect_ray(query)

func deposit(hit: Dictionary, size: float, merge: bool = true) -> Decal:
	if hit.is_empty() or (hit.normal as Vector3).length_squared() < 0.5:
		return null
	var point: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	if merge:
		for stain: Decal in stains:
			if stain.visible and stain.global_position.distance_squared_to(point) < 0.025 and stain.global_basis.y.dot(normal) > 0.9:
				var grown := minf(stain.size.x + 0.012, 0.65)
				stain.size = Vector3(grown, 0.12, grown)
				stain.set_meta("born", _clock)
				return stain
	var decal: Decal
	if stains.size() < MAX_STAINS:
		decal = Decal.new()
		decal.texture_albedo = _texture
		decal.texture_orm = _orm
		decal.normal_fade = 0.7
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = 22.0
		decal.distance_fade_length = 8.0
		add_child(decal)
	else:
		decal = stains.pop_front()
	stains.append(decal)
	decal.texture_orm = _orm
	decal.visible = true
	decal.modulate = Color.WHITE
	decal.size = Vector3(size, 0.12, size)
	decal.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, normal.normalized())), point + normal * 0.025)
	decal.rotate_object_local(Vector3.UP, float(stains.size()) * 2.39996 + _clock)
	decal.set_meta("born", _clock)
	return decal

func wound_mark(parent: Node3D, point: Vector3, outward: Vector3) -> Decal:
	if get_tree().get_nodes_in_group("blood_wound_marks").size() >= MAX_WOUND_MARKS:
		return null
	var decal := Decal.new()
	decal.texture_albedo = _texture
	decal.size = Vector3(0.19, 0.24, 0.19)
	decal.modulate = Color(0.8, 0.65, 0.65)
	decal.normal_fade = 0.6
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 15.0
	decal.distance_fade_length = 10.0
	parent.add_child(decal)
	decal.add_to_group("blood_wound_marks")
	decal.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, outward.normalized())), point)
	return decal

func _process(delta: float) -> void:
	_clock += delta
	_stain_clock += delta
	if _stain_clock < 0.1:
		return
	_stain_clock = 0.0
	for stain: Decal in stains:
		if not stain.visible:
			continue
		var age := _clock - float(stain.get_meta("born", 0.0))
		var dry := clampf(age / 45.0, 0.0, 1.0)
		stain.modulate = Color(lerpf(1.0, 0.42, dry), lerpf(1.0, 0.55, dry), lerpf(1.0, 0.5, dry), 1.0 - smoothstep(STAIN_LIFETIME - 8.0, STAIN_LIFETIME, age))
		if dry > 0.6 and stain.texture_orm != _dry_orm:
			stain.texture_orm = _dry_orm
		stain.visible = age < STAIN_LIFETIME
