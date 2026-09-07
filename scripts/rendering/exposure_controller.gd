class_name ExposureController
extends Node

@export var enabled: bool = true
@export_range(0.05, 1.0) var middle_gray: float = 0.18
@export var minimum: float = 0.14
@export var maximum: float = 3.2
## Increase exposure when entering a dark room: slower gain recovery.
@export var brighten_stops_per_second: float = 0.6
## Reduce exposure when entering daylight: faster highlight protection.
@export var darken_stops_per_second: float = 1.2
## Minimum exposure error in STOPS before adaptation (not linear luminance).
@export_range(0.0, 0.1) var adaptation_threshold: float = 0.008

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
	# Diagnostic colors are not scene luminance; do not meter them while paused.
	if not enabled or not is_finite(value) or value <= 0.0:
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
	# Names refer to the exposure multiplier, not scene brightness.
	var current_stops := log(maxf(current_exposure, 0.001)) / log(2.0)
	var target_stops := log(maxf(_target, 0.001)) / log(2.0)
	# Dead zone: don't adapt for tiny luminance changes (prevents micro-hunting on
	# surfaces that flicker slightly due to TAA or particle effects).
	if absf(target_stops - current_stops) < adaptation_threshold:
		return
	var rate := brighten_stops_per_second if _target > current_exposure else darken_stops_per_second
	var stops := move_toward(current_stops, target_stops, maxf(rate, 0.0) * maxf(delta, 0.0))
	current_exposure = pow(2.0, stops)
	_environment.environment.tonemap_exposure = current_exposure
