# User Asset Report

Checked on 2026-07-11:

- `~/Downloads/` — no weapon models found.
- `~/Загрузки/fps_pistol_animations.zip` — copied, original unchanged.
- `~/Загрузки/fps-ak-74m-animations.zip` — copied, original unchanged.

## Pistol

Format: glTF 2.0 (`scene.gltf` + `scene.bin`), one skin, arms and pistol meshes, skeleton.

Animation mapping:

| Gameplay action | Imported clip / fallback |
| --- | --- |
| idle, aim, sprint | `Armature|FPS_Pistol_Idle` (procedural pose for aim) |
| walk | `Armature|FPS_Pistol_Walk` |
| fire, empty fire | `Armature|FPS_Pistol_Fire` |
| reload | `Armature|FPS_Pistol_Reload_easy` |
| empty reload | `Armature|FPS_Pistol_Reload_full` |
| draw, hide, inspect | idle plus procedural tween fallback |

## AK-74M

Format: FBX (`source/FpsAnims.fbx`), imported successfully by Godot 4.7 ufbx importer; arms, rifle, skeleton and external PBR textures are included.

Animation mapping:

| Gameplay action | Imported clip / fallback |
| --- | --- |
| draw | `Rig|AK_Draw` |
| idle, aim, sprint | `Rig|AK_Idle` (procedural pose for aim) |
| walk | `Rig|AK_Walk` |
| reload | `Rig|AK_Reload` |
| empty reload | `Rig|AK_Reload_full` |
| tactical reload | `Rig|AK_Reload_var2` |
| fire, empty fire, hide, inspect | procedural recoil/tween fallback if no matching imported clip is present |

Original archives were not deleted or modified.

