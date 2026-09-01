# ZERO FRAME — Asset Credits

## Weapons

### FPS pistol animations

- Author: Cransh (`ccransh`)
- Source: https://sketchfab.com/3d-models/fps-pistol-animations-0d7a343dcb6f401197a73c91aee93f6d
- License: Creative Commons Attribution 4.0 (CC BY 4.0)
- Use: first-person pistol, arms, skeleton, textures and animation clips.
- Changes: copied from the user's archive; imported by Godot 4.7; runtime scale/placement adjusted. Godot converts its specular/glossiness materials to metallic/roughness.

### FPS AK-74m animations

- Animation author: Cransh (`ccransh`)
- Underlying AK model credited on the source page to creationwasteland; FP arms to DJMaesen (`bumstrum`).
- Source: https://sketchfab.com/3d-models/fps-ak-74m-animations-94be8385c402474cacd39bc096c6ca14
- License: Creative Commons Attribution (CC BY; source page checked 2026-07-11).
- Use: first-person AK-74M, arms, skeleton, textures and animation clips.
- Changes: copied from the user's archive; FBX imported by Godot 4.7; runtime scale/placement adjusted.

## Audio

### Firearm in a compact space 02

- Source file: user-provided `~/Загрузки/firearm-in-a-compact-space-02.mp3`.
- Author/source/license: not bundled with the downloaded file; must be confirmed before redistribution.
- Use: current indoor shot report for both weapons.
- Changes: copied unchanged; runtime pitch is `0.92` for AK-74M and `1.12` for pistol.

### Gunshot Sounds

- Author: Tabasco
- Source: https://opengameart.org/content/gunshot-sounds
- License: CC0 / public-domain dedication.
- Use: SKS recording for AK-74M report and CZ-52 recording for pistol report.
- Changes: individual shots trimmed from the recordings; high-pass filtering, compression and peak limiting; encoded to OGG Vorbis.

### Platformer Sounds: Terminal, Interaction, Door, Shots, Bang and Footsteps

- Author: yd
- Source: https://opengameart.org/content/platformer-sounds-terminal-interaction-door-shots-bang-and-footsteps
- License: CC0 / public-domain dedication.
- Use: AK/pistol shot placeholders, door, electrical/mechanical ambience, concrete/metal steps and metal impact.
- Changes: selected individual OGG files and renamed by gameplay role; no waveform modification.

## Environment models and general sounds

### Warehouse 3D FBX model

- Author: PineappleBang!
- Source: https://max-and-mimbo.itch.io/warehouse-3d-fbx-model
- Source file: user-provided `warehouse-fbx-model-free.zip`.
- License: no explicit license text was bundled in the archive or displayed on the public product page; redistribution rights must be confirmed by the asset owner before publishing the project.
- Use: the only playable test map.
- Changes: copied without changing the original archive, imported through Godot ufbx, runtime trimesh collision added.

### Kenney Starter Kit 3D Platformer

- Author: Kenney
- Source: https://github.com/KenneyNL/Starter-Kit-3D-Platformer
- Asset license: CC0 (project code is MIT; only assets are copied here).
- Use: compact brick/platform/character GLB props and fallback general movement/impact OGG files.
- Changes: selected a small subset; environment architecture itself is original procedural geometry.

Full license copies and bundled notices are in `third_party_licenses/`.

## Photoreal environment

### GtgAssetsKit GD4 — Photorealism

- Author: ghgltggamer.
- Source: user-provided `GtgAssetsKit-GD4---Photorealism-61f6b75518d4471deb18b49fe6458b49a3c50e06.zip`.
- License: MIT for the kit; bundled Poly Haven assets are CC0.
- Use: selected abandoned-building props only, copied into `assets/gtg/props/`; original archive remains unchanged.

### Poly Haven PBR materials

- Source: https://polyhaven.com/
- License: CC0.
- Use: 2K brick, concrete, plaster, worn wood, rusty/corrugated metal and rocky-ground PBR maps. `concrete_wall_008` is used on architectural concrete and interior safety floors.
- Download: each slug and file URL is validated by `tools/fetch_polyhaven.py` through the Poly Haven API.

### Poly Haven Grass Medium 01

- Source: https://polyhaven.com/a/grass_medium_01
- License: CC0.
- Use: official 1K glTF tuft and albedo, OpenGL normal, ARM and alpha maps for the abandoned-complex grass cover.
- Changes: the 40-triangle `tiny_c` tuft is batched through `MultiMesh`; it has no collision or player-driven physics, and only low-frequency shader wind remains.

### Physical atmosphere sky shader

- Type: Rayleigh, Mie and ozone atmospheric scattering sky shader.
- Source: supplied by the user for this project.
- Changes: connected to the primary directional sun and configured for a moderate 128px radiance cubemap.

### Mud Road (Pure Sky) HDRI

- Source: https://polyhaven.com/a/mud_road_puresky
- License: CC0.
- File: `assets/environment/sky/mud_road_puresky_2k.hdr`.
- Use: active visible panorama and radiance source for every playable map. This
  pure-sky version contains no foreign ground or building geometry.

### Previous overcast industrial courtyard HDR

- File: `assets/environment/sky/overcast_industrial_courtyard_2k.hdr`.
- Use: retained only as an inactive legacy option.
- Source/license metadata was not bundled with the existing project file and must be confirmed before redistribution.

### sky_09 2K

- Source file: user-provided `~/Загрузки/sky_09_2k.zip`.
- Use: retained as an optional stylized sky asset; it is not active in the photoreal preset because the PNG is LDR and painterly.

### Hexaquo realistic Godot environment demo resources

- Author/tutorial: Karl Bittner, Hexaquo.
- Source: https://git.hexaquo.at/karl/realistic-godot-environment
- Use: exact Poly Haven 4K `concrete_wall_007` PBR maps, 2K `island_tree_02` model and the supplied LUT.
- Asset licenses: Poly Haven assets are CC0; tutorial text/code attribution retained here.

### Unfinished Buildings

- Author: loafbrr_1.
- Source: https://opengameart.org/content/unfinished-buildings
- License: CC0.
- Use: `Structures_8` and `Structures_2` as the playable abandoned-building complex; imported from the supplied glTF and given Godot 4 trimesh collision.
