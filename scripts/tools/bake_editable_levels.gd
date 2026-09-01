extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const LEVELS: Array[Array] = [
	["res://scenes/levels/procedural_sources/abandoned_building.tscn", "res://scenes/levels/abandoned_building.tscn"],
	["res://scenes/levels/procedural_sources/test_range.tscn", "res://scenes/levels/test_range.tscn"],
	["res://scenes/levels/procedural_sources/maps/building_scan.tscn", "res://scenes/levels/maps/building_scan.tscn"],
	["res://scenes/levels/procedural_sources/maps/hore_abbey.tscn", "res://scenes/levels/maps/hore_abbey.tscn"],
	["res://scenes/levels/procedural_sources/maps/slade_green.tscn", "res://scenes/levels/maps/slade_green.tscn"],
	["res://scenes/levels/procedural_sources/maps/brutalist_interior.tscn", "res://scenes/levels/maps/brutalist_interior.tscn"],
	["res://scenes/levels/procedural_sources/maps/squinch_domes.tscn", "res://scenes/levels/maps/squinch_domes.tscn"],
]

func _initialize() -> void:
	call_deferred("_bake_all")

func _bake_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/levels/maps"))
	var only := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			only = argument.trim_prefix("--only=")
	for entry: Array in LEVELS:
		if not only.is_empty() and not (entry[1] as String).ends_with("/%s.tscn" % only):
			continue
		await _bake_level(entry[0] as String, entry[1] as String)
	quit()

func _bake_level(source_path: String, destination_path: String) -> void:
	var source := load(source_path) as PackedScene
	if source == null:
		push_error("Cannot load level: %s" % source_path)
		return
	var level := source.instantiate() as Node3D
	root.add_child(level)
	await process_frame
	await process_frame

	var old_player := _find_player(level)
	var player_transform := Transform3D.IDENTITY
	if old_player != null:
		player_transform = old_player.transform
		old_player.free()
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.name = "Player"
	player.transform = player_transform
	level.add_child(player)

	# Runtime builders have finished their work. The baked scene owns the result
	# and no longer regenerates or repositions anything when opened or played.
	level.set_script(null)
	_clear_runtime_loader_scripts(level)
	_assign_owner(level, level)

	var packed := PackedScene.new()
	var pack_error := packed.pack(level)
	if pack_error != OK:
		push_error("Cannot pack %s: %s" % [destination_path, error_string(pack_error)])
	else:
		var save_error := ResourceSaver.save(packed, destination_path)
		if save_error != OK:
			push_error("Cannot save %s: %s" % [destination_path, error_string(save_error)])
		else:
			print("BAKED_EDITABLE_LEVEL ", destination_path)
	level.free()
	await process_frame

func _find_player(node: Node) -> CharacterBody3D:
	if node is PlayerController:
		return node as CharacterBody3D
	for child: Node in node.get_children():
		var result := _find_player(child)
		if result != null:
			return result
	return null

func _clear_runtime_loader_scripts(node: Node) -> void:
	var script := node.get_script() as Script
	if script != null and script.resource_path == "res://scripts/core/imported_map_runtime.gd":
		node.set_script(null)
	for child: Node in node.get_children():
		_clear_runtime_loader_scripts(child)

func _assign_owner(node: Node, scene_owner: Node) -> void:
	for child: Node in node.get_children():
		# A non-null owner marks content that already belongs to an instanced
		# PackedScene (glTF, warehouse, player, weapon). Preserve that boundary so
		# the level references the source scene instead of embedding every mesh.
		if child.owner == null:
			child.owner = scene_owner
			_assign_owner(child, scene_owner)
