class_name ExposureMeter
extends CompositorEffect

## Meter the WORLD's linear HDR buffer before tonemapping/HUD/viewmodel. One small
## asynchronous readback at ~8 Hz, never a full-resolution CPU screenshot. Both worlds
## consume the same exposure; independent native auto-exposure would meter the gun
## against its transparent background and make it a separately exposed studio shot.
signal luminance_measured(value: float)

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _sampler: RID
var _values: RID
var _pending := false
var _last_sample: int = 0

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	RenderingServer.call_on_render_thread(_initialize_gpu)

func _initialize_gpu() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	var source := RDShaderSource.new()
	source.source_compute = """
#version 450
layout(local_size_x=8, local_size_y=8, local_size_z=1) in;
layout(set=0, binding=0) uniform sampler2D hdr_image;
layout(set=0, binding=1, std430) restrict writeonly buffer Meter { float values[]; };
void main() {
    uvec2 p = gl_GlobalInvocationID.xy;
    vec2 uv = vec2(0.15) + (vec2(p) + 0.5) / vec2(32.0, 24.0) * 0.7;
    vec3 c = max(textureLod(hdr_image, uv, 0.0).rgb, vec3(0.0));
    float luminance = dot(c, vec3(0.2126, 0.7152, 0.0722));
    values[p.y * 32u + p.x] = log(clamp(luminance, 0.001, 64.0));
}
"""
	var spirv := _rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():
		push_error("Exposure meter: " + spirv.compile_error_compute)
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)
	var state := RDSamplerState.new()
	state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	_sampler = _rd.sampler_create(state)
	_values = _rd.storage_buffer_create(32 * 24 * 4)

func _render_callback(_type: int, render_data: RenderData) -> void:
	if _rd == null or not _pipeline.is_valid() or _pending:
		return
	if Time.get_ticks_msec() - _last_sample < 125:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null or buffers.get_internal_size().x == 0:
		return
	var color := RDUniform.new()
	color.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	color.binding = 0
	color.add_id(_sampler)
	color.add_id(buffers.get_color_layer(0))
	var output := RDUniform.new()
	output.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	output.binding = 1
	output.add_id(_values)
	var uniforms := UniformSetCacheRD.get_cache(_shader, 0, [color, output])
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	_rd.compute_list_bind_uniform_set(list, uniforms, 0)
	_rd.compute_list_dispatch(list, 4, 3, 1)
	_rd.compute_list_end()
	_last_sample = Time.get_ticks_msec()
	_pending = true
	var error := _rd.buffer_get_data_async(_values, _readback)
	if error != OK:
		_pending = false
		push_error("Exposure meter readback: " + error_string(error))

func _readback(data: PackedByteArray) -> void:
	var samples := data.to_float32_array()
	var total := 0.0
	for value: float in samples:
		total += value
	if not samples.is_empty():
		luminance_measured.emit.call_deferred(exp(total / samples.size()))
	_pending = false

func release() -> void:
	enabled = false
	RenderingServer.call_on_render_thread(_release_gpu)

func _release_gpu() -> void:
	if _rd == null:
		return
	for handle: RID in [_pipeline, _shader, _sampler, _values]:
		if handle.is_valid():
			_rd.free_rid(handle)
	_pipeline = RID()
	_shader = RID()
	_sampler = RID()
	_values = RID()
