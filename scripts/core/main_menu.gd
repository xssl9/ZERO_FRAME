extends Control

const MAPS: Array[Array] = [
	["ЗАБРОШЕННЫЙ КОМПЛЕКС", "res://scenes/levels/abandoned_building.tscn"],
	["WAREHOUSE TEST", "res://scenes/levels/test_range.tscn"],
	["BUILDING SCAN — INTERIOR", "res://scenes/levels/maps/building_scan.tscn"],
	["RUINS OF HORE ABBEY", "res://scenes/levels/maps/hore_abbey.tscn"],
	["SLADE GREEN COMMAND POST", "res://scenes/levels/maps/slade_green.tscn"],
	["BRUTALIST CONCRETE INTERIOR", "res://scenes/levels/maps/brutalist_interior.tscn"],
	["SQUINCH DOMES", "res://scenes/levels/maps/squinch_domes.tscn"]
]

const GRAPHICS_NAMES: PackedStringArray = ["AUTO", "PERFORMANCE", "HIGH", "ULTRA"]
var graphics_button: Button

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var background := ColorRect.new()
	background.color = Color("071015")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var title := Label.new()
	title.text = "ZERO FRAME"
	title.add_theme_font_size_override("font_size", 54)
	title.position = Vector2(80.0, 48.0)
	background.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "BODYCAM MAP SELECT   •   %d КАРТ" % MAPS.size()
	subtitle.modulate = Color("7f9ba5")
	subtitle.position = Vector2(84.0, 118.0)
	background.add_child(subtitle)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(80.0, 175.0)
	scroll.size = Vector2(460.0, 455.0)
	background.add_child(scroll)
	var buttons := VBoxContainer.new()
	buttons.custom_minimum_size = Vector2(430.0, 0.0)
	buttons.add_theme_constant_override("separation", 8)
	scroll.add_child(buttons)
	for map_data: Array in MAPS:
		_add_button(buttons, map_data[0] as String, _start_map.bind(map_data[1] as String))
	graphics_button = _add_button(buttons, "", _cycle_graphics)
	_refresh_graphics_button()
	_add_button(buttons, "ВЫХОД", _quit)

func _add_button(parent: VBoxContainer, label_text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(420.0, 48.0)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _cycle_graphics() -> void:
	var current := int(ProjectSettings.get_setting("zero_frame/graphics_quality", 0))
	ProjectSettings.set_setting("zero_frame/graphics_quality", (current + 1) % GRAPHICS_NAMES.size())
	_refresh_graphics_button()

func _refresh_graphics_button() -> void:
	var current := clampi(int(ProjectSettings.get_setting("zero_frame/graphics_quality", 0)), 0, GRAPHICS_NAMES.size() - 1)
	graphics_button.text = "ГРАФИКА: %s" % GRAPHICS_NAMES[current]

func _start_map(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func _quit() -> void:
	get_tree().quit()
