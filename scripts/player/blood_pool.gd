## Animates blood drops on a floor quad via shader uniforms.
## Place a BloodPool node (MeshInstance3D with blood_pool.gdshader) in the level.
## Call drop_at(uv_pos) to spawn a drop at that UV position on the mesh.
##
## pool_size MUST match TOTAL_BLOOD_DROPS in blood_pool.gdshader (default 64).

extends MeshInstance3D
class_name BloodPool

@export var pool_size: int = 64
@export var growing_time: float = 0.18
@export var drying_time: float = 5.0
@export var delay_until_drying_starts: float = 0.25

@onready var _mat: ShaderMaterial = get_active_material(0)
var _pool: Array[BloodDrop] = []


func _ready() -> void:
	var positions := PackedVector2Array()
	positions.resize(pool_size)
	_mat.set_shader_parameter("positions", positions)

	var scales := PackedFloat32Array()
	scales.resize(pool_size)
	_mat.set_shader_parameter("scales", scales)

	BloodDrop.mat = _mat
	for i in pool_size:
		_pool.append(BloodDrop.new(i))


## pos — UV coordinate on the mesh (0..1 range).
func drop_at(pos: Vector2) -> void:
	for drop in _pool:
		if drop.active:
			continue
		drop.start(pos)
		var tw: Tween = get_tree().create_tween()
		tw.tween_method(drop.animate, 0.0, growing_time, growing_time)
		tw.tween_method(drop.animate, growing_time, 0.0, drying_time).set_delay(delay_until_drying_starts)
		tw.finished.connect(drop.end)
		return


class BloodDrop:
	var active: bool = false
	var _index: int
	static var mat: ShaderMaterial

	func _init(index: int) -> void:
		_index = index

	func start(pos: Vector2) -> void:
		active = true
		mat.set_indexed("shader_parameter/positions:" + str(_index), pos)

	func animate(value: float) -> void:
		mat.set_indexed("shader_parameter/scales:" + str(_index), value)

	func end() -> void:
		active = false
		mat.set_indexed("shader_parameter/scales:" + str(_index), 0.0)
