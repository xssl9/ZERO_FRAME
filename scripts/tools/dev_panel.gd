class_name DevPanel
extends Node

## DEV PANEL — hit-testing sandbox
## F1 — открыть/закрыть.
## Добавляется как дочерний к GlobalInput (autoload).
## Создаёт собственный CanvasLayer прямо в root-Viewport,
## чтобы UI гарантированно рендерился поверх всего.

const SPAWN_DISTANCE_DEFAULT := 3.0
const SPAWN_DISTANCE_MIN     := 1.0
const SPAWN_DISTANCE_MAX     := 20.0

# ── UI ─────────────────────────────────────────────────────────────────────
var _canvas: CanvasLayer          # живёт в root, не в GlobalInput
var _root: PanelContainer
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

var hit_feedback: HitFeedback = null

# ── Lifecycle ──────────────────────────────────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hit_feedback = HitFeedback.new()
	hit_feedback.name = "HitFeedback"
	add_child(hit_feedback)
	call_deferred("_build_canvas")

func _build_canvas() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "DevPanelCanvas"
	_canvas.layer = 201
	_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_canvas)
	_build_ui()
	_root.hide()

func _exit_tree() -> void:
	if is_instance_valid(_canvas):
		_canvas.queue_free()

# ── Input ──────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("dev_panel_toggle") and not event.is_echo():
		_toggle()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	if not is_instance_valid(_root):
		return
	_opened = not _opened
	_root.visible = _opened
	if _opened:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		var player := get_tree().get_first_node_in_group("player") as PlayerController
		if player != null and player.health > 0.0 and not player.menu_open:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ── UI construction ────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = PanelContainer.new()
	_root.name = "DevPanelRoot"
	_canvas.add_child(_root)

	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_root.offset_left   = 16.0
	_root.offset_top    = 16.0
	_root.offset_right  = 330.0
	_root.offset_bottom = 530.0

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_root.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "▶ DEV PANEL  [F1]"
	title.add_theme_font_size_override("font_size", 15)
	title.modulate = Color(0.9, 0.85, 0.3)
	vbox.add_child(title)
	vbox.add_child(_sep())

	# Spawn Distance
	var dist_row := HBoxContainer.new()
	vbox.add_child(dist_row)
	var dist_lbl := Label.new()
	dist_lbl.text = "Spawn Distance:"
	dist_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dist_row.add_child(dist_lbl)
	var btn_m := Button.new()
	btn_m.text = "−"
	btn_m.pressed.connect(_on_dist_minus)
	dist_row.add_child(btn_m)
	_spawn_distance_label = Label.new()
	_spawn_distance_label.text = "%.1f m" % _spawn_distance
	_spawn_distance_label.custom_minimum_size.x = 54.0
	_spawn_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dist_row.add_child(_spawn_distance_label)
	var btn_p := Button.new()
	btn_p.text = "+"
	btn_p.pressed.connect(_on_dist_plus)
	dist_row.add_child(btn_p)
	vbox.add_child(_sep())

	# Spawn buttons
	vbox.add_child(_btn("Spawn Player  ×1",  _on_spawn_1))
	vbox.add_child(_btn("Spawn Player  ×5",  _on_spawn_5))
	vbox.add_child(_btn("Spawn Player  ×10", _on_spawn_10))
	vbox.add_child(_btn("Clear All",         _on_clear_all, Color(1.0, 0.35, 0.3)))
	vbox.add_child(_sep())

	# Toggles
	_hitbox_btn   = _toggle_btn("Show Hitboxes",   _on_toggle_hitboxes)
	_bone_btn     = _toggle_btn("Show Bones",       _on_toggle_bones)
	_debug_hit_btn = _toggle_btn("Debug Hit Info",  _on_toggle_debug_hit)
	vbox.add_child(_hitbox_btn)
	vbox.add_child(_bone_btn)
	vbox.add_child(_debug_hit_btn)
	vbox.add_child(_sep())

	# Info readout
	_info_label = Label.new()
	_info_label.text = "No hits yet."
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_font_size_override("font_size", 12)
	_info_label.modulate = Color(0.75, 1.0, 0.75)
	vbox.add_child(_info_label)

func _sep() -> HSeparator:
	return HSeparator.new()

func _btn(label: String, cb: Callable, tint: Color = Color.WHITE) -> Button:
	var b := Button.new()
	b.text = label
	b.modulate = tint
	b.pressed.connect(cb)
	return b

func _toggle_btn(label: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.toggled.connect(cb)
	return b

# ── Distance ───────────────────────────────────────────────────────────────

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
	if is_instance_valid(_dummy_container):
		_dummy_container.queue_free()
	_dummy_container = null
	_hitbox_overlays.clear()
	_bone_overlays.clear()
	_info_label.text = "Cleared."

func _ensure_container() -> void:
	if is_instance_valid(_dummy_container):
		return
	_dummy_container = Node3D.new()
	_dummy_container.name = "DevDummyContainer"
	var scene := get_tree().current_scene
	if scene != null:
		scene.add_child(_dummy_container)

func _spawn_dummies(count: int) -> void:
	_ensure_container()
	if not is_instance_valid(_dummy_container):
		_info_label.text = "Нет сцены для спавна."
		return
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player == null:
		_info_label.text = "Игрок не найден."
		return

	var fwd   := -player.global_transform.basis.z.normalized()
	var right := player.global_transform.basis.x.normalized()

	for i: int in count:
		var model := SoldierModel.instantiate()
		model.name = "DevDummy_%d" % _dummy_container.get_child_count()
		_dummy_container.add_child(model)

		var offset_x := (float(i) - float(count - 1) * 0.5) * 1.2
		model.global_position = player.global_position + fwd * _spawn_distance + right * offset_x
		model.look_at(player.global_position, Vector3.UP)

		# Skeleton + AnimationPlayer
		var skeleton: Skeleton3D = null
		for c: Node in model.find_children("*", "Skeleton3D", true, false):
			skeleton = c as Skeleton3D
			break
		var ap: AnimationPlayer = null
		for c: Node in model.find_children("*", "AnimationPlayer", true, false):
			ap = c as AnimationPlayer
			break

		# Shared physical ragdoll, health-based death and cosmetic wounds.
		if skeleton != null and ap != null:
			var ragdoll := SoldierRagdoll.new()
			ragdoll.name = "Ragdoll"
			skeleton.add_child(ragdoll)

			var rig_mod := SoldierRigModifier.new()
			rig_mod.name = "AimModifier"
			rig_mod.hide_upper_body = false
			skeleton.add_child(rig_mod)

			var anim_tree := AnimationTree.new()
			anim_tree.name = "DummyAnimTree"
			model.add_child(anim_tree)
			ragdoll._anim_tree = anim_tree

			var locomotion := SoldierLocomotion.new()
			locomotion.name = "DummyLocomotion"
			model.add_child(locomotion)
			locomotion.build(anim_tree, ap)

			var blood := SoldierBlood.new()
			model.add_child(blood)
			blood.configure(skeleton, ragdoll)
			model.set_meta("blood", blood)
			model.set_meta("ragdoll", ragdoll)
			model.set_meta("health", 100.0)

		# Hitboxes
		if skeleton != null:
			var areas := SoldierHitboxes.build(skeleton, model, 0)
			for area: Area3D in areas:
				area.set_meta("dev_dummy", true)
			if _show_hitboxes:
				_add_hitbox_overlays_for(areas)
			if _show_bones:
				_add_bone_overlays_for(skeleton)

	_info_label.text = "Spawned %d. Total: %d" % [count, _dummy_container.get_child_count()]

# ── Show Hitboxes ──────────────────────────────────────────────────────────

func _on_toggle_hitboxes(pressed: bool) -> void:
	_show_hitboxes = pressed
	_hitbox_btn.text = "Hide Hitboxes" if pressed else "Show Hitboxes"
	if not pressed:
		for o: MeshInstance3D in _hitbox_overlays:
			if is_instance_valid(o): o.queue_free()
		_hitbox_overlays.clear()
		return
	if not is_instance_valid(_dummy_container):
		return
	for dummy: Node in _dummy_container.get_children():
		var areas: Array[Area3D] = []
		for c: Node in dummy.find_children("Hit_*", "Area3D", true, false):
			areas.append(c as Area3D)
		_add_hitbox_overlays_for(areas)

func _add_hitbox_overlays_for(areas: Array[Area3D]) -> void:
	for area: Area3D in areas:
		var sn := area.get_node_or_null("Shape") as CollisionShape3D
		if sn == null:
			continue
		var overlay := MeshInstance3D.new()
		overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = _zone_color_hb(area.get_meta("hit_zone", "limbs") as String)
		overlay.material_override = mat
		if sn.shape is SphereShape3D:
			var s := sn.shape as SphereShape3D
			var m := SphereMesh.new()
			m.radius = s.radius; m.height = s.radius * 2.0
			m.radial_segments = 10; m.rings = 5
			overlay.mesh = m
		elif sn.shape is CapsuleShape3D:
			var c := sn.shape as CapsuleShape3D
			var m := CapsuleMesh.new()
			m.radius = c.radius; m.height = c.height
			m.radial_segments = 10; m.rings = 4
			overlay.mesh = m
		else:
			continue
		sn.add_child(overlay)
		_hitbox_overlays.append(overlay)

func _zone_color_hb(zone: String) -> Color:
	match zone:
		"head":  return Color(1.0, 0.2, 0.1, 0.35)
		"torso": return Color(1.0, 0.7, 0.0, 0.28)
		_:       return Color(0.2, 0.8, 1.0, 0.25)

# ── Show Bones ─────────────────────────────────────────────────────────────

func _on_toggle_bones(pressed: bool) -> void:
	_show_bones = pressed
	_bone_btn.text = "Hide Bones" if pressed else "Show Bones"
	if not pressed:
		for o: Node3D in _bone_overlays:
			if is_instance_valid(o): o.queue_free()
		_bone_overlays.clear()
		return
	if not is_instance_valid(_dummy_container):
		return
	for dummy: Node in _dummy_container.get_children():
		var sk: Skeleton3D = null
		for c: Node in dummy.find_children("*", "Skeleton3D", true, false):
			sk = c as Skeleton3D; break
		if sk != null:
			_add_bone_overlays_for(sk)

func _add_bone_overlays_for(sk: Skeleton3D) -> void:
	for bi: int in sk.get_bone_count():
		var dot := MeshInstance3D.new()
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sm := SphereMesh.new()
		sm.radius = 0.022; sm.height = 0.044
		sm.radial_segments = 6; sm.rings = 3
		dot.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.3, 1.0, 0.4)
		dot.material_override = mat
		var att := BoneAttachment3D.new()
		att.bone_idx = bi
		sk.add_child(att)
		att.add_child(dot)
		_bone_overlays.append(att)

# ── Debug Hit Info ─────────────────────────────────────────────────────────

func _on_toggle_debug_hit(pressed: bool) -> void:
	_debug_hit_btn.text = "Hide Hit Info" if pressed else "Debug Hit Info"
	if hit_feedback != null:
		hit_feedback.debug_hit_info = pressed

func report_hit(zone: String, damage: float, distance: float, killed: bool) -> void:
	var s := "[%s]  %.1f dmg  %.1f m" % [zone.to_upper(), damage, distance]
	if killed: s += "  KILLED"
	_info_label.text = s
