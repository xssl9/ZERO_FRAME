class_name SoldierAvatar
extends Node3D

## Networked soldier avatar visible to all peers.
##
## The local peer's avatar is invisible: body awareness lives on
## PlayerController, and this node only pushes state to the synchroniser.
## Remote avatars display the full soldier model with 8-way locomotion,
## per-bone hitboxes and a weapon proxy attached to the right hand.

const MODEL_PATH := "res://IMPORTANT_MULTIPLAYER_ASSETS/soldier_rifle_locomotion.glb"
const INTERP_SPEED := 14.0

# --- Replicated state (authority writes, remotes read) --------------------

var sync_position: Vector3 = Vector3.ZERO
var sync_rotation_y: float = 0.0
var sync_pitch: float = 0.0
var sync_velocity: Vector3 = Vector3.ZERO
var sync_crouching: bool = false
var sync_aiming: bool = false
var sync_sprinting: bool = false
var sync_airborne: bool = false
var sync_dead: bool = false
var sync_weapon_index: int = 0

var peer_id: int = 0
var steam_id: int = 0
var is_local: bool = false

var _model: Node3D
var _skeleton: Skeleton3D
var _animation_player: AnimationPlayer
var _animation_tree: AnimationTree
var _locomotion: SoldierLocomotion
var _rig_modifier: SoldierRigModifier
var _weapon_attach: BoneAttachment3D
var _weapon_proxies: Array[Node3D] = []
var _hitboxes: Array[Area3D] = []

# --- Public API (called by NetworkGame) -----------------------------------

func configure(p_peer: int, p_steam_id: int) -> void:
	peer_id = p_peer
	steam_id = p_steam_id

func set_dead(dead: bool) -> void:
	sync_dead = dead
	if dead and _locomotion != null:
		_locomotion.play_death("torso", sync_crouching, false)

# --- Lifecycle ------------------------------------------------------------

func _ready() -> void:
	if peer_id == 0:
		return
	# Determine locality once inside the tree where multiplayer API is valid.
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		is_local = is_multiplayer_authority()
	else:
		is_local = true
	_build()

func _build() -> void:
	_build_synchronizer()
	if is_local:
		# Body awareness lives on PlayerController — local avatar just syncs.
		visible = false
		return
	# Remote avatar: load full model, locomotion, hitboxes, weapon.
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("SOLDIER_AVATAR: не удалось загрузить %s" % MODEL_PATH)
		return
	_model = packed.instantiate()
	_model.name = "SoldierModel"
	add_child(_model)
	_find_skeleton_and_player()
	if _skeleton == null or _animation_player == null:
		push_error("SOLDIER_AVATAR: Skeleton3D или AnimationPlayer не найдены")
		return
	# AnimationTree — must sit inside the same subtree as the AnimationPlayer.
	_animation_tree = AnimationTree.new()
	_animation_tree.name = "SoldierAnimTree"
	_model.add_child(_animation_tree)
	# 8-way locomotion via the shared builder.
	_locomotion = SoldierLocomotion.new()
	_locomotion.name = "Locomotion"
	add_child(_locomotion)
	if not _locomotion.build(_animation_tree, _animation_player):
		push_warning("SOLDIER_AVATAR: locomotion build вернул false")
	# Rig modifier for aim pitch (no upper-body hiding — full body visible).
	_rig_modifier = SoldierRigModifier.new()
	_rig_modifier.name = "AimModifier"
	_rig_modifier.hide_upper_body = false
	_skeleton.add_child(_rig_modifier)
	# Per-bone hitboxes on collision layer 3.
	_hitboxes = SoldierHitboxes.build(_skeleton, self, peer_id)
	# Weapon proxy mesh in the right hand.
	_build_weapon_attachment()

func _find_skeleton_and_player() -> void:
	for child: Node in _model.find_children("*", "Skeleton3D", true, false):
		_skeleton = child as Skeleton3D
		break
	for child: Node in _model.find_children("*", "AnimationPlayer", true, false):
		_animation_player = child as AnimationPlayer
		break

# --- Weapon proxy ---------------------------------------------------------

func _build_weapon_attachment() -> void:
	if _skeleton == null:
		return
	var hand_idx := _skeleton.find_bone("mixamorig_RightHand")
	if hand_idx < 0:
		push_warning("SOLDIER_AVATAR: mixamorig_RightHand не найдена")
		return
	_weapon_attach = BoneAttachment3D.new()
	_weapon_attach.name = "WeaponAttach"
	_weapon_attach.bone_name = "mixamorig_RightHand"
	_weapon_attach.bone_idx = hand_idx
	_skeleton.add_child(_weapon_attach)
	# AK-74M proxy (dark steel box with stock proportions).
	var ak := _weapon_proxy("AK", Vector3(0.05, 0.06, 0.72), Color(0.18, 0.17, 0.16))
	ak.position = Vector3(0.0, 0.03, -0.34)
	_weapon_attach.add_child(ak)
	_weapon_proxies.append(ak)
	# Pistol proxy.
	var pistol := _weapon_proxy("Pistol", Vector3(0.035, 0.13, 0.20), Color(0.14, 0.14, 0.13))
	pistol.position = Vector3(0.0, -0.01, -0.09)
	pistol.visible = false
	_weapon_attach.add_child(pistol)
	_weapon_proxies.append(pistol)

static func _weapon_proxy(wname: String, box_size: Vector3, color: Color) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.name = "%sProxy" % wname
	var box := BoxMesh.new()
	box.size = box_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.82
	mat.metallic = 0.35
	box.material = mat
	inst.mesh = box
	return inst

# --- Synchronizer ---------------------------------------------------------

func _build_synchronizer() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Synchronizer"
	var config := SceneReplicationConfig.new()
	for prop: String in [
		"sync_position", "sync_rotation_y", "sync_pitch", "sync_velocity",
		"sync_crouching", "sync_aiming", "sync_sprinting", "sync_airborne",
		"sync_dead", "sync_weapon_index"]:
		config.add_property(NodePath(".:%s" % prop))
	sync.replication_config = config
	add_child(sync)

# --- Per-frame update -----------------------------------------------------

func _process(delta: float) -> void:
	if peer_id == 0:
		return
	if is_local:
		_push_local_state()
	else:
		_apply_remote_state(delta)

func _push_local_state() -> void:
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player == null:
		return
	sync_position = player.global_position
	sync_rotation_y = player.global_rotation.y
	# The pitch pivot sits above the camera in the bodycam rig.
	if player.bodycam != null:
		var pivot := player.bodycam.get_parent() as Node3D
		if pivot != null:
			sync_pitch = pivot.rotation.x
	sync_velocity = player.velocity
	sync_crouching = Input.is_action_pressed("crouch")
	sync_aiming = Input.is_action_pressed("aim")
	var h_speed := Vector2(player.velocity.x, player.velocity.z).length()
	sync_sprinting = Input.is_action_pressed("sprint") and h_speed > PlayerController.SPRINT_SPEED * 0.6
	sync_airborne = not player.is_on_floor()
	if player.weapon_manager != null:
		sync_weapon_index = player.weapon_manager.current_index

func _apply_remote_state(delta: float) -> void:
	var w := 1.0 - exp(-INTERP_SPEED * delta)
	global_position = global_position.lerp(sync_position, w)
	global_rotation.y = lerp_angle(global_rotation.y, sync_rotation_y, w)
	# Drive aim pitch on the skeleton modifier.
	if _rig_modifier != null:
		_rig_modifier.aim_pitch = rad_to_deg(sync_pitch)
	# Locomotion: convert velocity into skeleton-local space.
	if _locomotion != null:
		var local_vel := global_transform.basis.inverse() * sync_velocity
		_locomotion.update(local_vel, sync_crouching, sync_aiming, sync_sprinting, sync_airborne, sync_dead, delta)
	# Toggle weapon proxy visibility.
	if _weapon_proxies.size() >= 2:
		_weapon_proxies[0].visible = (sync_weapon_index == 0)
		_weapon_proxies[1].visible = (sync_weapon_index == 1)
