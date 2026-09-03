extends SceneTree

## Measures what one uncompensated magazine does to the aim, so recoil can be re-tuned without
## guessing. Fires the active weapon dry at its own rate of fire and reports how far the view
## moved and how far the muzzle wandered inside the free-aim envelope on the way.
##
## godot --headless --script res://scripts/tools/recoil_measure.gd -- [--pistol]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var level := (load("res://scenes/levels/dev_test_grid.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for frame: int in 30:
		await physics_frame
	var player := get_first_node_in_group("player") as PlayerController
	var manager := player.weapon_manager
	var weapon := manager.weapons[manager.current_index]
	# Pitch lives on the rig above the camera; yaw is the body's own rotation.
	var pivot := player.camera.get_parent() as Node3D
	var start_pitch := pivot.rotation.x
	var start_yaw := player.rotation.y
	var interval_ms: int = int(60000.0 / weapon.rounds_per_minute)
	var peak_free_aim := 0.0
	var peak_view := 0.0
	for round_index: int in weapon.magazine_size:
		weapon.fire_once()
		var deadline: int = Time.get_ticks_msec() + interval_ms
		while Time.get_ticks_msec() < deadline:
			await process_frame
			peak_view = maxf(peak_view, rad_to_deg(absf(pivot.rotation.x - start_pitch)))
		peak_free_aim = maxf(peak_free_aim, rad_to_deg(manager.free_aim().length()))
	print("RECOIL weapon=%s rounds=%d pitch_up=%.1f yaw=%.1f peak_view_pitch=%.1f peak_free_aim=%.2f (degrees)" % [
		weapon.weapon_name, weapon.magazine_size,
		rad_to_deg(pivot.rotation.x - start_pitch),
		rad_to_deg(start_yaw - player.rotation.y),
		peak_view, peak_free_aim])
	quit()
