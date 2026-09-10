class_name PlantFileManager
extends RefCounted

const USER_PRESETS_PATH: String = "user://presets/"
static var _user_presets_2D: Dictionary[String, PlantPreset] = {}
static var _user_presets_3D: Dictionary[String, PlantPreset] = {}

static var grass: PlantPreset:
    get:
        return PlantPreset.new(
            "X", {
            "F": "FF",
            "X": "F+[[X]-X]-F[-FX]+X"
        })

static var algae: PlantPreset:
    get:
        return PlantPreset.new(
            "VZFFF",
            {
                "V": "[+++W][---W]YV",
                "W": "+X[-W]Z",
                "X": "-W[+X]Z",
                "Y": "YZ",
                "Z": "[-FFF][+FFF]F"
            },
            8
        )

static var deciduous_2D: PlantPreset:
    get:
        return PlantPreset.new(
            "X", {
            "X": "fA",
            "A": "[--l++++l][-Y]fB",
            "Y": "fB",
            "B": "[--l++++l][+X]fA"        
            },
            14,
            20.0,
            0.5,
            0.25,
            30.0,
            9.0,
            0.0,
            Color(0.12, 0.49, 0.12),
            null,
            1.0,
            Color(0.37, 0.19, 0.09),
         )

static var evergreen_2D: PlantPreset:
    get:
        return PlantPreset.new(
            "X",
            {
                "X": "[-k+++k]f[+k---k]f[A]X",
                "A": "[+++B][-j]f[---C]",
                "B": "[--k]f[+D]B",
                "C": "[++k]f[-D]C",
                "D": "E",
                "E": "[--k]fD",
            },
            11,
            15.5,
            0.4,
            2.0,
            26.0,
            4.7,
            0.1,
            Color(0.05, 0.2, 0.05),
            null,
            1.44,
        )

static var deciduous_3D: PlantPreset:
    get:
        return PlantPreset.new(
            "X",
            {
                "X": "f/A",
                "A": "[\\\\l////l][-Y]f/B",
                "Y": "f/B",
                "B": "[\\\\l////l][+X]f/A"
            },
            11,
            14.0,
            1.0,
            0.7,
            48.0,
            9.0,
            0.0,
            Color(0.0, 0.1, 0.0),
            null,
            10.0,
        )

static var evergreen_3D: PlantPreset:
    get:
        return PlantPreset.new(
            "X",
            {
                "X": "fffffA",
                "A": "kf\\[--//Y][++\\\\Y]kfA",
                "Y": "fB",
                "B": "kf[-C]\\\\\\B",
                "C": "f[-k][+k]C"
            },
            14,
            6.0,
            1.0,
            0.4,
            45.0,
            8.0,
            0.01,
            Color(0.04, 0.18, 0.04),
            null,
            10.0
        )

static var _builtin_presets_2D: Dictionary[String, PlantPreset]:
    get:
        return {
            "deciduous_2D": deciduous_2D,
            "evergreen_2D": evergreen_2D,
        }

static var _builtin_presets_3D: Dictionary[String, PlantPreset]:
    get:
        return {
            "deciduous_3D": deciduous_3D,
            "evergreen_3D": evergreen_3D,
        }

static var presets_2D: Dictionary[String, PlantPreset]:
    get:
        var merged: Dictionary = _builtin_presets_2D.duplicate()
        for key: String in _user_presets_2D:
            merged[key] = _user_presets_2D[key]
        return merged

static var presets_3D: Dictionary[String, PlantPreset]:
    get:
        var merged: Dictionary = _builtin_presets_3D.duplicate()
        for key: String in _user_presets_3D:
            merged[key] = _user_presets_3D[key]
        return merged


static func load_user_preset_group(group_name: String, output: Dictionary[String, PlantPreset]) -> void:
    output.clear()
    var file_path: String = USER_PRESETS_PATH + group_name + ".json"
    if not FileAccess.file_exists(file_path):
        return
    var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
    if file == null:
        return
    var json: JSON = JSON.new()
    @warning_ignore("return_value_discarded")
    json.parse(file.get_as_text())
    file.close()
    var data: Variant = json.data
    if data is Dictionary:
        for key: String in data:
            if data[key] is not Dictionary:
                continue
            var raw_entry: Dictionary = data[key]
            var entry: Dictionary[String, Variant] = {}
            for entry_key: String in raw_entry:
                entry[entry_key] = raw_entry[entry_key]
            output[key] = PlantPreset.from_dict(entry)

static func load_user_presets() -> void:
    load_user_preset_group("presets_2D", _user_presets_2D)
    load_user_preset_group("presets_3D", _user_presets_3D)


static func save_user_preset(preset_name: String, preset: PlantPreset, preset_group: String) -> void:
    load_user_presets()
    var data: Dictionary[String, Variant] = {}
    var input: Dictionary[String, PlantPreset] = _user_presets_2D
    if preset_group == "presets_3D":
        input = _user_presets_3D
    # Preserve existing user presets
    for key: String in input:
        data[key] = input[key].to_dict()
    # Add new preset from current settings
    var new_preset: PlantPreset = preset
    data[preset_name] = new_preset.to_dict()
    var file: FileAccess = FileAccess.open(USER_PRESETS_PATH + preset_group + ".json", FileAccess.WRITE)
    if file == null:
        var dir: DirAccess = DirAccess.open("user://")
        @warning_ignore("return_value_discarded")
        dir.make_dir_recursive(USER_PRESETS_PATH)
        file = FileAccess.open(USER_PRESETS_PATH + preset_group + ".json", FileAccess.WRITE)
        if file == null:
            push_error("Could not open file for writing: " + USER_PRESETS_PATH + preset_group + ".json")
            return
    @warning_ignore("return_value_discarded")
    file.store_string(JSON.stringify(data, "    "))
    file.close()
    load_user_presets()
    print("Preset '" + preset_name + "' saved to " + USER_PRESETS_PATH + preset_group + ".json")


static func save_preset(preset_name: String, preset: PlantPreset, preset_group: String) -> void:
    if preset_name.strip_edges().is_empty():
        push_warning("Enter a preset name before saving.")
        return

    var preset_key: String = preset_name.strip_edges().to_snake_case()

    if preset_group == "presets_2D" and presets_2D.has(preset_key):
        push_warning("Preset '" + preset_key + "' already exists.")
        return
        
    if preset_group == "presets_3D" and presets_3D.has(preset_key):
        push_warning("Preset '" + preset_key + "' already exists.")
        return

    save_user_preset(preset_key, preset, preset_group)


static func remove_user_preset(preset_name: String, preset_group: String) -> void:
    load_user_presets()
    var input: Dictionary[String, PlantPreset] = _user_presets_2D
    if preset_group == "presets_3D":
        input = _user_presets_3D
    if not input.has(preset_name):
        push_warning("Preset '" + preset_name + "' does not exist in user presets.")
        return
    input.erase(preset_name)
    var data: Dictionary[String, Variant] = {}
    for key: String in input:
        data[key] = input[key].to_dict()
    var file: FileAccess = FileAccess.open(USER_PRESETS_PATH + preset_group + ".json", FileAccess.WRITE)
    if file == null:
        push_error("Could not open file for writing: " + USER_PRESETS_PATH + preset_group + ".json")
        return
    @warning_ignore("return_value_discarded")
    file.store_string(JSON.stringify(data, "    "))
    file.close()
    load_user_presets()
    print("Preset '" + preset_name + "' removed from " + USER_PRESETS_PATH + preset_group + ".json")