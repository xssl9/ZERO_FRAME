class_name RenderingDebug
extends Node

## F8 cycles visual diagnostics, F7 cycles weather. No shipping HUD unless active.
## Material channels cover dev_grid and StandardMaterial3D (including both weapons).
## Native reflection view shows probe coverage, NOT a fabricated reflection buffer.
enum Mode { OFF, ROUGHNESS, METALLIC, NORMALS, AO, WETNESS, MATERIAL_IDS, PUDDLES, SHADOWS, EXPOSURE, GI, REFLECTION_PROBES }
const LABELS := ["OFF", "ROUGHNESS", "METALLIC", "WORLD NORMALS", "AO", "WETNESS (bound materials only)", "MATERIAL IDS", "PUDDLE MASK", "SHADOW ATLAS", "SCENE LUMINANCE", "GI BUFFER", "REFLECTION PROBE CLUSTERS"]
var mode: Mode = Mode.OFF
var host: PhotorealEnvironment
var _originals: Dictionary = {}
var _lens: CanvasLayer
var _label: Label
var _saved_exposure_enabled: bool = true

func configure(environment: PhotorealEnvironment) -> void:
	host = environment
	_lens = host.get_parent().find_child("BodycamOverlay", true, false) as CanvasLayer
	var layer := CanvasLayer.new()
	layer.layer = 110
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(20.0, 75.0)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_label)
	_label.visible = false

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_F8:
		set_mode((int(mode) + 1) % Mode.size() as Mode)
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_F7:
		host.weather = (int(host.weather) % 4 + 1) as PhotorealEnvironment.Weather
		host.apply_preset()
		get_viewport().set_input_as_handled()

func set_mode(value: Mode) -> void:
	if host == null:
		return
	for mesh: MeshInstance3D in _originals:
		if not is_instance_valid(mesh):
			continue
		var saved: Array = _originals[mesh]
		mesh.material_override = saved[0]
		for surface: int in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(surface, saved[surface + 1])
	_originals.clear()
	if mode == Mode.OFF and value != Mode.OFF and host.exposure_controller != null:
		_saved_exposure_enabled = host.exposure_controller.enabled
	mode = value
	if host.exposure_controller != null:
		host.exposure_controller.enabled = _saved_exposure_enabled if mode == Mode.OFF else false
	if _lens != null:
		_lens.visible = mode == Mode.OFF
	var viewport := host.get_viewport()
	viewport.debug_draw = Viewport.DEBUG_DRAW_DISABLED
	match mode:
		Mode.SHADOWS: viewport.debug_draw = Viewport.DEBUG_DRAW_SHADOW_ATLAS
		Mode.EXPOSURE: viewport.debug_draw = Viewport.DEBUG_DRAW_SCENE_LUMINANCE
		Mode.GI: viewport.debug_draw = Viewport.DEBUG_DRAW_GI_BUFFER
		Mode.REFLECTION_PROBES: viewport.debug_draw = Viewport.DEBUG_DRAW_CLUSTER_REFLECTION_PROBES
	for material: ShaderMaterial in host.wetness_manager.materials:
		if not material.shader.resource_path.ends_with("rain_puddles.gdshader"):
			material.set_shader_parameter("debug_view", int(mode) if mode <= Mode.MATERIAL_IDS else 0)
			material.set_shader_parameter("material_id", Color.from_hsv(float(material.get_instance_id() % 97) / 97.0, 0.65, 0.8))
		else:
			material.set_shader_parameter("debug_puddles", mode == Mode.PUDDLES)
	if mode > Mode.OFF and mode <= Mode.MATERIAL_IDS:
		_apply_standard_debug()
	_label.visible = mode != Mode.OFF

func _apply_standard_debug() -> void:
	var copies: Dictionary = {}
	for node: Node in host.get_parent().find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var saved: Array = [mesh.material_override]
		for surface: int in mesh.mesh.get_surface_count():
			saved.append(mesh.get_surface_override_material(surface))
		_originals[mesh] = saved
		for surface: int in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			if not copies.has(source):
				var debug := ShaderMaterial.new()
				debug.shader = preload("res://shaders/material_debug.gdshader")
				debug.set_shader_parameter("mode", int(mode))
				debug.set_shader_parameter("roughness", source.roughness)
				debug.set_shader_parameter("metallic", source.metallic)
				debug.set_shader_parameter("roughness_map", source.roughness_texture)
				debug.set_shader_parameter("metallic_map", source.metallic_texture)
				debug.set_shader_parameter("ao_map", source.ao_texture if source.ao_enabled else null)
				debug.set_shader_parameter("normal_map", source.normal_texture)
				debug.set_shader_parameter("has_normal", source.normal_enabled)
				debug.set_shader_parameter("normal_strength", source.normal_scale)
				debug.set_shader_parameter("roughness_channel", _channel(source.roughness_texture_channel))
				debug.set_shader_parameter("metallic_channel", _channel(source.metallic_texture_channel))
				debug.set_shader_parameter("ao_channel", _channel(source.ao_texture_channel))
				debug.set_shader_parameter("uv_scale", source.uv1_scale)
				debug.set_shader_parameter("uv_offset", source.uv1_offset)
				debug.set_shader_parameter("material_id", Color.from_hsv(float(copies.size()) * 0.618, 0.65, 0.8))
				copies[source] = debug
			if mesh.material_override != null:
				mesh.material_override = copies[source]
				break
			mesh.set_surface_override_material(surface, copies[source])

func _channel(index: int) -> Vector4:
	if index == BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE:
		return Vector4(0.333333, 0.333333, 0.333333, 0.0)
	var mask := Vector4.ZERO
	mask[clampi(index, 0, 3)] = 1.0
	return mask

func _process(_delta: float) -> void:
	if mode == Mode.OFF or host == null:
		return
	_label.text = "F8: %s | F7: %s\nwetness %.3f / target %.3f | exposure %.3f" % [LABELS[mode], host.profile.label,
		host.wetness_manager.wetness, host.wetness_manager.target_wetness, host.exposure_in_effect()]
