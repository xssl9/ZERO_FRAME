extends Node

## Match orchestration: turns a Steam lobby into a running round.
##
## The whole flow is built so that no peer ever receives a spawn command before
## its own level exists. The host loads the map, opens the socket and only then
## publishes STATE_PLAYING; a client loads the map first and dials in afterwards.
## Because a client is already inside the level when `peer_connected` fires on the
## host, MultiplayerSpawner's late-join replay always lands on a live spawn path.

const AVATAR_SCENE := "res://scenes/player/soldier_avatar.tscn"
const SPAWN_GROUP := "player_spawn_point"
const RESPAWN_DELAY := 5.0
const MAX_HEALTH := 100.0
const MAPS := ["res://scenes/levels/dev_test_grid.tscn", "res://scenes/levels/pvp_linse.tscn", "res://scenes/levels/parking_garage_rework.tscn"]

## Server-side damage scaling. Both the hit zone and these multipliers are
## resolved on the host, never supplied by the shooting client.
const ZONE_MULTIPLIER := ShotBallistics.ZONE_MULTIPLIER

signal match_state_changed(active: bool)
signal local_health_changed(health: float)
signal peer_list_changed()

var active: bool = false
var map_path: String = ""

var _spawner: MultiplayerSpawner = null
var _avatar_root: Node3D = null
var _health: Dictionary = {}
var _last_shot: Dictionary = {}
var _round_id := 0
var _spawn_index: Dictionary = {}
var _local_spawn_index: int = 0
var _next_spawn_index: int = 0
var _loading: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SteamManager.match_requested.connect(_on_match_requested)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_server_disconnected)
	SteamManager.lobby_exited.connect(_on_lobby_exited)

func _on_lobby_exited() -> void:
	if active or _loading:
		_loading = false
		leave_match()
		await _leave_to_menu()

func is_server() -> bool:
	return active and multiplayer.multiplayer_peer != null and multiplayer.is_server()

func local_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1
	return multiplayer.get_unique_id()

func health_of(peer: int) -> float:
	return float(_health.get(peer, MAX_HEALTH))

# --- Entering a match -----------------------------------------------------

## Host side. Called from the lobby UI once everyone is ready.
func host_match(wanted_map: String) -> void:
	if _loading or active:
		return
	if not SteamManager.is_host() or not SteamManager.everyone_ready() or not wanted_map in MAPS:
		return
	_loading = true
	map_path = wanted_map
	if not await _enter_map(wanted_map):
		_loading = false
		return
	if SteamManager.open_as_host() != OK:
		_loading = false
		await _leave_to_menu()
		return
	active = true
	_loading = false
	_spawn_index[1] = 0
	_local_spawn_index = 0
	_next_spawn_index = 1
	_health[1] = MAX_HEALTH
	_place_local_player(0)
	_spawn_avatar_for(1)
	match_state_changed.emit(true)
	peer_list_changed.emit()
	# Published last: this is what pulls the clients in, and by now we are already
	# listening with a spawner in place.
	SteamManager.publish_match(wanted_map)

## Client side, driven by the lobby flipping to STATE_PLAYING.
func _on_match_requested(wanted_map: String) -> void:
	if _loading or active or SteamManager.is_host():
		return
	var host_id := SteamManager.host_steam_id()
	if host_id == 0:
		return
	_loading = true
	map_path = wanted_map
	if not await _enter_map(wanted_map):
		_loading = false
		return
	if SteamManager.open_as_client(host_id) != OK:
		_loading = false
		await _leave_to_menu()
		return
	active = true
	_loading = false
	match_state_changed.emit(true)

func leave_match() -> void:
	if not active:
		return
	active = false
	_round_id += 1
	_last_shot.clear()
	_health.clear()
	_spawn_index.clear()
	_next_spawn_index = 0
	_spawner = null
	_avatar_root = null
	SteamManager.close_transport()
	SteamManager.set_ready(false)
	if SteamManager.is_host():
		SteamManager.reopen_lobby()
	match_state_changed.emit(false)

func _on_server_disconnected() -> void:
	if not active:
		return
	leave_match()
	await _leave_to_menu()

func _leave_to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await get_tree().process_frame

## Loads the level and waits until it is genuinely the current scene, because
## `change_scene_to_file` only queues the swap. Everything downstream - the
## spawner, the socket - depends on the level already being there.
func _enter_map(wanted_map: String) -> bool:
	if not wanted_map in MAPS:
		push_error("NETWORK_GAME: неизвестная карта %s" % wanted_map)
		return false
	get_tree().paused = false
	if get_tree().change_scene_to_file(wanted_map) != OK:
		push_error("NETWORK_GAME: не удалось загрузить карту %s" % wanted_map)
		return false
	for _attempt: int in 240:
		await get_tree().process_frame
		if not _loading:
			return false
		var current := get_tree().current_scene
		if current != null and current.scene_file_path == wanted_map and current.is_node_ready():
			_build_network_root(current)
			return true
	push_error("NETWORK_GAME: карта %s не стала текущей сценой" % wanted_map)
	return false

## The replicated subtree is created identically on every peer, so the NodePaths
## the spawner and the synchronizers travel over match without being authored
## into each level by hand.
func _build_network_root(level: Node) -> void:
	var network_root := Node3D.new()
	network_root.name = "NetworkRoot"
	level.add_child(network_root)

	_avatar_root = Node3D.new()
	_avatar_root.name = "Avatars"
	network_root.add_child(_avatar_root)

	_spawner = MultiplayerSpawner.new()
	_spawner.name = "SoldierSpawner"
	network_root.add_child(_spawner)
	_spawner.spawn_path = _spawner.get_path_to(_avatar_root)
	_spawner.spawn_function = _spawn_soldier

func spawn_points() -> Array[Node]:
	var points := get_tree().get_nodes_in_group(SPAWN_GROUP)
	points.sort_custom(func(a: Node, b: Node) -> bool: return a.name < b.name)
	return points

func _place_local_player(index: int) -> void:
	var points := spawn_points()
	if points.is_empty():
		return
	var marker := points[index % points.size()] as Node3D
	if marker == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	if player.has_method("teleport_to"):
		player.call("teleport_to", marker.global_transform)

# --- Spawning -------------------------------------------------------------

func _spawn_soldier(data: Variant) -> Node:
	var info := data as Dictionary
	var peer: int = int(info.get("peer", 1))
	var scene := load(AVATAR_SCENE) as PackedScene
	var avatar := scene.instantiate()
	avatar.name = "Soldier_%d" % peer
	# Player ownership is separate from the host-owned synchronizer created in ready.
	avatar.set_multiplayer_authority(peer)
	if avatar.has_method("configure"):
		avatar.call("configure", peer, int(info.get("steam", 0)))
	return avatar

func _spawn_avatar_for(peer: int) -> void:
	if _spawner == null or _avatar_root == null:
		return
	if _avatar_root.has_node("Soldier_%d" % peer):
		return
	_spawner.spawn({"peer": peer, "steam": SteamManager.steam_id if peer == 1 else 0})

func avatar_for(peer: int) -> Node3D:
	if _avatar_root == null:
		return null
	return _avatar_root.get_node_or_null("Soldier_%d" % peer) as Node3D

func local_avatar() -> Node3D:
	return avatar_for(local_peer_id())

func _on_peer_connected(peer: int) -> void:
	if not is_server():
		return
	var index := _next_spawn_index
	_next_spawn_index += 1
	_spawn_index[peer] = index
	_health[peer] = MAX_HEALTH
	_assign_spawn_index.rpc_id(peer, index)
	_spawn_avatar_for(peer)
	peer_list_changed.emit()

func _on_peer_disconnected(peer: int) -> void:
	if not is_server():
		return
	_health.erase(peer)
	_spawn_index.erase(peer)
	_last_shot.erase(peer)
	var avatar := avatar_for(peer)
	if avatar != null:
		avatar.queue_free()
	peer_list_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _assign_spawn_index(index: int) -> void:
	_local_spawn_index = index
	_place_local_player(index)

# --- Host-distributed state and sound -------------------------------------

# Steam's peer has no server relay. Clients submit only their own pose; the
# host-owned synchronizers distribute it to every other client.
func submit_pose(avatar: SoldierAvatar) -> void:
	if not active or avatar.peer_id != local_peer_id():
		return
	_receive_pose.rpc_id(1, avatar.sync_position, avatar.sync_rotation_y,
		avatar.sync_pitch, avatar.sync_velocity, avatar.sync_crouching,
		avatar.sync_aiming, avatar.sync_sprinting, avatar.sync_airborne,
		avatar.sync_weapon_index, avatar.sync_flashlight)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_pose(position: Vector3, yaw: float, pitch: float, velocity: Vector3,
		crouching: bool, aiming: bool, sprinting: bool, airborne: bool,
		weapon: int, flashlight: bool) -> void:
	if not is_server() or not position.is_finite() or not velocity.is_finite():
		return
	if not is_finite(yaw) or not is_finite(pitch) or absf(pitch) > PI / 2.0 or weapon < 0 or weapon > 1:
		return
	var sender := multiplayer.get_remote_sender_id()
	var avatar := avatar_for(sender) as SoldierAvatar
	if avatar == null or not _health.has(sender):
		return
	avatar.sync_position = position
	avatar.sync_rotation_y = yaw
	avatar.sync_pitch = pitch
	avatar.sync_velocity = velocity
	avatar.sync_crouching = crouching
	avatar.sync_aiming = aiming
	avatar.sync_sprinting = sprinting
	avatar.sync_airborne = airborne
	avatar.sync_weapon_index = weapon
	avatar.sync_flashlight = flashlight

func submit_sound(event: String, variant: int, gain: float, pitch: float) -> void:
	if active:
		_receive_sound.rpc_id(1, event, variant, gain, pitch)

@rpc("any_peer", "call_local", "reliable")
func _receive_sound(event: String, variant: int, gain: float, pitch: float) -> void:
	if not is_server() or not is_finite(gain) or not is_finite(pitch):
		return
	if event not in ["step", "land", "breath", "shot", "reload", "reload_stop"] or variant < 0 or variant > 5:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = local_peer_id()
	if avatar_for(sender) == null or not _health.has(sender) or health_of(sender) <= 0.0:
		return
	_play_sound.rpc(sender, event, variant, clampf(gain, -60.0, 16.0), clampf(pitch, 0.5, 2.0))

@rpc("authority", "call_local", "reliable")
func _play_sound(sender: int, event: String, variant: int, gain: float, pitch: float) -> void:
	if sender == local_peer_id():
		return
	var avatar := avatar_for(sender) as SoldierAvatar
	if avatar != null:
		avatar._receive_sound(event, variant, gain, pitch)

# --- Damage ---------------------------------------------------------------

## Clients submit a ray, never a victim, zone or damage value. The host traces
## its bone hitboxes and cover geometry; the local trace is cosmetic feedback.
func report_shot(origin: Vector3, direction: Vector3, weapon: int, muzzle: Vector3) -> void:
	if active:
		_receive_shot.rpc_id(1, origin, direction, weapon, muzzle)

@rpc("any_peer", "call_local", "reliable")
func _receive_shot(origin: Vector3, direction: Vector3, weapon: int, muzzle: Vector3) -> void:
	if not is_server() or weapon < 0 or weapon > 1 or not origin.is_finite() or not direction.is_finite():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = local_peer_id()
	var shooter := avatar_for(sender) as SoldierAvatar
	if shooter == null or health_of(sender) <= 0.0 or not _health.has(sender):
		return
	if not muzzle.is_finite() or muzzle.distance_to(origin) > 1.8:
		return
	if origin.distance_to(shooter.sync_position) > 2.5 or direction.length() < 0.9 or direction.length() > 1.1:
		return
	var now := Time.get_ticks_msec()
	var interval := 60_000.0 / (650.0 if weapon == 0 else 330.0)
	if float(now - int(_last_shot.get(sender, -10000))) < interval * 0.8:
		return
	_last_shot[sender] = now
	var excluded: Array[RID] = []
	for area: Area3D in shooter._hitboxes:
		excluded.append(area.get_rid())
	# The host's movement capsule is not a hitbox.
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player != null:
		excluded.append(player.get_rid())
	var space := shooter.get_world_3d().direct_space_state
	# A reported camera on the far side of cover cannot bypass that cover.
	var chest := shooter.sync_position + Vector3(0, 0.85 if shooter.sync_crouching else 1.35, 0)
	if not ShotBallistics.ray(space, chest, origin, excluded).is_empty():
		return
	var hit := ShotBallistics.trace(space, origin, direction, muzzle, excluded)
	if hit.is_empty():
		return
	var collider := hit.collider as Area3D
	if collider == null or not collider.has_meta("hit_peer"):
		_show_impact.rpc(sender, hit.position, hit.normal)
		return
	var target_peer := int(collider.get_meta("hit_peer"))
	if not _health.has(target_peer) or health_of(target_peer) <= 0.0:
		return
	var zone := String(collider.get_meta("hit_zone"))
	var damage := ShotBallistics.damage_at(weapon, zone, muzzle.distance_to(hit.position))
	var remaining := maxf(0.0, health_of(target_peer) - damage)
	_push_health.rpc(target_peer, remaining)
	if sender == local_peer_id():
		_confirm_hit(zone, remaining <= 0.0)
	else:
		_confirm_hit.rpc_id(sender, zone, remaining <= 0.0)
	if remaining <= 0.0:
		_schedule_respawn(target_peer)

@rpc("authority", "call_local", "unreliable")
func _show_impact(shooter: int, point: Vector3, normal: Vector3) -> void:
	if shooter == local_peer_id():
		return
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player != null and player.weapon_manager != null:
		player.weapon_manager.weapons[0]._spawn_impact(point, normal)

@rpc("authority", "call_local", "reliable")
func _push_health(target_peer: int, value: float) -> void:
	_health[target_peer] = value
	var avatar := avatar_for(target_peer) as SoldierAvatar
	if avatar != null:
		avatar.sync_health = value
	if target_peer == local_peer_id():
		local_health_changed.emit(value)

## Hit feedback for the shooter alone: the marker and the kill line never travel
## to anyone else.
@rpc("authority", "call_local", "reliable")
func _confirm_hit(zone: String, killed: bool) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("notify_hit_confirmed"):
		player.call("notify_hit_confirmed", zone, killed)

func _schedule_respawn(target_peer: int) -> void:
	var round_id := _round_id
	var timer := get_tree().create_timer(RESPAWN_DELAY, false)
	await timer.timeout
	if round_id != _round_id or not is_server() or not _health.has(target_peer):
		return
	_health[target_peer] = MAX_HEALTH
	_push_health.rpc(target_peer, MAX_HEALTH)
	if target_peer == 1:
		_respawn(int(_spawn_index.get(1, 0)))
	else:
		_respawn.rpc_id(target_peer, int(_spawn_index.get(target_peer, 0)))

@rpc("authority", "call_remote", "reliable")
func _respawn(index: int) -> void:
	_place_local_player(index)
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("revive"):
		player.call("revive")
