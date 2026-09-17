extends Node

# Real processes, real Spawner/Synchronizer; SceneMultiplayer relay disabled so
# ENet cannot silently repair the topology that SteamMultiplayerPeer lacks.
var slot := 0
var count := 3
var port := 29835
var phase := 0
var network: Node
var player: PlayerController
var fixture: Node3D
var acknowledgements := {}
var sent_phase := -1
var elapsed := 0.0
var phase_time := 0.0
var sound_time := 0.0
var reconnecting := false
var finished := false
var old_peer := 0
var previous_positions := {}
var moved := {}
var bootstrap_death := false
var late_dead_snapshot := false

func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--slot="):
			slot = argument.trim_prefix("--slot=").to_int()
		if argument.begins_with("--count="):
			count = argument.trim_prefix("--count=").to_int()
		if argument.begins_with("--port="):
			port = argument.trim_prefix("--port=").to_int()
	network = get_node("/root/NetworkGame")
	fixture = Node3D.new()
	fixture.name = "Fixture"
	add_child(fixture)
	player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	fixture.add_child(player)
	player.set_physics_process(false)
	player.weapon_manager.set_process(false)
	network._build_network_root(fixture)
	_connect_transport()
	if slot == 0:
		network._health[1] = 100.0
		network._spawn_avatar_for(1)

func _connect_transport() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, count + 2) if slot == 0 else peer.create_client("127.0.0.1", port)
	if error != OK:
		_fail("transport error " + str(error))
		return
	(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.multiplayer_peer = peer
	network.active = true

func _process(delta: float) -> void:
	if finished:
		return
	elapsed += delta
	phase_time += delta
	if elapsed > 48.0:
		for avatar: SoldierAvatar in network._avatar_root.get_children():
			print("STAR_DIAGNOSTIC peer=", avatar.peer_id, " position=", avatar.sync_position, " health=", avatar.sync_health, " pitch=", avatar.sync_pitch, " aim=", avatar.sync_aiming, " airborne=", avatar.sync_airborne, " animation=", avatar._locomotion._playback.get_current_node(), " local=", avatar.is_local, " moved=", moved)
		_fail("timeout phase=%d acknowledgements=%s peers=%s" % [phase, acknowledgements, multiplayer.get_peers()])
		return
	# Distinct, changing poses, yaw, pitch, weapon and animation flags per owner.
	player.position = Vector3(slot * 3.0 + sin(elapsed) * 0.3, 0, 10 + slot * 3)
	player.rotation.y = slot * 0.2
	player.bodycam.rotation.x = slot * 0.1
	player.velocity = Vector3(1 + slot, 0, -1)
	player.crouching = slot % 2 == 1
	player.sprinting = slot % 2 == 0
	player.weapon_manager.current_index = slot % 2
	player.flashlight.visible = slot % 2 == 1
	if slot % 2 == 1:
		Input.action_press("aim")
	else:
		Input.action_release("aim")
	if reconnecting or network._avatar_root == null:
		return
	var local := network.local_avatar() as SoldierAvatar
	if local == null:
		return
	sound_time += delta
	if sound_time > 0.4:
		sound_time = 0.0
		local.send_sound("step", slot % 6, -10, 1)
	if phase == 0 and slot == 0 and elapsed > 1.0 and not bootstrap_death:
		# Host dies before the delayed client connects: health must arrive through
		# the spawner's synchronizer snapshot, not only the earlier death RPC.
		bootstrap_death = true
		network._push_health.rpc(1, 0.0)
		network._schedule_respawn(1)
	if phase == 0 and slot == count - 1:
		var host := network.avatar_for(1) as SoldierAvatar
		if host != null and host.sync_dead and host._ragdoll.running:
			late_dead_snapshot = true
	if phase == 1:
		var victim := _avatar_in_slot(count - 1)
		if victim != null and victim.sync_dead and victim._ragdoll.running:
			_ack_once()
	elif phase == 3:
		if slot != count - 1 and network._avatar_root.get_child_count() == count - 1:
			if _avatar_in_slot(count - 1) == null:
				_ack_once()
	elif phase_time > 0.8 and _all_visible_and_synced():
		_ack_once()
	if slot != 0:
		return
	var expected := count - 1 if phase == 3 else count
	if acknowledgements.size() != expected:
		return
	if phase == 0:
		var victim := _avatar_in_slot(count - 1)
		old_peer = victim.peer_id
		_set_phase.rpc(1)
		network._push_health.rpc(old_peer, 0.0)
		network._schedule_respawn(old_peer)
	elif phase == 1 and network.health_of(old_peer) == 100.0:
		_set_phase.rpc(2)
	elif phase == 2:
		_set_phase.rpc(3)
	elif phase == 3:
		if network.avatar_for(old_peer) != null or network._health.has(old_peer) or network._spawn_index.has(old_peer) or network._last_shot.has(old_peer):
			_fail("orphaned disconnected owner")
			return
		_set_phase.rpc(4)
	elif phase == 4:
		if _avatar_in_slot(count - 1).peer_id == old_peer:
			_fail("reconnect did not use a new peer ID")
			return
		_finish.rpc()

func _avatar_in_slot(wanted: int) -> SoldierAvatar:
	for avatar: SoldierAvatar in network._avatar_root.get_children():
		if absf(avatar.sync_position.z - (10 + wanted * 3)) < 0.05:
			return avatar
	return null

func _all_visible_and_synced() -> bool:
	if slot == count - 1 and not late_dead_snapshot:
		return false
	if network._avatar_root.get_child_count() != count:
		return false
	var owners := {}
	var slots := {}
	for avatar: SoldierAvatar in network._avatar_root.get_children():
		var owner_slot := roundi((avatar.sync_position.z - 10) / 3.0)
		if owner_slot < 0 or owner_slot >= count or slots.has(owner_slot) or owners.has(avatar.peer_id):
			return false
		slots[owner_slot] = true
		owners[avatar.peer_id] = true
		if avatar.name != "Soldier_%d" % avatar.peer_id or avatar.get_multiplayer_authority() != avatar.peer_id:
			_fail("node path/ownership mismatch")
			return false
		if avatar.get_node("Synchronizer").get_multiplayer_authority() != 1:
			_fail("client-to-client replication authority")
			return false
		if avatar.sync_dead or avatar.sync_health != 100.0 or avatar._ragdoll.running:
			return false
		if avatar.is_local != (avatar.peer_id == multiplayer.get_unique_id()) or avatar.visible == avatar.is_local:
			_fail("local/remote visibility mismatch")
			return false
		if absf(avatar.sync_pitch - owner_slot * 0.1) > 0.01 or absf(avatar.sync_rotation_y - owner_slot * 0.2) > 0.01:
			return false
		if avatar.sync_weapon_index != owner_slot % 2 or avatar.sync_crouching != (owner_slot % 2 == 1) or avatar.sync_sprinting != (owner_slot % 2 == 0):
			return false
		if avatar.sync_flashlight != (owner_slot % 2 == 1) or avatar.sync_velocity.distance_to(Vector3(1 + owner_slot, 0, -1)) > 0.01:
			return false
		if avatar.sync_aiming != (owner_slot % 2 == 1) or not avatar.sync_airborne:
			return false
		if avatar._locomotion._playback.get_current_node() != "jump":
			return false
		if avatar.global_position.distance_to(avatar.sync_position) > 0.15 or not avatar._animation_tree.active:
			return false
		if not avatar.is_local:
			var heard := false
			for voice: AudioStreamPlayer3D in avatar._audio._voices:
				heard = heard or voice.stream != null
			if not heard:
				return false
		if previous_positions.has(avatar.peer_id) and avatar.sync_position.distance_to(previous_positions[avatar.peer_id]) > 0.03:
			moved[avatar.peer_id] = true
		if not previous_positions.has(avatar.peer_id):
			previous_positions[avatar.peer_id] = avatar.sync_position
	return moved.size() == count

func _ack_once() -> void:
	if sent_phase != phase:
		sent_phase = phase
		_ack.rpc_id(1, phase)

@rpc("any_peer", "call_local", "reliable")
func _ack(value: int) -> void:
	if slot == 0 and value == phase:
		var sender := multiplayer.get_remote_sender_id()
		acknowledgements[multiplayer.get_unique_id() if sender == 0 else sender] = true

@rpc("authority", "call_local", "reliable")
func _set_phase(value: int) -> void:
	phase = value
	phase_time = 0.0
	acknowledgements.clear()
	previous_positions.clear()
	moved.clear()
	print("STAR_PHASE slot=", slot, " phase=", phase)
	if phase == 3 and slot == count - 1:
		_reconnect()

func _reconnect() -> void:
	reconnecting = true
	network.leave_match()
	fixture.get_node("NetworkRoot").queue_free()
	await get_tree().create_timer(3.0).timeout
	network._build_network_root(fixture)
	phase = 4
	phase_time = 0.0
	_connect_transport()
	reconnecting = false

@rpc("authority", "call_local", "reliable")
func _finish() -> void:
	finished = true
	print("NETWORK_STAR_PASS slot=", slot, " count=", count, " relay=false: all owners/poses/flags/audio, late join, death/respawn, disconnect/reconnect")
	# All peers received the completion barrier. Suppress production menu loading
	# during teardown, otherwise the first closing socket destroys this test node
	# on clients while their completion timer is still awaiting.
	network.active = false
	await get_tree().create_timer(0.5).timeout
	SteamManager.close_transport()
	get_tree().quit()

func _fail(message: String) -> void:
	finished = true
	push_error("NETWORK_STAR_FAIL slot=%d %s" % [slot, message])
	get_tree().quit(1)
