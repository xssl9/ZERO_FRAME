@tool
extends EditorScenePostImport

## Physics is built from the same evaluated meshes as the live Blender export,
## never from the old parking layout. No runtime material replacement.
func _post_import(scene: Node) -> Object:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/parking_rework/live_export.json"))
	var records: Dictionary = {}
	for record: Dictionary in report["meshes"]:
		records[String(record["name"]).validate_node_name()] = record
	var matched := 0
	var colliders := 0
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var key := String(mesh.name)
		if not records.has(key):
			push_error("PARKING_IMPORT unknown mesh " + key)
			continue
		var record: Dictionary = records[key]
		matched += 1
		mesh.set_meta("parking_source_name", record["name"])
		mesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		var source_name := String(record["name"])
		var overlay := source_name.begins_with("WEAR_") or source_name.begins_with("RW_Oil_") or source_name.begins_with("RW_DrainDirt_") or source_name.begins_with("RW_TireLane_") or source_name.begins_with("RW_PipeRunoff_") or "_Bay" in source_name or "_Tag" in source_name or "Hairline" in source_name or "WallCracks" in source_name
		if overlay:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if not record["solid"]:
			continue
		var body := StaticBody3D.new()
		body.name = "ParkingCollision"
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		shape.shape = mesh.mesh.create_trimesh_shape()
		mesh.add_child(body)
		body.add_child(shape)
		body.owner = scene
		shape.owner = scene
		colliders += 1
	if matched != records.size():
		push_error("PARKING_IMPORT matched %d/%d" % [matched, records.size()])
	scene.set_meta("parking_export_sha256", report["glb_sha256"])
	print("PARKING_IMPORT meshes=", matched, " colliders=", colliders)
	return scene
