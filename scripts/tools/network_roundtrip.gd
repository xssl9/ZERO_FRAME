extends SceneTree

const HOST_POSITION := Vector3(0, 0, 18)
const CLIENT_POSITION := Vector3(3, 0, 18)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var server := "--server" in OS.get_cmdline_user_args()
	var network := root.get_node("NetworkGame")
	var level := (load("res://scenes/levels/dev_test_grid.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	network._build_network_root(level)
	var player := get_first_node_in_group("player") as PlayerController
	player.set_physics_process(false)
	player.weapon_manager.set_process(false)
	player.camera.set_process(false)
	player.position = HOST_POSITION if server else CLIENT_POSITION
	player.rotation = Vector3.ZERO
	player.bodycam.rotation.x = 0.3
	player.velocity = Vector3(1, 0, -1)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(29834) if server else peer.create_client("127.0.0.1", 29834)
	if error != OK:
		push_error("ENet setup failed: " + str(error))
		quit(1)
		return
	root.multiplayer.multiplayer_peer = peer
	network.active = true
	if server:
		network._health[1] = 100.0
		network._spawn_avatar_for(1)
	var deadline := Time.get_ticks_msec() + 25000
	var sent := false
	var received_audio := false
	var killed := false
	var saw_death := false
	var remote_moved_during_menu := false
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if not is_instance_valid(player):
			push_error("NETWORK_ROUNDTRIP connection ended before assertions completed")
			quit(1)
			return
		# Spawn assignment teleports the client's local controller; place it at the
		# test position after assignment to exercise real state replication.
		player.position = HOST_POSITION if server else CLIENT_POSITION
		var local := network.local_avatar() as SoldierAvatar
		if local == null:
			continue
		var other: SoldierAvatar
		for node: Node in network._avatar_root.get_children():
			if not node.is_local:
				other = node
		if other == null or other._skeleton == null:
			continue
		for voice: AudioStreamPlayer3D in other._audio._voices:
			if voice.stream != null:
				received_audio = true
		if server and player.menu_open and other.sync_position.distance_to(CLIENT_POSITION) > 0.08:
			remote_moved_during_menu = true
		if absf(other.sync_pitch - 0.3) > 0.01:
			continue
		if server and not sent and other.sync_position.distance_to(CLIENT_POSITION) < 0.05:
			# Allow interpolation / bone attachments to settle before tracing.
			await create_timer(1.0).timeout
			local.send_sound("shot", 0, -1.0, 1.0)
			_fire_at_head(network, player, other, 0)
			player.pause_menu.set_open(true)
			if paused or not network.active:
				push_error("NETWORK_ROUNDTRIP host menu stopped the match")
				quit(1)
				return
			sent = true
		elif not server and not sent and player.health == 15.0 and received_audio:
			# The host has its menu open. Exercise actual client locomotion and
			# replication before the client opens its own menu as well.
			var before := player.position
			player.velocity = Vector3.ZERO
			Input.action_press("move_right")
			for frame: int in 12:
				player._physics_process(1.0 / 60.0)
				await physics_frame
			Input.action_release("move_right")
			player.velocity = Vector3.ZERO
			if player.position.x < before.x + 0.1:
				push_error("NETWORK_ROUNDTRIP host menu prevented client movement")
				quit(1)
				return
			local.send_sound("step", 1, -5.0, 0.95)
			_fire_at_head(network, player, other, 1)
			player.pause_menu.set_open(true)
			if paused or not network.active:
				push_error("NETWORK_ROUNDTRIP client menu stopped the match")
				quit(1)
				return
			sent = true
		if server and player.health == 37.5 and received_audio and not killed:
			# Respect the real server fire-rate gate before the lethal follow-up.
			await create_timer(0.2).timeout
			_fire_at_head(network, player, other, 0)
			killed = true
		if not server and player.health <= 0.0:
			saw_death = true
			if not local.sync_dead:
				push_error("NETWORK_ROUNDTRIP dead state was not applied")
				quit(1)
				return
		if server and killed and network.health_of(other.peer_id) == 100.0:
			if not remote_moved_during_menu or not player.menu_open:
				push_error("NETWORK_ROUNDTRIP missing movement replication while host menu open")
				quit(1)
				return
			print("NETWORK_ROUNDTRIP server PASS: position/pitch, client movement during host menu, spatial audio, barrel raycasts/head multipliers, death/respawn with menu open")
			await create_timer(1.0).timeout
			await _shutdown(network)
			quit()
			return
		if not server and sent and saw_death and player.health == 100.0 and not local.sync_dead:
			if not player.menu_open:
				push_error("NETWORK_ROUNDTRIP respawn unexpectedly closed the menu")
				quit(1)
				return
			print("NETWORK_ROUNDTRIP client PASS: owned synchronizer, movement, shot audio, health replication, death/respawn with menu open")
			await create_timer(0.5).timeout
			await _shutdown(network)
			quit()
			return
	push_error("NETWORK_ROUNDTRIP TIMEOUT server=%s sent=%s audio=%s health=%s" % [server, sent, received_audio, player.health])
	network.leave_match()
	quit(1)

func _shutdown(network: Node) -> void:
	network.leave_match()
	current_scene.free()
	# Audio playback is released by the mixer, not synchronously by Node.free().
	for frame: int in 12:
		await physics_frame

func _fire_at_head(network: Node, player: PlayerController, target: SoldierAvatar, weapon: int) -> void:
	var area := target._hitboxes[0]
	var shape := area.get_child(0) as CollisionShape3D
	var origin := player.position + Vector3(0, 1.5, 0)
	var direction := (shape.global_position - origin).normalized()
	var excluded: Array[RID] = [player.get_rid()]
	for hitbox: Area3D in (network.local_avatar() as SoldierAvatar)._hitboxes:
		excluded.append(hitbox.get_rid())
	player.weapon_manager._select(weapon)
	var muzzle := player.weapon_manager.weapons[weapon].world_muzzle_position(player.camera)
	var trace := ShotBallistics.trace(player.get_world_3d().direct_space_state, origin, direction, muzzle, excluded)
	var collider := trace.get("collider") as Area3D
	print("ROUNDTRIP_SHOT muzzle_offset=", muzzle.distance_to(origin), " zone=", collider.get_meta("hit_zone", "none") if collider != null else "cover/miss")
	network.report_shot(origin, direction, weapon, muzzle)
