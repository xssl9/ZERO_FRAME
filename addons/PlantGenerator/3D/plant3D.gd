@tool
@icon("../Assets/icon3D.svg")
## A 3D L-system plant generator that creates plants based on user-defined axioms and production rules. Users can edit the plant's visuals. The plant can grow over time.
class_name Plant3D
extends MeshInstance3D

const _Calculator = preload("../Calculation/calculator.gd")
const _Sentence = _Calculator.Sentence
const _Symbol = _Calculator.Symbol
const SPECIAL_CHARACTERS: String = "[]+-fFlLabcdef"
var _plant_generator: PlantGenerator
var _wind_direction: float = 0.0
var _mat: StandardMaterial3D
var _mat_leaf: StandardMaterial3D
var _current_frame: float = 1.0
var _total_frames: float = 60.0
var _time_since_last_frame: float = 0.0
var _spf: float = 1.0 / 60.0
var _preset_to_save: String = ""
var _preset_to_load: String = ""
var _preset_to_remove: String = ""

var _presets: Dictionary[String, PlantPreset]:
	get:
		return _get_presets()

var _user_presets: Dictionary[String, PlantPreset]:
	get:
		return _get_user_presets()

@export_group("L-system")

## Initial axiom from which the plant will start growing.
@export var axiom: String = "X":
	set(value):
		axiom = value
		if _plant_generator:
			_plant_generator.axiom = value
			_draw()

## Production rules for the L-system.
@export var rules: Dictionary[String, String] = {
	"X": "f[&k][////&k]X"
}:
	set(value):
		for key in value.keys():
			if key.length() > 1:
				push_warning("Rule keys should be single characters. Ignoring key: " + key)
				value.erase(key)
			if key in SPECIAL_CHARACTERS:
				push_warning("Rule key '" + key + "' is a special character. This may cause unexpected behavior.")
			if value[key].count("[") != value[key].count("]"):
				push_warning("Rule for key '" + key + "' has unbalanced brackets. This may cause unexpected behavior.")
				rules = value
				return
		rules = value
		if _plant_generator:
			_plant_generator.rules = value
			_draw()

@export_group("Steps")

## The current growth step of the plant.
@export var current_step: int = 5:
	set(value):
		if growing:
			if (value - current_step != 1):
				push_error("current_step can only be incremented by 1 during growth animation.")
				return
			else:
				_plant_generator.grow_one_step()
		current_step = value
		if is_node_ready():
			current_step = clampi(value, 1, max_steps)
		if _plant_generator:
			_plant_generator.steps = value
			if not growing:
				_plant_generator.recalculate()
			_draw()

## The maximum growth steps allowed for the plant. Increasing this allows for more complex plants but may cause performance issues.
@export_range(1, 20, 1) var max_steps: int = 5:
	set(value):
		max_steps = value
		if is_node_ready():
			current_step = clampi(current_step, 1, max_steps)
		if _plant_generator:
			_plant_generator.max_steps = value
			_draw()

@export_group("Geometry")

## Length of branch segments.
@export_range(0.1, 200.0, 0.1, "or_greater") var branch_length: float = 10.0:
	set(value):
		branch_length = value
		if _plant_generator:
			_draw()

## Variation in branch length.
@export_range(0.0, 2.0, 0.1, "or_greater") var branch_length_randomness: float = 0.0:
	set(value):
		branch_length_randomness = value
		if _plant_generator:
			_plant_generator.branch_length_randomness = value
			_draw()

## Thickness of thinnest branches.
@export_range(0.1, 50.0, 0.1, "or_greater") var branch_width: float = 0.5:
	set(value):
		if value <= 0.0:
			branch_width = 0.1
		else:
			branch_width = value
		if _plant_generator:
			_plant_generator.branch_width = branch_width
			_draw()

## Angle in degrees for branch rotation.
@export_range(-360.0, 360.0) var angle: float = 45.0:
	set(value):
		angle = value
		if _plant_generator:
			_draw()

## Threshold for leaf growth. Leaves will only grow on branches thinner than this factor times the initial branch width.
@export_range(0.0, 10.0, 0.1, "or_greater") var leaf_growth_threshold: float = 8.0:
	set(value):
		leaf_growth_threshold = value
		if _plant_generator:
			_draw()

## Tropism strength. Higher values will cause the plant to bend more towards the tropism vector (currently hardcoded as up). This can be used to create effects like gravity or phototropism.
@export var tropism_strength: float = 0.0:
	set(value):
		tropism_strength = value
		if _plant_generator:
			_draw()

@export_group("Textures")

## Color for the leaves.
@export var leaf_color: Color = Color(0.2, 0.8, 0.2):
	set(value):
		leaf_color = value
		if _plant_generator:
			_draw()

## Texture for the leaves. Should have transparent background.
@export var leaf_texture: Texture2D:
	set(value):
		leaf_texture = value
		if _plant_generator:
			_draw()

## Scale factor for the leaves.
@export var leaf_scale: float = 10.0:
	set(value):
		leaf_scale = value
		if _plant_generator:
			_draw()

## Color of the branches when no branch texture is set.
@export var branch_color: Color = Color(0.2, 0.1, 0.05):
	set(value):
		branch_color = value
		if _plant_generator:
			_draw()

## Texture for the branches. Overrides branch_color when set.
@export var branch_texture: Texture2D:
	set(value):
		branch_texture = value
		if _plant_generator:
			_draw()

## Scale factor for the branch texture.
@export var branch_texture_scale: float = 1.0:
	set(value):
		branch_texture_scale = value
		if _plant_generator:
			_draw()

@export_group("Animation")

## Time in seconds for one growth step.
@export var growth_time: float = 5.0:
	set(value):
		growth_time = value
		_total_frames = growth_time * growth_fps

## Whether the plant is currently growing. When true, the plant will automatically grow one step at a time based on the growth_time and growth_fps settings.
@export var growing: bool = false:
	set(value):
		growing = value

## Frames per second for growth animation.
@export var growth_fps: int = 60:
	set(value):
		growth_fps = value
		_total_frames = growth_time * growth_fps
		_spf = 1.0 / growth_fps

## Strength of the wind affecting the plant. Higher values will cause more swaying in the branches and leaves.
@export var wind_strength: float = 0.0:
	set(value):
		wind_strength = value

@export_group("Presets")

@export_tool_button("Save as PlantPreset", "Save") var _save_preset_btn: Callable = _show_save_preset_dialog
@export_tool_button("Load PlantPreset", "Load") var _load_preset_btn: Callable = _show_load_preset_dialog
@export_tool_button("Remove PlantPreset", "Remove") var _remove_preset_btn: Callable = _show_remove_preset_dialog


func _ready() -> void:
	current_step = clampi(current_step, 1, max_steps)
	_plant_generator = PlantGenerator.new(axiom, rules, current_step, max_steps, branch_length_randomness, branch_width)
	_plant_generator._ready()
	PlantFileManager.load_user_presets()
	notify_property_list_changed()
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat_leaf = StandardMaterial3D.new()
	_draw()
	_total_frames = growth_time * growth_fps
	_spf = 1.0 / growth_fps


func _process(delta: float) -> void:
	_time_since_last_frame += delta
	if growing:
		if _time_since_last_frame >= _spf:
			_time_since_last_frame -= _spf
			if _current_frame >= _total_frames:
				if current_step >= max_steps:
					growing = false
				else:
					_current_frame = 1.0
					current_step += 1
				return
			_current_frame += 1.0
	if _plant_generator and (wind_strength != 0.0 or growing):
		_draw()


func _validate_property(property: Dictionary) -> void:
	if property.name == "preset":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(_presets.keys())


func _get_presets() -> Dictionary[String, PlantPreset]:
	return PlantFileManager.presets_3D


func _get_user_presets() -> Dictionary[String, PlantPreset]:
	return PlantFileManager._user_presets_3D


func _get_preset(key: String) -> PlantPreset:
	return _presets.get(key)


func _apply_tropism(direction: Basis, tropism_vector: Vector2) -> Basis:
	var current_growth: Vector3 = -direction.z  # Current growth direction
	var desired_direction: Vector3 = Vector3(tropism_vector.x, tropism_vector.y, 0).normalized()
	
	# Calculate rotation axis perpendicular to both vectors
	var rotation_axis: Vector3 = current_growth.cross(desired_direction)
	
	# If vectors are parallel, no rotation needed
	if rotation_axis.length() < 0.001:
		return direction
	
	rotation_axis = rotation_axis.normalized()
	
	# Calculate angle between directions
	var angle_difference: float = current_growth.angle_to(desired_direction)
	
	# Apply tropism with smoothing factor
	return direction.rotated(rotation_axis, angle_difference * tropism_strength)


func _get_branch_length(level: int, ignore_frame: bool, length_factor: float) -> float:
	var base_length: float = branch_length * pow(1.0, level)
	if ignore_frame:
		return (length_factor * base_length)
	return (length_factor * base_length) * (_current_frame / _total_frames)


func _get_branch_width(old_branch_width: float, current_branch_width: float) -> float:
	return lerp(old_branch_width, current_branch_width, _current_frame / _total_frames)


func _show_save_preset_dialog() -> void:
	var save_preset_dialog: AcceptDialog = AcceptDialog.new()
	save_preset_dialog.title = "Save PlantPreset"
	save_preset_dialog.dialog_text = "Enter a preset name."
	save_preset_dialog.ok_button_text = "Save"
	save_preset_dialog.min_size = Vector2i(320, 120)

	var name_input: LineEdit = LineEdit.new()
	name_input.placeholder_text = "Preset name"
	name_input.text = _preset_to_save
	save_preset_dialog.add_child(name_input)

	save_preset_dialog.confirmed.connect(func() -> void:
		_preset_to_save = name_input.text.strip_edges()
		if _preset_to_save.is_empty():
			push_warning("Preset name cannot be empty.")
			return
		save_preset(_preset_to_save)
		save_preset_dialog.queue_free()
	)
	save_preset_dialog.close_requested.connect(save_preset_dialog.queue_free)

	EditorInterface.popup_dialog_centered(save_preset_dialog, Vector2i(320, 120))


## Saves the current plant configuration as a new preset.
func save_preset(preset_name: String) -> void:    
	PlantFileManager.save_preset(preset_name, PlantPreset.new(axiom, rules, max_steps, branch_length, branch_length_randomness, branch_width, angle, leaf_growth_threshold, tropism_strength, leaf_color, leaf_texture, leaf_scale, branch_color, branch_texture, branch_texture_scale, growth_time, growth_fps, wind_strength), "presets_3D")
	notify_property_list_changed()


func _show_load_preset_dialog() -> void:
	var load_preset_dialog: AcceptDialog = AcceptDialog.new()
	load_preset_dialog.title = "Load PlantPreset"
	load_preset_dialog.dialog_text = "Select a preset."
	load_preset_dialog.ok_button_text = "Load"
	load_preset_dialog.min_size = Vector2i(320, 120)

	var preset_dropdown: OptionButton = OptionButton.new()
	var preset_names: PackedStringArray = _presets.keys()
	preset_names.sort()
	for preset_name: String in preset_names:
		preset_dropdown.add_item(preset_name)

	if preset_dropdown.item_count == 0:
		preset_dropdown.add_item("No presets available")
		preset_dropdown.disabled = true
	else:
		var preset_index: int = preset_names.find(_preset_to_load)
		preset_dropdown.selected = preset_index if preset_index != -1 else 0

	load_preset_dialog.add_child(preset_dropdown)

	load_preset_dialog.confirmed.connect(func() -> void:
		if preset_dropdown.disabled:
			push_warning("No presets are available.")
			return
		_preset_to_load = preset_dropdown.get_item_text(preset_dropdown.selected)
		load_preset(_preset_to_load)
		load_preset_dialog.queue_free()
	)
	load_preset_dialog.close_requested.connect(load_preset_dialog.queue_free)

	EditorInterface.popup_dialog_centered(load_preset_dialog, Vector2i(320, 120))


## Loads preset and applies its settings to the plant.
func load_preset(preset_name: String) -> void:
	var preset_data: PlantPreset = _get_preset(preset_name)
	if preset_data != null:
		max_steps = preset_data.max_steps
		axiom = preset_data.axiom
		rules = preset_data.ruleset
		branch_length = preset_data.branch_length
		branch_length_randomness = preset_data.branch_length_randomness
		branch_width = preset_data.branch_width
		angle = preset_data.angle
		leaf_growth_threshold = preset_data.leaf_growth_threshold
		tropism_strength = preset_data.tropism_strength
		leaf_color = preset_data.leaf_color
		leaf_texture = preset_data.leaf_texture
		leaf_scale = preset_data.leaf_scale
		branch_color = preset_data.branch_color
		branch_texture = preset_data.branch_texture
		branch_texture_scale = preset_data.branch_texture_scale
		growth_time = preset_data.growth_time
		growth_fps = preset_data.growth_fps
		wind_strength = preset_data.wind_strength
		if Engine.is_editor_hint():
			EditorInterface.mark_scene_as_unsaved()


func _show_remove_preset_dialog() -> void:
	var remove_preset_dialog: AcceptDialog = AcceptDialog.new()
	remove_preset_dialog.title = "Remove PlantPreset"
	remove_preset_dialog.dialog_text = "Select a preset."
	remove_preset_dialog.ok_button_text = "Remove"
	remove_preset_dialog.min_size = Vector2i(320, 120)

	var preset_dropdown: OptionButton = OptionButton.new()
	var preset_names: PackedStringArray = _user_presets.keys()
	preset_names.sort()
	for preset_name: String in preset_names:
		preset_dropdown.add_item(preset_name)

	if preset_dropdown.item_count == 0:
		preset_dropdown.add_item("No presets available")
		preset_dropdown.disabled = true
	else:
		var preset_index: int = preset_names.find(_preset_to_remove)
		preset_dropdown.selected = preset_index if preset_index != -1 else 0

	remove_preset_dialog.add_child(preset_dropdown)

	remove_preset_dialog.confirmed.connect(func() -> void:
		if preset_dropdown.disabled:
			push_warning("No presets are available.")
			return
		_preset_to_remove = preset_dropdown.get_item_text(preset_dropdown.selected)
		remove_preset(_preset_to_remove)
		remove_preset_dialog.queue_free()
	)
	remove_preset_dialog.close_requested.connect(remove_preset_dialog.queue_free)

	EditorInterface.popup_dialog_centered(remove_preset_dialog, Vector2i(320, 120))


## Removes a user-defined preset.
func remove_preset(preset_name: String) -> void:
	PlantFileManager.remove_user_preset(preset_name, "presets_3D")
	notify_property_list_changed()

func _draw() -> void:
	if not _plant_generator.sentence:
		return

	var m: ImmediateMesh = mesh
	if not m:
		m = ImmediateMesh.new()
		mesh = m

	m.clear_surfaces()

	if branch_texture:
		_mat.albedo_texture = branch_texture
		_mat.uv1_scale = Vector3(branch_texture_scale, branch_texture_scale, 1.0)
		_mat.vertex_color_use_as_albedo = false
		_mat.texture_repeat = true
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		
	else:
		_mat.albedo_texture = null
		_mat.vertex_color_use_as_albedo = true
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


	if leaf_texture:
		_mat_leaf.albedo_texture = leaf_texture
		_mat_leaf.uv1_scale = Vector3.ONE
		_mat_leaf.texture_repeat = false
		_mat_leaf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_mat_leaf.vertex_color_use_as_albedo = false
		_mat_leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		_mat_leaf.albedo_texture = null
		_mat_leaf.vertex_color_use_as_albedo = true
		_mat_leaf.cull_mode = BaseMaterial3D.CULL_DISABLED

	var stack: Array = []
	var draw_position: Vector3 = Vector3.ZERO
	var helper_basis: Basis = transform.basis.rotated(Vector3.LEFT, deg_to_rad(-90.0))
	var level: int = 0
	var current_branch_current_width: float = 0.0

	var leaves_to_place: Array = []
	var branch_surface_started: bool = false

	_wind_direction += randf_range(- wind_strength, wind_strength)

	for symbol: _Symbol in _plant_generator.sentence.symbols:
		match symbol.character:
			"[":
				stack.push_front([draw_position, helper_basis, level])
			"]":
				draw_position = stack[0][0]
				helper_basis = stack[0][1]
				level = stack[0][2]
				stack.pop_front()
			"F":
				current_branch_current_width = symbol.attributes.current_width
				level += 1
				helper_basis = _apply_tropism(helper_basis, Vector2.DOWN)
				if not branch_surface_started:
					m.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat)
					branch_surface_started = true
				draw_position = _draw_branch(m, draw_position, - helper_basis.z.normalized(), helper_basis.x.normalized(), helper_basis.y.normalized(), level, symbol.attributes.length_factor, symbol.attributes.current_width, symbol.attributes.desired_width, true)
			"f":
				current_branch_current_width = symbol.attributes.current_width
				level += 1
				helper_basis = _apply_tropism(helper_basis, Vector2.DOWN)
				if not branch_surface_started:
					m.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat)
					branch_surface_started = true
				draw_position = _draw_branch(m, draw_position, - helper_basis.z.normalized(), helper_basis.x.normalized(), helper_basis.y.normalized(), level, symbol.attributes.length_factor, symbol.attributes.current_width, symbol.attributes.desired_width)
			"-":
				helper_basis = helper_basis.rotated(helper_basis.y.normalized(), deg_to_rad(angle))
			"+":
				helper_basis = helper_basis.rotated(helper_basis.y.normalized(), deg_to_rad(- angle))
			"&":
				helper_basis = helper_basis.rotated(helper_basis.x.normalized(), deg_to_rad(- angle))
			"^":
				helper_basis = helper_basis.rotated(helper_basis.x.normalized(), deg_to_rad(angle))
			"/":
				helper_basis = helper_basis.rotated(- helper_basis.z.normalized(), deg_to_rad(angle))
			"\\":
				helper_basis = helper_basis.rotated(- helper_basis.z.normalized(), deg_to_rad(- angle))
			"|":
				helper_basis = helper_basis.rotated(helper_basis.y.normalized(), deg_to_rad(180.0))
			"l":
				var branch_thickness_factor: float = current_branch_current_width / branch_width
				if branch_thickness_factor < leaf_growth_threshold:
					leaves_to_place.append([draw_position, helper_basis.rotated(Vector3.UP, deg_to_rad(_wind_direction)), false])
			"L":
				var branch_thickness_factor: float = current_branch_current_width / branch_width
				if branch_thickness_factor < leaf_growth_threshold:
					leaves_to_place.append([draw_position, helper_basis.rotated(Vector3.UP, deg_to_rad(_wind_direction)), true])

	if branch_surface_started:
		m.surface_end()

	var leaf_surface_started: bool = false

	var leaf_count: int = leaves_to_place.size()
	for i in range(leaf_count):
		if not leaf_surface_started:
			m.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat_leaf)
			leaf_surface_started = true
		_draw_leaf_billboard(m, leaves_to_place[i][0], leaves_to_place[i][1], leaves_to_place[i][2])

	if leaf_surface_started:
		m.surface_end()

func _draw_line_3d(m: ImmediateMesh, start: Vector3, end: Vector3, normal: Vector3, up: Vector3, color: Color, width: float) -> void:
	normal *= (width / 2.0)
	up *= (width / 2.0)

	var p1: Vector3 = start + normal
	var p2: Vector3 = start - normal
	var p3: Vector3 = end + normal
	var p4: Vector3 = end - normal
	var p5: Vector3 = start + up
	var p6: Vector3 = end + up

	m.surface_set_color(color)

	var uv_start: float = 0.0
	var uv_end: float = (start - end).length()
	
	# Triangle 1
	m.surface_set_uv(Vector2(0.0, 0.0))
	m.surface_add_vertex(p1)
	m.surface_set_uv(Vector2(uv_end, uv_end))
	m.surface_add_vertex(p3)
	m.surface_set_uv(Vector2(0.0, uv_end))
	m.surface_add_vertex(p2)
	
	# Triangle 2
	m.surface_set_uv(Vector2(0.0, uv_end))
	m.surface_add_vertex(p2)
	m.surface_set_uv(Vector2(uv_end, uv_end))
	m.surface_add_vertex(p3)
	m.surface_set_uv(Vector2(uv_end, 0.0))
	m.surface_add_vertex(p4)
	
	# Triangle 3
	m.surface_set_uv(Vector2(0.0, 0.0))
	m.surface_add_vertex(p1)
	m.surface_set_uv(Vector2(0.0, uv_end))
	m.surface_add_vertex(p5)
	m.surface_set_uv(Vector2(uv_end, 0.0))
	m.surface_add_vertex(p3)
	
	# Triangle 4
	m.surface_set_uv(Vector2(0.0, uv_end))
	m.surface_add_vertex(p5)
	m.surface_set_uv(Vector2(uv_end, uv_end))
	m.surface_add_vertex(p6)
	m.surface_set_uv(Vector2(uv_end, 0.0))
	m.surface_add_vertex(p3)
	
	# Triangle 5
	m.surface_set_uv(Vector2(uv_end, uv_end))
	m.surface_add_vertex(p2)
	m.surface_set_uv(Vector2(uv_end, 0.0))
	m.surface_add_vertex(p4)
	m.surface_set_uv(Vector2(0.0, uv_end))
	m.surface_add_vertex(p5)
	
	# Triangle 6
	m.surface_set_uv(Vector2(uv_end, 0.0))
	m.surface_add_vertex(p4)
	m.surface_set_uv(Vector2(uv_end, uv_end))
	m.surface_add_vertex(p6)
	m.surface_set_uv(Vector2(0.0, uv_end))
	m.surface_add_vertex(p5)

	# Bottom
	m.surface_set_uv(Vector2(0.0, 0.0))
	m.surface_add_vertex(p1)
	m.surface_set_uv(Vector2(0.0, uv_end))
	m.surface_add_vertex(p2)
	m.surface_set_uv(Vector2(uv_end / 2.0, uv_end / 2.0))
	m.surface_add_vertex(p5)

	# Top
	m.surface_set_uv(Vector2(uv_end, 0.0))
	m.surface_add_vertex(p3)
	m.surface_set_uv(Vector2(uv_end, uv_end))
	m.surface_add_vertex(p6)
	m.surface_set_uv(Vector2(uv_end / 2.0, uv_end / 2.0))
	m.surface_add_vertex(p4)


func _draw_branch(m: ImmediateMesh, draw_position: Vector3, draw_direction: Vector3, draw_normal: Vector3, draw_up: Vector3, level: int, length_factor: float, current_width: float, desired_width: float, ignore_frame: bool = false) -> Vector3:
	var new_position: Vector3 = draw_position + draw_direction * _get_branch_length(level, ignore_frame, length_factor)
	_draw_line_3d(m, draw_position, new_position, - draw_normal, draw_up, branch_color, _get_branch_width(current_width, desired_width))
	_draw_line_3d(m, draw_position, new_position, draw_normal, - draw_up, branch_color, _get_branch_width(current_width, desired_width))
	return new_position

func _draw_leaf_billboard(m: ImmediateMesh, draw_position: Vector3, helper_basis: Basis, ignore_frame: bool = false) -> void:
	var leaf_size: Vector2 = Vector2(1, 1)
	var leaf_progress: float = 1.0
	if not ignore_frame:
		leaf_progress = _current_frame / _total_frames

	var leaf_draw_scale: float = leaf_scale * leaf_progress
	
	var right: Vector3 = helper_basis.x * leaf_size.x * leaf_draw_scale
	var up: Vector3 = helper_basis.y * leaf_size.y * leaf_draw_scale

	var p1: Vector3 = draw_position
	var p2: Vector3 = draw_position - right * 0.5 + up * 0.5
	var p3: Vector3 = draw_position + right * 0.5 + up * 0.5
	var p4: Vector3 = draw_position + up
	
	m.surface_set_color(leaf_color)

	m.surface_set_uv(Vector2(0.5, 1.0))
	m.surface_add_vertex(p1)
	m.surface_set_uv(Vector2(1.0, 0.5))
	m.surface_add_vertex(p2)
	m.surface_set_uv(Vector2(0.0, 0.5))
	m.surface_add_vertex(p3)

	m.surface_set_uv(Vector2(1.0, 0.5))
	m.surface_add_vertex(p2)
	m.surface_set_uv(Vector2(0.5, 0.0))
	m.surface_add_vertex(p4)
	m.surface_set_uv(Vector2(0.0, 0.5))
	m.surface_add_vertex(p3)
