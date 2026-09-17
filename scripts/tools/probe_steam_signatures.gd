extends SceneTree

# GodotSteam's method signatures move between releases. Printing the real ones is
# cheaper than guessing and getting a silent runtime error inside a lobby callback.

const WANTED: PackedStringArray = [
	"steamInit", "steamInitEx", "createLobby", "joinLobby", "leaveLobby",
	"activateGameOverlayInviteDialog", "getSteamID", "getPersonaName",
	"setLobbyData", "getLobbyData", "setLobbyMemberData", "getLobbyMemberData",
	"getNumLobbyMembers", "getLobbyMemberByIndex", "getLobbyOwner",
	"run_callbacks", "setLobbyJoinable", "getFriendPersonaName",
	"getSmallFriendAvatar", "isSteamRunning", "inviteUserToLobby",
	"setLobbyType", "getLobbyOwner", "isOverlayEnabled", "getFriendCount",
	"getFriendByIndex", "getFriendPersonaState", "getMediumFriendAvatar", "getPlayerAvatar"]

func _initialize() -> void:
	for method: Dictionary in ClassDB.class_get_method_list("Steam", true):
		var method_name := String(method["name"])
		if not method_name in WANTED:
			continue
		var parts: PackedStringArray = []
		for argument: Dictionary in method["args"]:
			parts.append("%s: %s" % [argument["name"], _type_name(argument)])
		print("Steam.%s(%s) -> %s" % [method_name, ", ".join(parts), _type_name(method["return"])])
	print("---")
	for method: Dictionary in ClassDB.class_get_method_list("SteamMultiplayerPeer", true):
		var method_name := String(method["name"])
		if not method_name.begins_with("create") and not method_name.begins_with("set_") :
			continue
		var parts: PackedStringArray = []
		for argument: Dictionary in method["args"]:
			parts.append("%s: %s" % [argument["name"], _type_name(argument)])
		print("SteamMultiplayerPeer.%s(%s) -> %s" % [method_name, ", ".join(parts), _type_name(method["return"])])
	print("---")
	for entry: Dictionary in ClassDB.class_get_signal_list("Steam", true):
		if String(entry["name"]) in ["lobby_created", "lobby_joined", "lobby_chat_update", "join_requested", "lobby_data_update", "lobby_invite"]:
			var parts: PackedStringArray = []
			for argument: Dictionary in entry["args"]:
				parts.append("%s: %s" % [argument["name"], _type_name(argument)])
			print("SIGNAL %s(%s)" % [entry["name"], ", ".join(parts)])
	print("---")
	for constant: String in ClassDB.class_get_enum_constants("Steam", "LobbyType", true):
		print("LobbyType.", constant, "=", ClassDB.class_get_integer_constant("Steam", constant))
	for constant: String in ClassDB.class_get_enum_constants("Steam", "ChatMemberStateChange", true):
		print("ChatMemberStateChange.", constant, "=", ClassDB.class_get_integer_constant("Steam", constant))
	quit()

func _type_name(entry: Dictionary) -> String:
	var type_id: int = int(entry["type"])
	if type_id == TYPE_OBJECT and String(entry.get("class_name", "")) != "":
		return String(entry["class_name"])
	return type_string(type_id)
