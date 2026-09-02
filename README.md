# ZERO FRAME

Playable Godot 4.7 first-person shooting sandbox.

Open `project.godot` in Godot and press F5. The main menu opens; pick `DEV TEST GRID` to load the test level. There is no story level.

Controls: WASD, mouse, Shift sprint, C crouch, LMB fire, RMB aim, V fire mode (AK only), R reload, 1/2 switch weapon, F flashlight, Esc menu.

The menu also carries the graphics preset (`AUTO`/`PERFORMANCE`/`HIGH`/`ULTRA`) and the weather (`ЯСНО`/`ДОЖДЬ`).

The AK-74M starts on full auto; V cycles it between `АВТО` and `ОД` (single). The pistol has no selector. Recoil moves the real aim, not just the camera: a held burst climbs and drifts right and has to be pulled back down. Compensating with the mouse cancels the automatic recovery, so the view does not spring back over your own aim.

## Maps

`DEV TEST GRID` is the greybox proving ground. `PVP — LINSE` is a RealityCapture photogrammetry scan of an abandoned cultural centre (`assets/environment/linse`), meant for fast PvP once there is any networking; for now it is a plain map with no weather. Its collision is a 48k-triangle trimesh built at load by `scripts/environment/scan_collision_body.gd`, and the same scene is what the main menu renders behind its buttons.

The scan needed two corrections. Its floor was tilted 2.22° out of level, measured by area-weighted plane fit over the up-facing faces and rotated flat in the node transform. Its units are not metres — floor-to-floor in the raw file is 43 units and one storey's rubble varies by 14 units — so the node is scaled by 0.075, which puts floor-to-floor at 3.2 m and the whole shell at 34 × 7 m with a 8.3 m height. Its lighting uses `PhotorealEnvironment.lighting_model = SCAN_FLAT`: a photogrammetry albedo already contains the real sunlight, its own shadows and its own ambient occlusion, so the flat model lights it with uniform white ambient, drops the sun to a shadowless 0.45 fill and turns SSAO, SSIL, SDFGI and fog off. Stacking those on top is what turned everything the original camera did not see into black.

## Test level

`scenes/levels/dev_test_grid.tscn` is a 48 × 48 m greybox room with a Poly Haven worn tile floor and concrete block walls (`shaders/dev_grid.gdshader`, world-space triplanar so a 48 m box tiles without UVs; `texture_blend = 0` falls back to the procedural checkerboard it started as), a walled perimeter, tall and chest-high test walls, cover boxes, stairs onto a raised platform, a 15° ramp, three orange targets on the far wall, a nine-beam overhead pergola that cuts the sunlight into shafts, and a daytime HDRI sky. Everything is authored geometry and fully editable in the editor — nothing is generated at runtime.

## Light and air

Sunlight is visible in the air, not just on surfaces: the environment runs volumetric fog with forward-biased scattering, the sun feeds it through `light_volumetric_fog_energy`, and the pergola beams are what break it into shafts. The flashlight (`F`) has a visible cone and every muzzle flash pulses the fog around the shooter. Density is one export — `shaft_density` on `PhotorealEnvironment` — and `0.0` gives clear air.

The sky is `kloofendal_43d_clear_puresky_2k.hdr`, a real HDRI whose solar disc peaks around 110 000 in luminance, and `PhysicalSun` is aligned to that disc (42.9° elevation) by `scripts/tools/align_sun_to_sky.gd`, so the shadows, the shafts and the sun you can see in the background all agree. `Environment.sky_rotation` must stay at zero or that alignment breaks. The sky it replaced measured a peak luminance of 0.8 — no dynamic range and no sun in it at all, which is why the level used to look flat and cast no visible shadows.

Godot 4.7 has no ray tracing, hardware or otherwise, and none of this is a path tracer. What `HIGH` runs is SDFGI (which does cone-trace rays against a signed distance field of the scene every frame), SSIL, screen-space reflections, SSAO, volumetric fog with GI injected into it, and additive glow above the tonemapper's white point. `ULTRA` raises SDFGI to six cascades, SSR to 64 steps and switches on TAA, which is what settles the temporal noise all of those produce. Presets are cycled in the main menu.

## Weather

The main menu has a `ПОГОДА` button that toggles between `ЯСНО` and `ДОЖДЬ`, and the level reads that choice when it loads. Clear is brighter and warmer with thin air and a harder sun (energy 3.1); rain is dimmer and cooler with roughly twice the fog and a sun that has been softened to 2.4 but pushes three times as much light into the air, which is where the shafts live. The two grades are absolute values in `PhotorealEnvironment`, not offsets, so switching back and forth cannot drift. Like the graphics preset, the choice lives in `ProjectSettings` for the session and resets on restart.

Rain also has a voice: a 28.5 s loop (`assets/audio/environment/rain_loop.ogg`) on a non-positional player at about -12 dB, because rain surrounds the listener rather than coming from a point in the level. It follows `RainSystem.intensity`, so lighter rain is quieter as well as thinner, and clear weather never starts it — the start is deferred until after the weather pass has run.

In the rain, `scripts/environment/rain_system.gd` keeps a 30 × 14 × 30 m drop volume centred on the player, so a few thousand particles cover the whole visible downpour instead of trying to fill the arena; the drops live in world space, so nothing slides sideways when you move, and there is a second flat emitter at foot level for splashes. `intensity` scales it down to nothing at `0.0`, which is exactly what clear weather sets.

The ground gets wet two ways. `shaders/dev_grid.gdshader` takes a `wetness` uniform that darkens the concrete and cuts its roughness by more than half, so the whole greybox turns glossy in one value. On top of that, `shaders/rain_puddles.gdshader` on the `WetGround` node (CC0 by shadecore_dev, see `ASSET_CREDITS.md`) is a single fullscreen pass: it rebuilds world position from the depth buffer, decides where standing water would pool from two noise octaves and the surface normal, animates rain rings on it and ray-marches the screen into the water for reflections. No authored water geometry anywhere, and it wets whatever the level happens to be. Clear weather hides that node, which is also the biggest thing the clear preset saves.

## Hands and weapon

The viewmodel renders in its own `SubViewport` with `own_world_3d`, so nothing about the level reaches it by itself. `PlayerController` copies it across: the weapon environment takes the level's ambient level and colour and its exposure, the weapon key light is re-aimed every frame along the real sun direction expressed in camera space (so turning around moves the highlight on the receiver), and in the rain a thin curtain of drops falls past the hands inside the weapon viewport. Without that the gun was lit by a fixed studio light in perpetual clear weather.

## Sound

The AK, pistol, run cycle and out-of-breath recordings are the user-supplied files from `game/sounds`, re-mastered into the project (see `ASSET_CREDITS.md`). Footsteps pick one of six separate recorded strides per step and never repeat the same one twice; walking pitches them down and softens them, crouching almost mutes them. After ten unbroken seconds of sprinting the player starts breathing hard *while still running*, one of five separate breaths at a time, mixed at about -23 dB so it sits under everything else. Shots and bullet impacts go through a `Weapons` bus with a hard limiter at -1 dBFS (`default_bus_layout.tres`, regenerated by `scripts/tools/generate_bus_layout.gd`), so a full magazine at 650 RPM compresses instead of clipping.

## Editing weapon cameras and transforms

Each weapon scene (`scenes/weapons/ak_viewmodel.tscn`, `scenes/weapons/pistol_viewmodel.tscn`) owns its own first-person camera, and the game uses it verbatim. There are three nodes you are meant to touch:

- `WeaponTuningCamera` — the actual in-game viewmodel camera. It sits at the weapon-scene origin with an identity transform, so whatever you drag it to in the editor *is* the framing you get in game. Enable Camera Preview on it to frame the weapon; do not use Left/Right Orthogonal view for placement. Its `fov`, `keep_aspect`, `near` and `far` are all read from the scene at runtime and never overwritten in code. `FORWARD_minus_Z` under it marks the same forward axis the player camera uses.
- `MuzzlePoint` — the barrel tip. The muzzle flash, its light and the hitscan origin all hang off this marker, so drag it if the flame does not sit exactly on the muzzle.
- `ModelAndArms` — moves the gun, hands, skeleton and animations together. Its scale is normalized to `1,1,1` for both weapons.

Do not rotate the imported `Skeleton3D` separately: the apparent opposite bone gizmo direction is the glTF/FBX bone coordinate convention, while the meshes are already bound through Skin. Long orange bones outside the arms are authored IK/control bones (`Head_Cam`, hand IK and pole targets), not detached deformation bones.

## Weapon feel

Recoil, bolt cycling and the muzzle flash are tuned per weapon through exports on `WeaponBase` (`Recoil profile`, `Muzzle flash` and `Audio` categories), overridden for the pistol in `scripts/weapons/weapon_manager.gd`. The shot animation is compressed to exactly one bolt cycle per round (`speed_scale = clip_length / fire_interval`, restarted with a `seek` on every shot), so at 650 RPM the AK's bolt runs at 3.4× and stays in sync with the shots instead of finishing once per three or four rounds. An uncompensated 30-round AK magazine walks the aim about 49° up and 8° right; the pistol snaps about 1° per shot and recovers between rounds.

The flash is procedural: three flame quads crossed at 60° around the barrel plus a face-on ragged star (the crossed quads are edge-on from the shooter's own view, which is why the star exists), a white-hot core, a dim halo, sparks and a gated powder-smoke puff. `shaders/muzzle_flash.gdshader` builds the tongues from fbm noise with a per-shot seed and a blackbody gradient, and every round jitters its size, brightness and rotation. Because the viewmodel lives in its own `World3D`, the flash also places a second `OmniLight3D` out in the level — without it the level would never light up when you fire. `scripts/tools/muzzle_flash_capture.gd` stages one round and saves the frame so the flash can be reviewed without playing (run it *without* `--headless`; it needs a GPU).

The project includes user-provided animated first-person AK and pistol assets, hitscan combat, bodycam movement, the dev test grid level, a graphics menu and a daytime HDRI environment. See `ASSET_CREDITS.md` and `USER_ASSET_REPORT.md` before redistribution.
