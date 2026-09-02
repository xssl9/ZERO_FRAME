@tool
class_name PhotorealEnvironment
extends WorldEnvironment

enum QualityPreset { AUTO, PERFORMANCE, HIGH, ULTRA }
# AUTO reads zero_frame/weather, which the main menu writes.
enum Weather { AUTO, CLEAR, RAIN }
# PHOTOREAL lights the scene from scratch. SCAN_FLAT is for photogrammetry: the albedo
# already contains the real lighting, its own shadows and its own ambient occlusion, so a
# second sun plus SSAO plus GI just crushes everything the camera did not see into black.
enum Lighting { PHOTOREAL, SCAN_FLAT }

# A true-HDR sky with a real solar disc (peak luminance around 110 000): the shafts
# need a sun bright enough to be a light source, and the DirectionalLight in the level
# is aligned to this panorama's sun by scripts/tools/align_sun_to_sky.gd.
const DEFAULT_HDR := preload("res://assets/environment/sky/kloofendal_43d_clear_puresky_2k.hdr")
# Only materials on this shader get a wetness value, so the puddle pass is left alone.
const GRID_SHADER := preload("res://shaders/dev_grid.gdshader")
const WEATHER_SETTING := "zero_frame/weather"
# The menu stores plain 0/1 in that setting rather than the enum above, because the enum
# carries an extra AUTO entry that the menu has no button for.
const WEATHER_SETTING_CLEAR := 0
const WEATHER_SETTING_RAIN := 1

# The exports below are the rain baseline the scene is authored in. Clear weather is a
# brighter, drier, thinner-aired absolute set rather than an offset, so switching back and
# forth can never drift.
const CLEAR_SKY_ENERGY := 0.95
const CLEAR_AMBIENT_ENERGY := 1.15
const CLEAR_EXPOSURE := 0.82
const CLEAR_SHAFT_DENSITY := 0.014
const CLEAR_FOG_ALBEDO := Color(1.0, 0.98, 0.95)
const RAIN_FOG_ALBEDO := Color(0.93, 0.95, 1.0)
# A rain sun is a sun behind water and cloud: weaker direct light, but far more of it
# scattered in the air, which is where the shafts live.
const CLEAR_SUN_ENERGY := 5.0
const RAIN_SUN_ENERGY := 4.0
const CLEAR_SUN_FOG_ENERGY := 2.6
const RAIN_SUN_FOG_ENERGY := 4.0

@export_category("Photoreal preset")
@export var quality_preset: QualityPreset = QualityPreset.AUTO
@export var use_hdr_panorama: bool = true
@export var panorama: Texture2D = DEFAULT_HDR
@export_range(0.1, 4.0, 0.05) var sky_energy: float = 0.7
@export_range(0.0, 4.0, 0.05) var ambient_energy: float = 0.9
@export_range(0.1, 2.0, 0.01) var exposure_multiplier: float = 0.7
# Rotating the sky moves its sun away from the DirectionalLight it was matched to, so
# this stays at zero unless the light is re-aligned with it.
@export_range(-180.0, 180.0, 1.0) var sky_rotation_degrees: float = 0.0
# Density of the volumetric fog the sunlight is scattered in. This is the single knob
# that decides how strong the light shafts are. Too much and an open daylit courtyard
# turns into milk, because the sun scatters in every froxel and not just in the shafts.
@export_range(0.0, 0.2, 0.001) var shaft_density: float = 0.022

@export_category("Lighting model")
@export var lighting_model: Lighting = Lighting.PHOTOREAL
# SCAN_FLAT only. Uniform light from every direction at this energy, which is what puts
# detail back into everything the sun does not reach instead of leaving it black.
@export_range(0.0, 4.0, 0.05) var scan_ambient_energy: float = 1.5
# The sun is kept as a weak, shadowless directional fill so the scan still has a hint of
# direction without a second set of hard shadows on top of its baked ones.
@export_range(0.0, 4.0, 0.05) var scan_sun_energy: float = 0.5
@export_range(0.1, 3.0, 0.01) var scan_exposure: float = 1.0

@export_category("Fill light")
# Flat light that guarantees nothing in frame is pitch black. Raise it for a hazier, more
# overcast look; 0.0 turns it off and leaves the scene to the sun and the sky alone.
@export_range(0.0, 3.0, 0.05) var fill_light_energy: float = 1.0
@export var fill_light_color: Color = Color(0.72, 0.79, 0.92)

@export_category("Weather")
@export var weather: Weather = Weather.AUTO

# Resolved grade for the weather in effect, so the exports above are never overwritten and
# toggling weather in the menu is repeatable.
var _rain: bool = true
var _sky_energy: float = 0.7
var _ambient_energy: float = 0.9
var _exposure: float = 0.7
var _shaft_density: float = 0.022
var _fog_albedo: Color = RAIN_FOG_ALBEDO
# Materials that draw the muzzle flash themselves through shaders/muzzle_flash_light.gdshaderinc.
var _flash_receivers: Array[ShaderMaterial] = []

func _ready() -> void:
	# WeaponBase looks the environment up by group to push flash state at it.
	add_to_group("photoreal_environment")
	apply_preset()
	call_deferred("_configure_scene_nodes")

# Two packed vec4s per material and nothing else, so a full-auto burst writing this every
# frame stays free: (position, energy) and (colour, radius).
func push_muzzle_flash(world_position: Vector3, color: Color, energy: float, radius: float) -> void:
	var packed_position := Vector4(world_position.x, world_position.y, world_position.z, maxf(energy, 0.0))
	var packed_color := Vector4(color.r, color.g, color.b, radius)
	for material: ShaderMaterial in _flash_receivers:
		if material == null:
			continue
		material.set_shader_parameter("flash_position_energy", packed_position)
		material.set_shader_parameter("flash_color_radius", packed_color)

func apply_preset() -> void:
	if environment == null:
		environment = Environment.new()
	_resolve_weather()
	_configure_sky()
	_configure_color_and_exposure()
	_configure_quality()

func _resolve_weather() -> void:
	var effective := weather
	if effective == Weather.AUTO:
		var requested := int(ProjectSettings.get_setting(WEATHER_SETTING, WEATHER_SETTING_RAIN))
		effective = Weather.RAIN if requested == WEATHER_SETTING_RAIN else Weather.CLEAR
	_rain = effective == Weather.RAIN
	_sky_energy = sky_energy if _rain else CLEAR_SKY_ENERGY
	_ambient_energy = ambient_energy if _rain else CLEAR_AMBIENT_ENERGY
	_exposure = exposure_multiplier if _rain else CLEAR_EXPOSURE
	_shaft_density = shaft_density if _rain else CLEAR_SHAFT_DENSITY
	_fog_albedo = RAIN_FOG_ALBEDO if _rain else CLEAR_FOG_ALBEDO
	if lighting_model == Lighting.SCAN_FLAT:
		# A scan carries its own weather in its pixels. Nothing here may darken it.
		_rain = false
		_ambient_energy = scan_ambient_energy
		_exposure = scan_exposure
		_shaft_density = 0.0

func is_raining() -> bool:
	return _rain

func ambient_energy_in_effect() -> float:
	return _ambient_energy

func exposure_in_effect() -> float:
	return _exposure

func _configure_sky() -> void:
	environment.background_mode = Environment.BG_SKY
	environment.background_energy_multiplier = _sky_energy
	# Photogrammetry needs light from every direction, not just from the visible sky: an
	# interior scan sees no sky at all, which is exactly why it went black.
	var flat := lighting_model == Lighting.SCAN_FLAT
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR if flat else Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color(1.0, 1.0, 1.0)
	environment.ambient_light_sky_contribution = 0.0 if flat else 0.88
	environment.ambient_light_energy = _ambient_energy
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
	# This, not CameraAttributesPhysical.exposure_multiplier, is what actually controls
	# exposure here: physical light units are off project-wide, so the physical camera's
	# exposure is nearly inert and only the tonemapper's pre-scale moves the image.
	environment.tonemap_exposure = _exposure
	environment.tonemap_white = 1.0
	# The previous contrast=1.3 crushed interiors and made PBR materials look
	# painted. AgX provides the shoulder without a second contrast operation.
	environment.adjustment_enabled = false
	# Additive glow above the tonemapper's white point, so only genuinely bright things
	# bloom: the sun, sky highlights, hot metal and the muzzle flash. Anything below the
	# threshold is left alone instead of the whole frame going milky.
	environment.glow_enabled = true
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.glow_intensity = 0.32
	environment.glow_strength = 1.05
	environment.glow_bloom = 0.06
	environment.glow_hdr_threshold = 1.05
	environment.glow_hdr_scale = 2.2
	if camera_attributes is CameraAttributesPhysical:
		var physical := camera_attributes as CameraAttributesPhysical
		physical.auto_exposure_enabled = false
		physical.exposure_sensitivity = 160.0
		physical.exposure_multiplier = _exposure

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

	# A scan already has ambient occlusion, indirect light and shadows baked into its
	# albedo. Adding SSAO, SSIL, SDFGI and fog on top is what turned every corner the
	# camera did not see into black, so the flat model runs the screen effects off.
	var flat := lighting_model == Lighting.SCAN_FLAT
	environment.ssao_enabled = not flat
	environment.ssao_radius = 0.9
	environment.ssao_intensity = 1.35
	environment.ssao_power = 1.25
	environment.ssao_detail = 0.55
	environment.ssao_horizon = 0.08
	environment.ssao_light_affect = 0.35
	environment.ssao_ao_channel_affect = 0.65
	environment.ssil_enabled = not flat and effective >= QualityPreset.HIGH
	environment.ssr_enabled = not flat and effective >= QualityPreset.HIGH
	environment.ssr_max_steps = 64 if effective == QualityPreset.ULTRA else (48 if effective >= QualityPreset.HIGH else 16)
	environment.ssr_fade_in = 0.15
	environment.ssr_fade_out = 2.0
	environment.ssr_depth_tolerance = 0.12
	_configure_global_illumination(effective if not flat else QualityPreset.PERFORMANCE)
	_configure_light_shafts(not flat and effective >= QualityPreset.HIGH, effective >= QualityPreset.HIGH)
	environment.fog_enabled = not flat
	environment.fog_density = 0.00065
	environment.fog_height_density = 0.012
	environment.fog_sky_affect = 0.08
	# TAA is what makes the ray-marched effects settle: SDFGI, SSIL, SSR and the fog are
	# all temporally noisy on their own. It is Ultra-only because it also softens motion.
	var view := get_viewport()
	if view != null:
		view.use_taa = effective == QualityPreset.ULTRA

# Godot has no hardware ray tracing. SDFGI is the closest thing it does have: it cone-
# traces rays against a signed distance field of the scene every frame, so bounced
# sunlight fills the shadowed side of geometry and, through gi_inject below, the fog.
func _configure_global_illumination(effective: QualityPreset) -> void:
	environment.sdfgi_enabled = effective == QualityPreset.ULTRA
	if not environment.sdfgi_enabled:
		return
	environment.sdfgi_use_occlusion = false
	environment.sdfgi_bounce_feedback = 0.75
	environment.sdfgi_cascades = 6 if effective == QualityPreset.ULTRA else 4
	environment.sdfgi_min_cell_size = 0.15
	environment.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	environment.sdfgi_energy = 1.35
	environment.sdfgi_normal_bias = 1.1
	environment.sdfgi_probe_bias = 1.1

# Visible shafts of sunlight. The fog volume is what light is actually scattered in, so
# the density has to be high enough to see and the scattering has to be forward-biased,
# otherwise the sun just tints the air instead of drawing beams through the shadows.
func _configure_light_shafts(enabled: bool, gi_available: bool) -> void:
	environment.volumetric_fog_enabled = enabled
	if not enabled:
		return
	environment.volumetric_fog_density = _shaft_density
	environment.volumetric_fog_albedo = _fog_albedo
	environment.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	environment.volumetric_fog_emission_energy = 0.0
	# Forward scattering: looking towards the sun lights the haze up hard, looking away
	# leaves it clear, which is what makes a beam read as a beam.
	environment.volumetric_fog_anisotropy = 0.42
	environment.volumetric_fog_length = 72.0
	environment.volumetric_fog_detail_spread = 2.0
	# With SDFGI on, bounced sunlight is scattered in the fog as well as direct sunlight,
	# so a shaft landing on a wall lights the air next to that wall too.
	environment.volumetric_fog_gi_inject = 1.0 if gi_available else 0.5
	# Ambient injection lifts the shadowed half of the fog, which is exactly the contrast
	# the shafts live on, so it stays low.
	environment.volumetric_fog_ambient_inject = 0.05
	# The panorama already contains its own sky haze; injecting more turns the horizon
	# into soup.
	environment.volumetric_fog_sky_affect = 0.06
	environment.volumetric_fog_temporal_reprojection_enabled = true
	environment.volumetric_fog_temporal_reprojection_amount = 0.9

func _configure_scene_nodes() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		scene_root = get_parent()
	if scene_root == null:
		return
	_configure_reflection_probes(scene_root)
	_configure_weather_nodes(scene_root)

func _configure_reflection_probes(scene_root: Node) -> void:
	var method := RenderingServer.get_current_rendering_method()
	var forward_plus := method != "gl_compatibility" and method != "mobile"
	var requested := int(ProjectSettings.get_setting("zero_frame/graphics_quality", QualityPreset.AUTO))
	var probes_enabled := forward_plus and requested != QualityPreset.PERFORMANCE
	for node: Node in scene_root.find_children("*", "ReflectionProbe", true, false):
		(node as ReflectionProbe).visible = probes_enabled

# Everything that is weather rather than grading: the downpour, the standing water, how
# wet the concrete looks and how hard the sun is pushing through it.
func _configure_weather_nodes(scene_root: Node) -> void:
	var rain_system := scene_root.find_child("Rain", true, false) as RainSystem
	if rain_system != null:
		rain_system.intensity = 1.0 if _rain else 0.0
	var wet_ground := scene_root.find_child("WetGround", true, false) as MeshInstance3D
	if wet_ground != null:
		# No puddles at all in clear weather: the pass is fullscreen, so switching it off
		# is also the single biggest thing the clear preset saves.
		wet_ground.visible = _rain
		var water := wet_ground.material_override as ShaderMaterial
		if water != null and not _flash_receivers.has(water):
			_flash_receivers.append(water)
	var sun := scene_root.find_child("PhysicalSun", true, false) as DirectionalLight3D
	if sun != null:
		if lighting_model == Lighting.SCAN_FLAT:
			# Weak and shadowless: the scan's own shadows are already in its texture, and a
			# second set on top is what made half of every room unreadable.
			sun.light_energy = scan_sun_energy
			sun.light_volumetric_fog_energy = 0.0
			sun.shadow_enabled = false
		else:
			sun.light_energy = RAIN_SUN_ENERGY if _rain else CLEAR_SUN_ENERGY
			sun.light_volumetric_fog_energy = RAIN_SUN_FOG_ENERGY if _rain else CLEAR_SUN_FOG_ENERGY
	_configure_fill_lights(sun)
	_configure_surface_wetness(scene_root)

# Sky and bounce fill. Godot hands ambient over to SDFGI whenever SDFGI is on, and in an
# open arena of thin walls SDFGI returns almost nothing, so relying on ambient alone is what
# left every surface out of direct sun black. Two weak shadowless directionals cannot be
# switched off by a GI decision, and because they add no specular and no fog energy the sun
# stays the only light that reads as a light.
func _configure_fill_lights(sun: DirectionalLight3D) -> void:
	var down := _ensure_fill_light("SkyFillDown")
	down.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	down.light_energy = fill_light_energy
	var anti := _ensure_fill_light("SkyFillAnti")
	var azimuth := 0.0
	if sun != null:
		var travel := -sun.global_transform.basis.z
		azimuth = rad_to_deg(atan2(-travel.x, -travel.z))
	# Aimed back along the sun's own direction, 25 degrees above the horizon.
	anti.rotation_degrees = Vector3(-25.0, azimuth + 180.0, 0.0)
	anti.light_energy = fill_light_energy * 0.7

func _ensure_fill_light(fill_name: String) -> DirectionalLight3D:
	var light := get_node_or_null(fill_name) as DirectionalLight3D
	if light == null:
		light = DirectionalLight3D.new()
		light.name = fill_name
		add_child(light)
	light.shadow_enabled = false
	# No specular and no fog contribution: a fill light that glints or lights the haze stops
	# being a fill and starts competing with the sun.
	light.light_specular = 0.0
	light.light_volumetric_fog_energy = 0.0
	light.light_color = fill_light_color
	light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	return light

func _configure_surface_wetness(scene_root: Node) -> void:
	var wetness := 1.0 if _rain else 0.0
	for node: Node in scene_root.find_children("*", "MeshInstance3D", true, false):
		var material := (node as MeshInstance3D).material_override as ShaderMaterial
		if material == null or material.shader != GRID_SHADER or _flash_receivers.has(material):
			continue
		_flash_receivers.append(material)
	for material: ShaderMaterial in _flash_receivers:
		if material.shader == GRID_SHADER:
			material.set_shader_parameter("wetness", wetness)
