extends SceneTree

# One-shot inspector: prints the real node tree, bone list and animation list of the
# soldier master model, so the locomotion tree is built against what the file
# actually contains rather than against what a README claims.

const MODEL := "res://IMPORTANT_MULTIPLAYER_ASSETS/soldier_rifle_locomotion.glb"

func _initialize() -> void:
	var packed := load(MODEL) as PackedScene
	if packed == null:
		push_error("INSPECT_LOAD_FAILED")
		quit(1)
		return
	var root := packed.instantiate()
	print("ROOT ", root.name, " (", root.get_class(), ")")
	_dump_tree(root, 1)
	var skeleton := _find_first(root, "Skeleton3D") as Skeleton3D
	if skeleton != null:
		print("BONE_COUNT ", skeleton.get_bone_count())
		for i: int in skeleton.get_bone_count():
			print("BONE %d %s parent=%d" % [i, skeleton.get_bone_name(i), skeleton.get_bone_parent(i)])
	var player := _find_first(root, "AnimationPlayer") as AnimationPlayer
	if player != null:
		var names := player.get_animation_list()
		print("ANIM_COUNT ", names.size())
		for name: String in names:
			var anim := player.get_animation(name)
			print("ANIM %s length=%.3f loop=%d tracks=%d" % [name, anim.length, anim.loop_mode, anim.get_track_count()])
	for child: Node in root.get_children():
		if child is MeshInstance3D:
			var mesh := child as MeshInstance3D
			print("MESH ", mesh.name, " surfaces=", mesh.mesh.get_surface_count(), " aabb=", mesh.get_aabb())
	root.free()
	quit()

func _dump_tree(node: Node, depth: int) -> void:
	for child: Node in node.get_children():
		print("  ".repeat(depth), "- ", child.name, " (", child.get_class(), ")")
		if depth < 3:
			_dump_tree(child, depth + 1)

func _find_first(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child: Node in node.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null
