extends SceneTree

## Temporary check: does every prop stand on the floor and clear of the level geometry?

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var level := (load("res://scenes/levels/parking_garage.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for frame: int in 40:
		await physics_frame
	var space := root.world_3d.direct_space_state
	var player := get_first_node_in_group("player") as Node3D
	var floating := 0
	var sunken := 0
	var embedded := 0
	var checked := 0
	for group_name: String in ["Cars", "Props"]:
		var group := level.get_node_or_null(group_name)
		if group == null:
			continue
		for node: Node in group.get_children():
			var body := node as Node3D
			if body == null:
				continue
			checked += 1
			var origin: Vector3 = body.global_position
			# Started just above the prop's own base, not a fixed height: a prop standing on the
			# 1.1 m dock in a 3 m room would otherwise be probed from above the ceiling.
			var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.4, origin + Vector3.DOWN * 3.0)
			if body is CollisionObject3D:
				query.exclude = [(body as CollisionObject3D).get_rid()]
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				print("  NO FLOOR under ", body.name, " at ", origin.snappedf(0.01))
				continue
			var gap: float = origin.y - (hit["position"] as Vector3).y
			if gap > 0.05:
				floating += 1
				print("  FLOATS %-22s gap=%.3f at %s" % [body.name, gap, str(origin.snappedf(0.01))])
			elif gap < -0.05:
				sunken += 1
				print("  SUNKEN %-22s gap=%.3f at %s" % [body.name, gap, str(origin.snappedf(0.01))])
			var shape := body.get_node_or_null("PropShape") as CollisionShape3D
			if shape == null:
				continue
			var box := shape.shape as BoxShape3D
			var probe := PhysicsShapeQueryParameters3D.new()
			var shrunk := BoxShape3D.new()
			# Shrunk a little: a crate resting on the floor legitimately touches it.
			shrunk.size = box.size * 0.86
			probe.shape = shrunk
			probe.transform = shape.global_transform
			probe.exclude = [(body as CollisionObject3D).get_rid()]
			var overlaps := space.intersect_shape(probe, 8)
			for overlap: Dictionary in overlaps:
				var other := overlap["collider"] as Node
				if other == player:
					continue
				embedded += 1
				print("  INSIDE %-22s box=%s -> %s" % [body.name, str(box.size.snappedf(0.01)), other.name])
				break
	print("PROP_CHECK checked=%d floating=%d sunken=%d embedded=%d" % [checked, floating, sunken, embedded])
	print("PROP_CHECK wall-mounted props (extinguishers) are expected to report a gap")
	quit()
