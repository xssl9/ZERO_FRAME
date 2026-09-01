class_name WeaponManager
extends Node3D

var weapons: Array[WeaponBase] = []
var current_index: int = 0
var sway: Vector2 = Vector2.ZERO
var sway_velocity: Vector2 = Vector2.ZERO
var base_position: Vector3 = Vector3(0.0, -0.18, -0.35)
var collision_camera: Camera3D
var collision_player: CharacterBody3D
var wall_pushback: float = 0.0
var wall_blocked: bool = false

func configure_weapon_collision(player: CharacterBody3D, player_camera: Camera3D) -> void:
	collision_player = player
	collision_camera = player_camera

func _ready() -> void:
	top_level = false
	position = base_position
	var ak := WeaponBase.new()
	ak.configure("AK-74M", 30, 30, 650.0, 34.0, false, "res://scenes/weapons/ak_viewmodel.tscn", "Rig|AK_Idle", "Rig|AK_Reload")
	add_child(ak)
	weapons.append(ak)
	var pistol := WeaponBase.new()
	pistol.configure("PISTOL", 15, 15, 330.0, 25.0, false, "res://scenes/weapons/pistol_viewmodel.tscn", "Armature|FPS_Pistol_Idle", "Armature|FPS_Pistol_Reload_easy")
	add_child(pistol)
	weapons.append(pistol)
	_select(1 if "--pistol" in OS.get_cmdline_user_args() else 0)

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("weapon_1"):
		_select(0)
	if Input.is_action_just_pressed("weapon_2"):
		_select(1)
	if Input.is_action_just_pressed("reload"):
		weapons[current_index].reload()
	if not wall_blocked:
		weapons[current_index].try_fire()
	weapons[current_index].set_aiming(Input.is_action_pressed("aim"))
	var movement := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	sway_velocity += (-sway * 54.0 - sway_velocity * 13.0) * delta
	sway += sway_velocity * delta
	var walk_roll := -movement.x * 0.018
	rotation = Vector3(
		sway.y * 0.018 - wall_pushback * 0.46,
		sway.x * 0.025,
		lerpf(rotation.z, walk_roll + wall_pushback * 0.08, 1.0 - exp(-delta * 9.0))
	)
	var collision_offset := Vector3(0.0, wall_pushback * 0.16, wall_pushback)
	position = position.lerp(base_position + collision_offset + Vector3(sway.x, -absf(sway.y), 0.0) * 0.002, 1.0 - exp(-delta * 18.0))

func _physics_process(delta: float) -> void:
	if collision_camera == null or collision_player == null or weapons.is_empty():
		return
	var weapon_length: float = 1.18 if weapons[current_index].weapon_name == "AK-74M" else 0.72
	var origin: Vector3 = collision_camera.global_position
	var forward: Vector3 = -collision_camera.global_transform.basis.z.normalized()
	var query := PhysicsRayQueryParameters3D.create(origin + forward * 0.08, origin + forward * weapon_length)
	query.exclude = [collision_player.get_rid()]
	query.collide_with_areas = false
	var hit := collision_player.get_world_3d().direct_space_state.intersect_ray(query)
	var target_pushback: float = 0.0
	if not hit.is_empty():
		var distance: float = origin.distance_to(hit["position"] as Vector3)
		target_pushback = clampf(weapon_length - distance + 0.12, 0.0, 0.62)
	wall_blocked = target_pushback > (0.2 if weapons[current_index].weapon_name == "AK-74M" else 0.13)
	var speed: float = 8.0 if target_pushback > wall_pushback else 13.0
	wall_pushback = move_toward(wall_pushback, target_pushback, speed * delta)

func add_look_impulse(relative: Vector2) -> void:
	sway_velocity += Vector2(clampf(-relative.x, -35.0, 35.0), clampf(-relative.y, -35.0, 35.0)) * 0.35

func _select(index: int) -> void:
	current_index = clampi(index, 0, weapons.size() - 1)
	for i: int in weapons.size():
		weapons[i].visible = i == current_index
		weapons[i].set_process(i == current_index)
		weapons[i].set_authored_camera_active(i == current_index)

func get_hud_text() -> String:
	if weapons.is_empty():
		return ""
	var weapon := weapons[current_index]
	var mode: String = " SEMI" if weapon.weapon_name == "AK-74M" else ""
	return "%s%s   %02d / %02d" % [weapon.weapon_name, mode, weapon.ammo, weapon.reserve]

func get_status_text() -> String:
	if weapons.is_empty():
		return ""
	var weapon := weapons[current_index]
	if weapon.reloading:
		return "ПЕРЕЗАРЯДКА"
	if weapon.ammo == 0:
		return "R — ПЕРЕЗАРЯДИТЬ"
	return ""

func get_active_camera_fov() -> float:
	if weapons.is_empty():
		return 96.0
	return weapons[current_index].authored_camera_fov

func get_active_camera_keep_aspect() -> Camera3D.KeepAspect:
	if weapons.is_empty():
		return Camera3D.KEEP_HEIGHT
	return weapons[current_index].authored_camera_keep_aspect

func get_active_authored_camera() -> Camera3D:
	if weapons.is_empty():
		return null
	return weapons[current_index].authored_camera
