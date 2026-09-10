@tool
extends EditorScenePostImport

## Alpha wear overlays must not cast rectangle shadows or participate in GI.
## Set this at import time, not every frame, and retain generated mesh LODs.
func _post_import(scene: Node) -> Object:
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var overlay := false
		for prefix: String in ["RW_Oil_", "RW_DrainDirt_", "RW_TireLane_", "RW_PipeRunoff_", "RW_FloorJoints_", "RW_CeilingReveals_", "RW_DrainRecess_"]:
			overlay = overlay or String(mesh.name).begins_with(prefix)
		if overlay:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		else:
			mesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	return scene
