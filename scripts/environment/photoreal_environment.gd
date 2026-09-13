@tool
class_name PhotorealEnvironment
extends WorldEnvironment

signal preset_applied

enum QualityPreset { AUTO, PERFORMANCE, HIGH, ULTRA }
# AUTO reads zero_frame/weather, which the main menu writes.
enum Weather { AUTO, CLEAR, RAIN, OVERCAST, HEAVY_RAIN }
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
@export var use_hdr_panorama: bool = false
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
@export_range(0.0, 3.0, 0.05) var fill_light_energy: float = 0.0
@export var fill_light_color: Color = Color(0.72, 0.79, 0.92)

@export_category("Weather")
@export var weather: Weather = Weather.AUTO
# Standing water without rainfall. An underground garage has wet concrete and puddles but no
# downpour, no drops falling past the hands and no sky to darken, and weather alone cannot say
# that: CLEAR dries the floor out and RAIN starts a storm indoors. Negative follows the weather,
# which is what every outdoor level wants.
@export_range(-1.0, 1.0, 0.01) var standing_water: float = -1.0

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
# How much water each surface can hold at all, read from the scene once and kept, because the
# wetness pass overwrites the value it would otherwise read back. The weather only scales this,
# so a level can author a soaked floor next to dry plaster and keep the difference.
var _authored_wetness: Dictionary = {}

@export_category("Realism tuning")
## Optional per-map overrides, ordered CLEAR, RAIN, OVERCAST, HEAVY RAIN.
@export var weather_profiles: Array[WeatherVisualProfile] = []
@export var enable_auto_exposure: bool = true
## Disable for thin-shell interiors; use authored probes / future LightmapGI there.
@export var allow_sdfgi: bool = true
@export_range(0.0, 1.0) var roughness_variation: float = 0.08
var profile: WeatherVisualProfile
var resolved_quality: QualityPreset = QualityPreset.HIGH
var wetness_manager: WetnessManager
var exposure_controller: ExposureController
var rendering_debug: RenderingDebug
var _scene_root: Node

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
	elif _scene_root == null:
		# Menu previews and gameplay must not mutate the same packed resource.
		environment = environment.duplicate() as Environment
	_resolve_weather()
	_configure_sky()
	_configure_color_and_exposure()
	_configure_quality()
	if is_instance_valid(_scene_root):
		_configure_reflection_probes(_scene_root)
		_configure_weather_nodes(_scene_root)
		if exposure_controller != null:
			exposure_controller.refresh_target()
	preset_applied.emit()

func atmosphere_density_in_effect() -> float:
	return _shaft_density

func base_exposure() -> float:
	return _exposure

func _resolve_weather() -> void:
	var index := int(weather) - 1
	if weather == Weather.AUTO:
		index = clampi(int(ProjectSettings.get_setting(WEATHER_SETTING, 0)), 0, 3)
	profile = weather_profiles[index] if index < weather_profiles.size() and weather_profiles[index] != null else WeatherVisualProfile.defaults(index)
	_rain = profile.rain_intensity > 0.0 and standing_water < 0.0
	_sky_energy = profile.sky_intensity
	_ambient_energy = profile.ambient_intensity
	_exposure = profile.exposure
	_shaft_density = profile.atmosphere_density
	_fog_albedo = Color(0.96, 0.97, 1.0)
	if standing_water >= 0.0:
		# Interior practical lights and authored exposure are independent of outdoor weather.
		_sky_energy = sky_energy
		_ambient_energy = ambient_energy
		_exposure = exposure_multiplier
		_shaft_density = minf(shaft_density, 0.001)
	if lighting_model == Lighting.SCAN_FLAT:
		_ambient_energy = scan_ambient_energy
		_exposure = scan_exposure
		_shaft_density *= 0.25

func is_raining() -> bool:
	return _rain

func ambient_energy_in_effect() -> float:
	return _ambient_energy

func exposure_in_effect() -> float:
	return environment.tonemap_exposure if environment != null else _exposure

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
		var physical := PhysicalSkyMaterial.new()
		physical.rayleigh_coefficient = 2.0
		physical.mie_coefficient = lerpf(0.005, 0.035, profile.cloud_cover)
		physical.mie_eccentricity = 0.76
		physical.turbidity = lerpf(2.0, 10.0, profile.cloud_cover)
		physical.ground_color = Color(0.18, 0.17, 0.15)
		var sky := Sky.new()
		sky.sky_material = physical
		sky.radiance_size = Sky.RADIANCE_SIZE_256
		sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
		environment.sky = sky
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
	if exposure_controller == null or not exposure_controller.enabled:
		environment.tonemap_exposure = _exposure
	environment.tonemap_white = 1.0
	# The previous contrast=1.3 crushed interiors and made PBR materials look
	# painted. AgX provides the shoulder without a second contrast operation.
	environment.adjustment_enabled = false
	# Additive glow above the tonemapper's white point, so only genuinely bright things
	# bloom: the sun, sky highlights, hot metal and the muzzle flash. Anything below the
	# threshold is left alone instead of the whole frame going milky.
	# Glow intensity varies by weather: rain scatters light less cleanly, so bloom is
	# slightly reduced; clear sky has the sharpest highlights.
	environment.glow_enabled = true
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.glow_intensity = profile.glow_intensity if profile != null else 0.12
	environment.glow_strength = 0.8
	environment.glow_bloom = 0.0
	# Threshold above AgX white point: only the sun disc, sky highlights, hot metal and
	# muzzle flash exceed this. Anything lower stays clean.
	environment.glow_hdr_threshold = 1.85
	environment.glow_hdr_scale = 1.0
	# Physical camera would also override authored FOV. ExposureController meters HDR
	# once for both viewports; no independent native adaptation or DOF is applied.
	camera_attributes = null

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
	resolved_quality = effective

	# SSAO: contact occlusion that makes objects sit on surfaces. Radius is kept small
	# to avoid the "dark halo" look; intensity scales with weather (overcast = more AO).
	var ssao_intensity_scale := profile.ssao_intensity_scale if profile != null else 1.0
	environment.ssao_enabled = not flat and effective >= QualityPreset.HIGH
	environment.ssao_radius = 0.28 if effective == QualityPreset.ULTRA else 0.22
	environment.ssao_intensity = 0.72 * ssao_intensity_scale
	environment.ssao_power = 1.1
	environment.ssao_detail = 0.5 if effective == QualityPreset.ULTRA else 0.35
	environment.ssao_horizon = 0.06
	# Light affect: how much SSAO darkens lit surfaces. Keep low so it only reads in
	# shadow, not as a dark ring around every object in direct sun.
	environment.ssao_light_affect = 0.22
	environment.ssao_ao_channel_affect = 0.72

	# SSIL: screen-space indirect lighting. Adds colour bleeding and bounce light.
	# Radius larger than SSAO to catch wall-to-floor bounce.
	environment.ssil_enabled = not flat and effective >= QualityPreset.HIGH
	environment.ssil_radius = 4.0 if effective == QualityPreset.ULTRA else 2.5
	environment.ssil_intensity = 0.8
	environment.ssil_sharpness = 0.98
	environment.ssil_normal_rejection = 1.0

	# SSR: screen-space reflections for wet surfaces, metal, glass.
	environment.ssr_enabled = not flat and effective >= QualityPreset.HIGH
	environment.ssr_max_steps = 80 if effective == QualityPreset.ULTRA else (56 if effective >= QualityPreset.HIGH else 16)
	environment.ssr_fade_in = 0.12
	environment.ssr_fade_out = 2.5
	environment.ssr_depth_tolerance = 0.10

	_configure_global_illumination(effective if not flat else QualityPreset.PERFORMANCE)
	_configure_light_shafts(not flat and effective >= QualityPreset.HIGH, effective >= QualityPreset.HIGH)

	# Fallback fog when volumetric is off (PERFORMANCE preset).
	environment.fog_enabled = not environment.volumetric_fog_enabled and standing_water < 0.0
	environment.fog_density = profile.fog_density if profile != null else 0.0003
	environment.fog_height_density = 0.0
	environment.fog_sky_affect = 0.06

	# TAA is what makes the ray-marched effects settle: SDFGI, SSIL, SSR and the fog are
	# all temporally noisy on their own. HIGH and above use TAA; PERFORMANCE uses MSAA.
	var view := get_viewport()
	if view != null:
		view.use_taa = effective >= QualityPreset.HIGH
		view.msaa_3d = Viewport.MSAA_DISABLED if view.use_taa else Viewport.MSAA_2X
		# Larger shadow atlas on ULTRA for sharper contact shadows at distance.
		view.positional_shadow_atlas_size = 4096 if effective == QualityPreset.ULTRA else (2048 if effective >= QualityPreset.HIGH else 1024)
		view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	if forward_plus:
		RenderingServer.directional_shadow_atlas_set_size(8192 if effective == QualityPreset.ULTRA else (4096 if effective >= QualityPreset.HIGH else 2048), true)

# Godot has no hardware ray tracing. SDFGI is the closest thing it does have: it cone-
# traces rays against a signed distance field of the scene every frame, so bounced
# sunlight fills the shadowed side of geometry and, through gi_inject below, the fog.
func _configure_global_illumination(effective: QualityPreset) -> void:
	environment.sdfgi_enabled = allow_sdfgi and effective >= QualityPreset.HIGH
	if not environment.sdfgi_enabled:
		return
	environment.sdfgi_use_occlusion = true
	# Bounce feedback: how much of the bounced light feeds back into the next bounce.
	# Too high causes colour bleeding to dominate; 0.45 gives natural indirect colour.
	environment.sdfgi_bounce_feedback = 0.42
	# More cascades = larger GI range. 6 covers a full outdoor arena; 4 is enough for
	# the parking garage interior where the geometry is close.
	environment.sdfgi_cascades = 6 if effective == QualityPreset.ULTRA else 4
	# Smaller cell = finer GI detail. 0.12 resolves thin walls and door frames.
	environment.sdfgi_min_cell_size = 0.12
	# 75% Y scale: outdoor scenes are wider than tall, so this saves probes without
	# losing vertical resolution in the areas that matter.
	environment.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	environment.sdfgi_energy = 1.0
	# Normal bias prevents self-occlusion on flat surfaces (light leaking through floors).
	environment.sdfgi_normal_bias = 1.2
	# Probe bias prevents the probe from sampling its own geometry.
	environment.sdfgi_probe_bias = 1.2

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
	# Rain/overcast: lower anisotropy because cloud-scattered light is more isotropic.
	var cloud_cover := profile.cloud_cover if profile != null else 0.0
	environment.volumetric_fog_anisotropy = lerpf(0.44, 0.22, cloud_cover)
	# Fog length: how far the volume extends from the camera. 80 m covers the full arena.
	environment.volumetric_fog_length = 80.0
	# Detail spread: higher = more variation in the fog density, which is what makes
	# shafts look like shafts rather than a uniform haze.
	environment.volumetric_fog_detail_spread = 2.2
	# With SDFGI on, bounced sunlight is scattered in the fog as well as direct sunlight,
	# so a shaft landing on a wall lights the air next to that wall too.
	environment.volumetric_fog_gi_inject = 1.0 if gi_available else 0.5
	# Ambient injection lifts the shadowed half of the fog, which is exactly the contrast
	# the shafts live on, so it stays low.
	environment.volumetric_fog_ambient_inject = 0.04
	# The panorama already contains its own sky haze; injecting more turns the horizon
	# into soup.
	environment.volumetric_fog_sky_affect = 0.05
	environment.volumetric_fog_temporal_reprojection_enabled = true
	# Higher reprojection = smoother but more ghosting on fast camera moves.
	# 0.88 is a good balance for a bodycam that moves quickly.
	environment.volumetric_fog_temporal_reprojection_amount = 0.88

func _configure_scene_nodes() -> void:
	# A menu selection can detach the preview before this deferred call runs.
	if not is_inside_tree():
		return
	# The containing level, not current_scene (which is the menu during previews).
	var scene_root := get_parent()
	if scene_root == null or is_instance_valid(_scene_root):
		return
	_scene_root = scene_root
	MaterialResponse.apply(scene_root)
	wetness_manager = WetnessManager.new()
	wetness_manager.name = "WetnessManager"
	add_child(wetness_manager)
	wetness_manager.configure(scene_root, standing_water if standing_water >= 0.0 else profile.wetness)
	if standing_water < 0.0 and not Engine.is_editor_hint():
		var roof_mask := RainExposureMask.new()
		roof_mask.name = "RainExposureMask"
		add_child(roof_mask)
		roof_mask.configure(scene_root as Node3D, wetness_manager.materials)
	_flash_receivers = wetness_manager.materials
	if not Engine.is_editor_hint():
		exposure_controller = ExposureController.new()
		exposure_controller.name = "ExposureController"
		exposure_controller.enabled = enable_auto_exposure
		add_child(exposure_controller)
		if enable_auto_exposure:
			exposure_controller.configure(self)
		if scene_root.find_child("Player", true, false) != null:
			rendering_debug = RenderingDebug.new()
			rendering_debug.name = "RenderingDebug"
			add_child(rendering_debug)
			rendering_debug.configure(self)
	_configure_reflection_probes(scene_root)
	_configure_weather_nodes(scene_root)
	if get_node_or_null("RealismManager") == null:
		var tuning := RealismManager.new()
		tuning.name = "RealismManager"
		tuning.roughness_variation = roughness_variation
		add_child(tuning)

func _configure_reflection_probes(scene_root: Node) -> void:
	var method := RenderingServer.get_current_rendering_method()
	var forward_plus := method != "gl_compatibility" and method != "mobile"
	var probes_enabled := forward_plus and resolved_quality != QualityPreset.PERFORMANCE
	for node: Node in scene_root.find_children("*", "ReflectionProbe", true, false):
		(node as ReflectionProbe).visible = probes_enabled
	for node: Node in scene_root.find_children("*", "Decal", true, false):
		if node is SurfaceDecal:
			node.visible = probes_enabled
			node.distance_fade_begin = 30.0 if resolved_quality == QualityPreset.ULTRA else 22.0

# Everything that is weather rather than grading: the downpour, the standing water, how
# wet the concrete looks and how hard the sun is pushing through it.
func _configure_weather_nodes(scene_root: Node) -> void:
	var rain_system := scene_root.find_child("Rain", true, false) as RainSystem
	if rain_system != null:
		rain_system.intensity = profile.rain_intensity if _rain else 0.0
		rain_system.wind = profile.wind
		rain_system.quality_scale = 1.0 if resolved_quality == QualityPreset.ULTRA else (0.7 if resolved_quality == QualityPreset.HIGH else 0.35)
	var wet_ground := scene_root.find_child("WetGround", true, false) as MeshInstance3D
	if wet_ground != null:
		# No puddles at all in clear weather: the pass is fullscreen, so switching it off
		# is also the single biggest thing the clear preset saves. An interior that asked for
		# standing water keeps it, since its water does not come from the sky.
		wet_ground.visible = _rain or standing_water > 0.0
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
			sun.light_energy = profile.sun_intensity
			sun.light_color = profile.sun_color
			# Angular distance controls penumbra softness. Overcast/rain profiles use a
			# larger value so shadows are soft and diffuse, matching cloud-filtered light.
			sun.light_angular_distance = profile.sun_angular_distance
			# Shadow blur from the weather profile: clear = sharp (1.0), overcast/rain = soft.
			sun.shadow_blur = profile.shadow_softness
			# Under heavy cloud cover the remaining directional shadow fades to near-invisible,
			# matching the diffuse wraparound of a fully overcast sky.
			sun.shadow_opacity = lerpf(1.0, 0.3, clampf((profile.cloud_cover - 0.5) / 0.5, 0.0, 1.0))
			# Volumetric fog scattering from the sun dims under clouds: no sharp god-rays
			# when the sky is a featureless grey dome.
			sun.light_volumetric_fog_energy = lerpf(1.0, 0.15, profile.cloud_cover)
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			# Extend shadow distance on ULTRA for better far-field contact shadows.
			sun.directional_shadow_max_distance = 80.0 if resolved_quality == QualityPreset.ULTRA else 65.0
			sun.directional_shadow_blend_splits = true
			# Pancaking reduces shadow acne on thin geometry without bias artifacts.
			sun.directional_shadow_pancake_size = 20.0
		sun.light_specular = 1.0
	_configure_fill_lights(sun)
	if wetness_manager != null:
		wetness_manager.target_wetness = standing_water if standing_water >= 0.0 else profile.wetness
		wetness_manager.rain_intensity = profile.rain_intensity if _rain else 0.0
		wetness_manager.roughness_variation = roughness_variation
		wetness_manager.publish()
	if wet_ground != null and wet_ground.material_override is ShaderMaterial:
		var water := wet_ground.material_override as ShaderMaterial
		water.set_shader_parameter("ssr_max_travel", 0.0 if resolved_quality == QualityPreset.PERFORMANCE else 24.0)
		water.set_shader_parameter("ssr_resolution", 0.6 if resolved_quality == QualityPreset.ULTRA else 1.0)
		water.set_shader_parameter("ssr_max_diff", 0.18)

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
	var factor := standing_water if standing_water >= 0.0 else (1.0 if _rain else 0.0)
	for node: Node in scene_root.find_children("*", "MeshInstance3D", true, false):
		var material := (node as MeshInstance3D).material_override as ShaderMaterial
		if material == null or material.shader != GRID_SHADER or _flash_receivers.has(material):
			continue
		_flash_receivers.append(material)
	for material: ShaderMaterial in _flash_receivers:
		if material.shader != GRID_SHADER:
			continue
		if not _authored_wetness.has(material):
			var authored: Variant = material.get_shader_parameter("wetness")
			_authored_wetness[material] = float(authored) if authored != null else 1.0
		material.set_shader_parameter("wetness", float(_authored_wetness[material]) * factor)
