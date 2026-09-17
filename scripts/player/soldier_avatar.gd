class_name SoldierAvatar
extends Node3D

## Networked soldier avatar visible to all peers.
##
## The local peer's avatar is invisible: body awareness lives on
## PlayerController. This node replicates state and maintains an unculled rig
## for the host's hit validation, including the host's own hitboxes.
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
var sync_flashlight: bool = false
var _flashlight: SpotLight3D
var _received_pose: bool = false
var _audio: SoldierAudio

func send_sound(event: String, variant: int, gain: float, pitch: float) -> void:
	if is_local and not sync_dead:
		_receive_sound.rpc(event, variant, gain, pitch)

@rpc("authority", "call_remote", "reliable")
func _receive_sound(event: String, variant: int, gain: float, pitch: float) -> void:
	if _audio != null and not sync_dead:
		_audio.play_event(event, variant, gain, pitch)

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
var _ragdoll: SoldierRagdoll

# --- Public API (called by NetworkGame) -----------------------------------

func configure(p_peer: int, p_steam_id: int) -> void:
	peer_id = p_peer
	steam_id = p_steam_id

func set_dead(dead: bool) -> void:
	if sync_dead == dead:
		return
	sync_dead = dead
	for area: Area3D in _hitboxes:
		area.set_deferred("collision_layer", 0 if dead else SoldierHitboxes.layer_mask())
	if dead and _audio != null:
		_audio.play_event("reload_stop", 0, 0, 1)
	if _ragdoll != null:
		_animation_tree.active = not dead
		_rig_modifier.active = not dead
		if dead:
			_animation_player.stop(true)
			_ragdoll.start(sync_velocity)
		else:
			_ragdoll.stop()
			_received_pose = false

# --- Lifecycle ------------------------------------------------------------

func _ready() -> void:
	# Remote poses are already interpolated below; do not interpolate them twice.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	# A local full rig is still needed for server-side hit validation. It is
	# hidden, not deleted; the separate body-awareness rig only affects rendering.
	_model = SoldierModel.instantiate()
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
	_ragdoll = SoldierRagdoll.new()
	_ragdoll.name = "Ragdoll"
	_skeleton.add_child(_ragdoll)
	# Per-bone hitboxes on collision layer 3.
	_hitboxes = SoldierHitboxes.build(_skeleton, self, peer_id)
	# Weapon proxy mesh in the right hand.
	_build_weapon_attachment()
	_flashlight = SpotLight3D.new()
	_flashlight.light_energy = 7.0
	_flashlight.spot_range = 24.0
	_flashlight.spot_angle = 23.0
	_flashlight.shadow_enabled = true
	_flashlight.spot_angle_attenuation = 1.6
	_flashlight.visible = false
	add_child(_flashlight)
	_audio = SoldierAudio.new()
	_audio.name = "SpatialAudio"
	add_child(_audio)

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
	_animation_tree.active = false
	_animation_player.play("idle")
	_animation_player.advance(0.0)
	var hand := global_transform.affine_inverse() * _skeleton.global_transform * _skeleton.get_bone_global_pose(hand_idx)
	for index: int in 2:
		var weapon := SoldierWeapon.build(index, self, hand)
		_weapon_attach.add_child(weapon)
		weapon.visible = index == sync_weapon_index
		_weapon_proxies.append(weapon)
	_animation_player.stop(true)
	_animation_tree.active = true

# --- Synchronizer ---------------------------------------------------------

func _build_synchronizer() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Synchronizer"
	var config := SceneReplicationConfig.new()
	for prop: String in [
		"sync_position", "sync_rotation_y", "sync_pitch", "sync_velocity",
		"sync_crouching", "sync_aiming", "sync_sprinting", "sync_airborne",
		"sync_weapon_index", "sync_flashlight"]:
		config.add_property(NodePath(".:%s" % prop))
	sync.replication_config = config
	sync.set_multiplayer_authority(peer_id)
	sync.replication_interval = 1.0 / 30.0
	add_child(sync)

# --- Per-frame update -----------------------------------------------------

func _process(delta: float) -> void:
	if peer_id == 0:
		return
	if is_local:
		_push_local_state()
	_apply_remote_state(delta)

func _push_local_state() -> void:
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player == null:
		return
	sync_position = player.global_position
	sync_rotation_y = player.global_rotation.y
	# The pitch pivot sits above the camera in the bodycam rig.
	if player.bodycam != null:
		sync_pitch = player.bodycam.rotation.x
	sync_velocity = player.velocity
	sync_crouching = player.crouching
	sync_aiming = player.gameplay_input_enabled() and Input.is_action_pressed("aim")
	sync_sprinting = player.sprinting
	sync_airborne = not player.is_on_floor()
	sync_flashlight = player.flashlight.visible
	if player.weapon_manager != null:
		sync_weapon_index = player.weapon_manager.current_index

func _apply_remote_state(delta: float) -> void:
	if sync_dead:
		if _flashlight != null:
			_flashlight.visible = false
		return
	var w := 1.0 - exp(-INTERP_SPEED * delta)
	if is_local or not _received_pose or global_position.distance_to(sync_position) > 4.0:
		global_position = sync_position
		global_rotation.y = sync_rotation_y
		_received_pose = true
		reset_physics_interpolation()
	else:
		global_position = global_position.lerp(sync_position, w)
		global_rotation.y = lerp_angle(global_rotation.y, sync_rotation_y, w)
	if _flashlight != null:
		_flashlight.visible = sync_flashlight and not is_local and not sync_dead
		if not _weapon_proxies.is_empty():
			var mount := _weapon_proxies[clampi(sync_weapon_index, 0, 1)].get_node("FlashlightMount") as Marker3D
			_flashlight.global_transform = mount.global_transform.orthonormalized()
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
