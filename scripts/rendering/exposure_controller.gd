class_name ExposureController
extends Node

@export var enabled: bool = true
@export_range(0.05, 1.0) var middle_gray: float = 0.18
@export var minimum: float = 0.18
@export var maximum: float = 3.0
@export var brighten_stops_per_second: float = 0.8
@export var darken_stops_per_second: float = 2.0

var measured_luminance: float = 0.18
var sample_count: int = 0
var current_exposure: float = 0.82
var _target: float = 0.82
var _environment: PhotorealEnvironment
var _meter: ExposureMeter
var _original_compositor: Compositor

func configure(host: PhotorealEnvironment) -> void:
	_environment = host
	current_exposure = host.environment.tonemap_exposure
	_target = current_exposure
	if RenderingServer.get_current_rendering_method() != "forward_plus" or DisplayServer.get_name() == "headless":
		return
	_meter = ExposureMeter.new()
	_meter.luminance_measured.connect(_on_luminance)
	_original_compositor = host.compositor
	var compositor := _original_compositor.duplicate() as Compositor if _original_compositor != null else Compositor.new()
	# Engine array properties are returned by value: append to a local copy, then
	# assign through the setter or the render callback is never registered.
	var effects: Array[CompositorEffect] = compositor.compositor_effects.duplicate()
	effects.append(_meter)
	compositor.compositor_effects = effects
	host.compositor = compositor

func _exit_tree() -> void:
	if _meter != null:
		_meter.luminance_measured.disconnect(_on_luminance)
		_meter.release()
		if is_instance_valid(_environment):
			_environment.compositor = _original_compositor
		_meter = null

func _on_luminance(value: float) -> void:
	if not is_finite(value) or value <= 0.0:
		return
	measured_luminance = value
	sample_count += 1
	refresh_target()

func refresh_target() -> void:
	if _environment == null:
		return
	_target = clampf(middle_gray * _environment.base_exposure() / maxf(measured_luminance, 0.001), minimum, maximum)

func _process(delta: float) -> void:
	if _environment == null or not enabled:
		return
	# Adapt in stops, not linearly in multiplier. No sine-wave hunting, no per-shot
	# exposure kick: the meter responds to actual HDR illumination, including flash.
	var rate := brighten_stops_per_second if _target > current_exposure else darken_stops_per_second
	var stops := move_toward(log(current_exposure) / log(2.0), log(_target) / log(2.0), rate * delta)
	current_exposure = pow(2.0, stops)
	_environment.environment.tonemap_exposure = current_exposure
