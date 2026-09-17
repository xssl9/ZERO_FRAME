extends SceneTree

# Run without --headless, with the Steam client running. Creates and leaves a
# temporary Friends Only lobby; never sends invitations to other accounts.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var steam := root.get_node("SteamManager")
	if not steam.available:
		push_error("STEAM_SMOKE UNVERIFIED: " + steam.status_text)
		quit(1)
		return
	steam.create_lobby()
	var deadline := Time.get_ticks_msec() + 15000
	while steam.lobby_id == 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	if steam.lobby_id == 0:
		push_error("STEAM_SMOKE: lobby creation timed out")
		quit(1)
		return
	# lobby_created and lobby_joined are separate queued callbacks.
	await create_timer(0.5).timeout
	steam.set_ready(true)
	await create_timer(0.5).timeout
	var valid: bool = steam.is_host() and steam.members().size() == 1 and steam.everyone_ready()
	var texture: Texture2D = steam.request_avatar(steam.steam_id)
	var avatar_received := [texture != null]
	steam.avatar_ready.connect(func(_id: int, _texture: ImageTexture) -> void: avatar_received[0] = true)
	await create_timer(2.0).timeout
	print("STEAM_SMOKE lobby/ready=", valid, " avatar=", avatar_received[0], " overlay_available=", Steam.isOverlayEnabled(), " friends_count=", steam.friends().size())
	var menu := (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	await process_frame
	menu._show_friends()
	valid = valid and menu._lobby_panel.visible and menu._member_avatars.size() == 1 and menu._friends_dialog.visible
	print("STEAM_SMOKE lobby UI / fallback friend picker=", valid)
	steam.leave_lobby()
	await create_timer(0.2).timeout
	valid = valid and steam.lobby_id == 0 and not menu._friends_dialog.visible
	menu.free()
	for frame: int in 12:
		await physics_frame
	quit(0 if valid else 1)
