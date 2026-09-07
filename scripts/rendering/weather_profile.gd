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

static func defaults(index: int) -> WeatherVisualProfile:
	var profile := WeatherVisualProfile.new()
	# Setting IDs 0=clear and 1=rain are retained for existing menus/tools.
	match index:
		1:
			profile.label = "RAIN"
			profile.rain_intensity = 0.6
			profile.wetness = 0.75
			profile.cloud_cover = 0.9
			profile.sun_intensity = 0.18
			profile.sun_angular_distance = 3.0
			profile.sky_intensity = 0.55
			profile.ambient_intensity = 0.5
			profile.fog_density = 0.0015
			profile.atmosphere_density = 0.006
			profile.wind = Vector3(2.2, 0.0, -1.1)
		2:
			profile.label = "OVERCAST"
			profile.cloud_cover = 0.82
			profile.sun_intensity = 0.35
			profile.sun_angular_distance = 2.0
			profile.sky_intensity = 0.75
			profile.ambient_intensity = 0.65
			profile.fog_density = 0.00065
			profile.atmosphere_density = 0.003
		3:
			profile.label = "HEAVY RAIN"
			profile.rain_intensity = 1.0
			profile.wetness = 1.0
			profile.cloud_cover = 1.0
			profile.sun_intensity = 0.06
			profile.sun_angular_distance = 4.0
			profile.sky_intensity = 0.4
			profile.ambient_intensity = 0.4
			profile.fog_density = 0.003
			profile.atmosphere_density = 0.012
			profile.wind = Vector3(3.8, 0.0, -2.0)
	return profile
