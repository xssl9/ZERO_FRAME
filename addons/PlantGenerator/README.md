# Godot Plant Generator

A powerful L-system based procedural plant generator for Godot 4.x. Create realistic and customizable plants in both 2D and 3D

## Features
- 2D and 3D plants
- automatic in-editor regeneration
- growth and wind animation
- Material support for bark and leaves
- built-in file handling for saving and loading plant configurations

## Installation

- copy `addons/PlantGenerator` into `your_project/addons/`
- enable the plugin in `Project → Project Settings → Plugins`

## Project Structure

```
├── README.md                 ← add-on documentation
├── plant_generator.gd        ← base plugin file 
├── plant.gd                  ← plant generator component
├── 2D/plant2D.gd             ← 2D implementation
├── 3D/plant3D.gd             ← 3D implementation
└── Calculation/calculator.gd ← L-system calculation engine
```

## Usage
- Add a `Plant2D` or `Plant3D` node to your scene:
- Edit parameters in Inspector or via code

## Parameters
- see in-editor documentation

## L-System Syntax

### Commands

| Symbol | Meaning |
|--------|---------|
| `F` | Draw branch segment and move forward |
| `f` | Draw branch segment which grows over time and move forward  |
| `+` | Turn right (2D) / Yaw right (3D) |
| `-` | Turn left (2D) / Yaw left (3D) |
| `[` | Push state (save position/rotation) |
| `]` | Pop state (restore position/rotation) |
| `L` | Draw leaf |
| `l` | Draw leaf which grows over time |
| `^` | Pitch up (3D only) |
| `&` | Pitch down (3D only) |
| `/` | Roll clockwise (3D only) |
| `\` | Roll anti-clockwise (3D only) |

### Built-in Rules

The following single-character rules are automatically applied:

| Symbol | Expands To |
|--------|-----------|
| `c` | `d` |
| `d` | `e` |
| `e` | `f` |
| `f` | `F` |
| `i` | `j` |
| `j` | `k` |
| `k` | `l` |
| `l` | `L` |

## Presets

Plants can be saved as presets for easy reuse:

- **Built-in Presets**: Pre-configured plant examples included with the addon
- **User Presets**: Custom plants saved by the user
- **Preset Management**: Load, save, and remove presets through the inspector


## Performance Considerations

- Use `max_steps` to limit generation complexity
- Higher `steps` values increase generation time exponentially

## Author
Vilém Janota

## Version
1.0.0

## License

See LICENSE file for details.

## Resources

- [L-System Wikipedia](https://en.wikipedia.org/wiki/L-system)
- [The Algorithmic Beauty of Plants](http://algorithmicbotany.org/)
- [Godot Documentation](https://docs.godotengine.org/)
