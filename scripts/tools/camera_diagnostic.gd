extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/levels/dev_test_grid.tscn") as PackedScene
	var level := packed.instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	var player := get_first_node_in_group("player") as PlayerController
	var viewport := player.get_node("WeaponLayer/WeaponViewportContainer/WeaponViewport") as SubViewport
	var active := viewport.get_camera_3d()
	print("WEAPON_CAMERA_DIAGNOSTIC current=", active.name if active != null else "none", " path=", active.get_path() if active != null else NodePath())
	quit()
