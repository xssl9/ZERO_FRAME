extends Node3D

const ImportedMapRuntimeScript = preload("res://scripts/core/imported_map_runtime.gd")

@export var is_test_range: bool = false
@export var visual_showcase: bool = false
@export_category("Downloaded Map")
@export_file("*.glb", "*.gltf", "*.fbx", "*.obj", "*.dae") var imported_map_path: String = ""
@export var imported_map_position: Vector3 = Vector3.ZERO
@export var imported_map_rotation_degrees: Vector3 = Vector3.ZERO
@export var imported_map_scale: Vector3 = Vector3.ONE
@export_range(1000, 400000, 1000) var imported_collision_triangle_budget: int = 180000
@export var safety_floor_size: Vector2 = Vector2(50.0, 50.0)
@export var safety_floor_uses_mud: bool = false
@export var map_title: String = ""

var concrete := Color("30373a")
var plaster := Color("555b58")
var brick := Color("513932")
var metal := Color("30363b")
var wood := Color("513f2f")
var wet := Color("151d21")

func _ready() -> void:
	_build_environment()
	var using_imported_map: bool = not imported_map_path.is_empty()
	if using_imported_map:
		_build_imported_map()
	else:
		_build_world()
	var player := PlayerController.new()
	var spawn := get_node_or_null("SpawnPoint3D") as Marker3D
	if spawn == null:
		spawn = get_node_or_null("PlayerSpawn") as Marker3D
	player.transform = spawn.transform if spawn != null else Transform3D(Basis.IDENTITY, Vector3(0.0, 1.2, -23.0))
	add_child(player)
	if using_imported_map:
		_add_fps_counter()
		_add_map_title()
	elif is_test_range:
		_build_test_range()
	else:
		_build_abandoned_building()
	if not using_imported_map:
		_build_grass_fields(player)
	if "--diagnose-floor" in OS.get_cmdline_user_args():
		var diagnostic_timer := get_tree().create_timer(2.0)
		diagnostic_timer.timeout.connect(func() -> void:
			var forward: Vector3 = -player.camera.global_transform.basis.z
			var ray := PhysicsRayQueryParameters3D.create(player.camera.global_position, player.camera.global_position + forward * 3.0)
			ray.exclude = [player.get_rid()]
			var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
			print("FLOOR_DIAGNOSTIC player=", player.global_position, " on_floor=", player.is_on_floor(), " camera_forward=", forward, " forward_hit=", hit.get("collider", "none"))
			get_tree().quit()
		)

func _build_environment() -> void:
	var environment := WorldEnvironment.new()
	environment.name = "PhysicalDayEnvironment"
	var settings := Environment.new()
	settings.background_mode = Environment.BG_SKY
	var sky_material := PhysicalSkyMaterial.new()
	sky_material.ground_color = Color("b8bbb6")
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	settings.sky = sky
	settings.background_energy_multiplier = 1.5
	settings.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	settings.ambient_light_sky_contribution = 0.78
	settings.ambient_light_energy = 0.58
	settings.tonemap_mode = Environment.TONE_MAPPER_AGX
	settings.tonemap_exposure = 0.62
	settings.tonemap_white = 1.0
	settings.adjustment_enabled = true
	settings.adjustment_brightness = 1.0
	settings.adjustment_contrast = 1.3
	settings.adjustment_saturation = 1.3
	settings.glow_enabled = true
	settings.glow_intensity = 0.16
	settings.glow_strength = 0.24
	settings.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	settings.glow_bloom = 0.1
	settings.ssao_enabled = true
	settings.ssao_radius = 1.1
	settings.ssao_intensity = 3.0
	settings.ssao_light_affect = 1.0
	settings.ssao_ao_channel_affect = 1.0
	var rendering_method: String = RenderingServer.get_current_rendering_method()
	# SSIL/SDFGI/volumetric fog are Forward+ features. Compatibility keeps the
	# same scene playable and falls back to SSAO plus depth fog.
	var forward_plus: bool = rendering_method != "gl_compatibility" and rendering_method != "mobile"
	settings.ssil_enabled = forward_plus
	settings.ssr_enabled = forward_plus
	settings.ssr_max_steps = 24
	settings.ssr_fade_in = 0.12
	settings.ssr_fade_out = 1.6
	settings.ssr_depth_tolerance = 0.18
	# SDFGI measured above the 16.67 ms/frame 60 FPS budget on the target Intel
	# iGPU even at 720p. Sky ambient + SSIL keep bounce light at a viable cost.
	settings.sdfgi_enabled = false
	settings.fog_enabled = true
	settings.fog_light_color = Color("b9c8ce")
	settings.fog_density = 0.001
	settings.fog_height = 0.5
	settings.fog_height_density = 0.025
	settings.fog_sky_affect = 0.0
	settings.fog_aerial_perspective = 1.0
	settings.volumetric_fog_enabled = false
	settings.volumetric_fog_density = 0.008
	settings.volumetric_fog_albedo = Color("d9d4c8")
	settings.volumetric_fog_length = 48.0
	settings.volumetric_fog_sky_affect = 0.0
	settings.volumetric_fog_gi_inject = 0.65
	var attributes := CameraAttributesPhysical.new()
	# Fixed exposure keeps the midday look stable; auto-exposure was pumping the
	# open sky and light concrete into a blown-out white.
	attributes.auto_exposure_enabled = false
	attributes.exposure_sensitivity = 160.0
	attributes.exposure_multiplier = 0.85
	environment.camera_attributes = attributes
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "PhysicalSun"
	sun.rotation_degrees = Vector3(-78.0, -25.0, 0.0)
	sun.light_color = Color("fff4df")
	sun.light_energy = 3.0
	sun.light_angular_distance = 0.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 65.0
	add_child(sun)

func _build_world() -> void:
	var ground := _static_box("Ground", Vector3(70.0, 0.25, 70.0), Vector3(0.0, -0.15, -8.0), wet)
	var ground_mesh := ground.get_node("MeshInstance3D") as MeshInstance3D
	ground_mesh.material_override = _make_soil_underlay_material()
	for pos: Vector3 in [Vector3(-7, 0.02, 9), Vector3(8, 0.02, 5), Vector3(11, 0.02, -8)]:
		var puddle := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 1.8
		cylinder.bottom_radius = 1.8
		cylinder.height = 0.018
		puddle.mesh = cylinder
		puddle.position = pos
		puddle.scale.z = 0.55
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("142b36")
		material.metallic = 0.0
		material.roughness = 0.16
		puddle.material_override = material
		add_child(puddle)

func _build_imported_map() -> void:
	var imported_level := ImportedMapRuntimeScript.new()
	imported_level.name = "DownloadedMap"
	add_child(imported_level)
	imported_level.build(imported_map_path, imported_map_position, imported_map_rotation_degrees, imported_map_scale, imported_collision_triangle_budget)
	var floor_material: StandardMaterial3D
	if safety_floor_uses_mud:
		floor_material = _make_polyhaven_floor_material("brown_mud_leaves_01", 0.0, 0.92, safety_floor_size, 1.3)
	else:
		floor_material = _make_polyhaven_floor_material("concrete_wall_008", 0.0, 0.82, safety_floor_size, 2.7)
	_pbr_box("SafetyFloor", Vector3(safety_floor_size.x, 0.2, safety_floor_size.y), Vector3(0.0, -0.11, 0.0), floor_material)

func _add_map_title() -> void:
	if map_title.is_empty():
		return
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	var title := Label.new()
	title.text = map_title + "   •   ESC — МЕНЮ"
	title.position = Vector2(24.0, 56.0)
	title.modulate = Color(0.78, 0.84, 0.82, 0.82)
	title.add_theme_font_size_override("font_size", 17)
	layer.add_child(title)

func _build_test_range() -> void:
	# Dedicated floor collider: the imported FBX surface is visual and may be
	# one-sided, so gameplay collision must not depend on its triangle winding.
	var floor_body := get_node_or_null("WarehouseFloorCollision") as StaticBody3D
	if floor_body == null:
		floor_body = StaticBody3D.new()
		floor_body.name = "WarehouseFloorCollision"
		floor_body.position = Vector3(0.0, -0.18, -23.0)
		add_child(floor_body)
	if floor_body.get_node_or_null("CollisionShape3D") == null:
		var floor_collision := CollisionShape3D.new()
		floor_collision.name = "CollisionShape3D"
		var floor_shape := BoxShape3D.new()
		floor_shape.size = Vector3(16.0, 0.35, 46.0)
		floor_collision.shape = floor_shape
		floor_body.add_child(floor_collision)
	var warehouse := get_node_or_null("WarehouseGeometry")
	if warehouse == null and not visual_showcase:
		var warehouse_resource := load("res://scenes/levels/warehouse_geometry.tscn") as PackedScene
		if warehouse_resource != null:
			warehouse = warehouse_resource.instantiate()
			warehouse.name = "WarehouseGeometry"
			add_child(warehouse)
	if warehouse != null:
		for node: Node in warehouse.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mesh_instance.create_trimesh_collision()
	_spawn_gtg_prop("res://assets/gtg/props/metal_tool_chest_1k.gltf", Vector3(-4.8, 0.0, -18.0), Vector3(0.0, 0.6, 0.0))
	_spawn_gtg_prop("res://assets/gtg/props/power_box_01_1k.gltf", Vector3(5.8, 0.0, -29.0), Vector3(0.0, -0.8, 0.0))
	var reflection := ReflectionProbe.new()
	reflection.position = Vector3(0.0, 2.5, -23.0)
	reflection.size = Vector3(14.0, 5.0, 40.0)
	reflection.update_mode = ReflectionProbe.UPDATE_ONCE
	reflection.intensity = 0.24
	add_child(reflection)
	for x: float in [-4.0, 0.0, 4.0]:
		_spawn_target(Vector3(x, 1.0, -24.0))
	_add_light(Vector3(0.0, 4.2, -4.0), Color("bad9e8"), 3.2)
	_add_light(Vector3(-5.0, 3.6, -18.0), Color("ffc06b"), 2.4)
	_add_light(Vector3(5.0, 3.6, -32.0), Color("9fcde5"), 2.6)
	if visual_showcase:
		_build_photoreal_material_zone()
	_add_fps_counter()

func _build_photoreal_material_zone() -> void:
	# Standalone test range: no warehouse geometry. Four PBR lanes exercise
	# concrete, painted plaster, weathered steel and wet road under one lighting setup.
	var floor := _static_box("RangeRoad", Vector3(16.0, 0.18, 42.0), Vector3(0.0, -0.09, -23.0), Color.WHITE)
	var floor_mesh := floor.get_node("MeshInstance3D") as MeshInstance3D
	floor_mesh.material_override = _make_gtg_material("road", "Road007", 0.08, 0.34)
	var left_wall := _static_box("RangeLeftWall", Vector3(0.22, 4.5, 42.0), Vector3(-8.0, 2.25, -23.0), Color.WHITE)
	(left_wall.get_node("MeshInstance3D") as MeshInstance3D).material_override = _make_gtg_material("plaster", "PaintedPlaster001", 0.0, 0.74)
	var right_wall := _static_box("RangeRightWall", Vector3(0.22, 4.5, 42.0), Vector3(8.0, 2.25, -23.0), Color.WHITE)
	(right_wall.get_node("MeshInstance3D") as MeshInstance3D).material_override = _make_gtg_material("metal", "Metal042A", 0.82, 0.32)
	var back_wall := _static_box("RangeBackWall", Vector3(16.0, 4.5, 0.22), Vector3(0.0, 2.25, -44.0), Color.WHITE)
	(back_wall.get_node("MeshInstance3D") as MeshInstance3D).material_override = _make_gtg_material("concrete", "Concrete019", 0.04, 0.62)
	var panels: Array[Array] = [
		[Vector3(-5.2, 1.6, -35.0), _make_gtg_material("concrete", "Concrete019", 0.04, 0.62)],
		[Vector3(-1.8, 1.6, -35.0), _make_gtg_material("plaster", "PaintedPlaster001", 0.0, 0.74)],
		[Vector3(1.8, 1.6, -35.0), _make_gtg_material("metal", "Metal042A", 0.82, 0.32)],
		[Vector3(5.2, 1.6, -35.0), _make_gtg_material("road", "Road007", 0.08, 0.34)]
	]
	for panel: Array in panels:
		var wall := _static_box("PBRMaterialPanel", Vector3(3.0, 3.2, 0.14), panel[0], Color.WHITE)
		var mesh := wall.get_node("MeshInstance3D") as MeshInstance3D
		mesh.material_override = panel[1] as Material

func _make_gtg_material(folder: String, prefix: String, metallic_value: float, roughness_value: float) -> StandardMaterial3D:
	var base := "res://assets/gtg/materials/%s/%s_1K-PNG_" % [folder, prefix]
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(base + "Color.png") as Texture2D
	material.normal_texture = load(base + "NormalGL.png") as Texture2D
	material.roughness_texture = load(base + "Roughness.png") as Texture2D
	material.metallic = metallic_value
	material.roughness = roughness_value
	material.uv1_scale = Vector3(2.2, 2.2, 2.2)
	return material

func _make_polyhaven_material(slug: String, metallic_value: float, roughness_value: float, uv_scale: float) -> StandardMaterial3D:
	var base := "res://assets/polyhaven/textures/%s/%s_" % [slug, slug]
	var arm := load(base + "arm_2k.jpg") as Texture2D
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(base + "diff_2k.jpg") as Texture2D
	material.normal_enabled = true
	material.normal_texture = load(base + "nor_gl_2k.jpg") as Texture2D
	material.ao_enabled = true
	material.ao_texture = arm
	material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.roughness_texture = arm
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	material.metallic_texture = arm
	material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	material.metallic = metallic_value
	material.roughness = roughness_value
	material.uv1_scale = Vector3.ONE * uv_scale
	return material

func _make_polyhaven_floor_material(slug: String, metallic_value: float, roughness_value: float, surface_size: Vector2, meters_per_tile: float) -> StandardMaterial3D:
	var material := _make_polyhaven_material(slug, metallic_value, roughness_value, 1.0)
	material.uv1_scale = Vector3(surface_size.x / meters_per_tile, surface_size.y / meters_per_tile, 1.0)
	material.normal_scale = 1.15
	if slug == "brown_mud_leaves_01":
		material.albedo_color = Color(1.42, 1.32, 1.22, 1.0)
	# SSAO supplies broad contact darkening; the packed AO would repeat at a very
	# high frequency over large terrain and over-darken the mip chain.
	material.ao_enabled = false
	return material

func _make_soil_underlay_material() -> StandardMaterial3D:
	# This only fills tiny gaps below the visual Poly Haven grass. Keeping it
	# texture-free prevents the former mud/leaves pattern showing through.
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("18180f")
	material.roughness = 0.98
	material.metallic = 0.0
	return material

func _make_hexaquo_concrete_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/hexaquo/concrete/concrete_wall_007_diff_4k.jpg") as Texture2D
	material.normal_enabled = true
	material.normal_scale = 2.0
	material.normal_texture = load("res://assets/hexaquo/concrete/concrete_wall_007_nor_gl_4k.png") as Texture2D
	material.roughness_texture = load("res://assets/hexaquo/concrete/concrete_wall_007_rough_4k.png") as Texture2D
	material.ao_enabled = true
	material.ao_texture = load("res://assets/hexaquo/concrete/concrete_wall_007_ao_4k.jpg") as Texture2D
	material.uv1_scale = Vector3.ONE * 0.2
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	return material

func _pbr_box(node_name: String, size: Vector3, position_value: Vector3, material: Material) -> StaticBody3D:
	var body := _static_box(node_name, size, position_value, Color.WHITE)
	(body.get_node("MeshInstance3D") as MeshInstance3D).material_override = material
	if size.length() > 5.0 and (size.y > 1.0 or size.x > 5.0 or size.z > 5.0):
		var occluder_instance := OccluderInstance3D.new()
		occluder_instance.name = "StructuralOccluder"
		var box_occluder := BoxOccluder3D.new()
		box_occluder.size = size
		occluder_instance.occluder = box_occluder
		body.add_child(occluder_instance)
	return body

func _build_abandoned_building() -> void:
	if _build_downloaded_abandoned_complex():
		return
	var concrete_pbr := _make_polyhaven_material("concrete_wall_008", 0.0, 0.76, 0.42)
	var brick_pbr := _make_polyhaven_material("brick_wall_006", 0.0, 0.82, 0.48)
	var plaster_pbr := _make_polyhaven_material("plastered_wall_03", 0.0, 0.72, 0.5)
	var metal_pbr := _make_polyhaven_material("rusty_metal_04", 0.68, 0.52, 0.7)
	var wood_pbr := _make_polyhaven_material("worn_planks", 0.0, 0.78, 0.75)
	_pbr_box("Foundation", Vector3(38.0, 0.4, 34.0), Vector3(0.0, 0.0, -8.0), concrete_pbr)
	# Segmented outer shell. Gaps between pieces are actual windows, not dark textures.
	for floor_index: int in 2:
		var y: float = 1.7 + floor_index * 3.4
		for z: float in [-22.0, -16.2, -10.4, -4.6, 1.2, 6.6]:
			_pbr_box("WestWallSegment", Vector3(0.38, 3.2, 4.45), Vector3(-18.8, y, z), plaster_pbr)
			_pbr_box("EastWallSegment", Vector3(0.38, 3.2, 4.45), Vector3(18.8, y, z), brick_pbr)
		for x: float in [-16.0, -10.2, -4.4, 4.4, 10.2, 16.0]:
			_pbr_box("RearWallSegment", Vector3(4.35, 3.2, 0.38), Vector3(x, y, -25.0), concrete_pbr)
		for x: float in [-14.2, -6.2, 6.2, 14.2]:
			_pbr_box("FrontWallSegment", Vector3(6.2, 3.2, 0.38), Vector3(x, y, 9.0), brick_pbr)
	# Real lintels/sills preserve structure while leaving sunlight openings.
	for z: float in [-19.1, -13.3, -7.5, -1.7, 3.9]:
		for x: float in [-18.8, 18.8]:
			_pbr_box("WindowLintel", Vector3(0.42, 0.36, 1.55), Vector3(x, 2.98, z), concrete_pbr)
			_pbr_box("UpperWindowLintel", Vector3(0.42, 0.36, 1.55), Vector3(x, 6.38, z), concrete_pbr)
	# Second floor is split around the staircase and two collapsed zones.
	_pbr_box("SecondFloorWest", Vector3(15.0, 0.28, 33.4), Vector3(-11.2, 3.42, -8.0), concrete_pbr)
	_pbr_box("SecondFloorCenterRear", Vector3(6.2, 0.28, 13.0), Vector3(0.0, 3.42, -18.2), concrete_pbr)
	_pbr_box("SecondFloorCenterFront", Vector3(6.2, 0.28, 10.0), Vector3(0.0, 3.42, 3.8), concrete_pbr)
	_pbr_box("SecondFloorEastRear", Vector3(8.0, 0.28, 14.0), Vector3(14.7, 3.42, -17.5), concrete_pbr)
	_pbr_box("SecondFloorEastFront", Vector3(8.0, 0.28, 10.0), Vector3(14.7, 3.42, 3.5), concrete_pbr)
	# Broken roof strips intentionally leave wide shafts for midday sun.
	for x: float in [-16.0, -10.0, -3.7, 4.2, 10.5, 16.0]:
		_pbr_box("BrokenRoofPanel", Vector3(4.4, 0.24, 33.0), Vector3(x, 6.82, -8.0), metal_pbr)
	for z: float in [-19.0, -12.0, -5.0, 2.0]:
		_pbr_box("GroundRoomDivider", Vector3(13.0, 3.05, 0.24), Vector3(-12.0, 1.72, z), plaster_pbr)
		_pbr_box("UpperRoomDivider", Vector3(12.0, 3.05, 0.24), Vector3(12.5, 5.05, z), brick_pbr)
	for i: int in 12:
		_pbr_box("Stair", Vector3(3.0, 0.25, 0.68), Vector3(6.0, 0.15 + i * 0.27, 5.8 - i * 0.54), concrete_pbr)
	for item: Array in [[Vector3(-7,0.55,-2),Vector3(2.5,1.1,0.8),wood_pbr],[Vector3(5,0.5,-10),Vector3(2.2,1.0,1.2),metal_pbr]]:
		_pbr_box("AbandonedCover", item[1], item[0], item[2])
	for i: int in 42:
		var rubble := _pbr_box("Rubble", Vector3(randf_range(0.16,0.62),randf_range(0.08,0.24),randf_range(0.18,0.7)), Vector3(randf_range(-17.4,17.4),0.14,randf_range(-23.8,7.8)), brick_pbr)
		rubble.rotation.y = randf_range(-PI, PI)
	# Curated local GTG/Poly Haven props. No duplicate external pack is loaded.
	_spawn_gtg_prop("res://assets/gtg/props/covered_car/covered_car_1k.gltf", Vector3(-6.8, 0.2, -11.8), Vector3(0.0, 0.35, 0.0), 1.0)
	_spawn_gtg_prop("res://assets/gtg/props/dead_tree_trunk_02/dead_tree_trunk_02_1k.gltf", Vector3(8.8, 0.1, -13.0), Vector3(0.0, -0.8, 0.0), 0.8)
	_spawn_gtg_prop("res://assets/gtg/props/old_tyre/old_tyre_1k.gltf", Vector3(-8.5, 0.2, 1.8), Vector3(1.4, 0.2, 0.0), 0.9)
	_spawn_gtg_prop("res://assets/gtg/props/wooden_stool_02/wooden_stool_02_1k.gltf", Vector3(4.2, 0.1, -1.0), Vector3(0.0, 1.1, 0.0), 1.0)
	_spawn_gtg_prop("res://assets/gtg/props/vintage_suitcase/vintage_suitcase_1k.gltf", Vector3(3.3, 0.15, -1.4), Vector3(0.0, -0.4, 0.0), 1.0)
	_spawn_gtg_prop("res://assets/gtg/props/compost_bags/compost_bags_1k.gltf", Vector3(-8.5, 0.1, -7.8), Vector3(0.0, 0.6, 0.0), 0.9)
	_spawn_gtg_prop("res://assets/gtg/props/cassette_player/cassette_player_1k.gltf", Vector3(-6.8, 0.72, -2.0), Vector3(0.0, 0.2, 0.0), 1.0)
	_spawn_gtg_prop("res://assets/gtg/props/small_oil_can_01/small_oil_can_01_1k.gltf", Vector3(6.4, 0.25, -12.0), Vector3(0.0, -1.0, 0.0), 1.0)
	_spawn_gtg_prop("res://assets/gtg/props/namaqualand_boulder_02/namaqualand_boulder_02_1k.gltf", Vector3(-2.5, 0.0, -14.0), Vector3(0.0, 0.8, 0.0), 0.55)
	_spawn_gtg_prop("res://assets/gtg/props/namaqualand_boulder_05/namaqualand_boulder_05_1k.gltf", Vector3(2.1, 0.0, 4.2), Vector3(0.0, -0.3, 0.0), 0.48)

func _build_downloaded_abandoned_complex() -> bool:
	var packed := load("res://UnfinishedBuildings/Gltf/UnfinishedBuildings.gltf") as PackedScene
	if packed == null:
		return false
	var source := packed.instantiate()
	var complex := Node3D.new()
	complex.name = "CC0AbandonedComplex"
	add_child(complex)
	var article_concrete := _make_hexaquo_concrete_material()
	var building_concrete := _make_polyhaven_material("concrete_wall_008", 0.0, 0.76, 0.5)
	var annex_plaster := _make_polyhaven_material("plastered_wall_03", 0.0, 0.78, 0.42)
	var pieces: Array[Array] = [
		["Structures_8", Vector3(0.0, 0.2, 0.0), 0.0, building_concrete],
		["Structures_2", Vector3(16.0, 0.2, -25.0), PI * 0.5, annex_plaster]
	]
	for piece_data: Array in pieces:
		var source_mesh := source.find_child(piece_data[0] as String, true, false) as MeshInstance3D
		if source_mesh == null or source_mesh.mesh == null:
			continue
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = piece_data[0] as String
		mesh_instance.mesh = source_mesh.mesh
		mesh_instance.material_override = piece_data[3] as Material
		mesh_instance.position = piece_data[1] as Vector3
		mesh_instance.rotation.y = piece_data[2] as float
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mesh_instance.visibility_range_end = 95.0
		complex.add_child(mesh_instance)
		mesh_instance.create_trimesh_collision()
	source.free()
	# Neutral soil is only a gap-filling underlay. The visible vegetation is the
	# Poly Haven grass_medium_01 asset, not the old mud-with-leaves texture.
	var courtyard_material := _make_soil_underlay_material()
	_pbr_box("AbandonedCourtyard", Vector3(58.0, 0.16, 54.0), Vector3(5.0, 0.08, -12.0), courtyard_material)
	# Exact article material remains on a bounded hero surface instead of being
	# sampled triplanar across the entire 54 m complex.
	_pbr_box("ArticleConcreteHeroWall", Vector3(7.0, 3.2, 0.22), Vector3(20.0, 1.8, 7.2), article_concrete)
	_spawn_gtg_prop("res://assets/hexaquo/tree/island_tree_02_2k.gltf", Vector3(-24.0, 0.15, -8.0), Vector3(0.0, 0.55, 0.0), 0.85)
	_spawn_gtg_prop("res://assets/gtg/props/covered_car/covered_car_1k.gltf", Vector3(-12.0, 0.2, -5.0), Vector3(0.0, 0.4, 0.0), 1.0)
	_spawn_gtg_prop("res://assets/gtg/props/compost_bags/compost_bags_1k.gltf", Vector3(8.0, 0.15, -6.0), Vector3(0.0, -0.8, 0.0), 0.9)
	_spawn_gtg_prop("res://assets/gtg/props/old_tyre/old_tyre_1k.gltf", Vector3(4.0, 0.2, 5.0), Vector3(1.4, 0.2, 0.0), 0.9)
	_spawn_gtg_prop("res://assets/gtg/props/metal_tool_chest_1k.gltf", Vector3(11.0, 0.1, -18.0), Vector3(0.0, 0.2, 0.0), 1.0)
	_spawn_gtg_prop("res://assets/gtg/props/vintage_suitcase/vintage_suitcase_1k.gltf", Vector3(-2.2, 0.62, -2.4), Vector3(0.0, 0.45, 0.0), 1.0)
	_spawn_gtg_prop("res://assets/gtg/props/wooden_stool_02/wooden_stool_02_1k.gltf", Vector3(2.1, 0.62, -2.8), Vector3(0.0, -0.35, 0.0), 1.0)
	_spawn_gtg_prop("res://assets/gtg/props/cassette_player/cassette_player_1k.gltf", Vector3(2.1, 1.18, -2.8), Vector3(0.0, -0.35, 0.0), 0.9)
	return true

func _build_grass_fields(target: Node3D) -> void:
	# Grass stays outside the concrete courtyard so the abandoned building keeps
	# a readable interior while the exterior gets a dense, wind-reactive layer.
	var patches: Array[Array] = [
		[Vector3(-29.5, 0.05, -11.0), Vector2(10.0, 24.0), 1800, 701],
		[Vector3(31.0, 0.05, -10.0), Vector2(8.0, 22.0), 1500, 702],
		[Vector3(5.0, 0.05, 21.5), Vector2(48.0, 10.0), 2100, 703],
		[Vector3(-28.0, 0.05, -34.0), Vector2(11.0, 10.0), 900, 704]
	]
	for patch: Array in patches:
		var field := GrassField.new()
		field.name = "GrassField_%d" % (patch[3] as int)
		field.position = patch[0] as Vector3
		field.configure(target, patch[1] as Vector2, patch[2] as int, patch[3] as int)
		add_child(field)

func _spawn_target(position_value: Vector3) -> void:
	var target := StaticBody3D.new()
	target.position = position_value
	add_child(target)
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.45
	cylinder.bottom_radius = 0.45
	cylinder.height = 0.12
	mesh.mesh = cylinder
	mesh.rotation.x = PI * 0.5
	target.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.9, 0.15)
	shape.shape = box
	target.add_child(shape)

func _static_box(node_name: String, size: Vector3, position_value: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position_value
	add_child(body)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body

func _make_wet_concrete_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/gtg/materials/concrete/Concrete019_1K-PNG_Color.png") as Texture2D
	# Darken the light concrete so midday sun does not blow the whole ground white.
	material.albedo_color = Color(0.42, 0.42, 0.44)
	material.normal_texture = load("res://assets/gtg/materials/concrete/Concrete019_1K-PNG_NormalGL.png") as Texture2D
	material.roughness_texture = load("res://assets/gtg/materials/concrete/Concrete019_1K-PNG_Roughness.png") as Texture2D
	material.roughness = 0.72
	material.metallic = 0.0
	material.uv1_scale = Vector3(12.0, 12.0, 12.0)
	return material

func _spawn_gtg_prop(path: String, position_value: Vector3, rotation_value: Vector3, scale_value: float = 1.0) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var prop := packed.instantiate() as Node3D
	prop.position = position_value
	prop.rotation = rotation_value
	prop.scale = Vector3.ONE * scale_value
	for node: Node in prop.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mesh_instance.visibility_range_end = 55.0
	add_child(prop)

func _add_light(position_value: Vector3, color: Color, energy: float) -> void:
	var light := OmniLight3D.new()
	light.position = position_value
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 8.0
	light.shadow_enabled = true
	add_child(light)

func _add_fps_counter() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(20.0, 20.0)
	label.add_theme_font_size_override("font_size", 18)
	layer.add_child(label)
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.autostart = true
	timer.timeout.connect(func() -> void: label.text = "FPS: %d  •  OBJECTS: %d" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	add_child(timer)
