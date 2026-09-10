@tool
class_name RealismManager
extends Node

## Centralized visual quality parameters for ZERO_FRAME photorealism.
## All key rendering knobs live here so they can be tuned without hunting
## through dozens of files. The manager pushes values to the relevant systems
## on change, so editing in the Inspector is live in the editor.
##
## Attach to the level root or to PhotorealEnvironment as a child.

@export_category("Surface Quality")
## Global roughness variation multiplier. Higher = more micro-detail on surfaces.
## 0.08 is the authored default; 0.12 adds visible wear without looking noisy.
@export_range(0.0, 0.3, 0.005) var roughness_variation: float = 0.08:
	set(value):
		roughness_variation = value
		_push_to_wetness()

## Global dust amount on upward-facing surfaces.
@export_range(0.0, 1.0, 0.01) var dust_amount: float = 0.0:
	set(value):
		dust_amount = value
		_push_surface_params()

## Global stain amount (water marks, oil, chemical residue).
@export_range(0.0, 1.0, 0.01) var stain_amount: float = 0.0:
	set(value):
		stain_amount = value
		_push_surface_params()

@export_category("Atmosphere")
## Fog density multiplier. 1.0 = weather profile default.
@export_range(0.0, 4.0, 0.05) var fog_density_scale: float = 1.0:
	set(value):
		fog_density_scale = value
		_push_atmosphere()

## Atmosphere density multiplier (volumetric fog / light shafts).
@export_range(0.0, 4.0, 0.05) var atmosphere_density_scale: float = 1.0:
	set(value):
		atmosphere_density_scale = value
		_push_atmosphere()

@export_category("Wetness")
## Current wetness level (0 = dry, 1 = fully soaked).
## Normally driven by WetnessManager from weather; override here for testing.
@export_range(-1.0, 1.0, 0.01) var wetness_override: float = -1.0:
	set(value):
		wetness_override = value
		_push_to_wetness()

@export_category("Exposure")
## Exposure adaptation speed multiplier. 1.0 = authored default.
@export_range(0.1, 3.0, 0.05) var adaptation_speed_scale: float = 1.0:
	set(value):
		adaptation_speed_scale = value
		_push_exposure()

## Minimum scene luminance the exposure controller targets.
@export_range(0.05, 0.5, 0.01) var exposure_minimum: float = 0.14:
	set(value):
		exposure_minimum = value
		_push_exposure()

## Maximum scene luminance the exposure controller targets.
@export_range(1.0, 5.0, 0.1) var exposure_maximum: float = 3.2:
	set(value):
		exposure_maximum = value
		_push_exposure()

@export_category("Camera")
## Bodycam lens distortion strength.
@export_range(0.0, 0.06, 0.001) var lens_distortion: float = 0.018:
	set(value):
		lens_distortion = value
		_push_camera()

## Bodycam chromatic aberration strength.
@export_range(0.0, 0.003, 0.0001) var chromatic_aberration: float = 0.0006:
	set(value):
		chromatic_aberration = value
		_push_camera()

## Bodycam sensor grain strength.
@export_range(0.0, 0.5, 0.01) var grain_strength: float = 0.08:
	set(value):
		grain_strength = value
		_push_camera()

## Bodycam vignette darkness.
@export_range(0.0, 0.5, 0.01) var vignette_darkness: float = 0.22:
	set(value):
		vignette_darkness = value
		_push_camera()

## Bodycam compression artifact strength (h.264 banding simulation).
@export_range(0.0, 0.2, 0.01) var compression_strength: float = 0.04:
	set(value):
		compression_strength = value
		_push_camera()

var _environment: PhotorealEnvironment
var _bodycam_material: ShaderMaterial

func _ready() -> void:
	call_deferred("_bind")

func _bind() -> void:
	# Find PhotorealEnvironment in the scene.
	for candidate: Node in get_tree().get_nodes_in_group("photoreal_environment"):
		if candidate.get_viewport() == get_viewport():
			_environment = candidate as PhotorealEnvironment
			break
	if _environment == null:
		_environment = get_parent() as PhotorealEnvironment
	if _environment == null:
		return
	if not _environment.preset_applied.is_connected(_push_all):
		_environment.preset_applied.connect(_push_all)
	# Menu previews and gameplay can coexist: never bind another world's player.
	for player: Node in get_tree().get_nodes_in_group("player"):
		if player.get_viewport() != _environment.get_viewport():
			continue
		for child: Node in player.find_children("*", "ColorRect", true, false):
			var mat := (child as ColorRect).material as ShaderMaterial
			if mat != null and mat.shader != null and mat.shader.resource_path == "res://shaders/bodycam.gdshader":
				_bodycam_material = mat
				break
	_push_all()

func _push_all() -> void:
	_push_to_wetness()
	_push_surface_params()
	_push_atmosphere()
	_push_exposure()
	_push_camera()

func _push_to_wetness() -> void:
	if _environment == null or _environment.wetness_manager == null:
		return
	_environment.wetness_manager.roughness_variation = roughness_variation
	var natural := _environment.standing_water if _environment.standing_water >= 0.0 else _environment.profile.wetness
	_environment.wetness_manager.target_wetness = wetness_override if wetness_override >= 0.0 else natural
	_environment.wetness_manager.publish()

func _push_surface_params() -> void:
	if _environment == null or _environment.wetness_manager == null:
		return
	for material: ShaderMaterial in _environment.wetness_manager.materials:
		if material.shader == null:
			continue
		for parameter: Dictionary in material.shader.get_shader_uniform_list():
			if parameter.name == "dust_amount":
				material.set_shader_parameter("dust_amount", dust_amount)
			elif parameter.name == "stain_amount":
				material.set_shader_parameter("stain_amount", stain_amount)

func _push_atmosphere() -> void:
	if _environment == null or _environment.environment == null or _environment.profile == null:
		return
	var env := _environment.environment
	# Resolved baseline retains scan/interior attenuation; never compound multipliers.
	env.volumetric_fog_density = _environment.atmosphere_density_in_effect() * atmosphere_density_scale
	env.fog_density = _environment.profile.fog_density * fog_density_scale

func _push_exposure() -> void:
	if _environment == null or _environment.exposure_controller == null:
		return
	var ec := _environment.exposure_controller
	ec.minimum = exposure_minimum
	ec.maximum = exposure_maximum
	ec.brighten_stops_per_second = 0.6 * adaptation_speed_scale
	ec.darken_stops_per_second = 1.2 * adaptation_speed_scale
	ec.refresh_target()

func _push_camera() -> void:
	if _bodycam_material == null:
		return
	_bodycam_material.set_shader_parameter("fisheye_strength", lens_distortion)
	_bodycam_material.set_shader_parameter("channel_offset", chromatic_aberration)
	_bodycam_material.set_shader_parameter("grain_strength", grain_strength)
	_bodycam_material.set_shader_parameter("vignette_darkness", vignette_darkness)
	_bodycam_material.set_shader_parameter("compression_strength", compression_strength)
