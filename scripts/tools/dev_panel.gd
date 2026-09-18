class_name DevPanel
extends CanvasLayer

## DEV PANEL — hit-testing sandbox
##
## F1 toggles the panel.
## All spawned dummies live in a dedicated Node3D container so Clear All is a
## single queue_free() on that container.
##
## The panel is added as a child of GlobalInput (autoload) so it survives
## scene changes and is always available in any level.

const SPAWN_DISTANCE_DEFAULT := 3.0
const SPAWN_DISTANCE_MIN     := 1.0
const SPAWN_DISTANCE_MAX     := 20.0

# ── UI references ──────────────────────────────────────────────────────────
var _root: PanelContainer          # shown/hidden instead of the CanvasLayer
var _spawn_distance_label: Label
var _hitbox_btn: Button
var _bone_btn: Button
var _debug_hit_btn: Button
var _info_label: Label

# ── State ──────────────────────────────────────────────────────────────────
var _opened: bool = false
var _spawn_distance: float = SPAWN_DISTANCE_DEFAULT
var _show_hitboxes: bool = false
var _show_bones: bool = false
var _dummy_container: Node3D = null
var _hitbox_overlays: Array[MeshInstance3D] = []
var _bone_overlays: Array[Node3D] = []

# Shared HitFeedback singleton (created once, lives here).
var hit_feedback: HitFeedback = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 201          # one above PauseMenu (200)
	_build_ui()
	_root.hide()         # hidden by default — same pattern as PauseMenu._shade
	_ensure_hit_feedback()

# ── Input ──────────────────────────────────────────────────────────────────
# CanvasLayer receives _input, not _unhandled_input — same as PauseMenu.

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("dev_panel_toggle") and not event.is_echo():
		_toggle()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	_opened = not _opened
	_root.visible = _opened
	if _opened:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		# Only recapture if the player is alive and in a level.
		var player := get_tree().get_first_node_in_group("player") as PlayerController
		if player != null and player.health > 0.0 and not player.menu_open:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ── UI construction ────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = PanelContainer.new()
	_root.name = "DevPanelRoot"
	add_child(_root)

	# Position: top-left corner with a small margin.
	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_root.offset_left   = 16.0
	_root.offset_top    = 16.0
	_root.offset_right  = 320.0
	_root.offset_bottom = 520.0

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_root.add_child(vbox)

	# ── Title ──
	var title := Label.new()
	title.text = "▶ DEV PANEL  [F1]"
	title.add_theme_font_size_override("font_size", 15)
	title.modulate = Color(0.9, 0.85, 0.3)
	vbox.add_child(title)

	vbox.add_child(_separator())

	# ── Spawn distance ──
	var dist_row := HBoxContainer.new()
	vbox.add_child(dist_row)
	var dist_lbl := Label.new()
	dist_lbl.text = "Spawn Distance:"
	dist_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dist_row.add_child(dist_lbl)
	var dist_minus := Button.new()
	dist_minus.text = "−"
	dist_minus.pressed.connect(_on_dist_minus)
	dist_row.add_child(dist_minus)
	_spawn_distance_label = Label.new()
	_spawn_distance_label.text = "%.1f m" % _spawn_distance
	_spawn_distance_label.custom_minimum_size.x = 52.0
	_spawn_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dist_row.add_child(_spawn_distance_label)
	var dist_plus := Button.new()
	dist_plus.text = "+"
	dist_plus.pressed.connect(_on_dist_plus)
	dist_row.add_child(dist_plus)

	vbox.add_child(_separator())

	# ── Spawn buttons ──
	vbox.add_child(_make_button("Spawn Player (×1)",  _on_spawn_1))
	vbox.add_child(_make_button("Spawn Player (×5)",  _on_spawn_5))
	vbox.add_child(_make_button("Spawn Player (×10)", _on_spawn_10))
	vbox.add_child(_make_button("Clear All",          _on_clear_all, Color(1.0, 0.35, 0.3)))

	vbox.add_child(_separator())

	# ── Visualisation toggles ──
	_hitbox_btn = _make_toggle_button("Show Hitboxes", _on_toggle_hitboxes)
	vbox.add_child(_hitbox_btn)
	_bone_btn = _make_toggle_button("Show Bones", _on_toggle_bones)
	vbox.add_child(_bone_btn)
	_debug_hit_btn = _make_toggle_button("Debug Hit Info", _on_toggle_debug_hit)
	vbox.add_child(_debug_hit_btn)

	vbox.add_child(_separator())

	# ── Info readout ──
	_info_label = Label.new()
	_info_label.text = "No hits yet."
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_font_size_override("font_size", 12)
	_info_label.modulate = Color(0.75, 1.0, 0.75)
	vbox.add_child(_info_label)

func _separator() -> HSeparator:
	return HSeparator.new()

func _make_button(label: String, callback: Callable, tint: Color = Color.WHITE) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.modulate = tint
	btn.pressed.connect(callback)
	return btn

func _make_toggle_button(label: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.toggle_mode = true
	btn.toggled.connect(callback)
	return btn

# ── Distance controls ──────────────────────────────────────────────────────

func _on_dist_minus() -> void:
	_spawn_distance = maxf(_spawn_distance - 1.0, SPAWN_DISTANCE_MIN)
	_spawn_distance_label.text = "%.1f m" % _spawn_distance

func _on_dist_plus() -> void:
	_spawn_distance = minf(_spawn_distance + 1.0, SPAWN_DISTANCE_MAX)
	_spawn_distance_label.text = "%.1f m" % _spawn_distance

# ── Spawn / Clear ──────────────────────────────────────────────────────────

func _on_spawn_1()  -> void: _spawn_dummies(1)
func _on_spawn_5()  -> void: _spawn_dummies(5)
func _on_spawn_10() -> void: _spawn_dummies(10)

func _on_clear_all() -> void:
	if _dummy_container != null and is_instance_valid(_dummy_container):
		_dummy_container.queue_free()
	_dummy_container = null
	_hitbox_overlays.clear()
	_bone_overlays.clear()
	_info_label.text = "Cleared."

func _ensure_container() -> void:
	if _dummy_container != null and is_instance_valid(_dummy_container):
		return
	_dummy_container = Node3D.new()
	_dummy_container.name = "DevDummyContainer"
	var scene := get_tree().current_scene
	if scene != null:
		scene.add_child(_dummy_container)

func _spawn_dummies(count: int) -> void:
	_ensure_container()
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player == null:
		_info_label.text = "No player found."
		return

	var forward := -player.global_transform.basis.z.normalized()
	var right   := player.global_transform.basis.x.normalized()

	for i: int in count:
		var model := SoldierModel.instantiate()
		model.name = "DevDummy_%d" % (_dummy_container.get_child_count())
		_dummy_container.add_child(model)

		# Spread dummies in a row perpendicular to the player's facing.
		var offset_x := (float(i) - float(count - 1) * 0.5) * 1.2
		var spawn_pos := player.global_position \
			+ forward * _spawn_distance \
			+ right * offset_x
		model.global_position = spawn_pos
		# Face the player.
		model.look_at(player.global_position, Vector3.UP)

		# Build hitboxes so the dummy is actually shootable.
		var skeleton: Skeleton3D = null
		for child: Node in model.find_children("*", "Skeleton3D", true, false):
			skeleton = child as Skeleton3D
			break
		if skeleton != null:
			var areas := SoldierHitboxes.build(skeleton, model, 0)
			# Tag each area so weapon_base can route the hit through HitFeedback.
			for area: Area3D in areas:
				area.set_meta("dev_dummy", true)
			# Optionally show hitbox overlays immediately.
			if _show_hitboxes:
				_add_hitbox_overlays_for(areas)
			if _show_bones:
				_add_bone_overlays_for(skeleton)

		# Play idle animation.
		var anim_player: AnimationPlayer = null
		for child: Node in model.find_children("*", "AnimationPlayer", true, false):
			anim_player = child as AnimationPlayer
			break
		if anim_player != null and anim_player.has_animation("idle"):
			anim_player.play("idle")

	_info_label.text = "Spawned %d dummy(s). Total: %d" % [count, _dummy_container.get_child_count()]

# ── Hitbox visualisation ───────────────────────────────────────────────────

func _on_toggle_hitboxes(pressed: bool) -> void:
	_show_hitboxes = pressed
	_hitbox_btn.text = ("Hide Hitboxes" if pressed else "Show Hitboxes")
	if not pressed:
		for overlay: MeshInstance3D in _hitbox_overlays:
			if is_instance_valid(overlay):
				overlay.queue_free()
		_hitbox_overlays.clear()
		return
	# Build overlays for all existing dummies.
	if _dummy_container == null or not is_instance_valid(_dummy_container):
		return
	for dummy: Node in _dummy_container.get_children():
		var skeleton: Skeleton3D = null
		for child: Node in dummy.find_children("*", "Skeleton3D", true, false):
			skeleton = child as Skeleton3D
			break
		if skeleton == null:
			continue
		var areas: Array[Area3D] = []
		for child: Node in skeleton.find_children("Hit_*", "Area3D", true, false):
			areas.append(child as Area3D)
		_add_hitbox_overlays_for(areas)

func _add_hitbox_overlays_for(areas: Array[Area3D]) -> void:
	for area: Area3D in areas:
		var shape_node := area.get_node_or_null("Shape") as CollisionShape3D
		if shape_node == null:
			continue
		var overlay := MeshInstance3D.new()
		overlay.name = "HitboxOverlay"
		overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var zone := area.get_meta("hit_zone", "limbs") as String
		mat.albedo_color = _zone_wire_color(zone)
		overlay.material_override = mat
		if shape_node.shape is SphereShape3D:
			var s := shape_node.shape as SphereShape3D
			var sphere := SphereMesh.new()
			sphere.radius = s.radius
			sphere.height = s.radius * 2.0
			sphere.radial_segments = 10
			sphere.rings = 5
			overlay.mesh = sphere
		elif shape_node.shape is CapsuleShape3D:
			var c := shape_node.shape as CapsuleShape3D
			var cap := CapsuleMesh.new()
			cap.radius = c.radius
			cap.height = c.height
			cap.radial_segments = 10
			cap.rings = 4
			overlay.mesh = cap
		else:
			continue
		shape_node.add_child(overlay)
		overlay.transform = Transform3D.IDENTITY
		_hitbox_overlays.append(overlay)

func _zone_wire_color(zone: String) -> Color:
	match zone:
		"head":
			return Color(1.0, 0.2, 0.1, 0.35)
		"torso":
			return Color(1.0, 0.7, 0.0, 0.28)
		_:
			return Color(0.2, 0.8, 1.0, 0.25)

# ── Bone visualisation ─────────────────────────────────────────────────────

func _on_toggle_bones(pressed: bool) -> void:
	_show_bones = pressed
	_bone_btn.text = ("Hide Bones" if pressed else "Show Bones")
	if not pressed:
		for overlay: Node3D in _bone_overlays:
			if is_instance_valid(overlay):
				overlay.queue_free()
		_bone_overlays.clear()
		return
	if _dummy_container == null or not is_instance_valid(_dummy_container):
		return
	for dummy: Node in _dummy_container.get_children():
		var skeleton: Skeleton3D = null
		for child: Node in dummy.find_children("*", "Skeleton3D", true, false):
			skeleton = child as Skeleton3D
			break
		if skeleton != null:
			_add_bone_overlays_for(skeleton)

func _add_bone_overlays_for(skeleton: Skeleton3D) -> void:
	for bone_idx: int in skeleton.get_bone_count():
		var dot := MeshInstance3D.new()
		dot.name = "BoneViz_%d" % bone_idx
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sphere := SphereMesh.new()
		sphere.radius = 0.022
		sphere.height = 0.044
		sphere.radial_segments = 6
		sphere.rings = 3
		dot.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.3, 1.0, 0.4, 0.9)
		dot.material_override = mat
		var attach := BoneAttachment3D.new()
		attach.name = "BoneAttach_%d" % bone_idx
		attach.bone_idx = bone_idx
		skeleton.add_child(attach)
		attach.add_child(dot)
		_bone_overlays.append(attach)

# ── Debug Hit Info toggle ──────────────────────────────────────────────────

func _on_toggle_debug_hit(pressed: bool) -> void:
	_debug_hit_btn.text = ("Hide Hit Info" if pressed else "Debug Hit Info")
	if hit_feedback != null:
		hit_feedback.debug_hit_info = pressed

## Called by weapon_base after a hitbox hit is confirmed.
func report_hit(zone: String, damage: float, distance: float, killed: bool) -> void:
	var zone_label := zone.to_upper()
	var killed_str := "  💀 KILLED" if killed else ""
	_info_label.text = "[%s]  %.1f dmg  %.1f m%s" % [zone_label, damage, distance, killed_str]

# ── HitFeedback singleton ──────────────────────────────────────────────────

func _ensure_hit_feedback() -> void:
	hit_feedback = HitFeedback.new()
	hit_feedback.name = "HitFeedback"
	add_child(hit_feedback)
