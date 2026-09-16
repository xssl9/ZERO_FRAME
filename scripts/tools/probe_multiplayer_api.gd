extends SceneTree

# Probes what the vendored GodotSteam build actually exposes, so the networking
# layer is written against the real API surface rather than against the docs of
# whichever GodotSteam version the addon happens to be.

func _initialize() -> void:
	for class_name_probe: String in ["Steam", "SteamMultiplayerPeer", "SteamPeer", "AnimationNodeBlendSpace2D", "AnimationNodeStateMachine", "MultiplayerSpawner", "MultiplayerSynchronizer"]:
		print("CLASS %s exists=%s" % [class_name_probe, ClassDB.class_exists(class_name_probe)])
	if ClassDB.class_exists("Steam"):
		var wanted: PackedStringArray = [
			"steamInit", "steamInitEx", "createLobby", "joinLobby", "leaveLobby",
			"activateGameOverlayInviteDialog", "getSteamID", "getPersonaName",
			"getFriendPersonaName", "setLobbyData", "getLobbyData", "setLobbyMemberData",
			"getLobbyMemberData", "getNumLobbyMembers", "getLobbyMemberByIndex",
			"getLobbyOwner", "run_callbacks", "runCallbacks", "setLobbyJoinable",
			"getSmallFriendAvatar", "getMediumFriendAvatar", "loadAvatar"]
		for method: String in wanted:
			print("  Steam.%s=%s" % [method, ClassDB.class_has_method("Steam", method, true)])
		var signals := ClassDB.class_get_signal_list("Steam", true)
		var interesting := ["lobby_created", "lobby_joined", "lobby_chat_update", "lobby_invite", "join_requested", "lobby_message", "lobby_data_update", "avatar_loaded", "persona_state_change"]
		for entry: Dictionary in signals:
			if String(entry["name"]) in interesting:
				print("  SIGNAL ", entry["name"], " args=", entry["args"].size())
	if ClassDB.class_exists("SteamMultiplayerPeer"):
		for method: String in ["create_host", "create_client", "createHost", "createClient", "create_lobby", "connect_lobby"]:
			print("  SteamMultiplayerPeer.%s=%s" % [method, ClassDB.class_has_method("SteamMultiplayerPeer", method, true)])
	# AnimationNodeAnimation gained a loop_mode override in 4.4; if it is here the
	# imported clips can loop without mutating the shared imported resources.
	var probe := AnimationNodeAnimation.new()
	print("AnimationNodeAnimation.loop_mode=", probe.get("loop_mode") != null)
	print("AnimationNodeAnimation.use_custom_timeline=", probe.get("use_custom_timeline") != null)
	quit()
