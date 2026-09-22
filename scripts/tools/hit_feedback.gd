class_name HitFeedback
extends Node

## Hit Feedback / Game Feel
##
## Provides:
##   - Cosmetic feedback only: never pauses local or network simulation
##   - Camera kick + shake via PlayerController.add_camera_impulse
##   - 3D debug marker at the hit point (visible when dev panel "Debug Hit Info" is on)
##
## Usage: call HitFeedback.on_hit(hit_dict, zone, player) from weapon_base after
## a confirmed hitbox hit. The singleton is added to the scene tree by DevPanel.

const CAMERA_KICK_PITCH := 0.18          # degrees of upward kick
const CAMERA_KICK_YAW := 0.06
const CAMERA_KICK_ROLL := 0.04
const MARKER_LIFETIME := 4.0
const MARKER_RADIUS := 0.045

## Set by DevPanel; when false the 3D markers are not spawned.
var debug_hit_info: bool = false

## Called by weapon_base._fire_hitscan() after a hitbox is confirmed.
## `hit`  — the Dictionary returned by ShotBallistics.trace()
## `zone` — "head" / "torso" / "limbs"
## `avatar` — the SoldierAvatar (or any Node3D) that was hit; may be null
func on_hit(hit: Dictionary, zone: String, avatar: Node3D) -> void:
	_do_camera_kick(zone)
	if debug_hit_info and not hit.is_empty():
		_spawn_debug_marker(hit.get("position", Vector3.ZERO), zone)

func _do_camera_kick(zone: String) -> void:
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player == null:
		return
	var pitch := CAMERA_KICK_PITCH * (1.5 if zone == "head" else 1.0)
	var yaw   := randf_range(-CAMERA_KICK_YAW, CAMERA_KICK_YAW)
	var roll  := randf_range(-CAMERA_KICK_ROLL, CAMERA_KICK_ROLL)
	player.add_camera_impulse(pitch, yaw, roll)

func _spawn_debug_marker(world_pos: Vector3, zone: String) -> void:
	var host: Node = get_tree().current_scene
	if host == null:
		return
	var marker := MeshInstance3D.new()
	marker.name = "HitDebugMarker"
	var sphere := SphereMesh.new()
	sphere.radius = MARKER_RADIUS
	sphere.height = MARKER_RADIUS * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	marker.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _zone_color(zone)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.85
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(marker)
	marker.global_position = world_pos
	# Fade and free after lifetime.
	var tween := create_tween()
	tween.tween_interval(MARKER_LIFETIME * 0.6)
	tween.tween_property(mat, "albedo_color:a", 0.0, MARKER_LIFETIME * 0.4)
	tween.tween_callback(marker.queue_free)

func _zone_color(zone: String) -> Color:
	match zone:
		"head":
			return Color(1.0, 0.15, 0.1)   # red
		"torso":
			return Color(1.0, 0.65, 0.0)   # orange
		_:
			return Color(0.2, 0.8, 1.0)    # cyan for limbs
