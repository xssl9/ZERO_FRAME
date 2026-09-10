class_name PlantPreset
extends RefCounted


var axiom: String = ""
var ruleset: Dictionary[String, String] = {}
var max_steps: int = 5
var branch_length: float = 10.0
var branch_length_randomness: float = 0.0
var branch_width: float = 1.0
var angle: float = 30.0
var leaf_growth_threshold: float = 5.0
var tropism_strength: float = 0.0
var leaf_color: Color = Color(0.12, 0.49, 0.12)
var leaf_texture: Texture2D = null
var leaf_scale: float = 1.0
var branch_color: Color = Color(0.2, 0.1, 0.05)
var branch_texture: Texture2D = null
var branch_texture_scale: float = 1.0
var growth_time: float = 1.0
var growth_fps: int = 30
var wind_strength: float = 0.0



static func from_dict(data: Dictionary[String, Variant]) -> PlantPreset:
    var axiom_: String = ""
    if data.has("axiom") and data["axiom"] is String:
        axiom_ = data["axiom"]

    var ruleset_: Dictionary[String, String] = {}
    if data.has("ruleset") and data["ruleset"] is Dictionary:
        for key in data["ruleset"]:
            if data["ruleset"][key] is String:
                ruleset_[str(key)] = data["ruleset"][key]

    var max_steps_: int = 5
    if data.has("max_steps") and (data["max_steps"] is float or data["max_steps"] is int):
        max_steps_ = int(data["max_steps"])

    var branch_length_: float = 10.0
    if data.has("branch_length") and (data["branch_length"] is float or data["branch_length"] is int):
        branch_length_ = float(data["branch_length"])

    var branch_length_randomness_: float = 0.0
    if data.has("branch_length_randomness") and (data["branch_length_randomness"] is float or data["branch_length_randomness"] is int):
        branch_length_randomness_ = float(data["branch_length_randomness"])

    var branch_width_: float = 1.0
    if data.has("branch_width") and (data["branch_width"] is float or data["branch_width"] is int):
        branch_width_ = float(data["branch_width"])

    var angle_: float = 30.0
    if data.has("angle") and (data["angle"] is float or data["angle"] is int):
        angle_ = float(data["angle"])

    var leaf_growth_threshold_: float = 5.0
    if data.has("leaf_growth_threshold") and (data["leaf_growth_threshold"] is float or data["leaf_growth_threshold"] is int):
        leaf_growth_threshold_ = float(data["leaf_growth_threshold"])

    var tropism_strength_: float = 0.0
    if data.has("tropism_strength") and (data["tropism_strength"] is float or data["tropism_strength"] is int):
        tropism_strength_ = float(data["tropism_strength"])

    var leaf_color_: Color = Color(0.12, 0.49, 0.12)
    if data.has("leaf_color"):
        leaf_color_ = Color.html(data["leaf_color"])

    var leaf_texture_: Texture2D = null
    if data.has("leaf_texture"):
        var lt = data["leaf_texture"]
        if lt is String and lt != "":
            var r = ResourceLoader.load(lt)
            if r is Texture2D:
                leaf_texture_ = r

    var leaf_scale_: float = 1.0
    if data.has("leaf_scale") and (data["leaf_scale"] is float or data["leaf_scale"] is int):
        leaf_scale_ = float(data["leaf_scale"])

    var branch_color_: Color = Color(0.2, 0.1, 0.05)
    if data.has("branch_color"):
        branch_color_ = Color.html(data["branch_color"])

    var branch_texture_: Texture2D = null
    if data.has("branch_texture"):
        var bt = data["branch_texture"]
        if bt is String and bt != "":
            var rb = ResourceLoader.load(bt)
            if rb is Texture2D:
                branch_texture_ = rb

    var branch_texture_scale_: float = 1.0
    if data.has("branch_texture_scale") and (data["branch_texture_scale"] is float or data["branch_texture_scale"] is int):
        branch_texture_scale_ = float(data["branch_texture_scale"])

    var growth_time_: float = 1.0
    if data.has("growth_time") and (data["growth_time"] is float or data["growth_time"] is int):
        growth_time_ = float(data["growth_time"])

    var growth_fps_: int = 30
    if data.has("growth_fps") and (data["growth_fps"] is float or data["growth_fps"] is int):
        growth_fps_ = int(data["growth_fps"])

    var wind_strength_: float = 0.0
    if data.has("wind_strength") and (data["wind_strength"] is float or data["wind_strength"] is int):
        wind_strength_ = float(data["wind_strength"])

    return PlantPreset.new(
        axiom_,
        ruleset_,
        max_steps_,
        branch_length_,
        branch_length_randomness_,
        branch_width_,
        angle_,
        leaf_growth_threshold_,
        tropism_strength_,
        leaf_color_,
        leaf_texture_,
        leaf_scale_,
        branch_color_,
        branch_texture_,
        branch_texture_scale_,
        growth_time_,
        growth_fps_,
        wind_strength_,
    )


func _init(
    axiom_: String,
    ruleset_: Dictionary[String, String],
    max_steps_: int = 5,
    branch_length_: float = 10.0,
    branch_length_randomness_: float = 0.0,
    branch_width_: float = 1.0,
    angle_: float = 30.0,
    leaf_growth_threshold_: float = 5.0,
    tropism_strength_: float = 0.0,
    leaf_color_: Color = Color(0.12, 0.49, 0.12),
    leaf_texture_: Texture2D = null,
    leaf_scale_: float = 1.0,
    branch_color_: Color = Color(0.2, 0.1, 0.05),
    branch_texture_: Texture2D = null,
    branch_texture_scale_: float = 1.0,
    growth_time_: float = 1.0,
    growth_fps_: int = 30,
    wind_strength_: float = 0.0,
) -> void:
    axiom = axiom_
    ruleset = ruleset_
    max_steps = max_steps_
    branch_length = branch_length_
    branch_length_randomness = branch_length_randomness_
    branch_width = branch_width_
    angle = angle_
    leaf_growth_threshold = leaf_growth_threshold_
    tropism_strength = tropism_strength_
    leaf_color = leaf_color_
    leaf_texture = leaf_texture_
    leaf_scale = leaf_scale_
    branch_color = branch_color_
    branch_texture = branch_texture_
    branch_texture_scale = branch_texture_scale_
    growth_time = growth_time_
    growth_fps = growth_fps_
    wind_strength = wind_strength_


func to_dict() -> Dictionary[String, Variant]:
    return {
        "axiom": axiom,
        "ruleset": ruleset,
        "max_steps": max_steps,
        "branch_length": branch_length,
        "branch_length_randomness": branch_length_randomness,
        "branch_width": branch_width,
        "angle": angle,
        "leaf_growth_threshold": leaf_growth_threshold,
        "tropism_strength": tropism_strength,
        "leaf_color": leaf_color.to_html(),
        "leaf_texture": leaf_texture.resource_path if leaf_texture else "",
        "leaf_scale": leaf_scale,
        "branch_color": branch_color.to_html(),
        "branch_texture": branch_texture.resource_path if branch_texture else "",
        "branch_texture_scale": branch_texture_scale,
        "growth_time": growth_time,
        "growth_fps": growth_fps,
        "wind_strength": wind_strength,
    }
