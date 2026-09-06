class_name EnemyController
extends CharacterBody3D

enum State { IDLE, PATROL, SUSPICIOUS, INVESTIGATE, COMBAT, SEARCH, COVER, RELOAD, INJURED, DEAD }

var state: State = State.PATROL
var health: float = 100.0
var player: PlayerController
var home: Vector3
var target: Vector3
var weapon_type: String = "AK"
var reaction_delay: float = 0.0
var fire_cooldown: float = 0.0
var think_cooldown: float = 0.0
var rng := RandomNumberGenerator.new()

func configure(type: String, tint: Color) -> void:
	weapon_type = type
	_build_visual(tint)

func _ready() -> void:
	add_to_group("enemies")
	home = global_position
	target = home
	rng.randomize()
	var body_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.8
	body_shape.shape = capsule
	body_shape.position.y = 0.9
	add_child(body_shape)

func _build_visual(tint: Color) -> void:
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.65
	body.mesh = capsule
	body.position.y = 0.92
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.82
	body.material_override = material
	add_child(body)
	var gun := MeshInstance3D.new()
	var gun_mesh := BoxMesh.new()
	gun_mesh.size = Vector3(0.11, 0.1, 0.7 if weapon_type == "AK" else 0.32)
	gun.mesh = gun_mesh
	gun.position = Vector3(0.3, 1.25, -0.35)
	add_child(gun)

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if player == null:
		player = get_tree().get_first_node_in_group("player") as PlayerController
		return
	think_cooldown -= delta
	fire_cooldown -= delta
	if think_cooldown <= 0.0:
		think_cooldown = rng.randf_range(0.16, 0.3)
		_think()
	_act(delta)

func _think() -> void:
	var distance := global_position.distance_to(player.global_position)
	if distance < 34.0 and _has_line_of_sight():
		state = State.COMBAT
		target = player.global_position
	elif state == State.COMBAT:
		state = State.SEARCH
		target = player.global_position
	elif state in [State.PATROL, State.IDLE] and global_position.distance_to(target) < 1.0:
		target = home + Vector3(rng.randf_range(-4.0, 4.0), 0.0, rng.randf_range(-4.0, 4.0))

func _has_line_of_sight() -> bool:
	var origin := global_position + Vector3.UP * 1.45
	var destination := player.global_position + Vector3.UP * 1.35
	var query := PhysicsRayQueryParameters3D.create(origin, destination)
	query.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit["collider"] == player

func _act(delta: float) -> void:
	if state == State.COMBAT:
		look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)
		if global_position.distance_to(player.global_position) > 9.0:
			_move_toward(target, delta, 2.2)
		if fire_cooldown <= 0.0:
			fire_cooldown = rng.randf_range(0.35, 0.75) if weapon_type == "AK" else rng.randf_range(0.8, 1.4)
			if _has_line_of_sight() and rng.randf() > 0.32:
				player.apply_damage(7.0 if weapon_type == "AK" else 12.0)
	elif state in [State.PATROL, State.SEARCH, State.INVESTIGATE]:
		_move_toward(target, delta, 1.5)

func _move_toward(destination: Vector3, delta: float, speed: float) -> void:
	var flat := destination - global_position
	flat.y = 0.0
	if flat.length() > 0.4:
		var direction := flat.normalized()
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		velocity.y -= 18.0 * delta
		move_and_slide()

func apply_damage(amount: float, _zone: String = "torso") -> void:
	health -= amount
	state = State.INJURED
	if health <= 0.0:
		state = State.DEAD
		rotation.z = deg_to_rad(88.0)
		set_collision_layer_value(1, false)
		var timer := get_tree().create_timer(12.0)
		timer.timeout.connect(func() -> void: set_physics_process(false))
	else:
		state = State.COMBAT
