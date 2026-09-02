@tool
class_name FullscreenMesh
extends MeshInstance3D

## Builds the oversized triangle a fullscreen shader pass needs: three vertices that cover
## the whole viewport once the shader overwrites POSITION, with culling defeated so it is
## never thrown away no matter where the camera looks.
##
## Used by shaders/rain_puddles.gdshader. Supplied by the user with the puddle shader.

@export_tool_button("Set up") var setup_tool: Callable = setup

func _ready() -> void:
	# Also built at runtime, so a fresh clone works without anyone pressing the button.
	if mesh == null or mesh.get_surface_count() == 0:
		setup()

func setup() -> void:
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0

	var built := ArrayMesh.new()
	var verts := PackedVector3Array()
	verts.append(Vector3(-1.0, -1.0, 0.0))
	verts.append(Vector3(3.0, -1.0, 0.0))
	verts.append(Vector3(-1.0, 3.0, 0.0))

	var mesh_array := []
	mesh_array.resize(Mesh.ARRAY_MAX)
	mesh_array[Mesh.ARRAY_VERTEX] = verts
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_array)
	mesh = built
