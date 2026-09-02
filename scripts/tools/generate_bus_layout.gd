extends SceneTree

## Regenerates res://default_bus_layout.tres.
##
## The gunshot samples are mastered close to full scale so automatic fire has real
## weight, which means overlapping tails can sum past 0 dBFS. Everything that fires or
## impacts goes to a Weapons bus with a hard limiter on it, so a long burst compresses
## instead of clipping against the output driver.
##
## Run with:  godot --headless --script res://scripts/tools/generate_bus_layout.gd

const LAYOUT_PATH := "res://default_bus_layout.tres"

func _initialize() -> void:
	while AudioServer.bus_count > 1:
		AudioServer.remove_bus(AudioServer.bus_count - 1)
	AudioServer.add_bus(1)
	AudioServer.set_bus_name(1, "Weapons")
	AudioServer.set_bus_send(1, "Master")
	var limiter := AudioEffectHardLimiter.new()
	# -1 dBFS of true-peak headroom, with a release long enough that a burst does not
	# audibly pump between rounds at 650 RPM.
	limiter.ceiling_db = -1.0
	limiter.pre_gain_db = 0.0
	limiter.release = 0.12
	AudioServer.add_bus_effect(1, limiter)
	var layout := AudioServer.generate_bus_layout()
	var error := ResourceSaver.save(layout, LAYOUT_PATH)
	print("BUS_LAYOUT path=", LAYOUT_PATH, " buses=", AudioServer.bus_count, " error=", error_string(error))
	quit(0 if error == OK else 1)
