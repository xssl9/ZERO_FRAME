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

## Server-side damage scaling. The client only reports which zone it hit; the
## numbers live here so a patched client cannot invent its own multipliers.
const ZONE_MULTIPLIER := {
	"head": 2.5,
	"torso": 1.0,
	"limbs": 0.7,
}

signal match_state_changed(active: bool)
signal local_health_changed(health: float)
signal peer_list_changed()

var active: bool = false
var map_path: String = ""

var _spawner: MultiplayerSpawner = null
var _avatar_root: Node3D = null
var _health: Dictionary = {}
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
	if not SteamManager.is_host():
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
	_health.clear()
	_spawn_index.clear()
	_next_spawn_index = 0
	_spawner = null
	_avatar_root = null
	SteamManager.close_transport()
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
	get_tree().paused = false
	if get_tree().change_scene_to_file(wanted_map) != OK:
		push_error("NETWORK_GAME: не удалось загрузить карту %s" % wanted_map)
		return false
	for _attempt: int in 240:
		await get_tree().process_frame
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
	# Set before the node enters the tree so the synchronizer inside it starts up
	# already owned by the right peer on every machine.
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
	var avatar := avatar_for(peer)
	if avatar != null:
		avatar.queue_free()
	peer_list_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _assign_spawn_index(index: int) -> void:
	_local_spawn_index = index
	_place_local_player(index)

# --- Damage ---------------------------------------------------------------

## Called on the shooter's machine. The trace itself stays client-side so firing
## feels immediate, but only the zone and the weapon's base damage travel; the
## server decides what that is worth and who ends up dead.
func report_hit(target_peer: int, zone: String, base_damage: float) -> void:
	if not active or target_peer <= 0:
		return
	_receive_hit.rpc_id(1, target_peer, zone, base_damage)

@rpc("any_peer", "call_local", "reliable")
func _receive_hit(target_peer: int, zone: String, base_damage: float) -> void:
	if not is_server():
		return
	if not _health.has(target_peer):
		return
	if float(_health[target_peer]) <= 0.0:
		return
	var multiplier: float = float(ZONE_MULTIPLIER.get(zone, 1.0))
	var applied: float = maxf(0.0, base_damage) * multiplier
	var remaining: float = maxf(0.0, float(_health[target_peer]) - applied)
	_health[target_peer] = remaining
	_push_health.rpc(target_peer, remaining)
	_confirm_hit.rpc_id(multiplayer.get_remote_sender_id(), zone, remaining <= 0.0)
	if remaining <= 0.0:
		_schedule_respawn(target_peer)

@rpc("authority", "call_local", "reliable")
func _push_health(target_peer: int, value: float) -> void:
	_health[target_peer] = value
	var avatar := avatar_for(target_peer)
	if avatar != null and avatar.has_method("set_dead"):
		avatar.call("set_dead", value <= 0.0)
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
	var timer := get_tree().create_timer(RESPAWN_DELAY, false)
	await timer.timeout
	if not is_server() or not _health.has(target_peer):
		return
	_health[target_peer] = MAX_HEALTH
	_push_health.rpc(target_peer, MAX_HEALTH)
	_respawn.rpc_id(target_peer, int(_spawn_index.get(target_peer, 0)))
	if target_peer == 1:
		_respawn(int(_spawn_index.get(1, 0)))

@rpc("authority", "call_remote", "reliable")
func _respawn(index: int) -> void:
	_place_local_player(index)
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("revive"):
		player.call("revive")
