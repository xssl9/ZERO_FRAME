@tool
class_name PhotorealEnvironment
extends WorldEnvironment

enum QualityPreset { AUTO, PERFORMANCE, HIGH, ULTRA }

const DEFAULT_HDR := preload("res://assets/environment/sky/mud_road_puresky_2k.hdr")

@export_category("Photoreal preset")
@export var quality_preset: QualityPreset = QualityPreset.AUTO
@export var use_hdr_panorama: bool = true
@export var panorama: Texture2D = DEFAULT_HDR
@export_range(0.1, 4.0, 0.05) var sky_energy: float = 0.85
@export_range(0.0, 2.0, 0.05) var ambient_energy: float = 0.72
@export_range(0.1, 2.0, 0.01) var exposure_multiplier: float = 0.96
@export_range(-180.0, 180.0, 1.0) var sky_rotation_degrees: float = -18.0

func _ready() -> void:
	apply_preset()
	call_deferred("_configure_reflection_probes")

func apply_preset() -> void:
	if environment == null:
		environment = Environment.new()
	_configure_sky()
	_configure_color_and_exposure()
	_configure_quality()

func _configure_sky() -> void:
	environment.background_mode = Environment.BG_SKY
	environment.background_energy_multiplier = sky_energy
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.88
	environment.ambient_light_energy = ambient_energy
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.sky_rotation = Vector3(0.0, deg_to_rad(sky_rotation_degrees), 0.0)
	if not use_hdr_panorama or panorama == null:
		return
	var panorama_material := PanoramaSkyMaterial.new()
	panorama_material.panorama = panorama
	panorama_material.energy_multiplier = 1.0
	panorama_material.filter = true
	var hdr_sky := Sky.new()
	hdr_sky.sky_material = panorama_material
	# 512 keeps cloud silhouettes clean in the visible background and produces
	# noticeably less blocky reflections than the old 256px radiance cubemap.
	hdr_sky.radiance_size = Sky.RADIANCE_SIZE_512
	hdr_sky.process_mode = Sky.PROCESS_MODE_QUALITY
	environment.sky = hdr_sky

func _configure_color_and_exposure() -> void:
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 1.0
	# The previous contrast=1.3 crushed interiors and made PBR materials look
	# painted. AgX provides the shoulder without a second contrast operation.
	environment.adjustment_enabled = false
	environment.glow_enabled = true
	environment.glow_intensity = 0.08
	environment.glow_strength = 0.14
	environment.glow_bloom = 0.035
	if camera_attributes is CameraAttributesPhysical:
		var physical := camera_attributes as CameraAttributesPhysical
		physical.auto_exposure_enabled = false
		physical.exposure_sensitivity = 160.0
		physical.exposure_multiplier = exposure_multiplier

func _configure_quality() -> void:
	var method := RenderingServer.get_current_rendering_method()
	var forward_plus := method != "gl_compatibility" and method != "mobile"
	var effective := quality_preset
	if effective == QualityPreset.AUTO:
		var requested := int(ProjectSettings.get_setting("zero_frame/graphics_quality", QualityPreset.AUTO))
		effective = requested
		if effective == QualityPreset.AUTO:
			effective = QualityPreset.HIGH if forward_plus else QualityPreset.PERFORMANCE
	if not forward_plus:
		effective = QualityPreset.PERFORMANCE

	environment.ssao_enabled = true
	environment.ssao_radius = 0.9
	environment.ssao_intensity = 1.35
	environment.ssao_power = 1.25
	environment.ssao_detail = 0.55
	environment.ssao_horizon = 0.08
	environment.ssao_light_affect = 0.35
	environment.ssao_ao_channel_affect = 0.65
	environment.ssil_enabled = effective >= QualityPreset.HIGH
	environment.ssr_enabled = effective >= QualityPreset.HIGH
	environment.ssr_max_steps = 48 if effective >= QualityPreset.HIGH else 16
	environment.ssr_fade_in = 0.15
	environment.ssr_fade_out = 2.0
	environment.ssr_depth_tolerance = 0.12
	# SDFGI is deliberately Ultra-only: it is not ray tracing and is expensive
	# on the target Intel iGPU. High uses SSIL plus static reflection probes.
	environment.sdfgi_enabled = effective == QualityPreset.ULTRA
	environment.volumetric_fog_enabled = effective >= QualityPreset.HIGH
	environment.volumetric_fog_density = 0.0035
	environment.volumetric_fog_length = 55.0
	environment.volumetric_fog_detail_spread = 2.0
	environment.volumetric_fog_gi_inject = 0.45
	environment.fog_enabled = true
	environment.fog_density = 0.00065
	environment.fog_height_density = 0.012
	environment.fog_sky_affect = 0.08

func _configure_reflection_probes() -> void:
	var method := RenderingServer.get_current_rendering_method()
	var forward_plus := method != "gl_compatibility" and method != "mobile"
	var requested := int(ProjectSettings.get_setting("zero_frame/graphics_quality", QualityPreset.AUTO))
	var probes_enabled := forward_plus and requested != QualityPreset.PERFORMANCE
	var scene_root := get_tree().current_scene
	if scene_root == null:
		scene_root = get_parent()
	for node: Node in scene_root.find_children("*", "ReflectionProbe", true, false):
		(node as ReflectionProbe).visible = probes_enabled
