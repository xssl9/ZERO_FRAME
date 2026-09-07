@tool
class_name WeatherVisualProfile
extends Resource

## Relative Godot light units, not lux: existing practical lights are authored without
## physical units. Keeping one scale avoids silently invalidating every interior lamp.
@export var label: String = "CLEAR"
@export_range(0.0, 1.0) var rain_intensity: float = 0.0
@export_range(0.0, 1.0) var wetness: float = 0.0
@export_range(0.0, 1.0) var cloud_cover: float = 0.0
@export var sun_intensity: float = 2.8
@export var sun_color: Color = Color(1.0, 0.985, 0.96)
@export var sun_angular_distance: float = 0.53
@export var sky_intensity: float = 0.85
@export var ambient_intensity: float = 0.65
@export var exposure: float = 0.82
@export var fog_density: float = 0.0003
@export var atmosphere_density: float = 0.0015
@export var wind: Vector3 = Vector3(1.2, 0.0, -0.6)
## Directional shadow softness multiplier (1.0 = authored, higher = softer penumbra).
@export_range(0.5, 4.0) var shadow_softness: float = 1.0
## SSAO intensity multiplier for this weather (overcast = more AO, bright sun = less).
@export_range(0.3, 2.0) var ssao_intensity_scale: float = 1.0
## Glow intensity for this weather (rain scatters light, so glow is slightly stronger).
@export_range(0.05, 0.5) var glow_intensity: float = 0.12

static func defaults(index: int) -> WeatherVisualProfile:
	var profile := WeatherVisualProfile.new()
	# Setting IDs 0=clear and 1=rain are retained for existing menus/tools.
	match index:
		1:
			# RAIN: overcast sky, wet surfaces, reduced direct sun, atmospheric haze.
			# Sun color shifts cooler — cloud-filtered light loses its warmth.
			profile.label = "RAIN"
			profile.rain_intensity = 0.6
			profile.wetness = 0.75
			profile.cloud_cover = 0.9
			profile.sun_intensity = 0.22
			profile.sun_color = Color(0.88, 0.91, 0.96)  # cool, cloud-filtered
			profile.sun_angular_distance = 3.0  # soft penumbra through cloud
			profile.sky_intensity = 0.52
			profile.ambient_intensity = 0.48
			profile.exposure = 0.72
			profile.fog_density = 0.0018
			profile.atmosphere_density = 0.007
			profile.wind = Vector3(2.2, 0.0, -1.1)
			profile.shadow_softness = 2.8
			profile.ssao_intensity_scale = 1.3
			profile.glow_intensity = 0.08
		2:
			# OVERCAST: diffuse sky, no hard shadows, flat but not dark.
			profile.label = "OVERCAST"
			profile.cloud_cover = 0.82
			profile.sun_intensity = 0.38
			profile.sun_color = Color(0.92, 0.93, 0.96)  # slightly cool, diffuse
			profile.sun_angular_distance = 2.2
			profile.sky_intensity = 0.72
			profile.ambient_intensity = 0.62
			profile.exposure = 0.78
			profile.fog_density = 0.0007
			profile.atmosphere_density = 0.0035
			profile.shadow_softness = 2.0
			profile.ssao_intensity_scale = 1.15
			profile.glow_intensity = 0.10
		3:
			# HEAVY RAIN: near-zero visibility, everything soaked, dense atmosphere.
			profile.label = "HEAVY RAIN"
			profile.rain_intensity = 1.0
			profile.wetness = 1.0
			profile.cloud_cover = 1.0
			profile.sun_intensity = 0.07
			profile.sun_color = Color(0.82, 0.86, 0.94)  # very cool, storm light
			profile.sun_angular_distance = 4.5
			profile.sky_intensity = 0.38
			profile.ambient_intensity = 0.36
			profile.exposure = 0.62
			profile.fog_density = 0.0035
			profile.atmosphere_density = 0.014
			profile.wind = Vector3(3.8, 0.0, -2.0)
			profile.shadow_softness = 3.5
			profile.ssao_intensity_scale = 1.5
			profile.glow_intensity = 0.06
	return profile
