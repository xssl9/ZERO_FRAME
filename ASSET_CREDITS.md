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

### User-supplied recordings (2026-09-01)

- Source files: `~/game/sounds/ak.wav`, `pistol outside.wav`, `pistol room.wav`, `бег.wav`,
  `отдышка после бега.wav`, `Промт_Ultra-realisti_#4-1788271076027.wav`.
- Author/source/license: supplied by the user, not bundled with any licence text; the
  filenames suggest prompt-generated material. Rights must be confirmed before
  redistribution.
- Use and changes (originals untouched, every edit is in the project copy):
  - `ak.wav` → `assets/audio/weapons/ak_shot.ogg`. Trimmed to 1.35 s, +4 dB at 110 Hz,
    compressed and limited so the body of the report is not 20 dB under its own
    transient, peak -1 dBFS.
  - `pistol outside.wav` → `assets/audio/weapons/pistol_shot.ogg`, and
    `pistol room.wav` → `pistol_shot_room.ogg`. Resampled to 80 % rate, which drops the
    pitch and stretches the tail, +4 dB at 150 Hz, -4 dB at 6 kHz, peak -3 dBFS. The
    outdoor version is the one the dev grid uses.
  - `бег.wav` → `assets/audio/footsteps/run_01.ogg` … `run_06.ogg`. The recorded run
    cycle cut into its six individual strides, each normalised to -6 dBFS.
  - `отдышка после бега.wav` → `assets/audio/player/breath_01.ogg` … `breath_05.ogg`.
    The inhale and the gasp cut apart, with three of the five retimed between 90 % and
    105 % rate so a long sprint never repeats the same breath.
  - `Промт_Exactly_5_seco_#3-1788283034811.wav` → `assets/audio/weapons/ak_reload.ogg`.
    Trimmed to the 4.24 s of actual mechanism (magazine out, magazine in, charging handle),
    peak -3 dBFS. This recording is what defines how long an AK reload takes in game.
  - `Continuous_heavy_aut_#3-1788285506411.wav` → `assets/audio/environment/rain_loop.ogg`.
    Turned into a seamless 28.5 s loop by crossfading the last 1.5 s over the first 1.5 s,
    peak -6 dBFS. Measured RMS varies by 0.2 dB across the whole 30 s, so the join lands
    inside steady noise and cannot be heard.
  - `Промт_Ultra-realisti_#4-1788271076027.wav` is not imported: it is a sub-bass boom
    (six descending low hits and a three-second rumble, nothing above 4 kHz) and its
    intended role is unconfirmed.
- The earlier `ak_fire*.ogg`, `pistol_fire*.ogg` and `footsteps/concrete.ogg` samples are
  no longer referenced, apart from `concrete.ogg` as a fallback if the run cycle is
  missing.

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

## Shaders

### Rain puddles with ripples using SSR

- Author: shadecore_dev (2025), published on https://godotshaders.com
- License: CC0.
- Includes the SSR implementation by marcelb:
  https://godotshaders.com/shader/transparent-water-shader-supporting-ssr/
- Includes the rain ripple effect by Zavie: https://www.shadertoy.com/view/ldfyzl
- Supplied by the user together with its `FullscreenMesh` helper script.
- Use: `shaders/rain_puddles.gdshader` plus `scripts/environment/fullscreen_mesh.gd`, as the
  `WetGround` fullscreen pass in the dev test grid. It rebuilds world position from the
  depth buffer, so it wets and reflects whatever geometry is already there without any
  authored water surfaces.
- Changes: reformatted to the project's tab indentation, the unused
  `surface_color_ssr_mix` local was dropped, and `FullscreenMesh` now also builds its
  triangle from `_ready()` so a fresh clone works without pressing the tool button.

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

### Kloofendal 43d Clear (Pure Sky) HDRI

- Source: https://polyhaven.com/a/kloofendal_43d_clear_puresky
- License: CC0.
- File: `assets/environment/sky/kloofendal_43d_clear_puresky_2k.hdr`, fetched and verified
  through the Poly Haven API by `tools/fetch_polyhaven.py`.
- Use: the active visible panorama, radiance source and the reference the sun is aligned
  to. Peak luminance is about 110 000 with the solar disc covering roughly eight pixels at
  2K, so it is a real high-dynamic-range sky that can act as a light source.
- The `PhysicalSun` transform in `scenes/levels/dev_test_grid.tscn` was computed from this
  file by `scripts/tools/align_sun_to_sky.gd` (sun at 42.9° elevation, panorama azimuth
  216.2°), so shadows and light shafts come from the sun that is visible in the sky.
  `Environment.sky_rotation` has to stay at zero for that to hold.

### Mud Road (Pure Sky) HDRI

- Source: https://polyhaven.com/a/mud_road_puresky
- License: CC0.
- File: `assets/environment/sky/mud_road_puresky_2k.hdr`.
- Use: previous panorama, now inactive. Measured peak luminance is only 0.8 with a median
  of 0.31, i.e. the copy in this project has no high dynamic range left and contains no
  solar disc at all, which is why it lit everything flat and had no sun to align to.

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
