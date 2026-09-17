extends Node

## Steam bootstrap, lobby lifecycle and the peer-to-peer transport.
##
## Every public call in here is safe when Steam is absent. A headless regression
## run, or a machine with the client closed, leaves `available` false: the lobby
## calls turn into no-ops, `status_text` explains why, and the single-player game
## is completely unaffected. Nothing outside this file may assume Steam exists.

## Spacewar. The real app id replaces this the day the project has one; the file
## `steam_appid.txt` beside project.godot has to carry the same number, because
## the Steam client reads that file rather than the argument below.
const APP_ID: int = 480
const LOBBY_MEMBER_LIMIT: int = 8
## Steam Networking Sockets multiplexes several logical channels over one
## connection. Zero is ours; nothing else in the project opens a socket.
const VIRTUAL_PORT: int = 0

## Lobby-wide keys. `KEY_STATE` flipping to STATE_PLAYING is the single event that
## sends every member into the map, so it is written last, after the host is
## already listening.
const KEY_HOST := "host_steam_id"
const KEY_MAP := "map"
const KEY_STATE := "state"
const STATE_LOBBY := "lobby"
const STATE_PLAYING := "playing"
## Per-member key: "1" once that player has pressed ready.
const KEY_READY := "ready"

signal availability_changed(is_available: bool)
signal lobby_entered(lobby_id: int)
signal lobby_exited()
signal lobby_members_changed()
## Raised on every member, host included, when the host flips the lobby to
## STATE_PLAYING. NetworkGame is what listens.
signal match_requested(map_path: String)
signal status_changed(text: String)
signal avatar_ready(steam_id: int, texture: ImageTexture)

var available: bool = false
var steam_id: int = 0
var persona_name: String = ""
var lobby_id: int = 0
var status_text: String = "STEAM: НЕ ИНИЦИАЛИЗИРОВАН"

var _avatar_cache: Dictionary = {}
var _avatar_requested: Dictionary = {}
var _initialised: bool = false
var _creating_lobby := false

func _ready() -> void:
	# The pump has to keep running while the tree is paused: the pause menu is
	# exactly where a player accepts an invite.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_initialise()

func _initialise() -> void:
	if _initialised:
		return
	_initialised = true
	if DisplayServer.get_name() == "headless":
		_set_status("STEAM: HEADLESS — API ОТКЛЮЧЁН")
		return
	if not ClassDB.class_exists("Steam"):
		_set_status("STEAM: РАСШИРЕНИЕ НЕ ЗАГРУЖЕНО")
		return
	var result: Dictionary = Steam.steamInitEx(APP_ID, false)
	# GodotSteam returns {status, verbal}; status 0 is OK. Anything else means no
	# client, no ownership or no appid file, and all of them are non-fatal here.
	var status: int = int(result.get("status", -1))
	if status != 0:
		_set_status("STEAM: %s" % String(result.get("verbal", "ошибка инициализации")))
		return
	available = true
	steam_id = Steam.getSteamID()
	persona_name = Steam.getPersonaName()
	_set_status("STEAM: %s" % persona_name)
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.lobby_data_update.connect(_on_lobby_data_update)
	# Accepting an invite from the friends list or from the overlay both land here.
	Steam.join_requested.connect(_on_join_requested)
	Steam.avatar_loaded.connect(_on_avatar_loaded)
	availability_changed.emit(true)
	_check_command_line_invite()

func _process(_delta: float) -> void:
	if available:
		# Initialised with embed_callbacks = false, so the callback queue is ours
		# to drain. Without this no lobby signal ever fires.
		Steam.run_callbacks()

func _exit_tree() -> void:
	if available and lobby_id != 0:
		Steam.leaveLobby(lobby_id)

# A friend's "Join game" from outside a running client starts the game with
# +connect_lobby <id> on the command line instead of firing join_requested.
func _check_command_line_invite() -> void:
	var arguments := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for index: int in arguments.size() - 1:
		if arguments[index] == "+connect_lobby":
			var wanted: int = arguments[index + 1].to_int()
			if wanted > 0:
				join_lobby(wanted)
			return

func _set_status(text: String) -> void:
	status_text = text
	status_changed.emit(text)

# --- Lobby ----------------------------------------------------------------

func create_lobby() -> void:
	if not available or lobby_id != 0 or _creating_lobby:
		return
	_creating_lobby = true
	_set_status("СОЗДАНИЕ ЛОББИ…")
	Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, LOBBY_MEMBER_LIMIT)

func join_lobby(target_lobby: int) -> void:
	if not available or target_lobby == 0 or target_lobby == lobby_id:
		return
	if lobby_id != 0:
		leave_lobby()
	_set_status("ПОДКЛЮЧЕНИЕ К ЛОББИ…")
	Steam.joinLobby(target_lobby)

func leave_lobby() -> void:
	if not available or lobby_id == 0:
		return
	if is_host():
		Steam.setLobbyJoinable(lobby_id, false)
		Steam.setLobbyData(lobby_id, KEY_STATE, "closed")
	Steam.leaveLobby(lobby_id)
	lobby_id = 0
	_set_status("STEAM: %s" % persona_name)
	lobby_exited.emit()

func invite_friend() -> bool:
	if not available or lobby_id == 0:
		return false
	if not Steam.isOverlayEnabled():
		_set_status("ОВЕРЛЕЙ НЕДОСТУПЕН — ВЫБЕРИТЕ ДРУГА В СПИСКЕ")
		return false
	Steam.activateGameOverlayInviteDialog(lobby_id)
	return true

func friends() -> PackedInt64Array:
	var result: PackedInt64Array = []
	if available:
		for index: int in Steam.getFriendCount(Steam.FRIEND_FLAG_IMMEDIATE):
			result.append(Steam.getFriendByIndex(index, Steam.FRIEND_FLAG_IMMEDIATE))
	return result

func invite_user(friend_id: int) -> bool:
	if not available or lobby_id == 0 or not friend_id in friends():
		return false
	var sent := Steam.inviteUserToLobby(lobby_id, friend_id)
	_set_status("ПРИГЛАШЕНИЕ ОТПРАВЛЕНО" if sent else "НЕ УДАЛОСЬ ОТПРАВИТЬ ПРИГЛАШЕНИЕ")
	return sent

func is_host() -> bool:
	return available and lobby_id != 0 and Steam.getLobbyOwner(lobby_id) == steam_id

func members() -> PackedInt64Array:
	var result: PackedInt64Array = []
	if not available or lobby_id == 0:
		return result
	for index: int in Steam.getNumLobbyMembers(lobby_id):
		result.append(Steam.getLobbyMemberByIndex(lobby_id, index))
	return result

func member_name(member_steam_id: int) -> String:
	if not available:
		return "ИГРОК"
	if member_steam_id == steam_id:
		return persona_name
	return Steam.getFriendPersonaName(member_steam_id)

func set_ready(is_ready: bool) -> void:
	if not available or lobby_id == 0:
		return
	Steam.setLobbyMemberData(lobby_id, KEY_READY, "1" if is_ready else "0")

func is_member_ready(member_steam_id: int) -> bool:
	if not available or lobby_id == 0:
		return false
	return Steam.getLobbyMemberData(lobby_id, member_steam_id, KEY_READY) == "1"

func everyone_ready() -> bool:
	var list := members()
	if list.is_empty():
		return false
	for member: int in list:
		if not is_member_ready(member):
			return false
	return true

func host_steam_id() -> int:
	if not available or lobby_id == 0:
		return 0
	var stored := Steam.getLobbyData(lobby_id, KEY_HOST)
	return stored.to_int() if stored != "" else Steam.getLobbyOwner(lobby_id)

## Host only. Publishing the map and flipping the state is what starts the match
## on every member, so the caller must already be listening for connections.
func publish_match(map_path: String) -> void:
	if not is_host():
		return
	Steam.setLobbyData(lobby_id, KEY_HOST, str(steam_id))
	Steam.setLobbyData(lobby_id, KEY_MAP, map_path)
	Steam.setLobbyData(lobby_id, KEY_STATE, STATE_PLAYING)
	# Keep the existing lobby policy: no new lobby members during a round.
	# Members loading at different speeds are supported: NetworkGame builds the
	# spawn path before opening the transport and replays existing avatars.
	Steam.setLobbyJoinable(lobby_id, false)

func reopen_lobby() -> void:
	if not is_host():
		return
	Steam.setLobbyData(lobby_id, KEY_STATE, STATE_LOBBY)
	Steam.setLobbyJoinable(lobby_id, true)

# --- Transport ------------------------------------------------------------

## Both halves of the transport return an Error. The caller decides what a
## failure means; this only owns the peer object itself.
func open_as_host() -> int:
	if not available:
		return ERR_UNAVAILABLE
	var peer := SteamMultiplayerPeer.new()
	var error := peer.create_host(VIRTUAL_PORT)
	if error != OK:
		_set_status("НЕ УДАЛОСЬ ОТКРЫТЬ СОКЕТ (%d)" % error)
		return error
	multiplayer.multiplayer_peer = peer
	return OK

func open_as_client(host_id: int) -> int:
	if not available:
		return ERR_UNAVAILABLE
	var peer := SteamMultiplayerPeer.new()
	var error := peer.create_client(host_id, VIRTUAL_PORT)
	if error != OK:
		_set_status("НЕ УДАЛОСЬ ПОДКЛЮЧИТЬСЯ (%d)" % error)
		return error
	multiplayer.multiplayer_peer = peer
	return OK

func close_transport() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null

# --- Avatars --------------------------------------------------------------

## Steam hands avatars over asynchronously. The texture arrives on `avatar_ready`
## which may fire before or after the caller has built its row, so the cache is
## checked first and the signal is only a fallback.
func request_avatar(member_steam_id: int) -> ImageTexture:
	if not available:
		return null
	if _avatar_cache.has(member_steam_id):
		return _avatar_cache[member_steam_id] as ImageTexture
	if not _avatar_requested.has(member_steam_id):
		_avatar_requested[member_steam_id] = true
		# getMediumFriendAvatar only returns an image handle. This wrapper
		# requests pixel data and emits avatar_loaded(size, buffer).
		Steam.getPlayerAvatar(2, member_steam_id)
	return null

func _on_avatar_loaded(loaded_id: int, size: int, buffer: PackedByteArray) -> void:
	if size <= 0 or buffer.is_empty():
		return
	var image := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, buffer)
	if image == null:
		return
	var texture := ImageTexture.create_from_image(image)
	_avatar_cache[loaded_id] = texture
	avatar_ready.emit(loaded_id, texture)

# --- Steam callbacks ------------------------------------------------------

func _on_lobby_created(connect_result: int, created_lobby: int) -> void:
	_creating_lobby = false
	if connect_result != 1:
		_set_status("ЛОББИ НЕ СОЗДАНО (%d)" % connect_result)
		return
	lobby_id = created_lobby
	Steam.setLobbyData(lobby_id, KEY_HOST, str(steam_id))
	Steam.setLobbyData(lobby_id, KEY_STATE, STATE_LOBBY)
	Steam.setLobbyJoinable(lobby_id, true)
	_set_status("ЛОББИ СОЗДАНО")
	lobby_entered.emit(lobby_id)
	lobby_members_changed.emit()

func _on_lobby_joined(joined_lobby: int, _permissions: int, _locked: bool, response: int) -> void:
	# 1 == k_EChatRoomEnterResponseSuccess.
	if response != 1:
		_set_status("ВХОД В ЛОББИ ОТКЛОНЁН (%d)" % response)
		return
	lobby_id = joined_lobby
	Steam.setLobbyMemberData(lobby_id, KEY_READY, "0")
	_set_status("В ЛОББИ")
	lobby_entered.emit(lobby_id)
	lobby_members_changed.emit()
	# A lobby that was already playing when we arrived starts us straight away.
	if Steam.getLobbyData(lobby_id, KEY_STATE) == STATE_PLAYING:
		_emit_match_request()

func _on_lobby_chat_update(updated_lobby: int, _changed_id: int, _making_change_id: int, _chat_state: int) -> void:
	if updated_lobby != lobby_id:
		return
	if _host_left():
		return
	lobby_members_changed.emit()

func _host_left() -> bool:
	var original_host := host_steam_id()
	if Steam.getLobbyData(lobby_id, KEY_STATE) == "closed" or (original_host != 0 and original_host != Steam.getLobbyOwner(lobby_id)):
		leave_lobby()
		_set_status("ХОСТ ЗАКРЫЛ ЛОББИ")
		return true
	return false

func _on_lobby_data_update(success: int, updated_lobby: int, _member_id: int) -> void:
	if success == 0 or updated_lobby != lobby_id or lobby_id == 0:
		return
	if _host_left():
		return
	lobby_members_changed.emit()
	if Steam.getLobbyData(lobby_id, KEY_STATE) == STATE_PLAYING:
		_emit_match_request()

func _on_join_requested(target_lobby: int, _friend_id: int) -> void:
	join_lobby(target_lobby)

func _emit_match_request() -> void:
	var map_path := Steam.getLobbyData(lobby_id, KEY_MAP)
	if map_path == "":
		return
	match_requested.emit(map_path)
