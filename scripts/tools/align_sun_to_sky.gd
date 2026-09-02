extends SceneTree

## Finds the sun in the HDRI panorama and prints the DirectionalLight3D transform that
## matches it, so shadows and light shafts come from where the sun visibly is in the sky
## instead of from a hand-picked angle.
##
## The panorama mapping is Godot's own (sky.glsl):
##   u = atan2(dir.x, -dir.z) / TAU,  v = acos(dir.y) / PI
## so it is inverted here to turn the brightest spot back into a direction. The result
## assumes Environment.sky_rotation is zero; any sky rotation has to be added to the
## azimuth by hand.
##
## Run with:  godot --headless --script res://scripts/tools/align_sun_to_sky.gd -- \
##                --panorama=res://assets/environment/sky/mud_road_puresky_2k.hdr

func _initialize() -> void:
	var panorama_path := "res://assets/environment/sky/mud_road_puresky_2k.hdr"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--panorama="):
			panorama_path = argument.trim_prefix("--panorama=")
	var image := Image.load_from_file(panorama_path)
	if image == null:
		push_error("SUN_ALIGN_LOAD_FAILED " + panorama_path)
		quit(1)
		return
	if image.is_compressed():
		image.decompress()
	# The HDR loader can hand back RGBE9995, whose get_pixel() clamps; converting to
	# straight floats first is what keeps the sun's real intensity readable.
	if image.get_format() != Image.FORMAT_RGBF and image.get_format() != Image.FORMAT_RGBAF:
		image.convert(Image.FORMAT_RGBAF)
	print("SUN_ALIGN format=", image.get_format())
	var width := image.get_width()
	var height := image.get_height()
	var brightest := 0.0
	for y: int in height:
		for x: int in width:
			var pixel := image.get_pixel(x, y)
			var luminance: float = pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
			brightest = maxf(brightest, luminance)
	# Weighted centroid of everything near the peak, so the centre of the solar disc is
	# found rather than one arbitrary hot pixel inside it.
	var threshold := brightest * 0.6
	var weight_sum := 0.0
	var u_sum := 0.0
	var v_sum := 0.0
	var hot_pixels := 0
	for y: int in height:
		for x: int in width:
			var pixel := image.get_pixel(x, y)
			var luminance: float = pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
			if luminance < threshold:
				continue
			hot_pixels += 1
			weight_sum += luminance
			u_sum += luminance * (float(x) + 0.5) / float(width)
			v_sum += luminance * (float(y) + 0.5) / float(height)
	if weight_sum <= 0.0:
		push_error("SUN_ALIGN_NO_SUN")
		quit(1)
		return
	var u: float = u_sum / weight_sum
	var v: float = v_sum / weight_sum
	var phi: float = v * PI
	var theta: float = u * TAU
	var to_sun := Vector3(sin(phi) * sin(theta), cos(phi), -sin(phi) * cos(theta)).normalized()
	# A DirectionalLight3D emits along -Z, so -Z has to point away from the sun.
	var basis_z := to_sun
	var basis_x := Vector3.UP.cross(basis_z).normalized()
	var basis_y := basis_z.cross(basis_x).normalized()
	var light_basis := Basis(basis_x, basis_y, basis_z)
	print("SUN_ALIGN panorama=", panorama_path, " size=", width, "x", height)
	print("  peak_luminance=", snappedf(brightest, 0.01), " hot_pixels=", hot_pixels)
	print("  uv=(", snappedf(u, 0.0001), ", ", snappedf(v, 0.0001), ")")
	print("  elevation=", snappedf(rad_to_deg(asin(to_sun.y)), 0.01), " deg  azimuth=", snappedf(rad_to_deg(theta), 0.01), " deg")
	print("  to_sun=", to_sun, "  light_travels=", -to_sun)
	print("  tscn transform = Transform3D(",
		"%.7f, %.7f, %.7f, " % [basis_x.x, basis_x.y, basis_x.z],
		"%.7f, %.7f, %.7f, " % [basis_y.x, basis_y.y, basis_y.z],
		"%.7f, %.7f, %.7f, " % [basis_z.x, basis_z.y, basis_z.z],
		"0, 18, 0)")
	print("  sanity: light_basis * Vector3.BACK = ", light_basis * Vector3.BACK)
	quit()
