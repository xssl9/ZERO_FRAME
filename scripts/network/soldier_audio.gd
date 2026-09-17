class_name SoldierAudio
extends Node3D

const WEAPON_SHOTS := ["res://assets/audio/weapons/ak_shot.ogg", "res://assets/audio/weapons/pistol_shot.ogg"]
var _voices: Array[AudioStreamPlayer3D] = []
var _next := 0
var _reload: AudioStreamPlayer3D
var _flash: OmniLight3D
var _flash_time := 0.0

func _ready() -> void:
	for index: int in 12:
		var voice := AudioStreamPlayer3D.new()
		voice.max_distance = 90.0
		voice.unit_size = 3.0
		add_child(voice)
		_voices.append(voice)
	_reload = AudioStreamPlayer3D.new()
	_reload.max_distance = 25.0
	_reload.position.y = 1.2
	add_child(_reload)
	_flash = OmniLight3D.new()
	_flash.light_color = Color("ffcb96")
	_flash.omni_range = 9.0
	_flash.light_energy = 0.0
	add_child(_flash)

func play_event(event: String, variant: int, gain: float, pitch: float) -> void:
	if event == "reload_stop":
		_reload.stop()
		return
	var path := ""
	var height := 0.1
	var bus := &"Master"
	match event:
		"shot":
			if variant < 0 or variant >= WEAPON_SHOTS.size():
				return
			path = WEAPON_SHOTS[variant]
			height = 1.3
			bus = &"Weapons"
			_flash_time = 0.075
			var avatar := get_parent() as SoldierAvatar
			_flash.position = Vector3(0.18, 0.9 if avatar.sync_crouching else 1.35, 0) + Vector3(0, 0, -0.55).rotated(Vector3.RIGHT, avatar.sync_pitch)
		"step":
			path = "res://assets/audio/footsteps/run_0%d.ogg" % (clampi(variant, 0, 5) + 1)
		"land":
			path = "res://assets/audio/land.ogg"
		"breath":
			path = "res://assets/audio/player/breath_0%d.ogg" % (clampi(variant, 0, 4) + 1)
			height = 1.4
		"reload":
			if variant == 0:
				_reload.stream = load("res://assets/audio/weapons/ak_reload.ogg")
				_reload.volume_db = -5.0
				_reload.play()
			return
		_:
			return
	var voice := _voices[_next]
	_next = (_next + 1) % _voices.size()
	voice.stream = load(path)
	voice.bus = bus
	voice.position.y = height
	voice.volume_db = clampf(gain, -30.0, 16.0)
	voice.pitch_scale = clampf(pitch, 0.8, 1.2)
	voice.play()

func _exit_tree() -> void:
	for voice: AudioStreamPlayer3D in _voices:
		voice.stop()
	if _reload != null:
		_reload.stop()

func _process(delta: float) -> void:
	_flash_time = maxf(0.0, _flash_time - delta)
	_flash.light_energy = 16.0 * pow(_flash_time / 0.075, 3.0)
