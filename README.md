# ZERO FRAME

Playable Godot 4.7 first-person shooting sandbox.

Open `project.godot` in Godot and press F5. The main menu opens; pick `DEV TEST GRID` to load the test level. There is no story level.

Controls: WASD, mouse, Shift sprint, C crouch, LMB fire, RMB aim, V fire mode (AK only), R reload, 1/2 switch weapon, F flashlight, Esc menu.

The AK-74M starts on full auto; V cycles it between `АВТО` and `ОД` (single). The pistol has no selector. Recoil moves the real aim, not just the camera: a held burst climbs and drifts right and has to be pulled back down. Compensating with the mouse cancels the automatic recovery, so the view does not spring back over your own aim.

## Test level

`scenes/levels/dev_test_grid.tscn` is the only map: a 48 × 48 m greybox room with a checkerboard grid floor (`shaders/dev_grid.gdshader`, 1 m per cell, thicker line every 8 m), a walled perimeter, tall and chest-high test walls, cover boxes, stairs onto a raised platform, a 15° ramp, three orange targets on the far wall, and a daytime HDRI sky. Everything is authored geometry and fully editable in the editor — nothing is generated at runtime.

## Editing weapon cameras and transforms

Each weapon scene (`scenes/weapons/ak_viewmodel.tscn`, `scenes/weapons/pistol_viewmodel.tscn`) owns its own first-person camera, and the game uses it verbatim. There are three nodes you are meant to touch:

- `WeaponTuningCamera` — the actual in-game viewmodel camera. It sits at the weapon-scene origin with an identity transform, so whatever you drag it to in the editor *is* the framing you get in game. Enable Camera Preview on it to frame the weapon; do not use Left/Right Orthogonal view for placement. Its `fov`, `keep_aspect`, `near` and `far` are all read from the scene at runtime and never overwritten in code. `FORWARD_minus_Z` under it marks the same forward axis the player camera uses.
- `MuzzlePoint` — the barrel tip. The muzzle flash, its light and the hitscan origin all hang off this marker, so drag it if the flame does not sit exactly on the muzzle.
- `ModelAndArms` — moves the gun, hands, skeleton and animations together. Its scale is normalized to `1,1,1` for both weapons.

Do not rotate the imported `Skeleton3D` separately: the apparent opposite bone gizmo direction is the glTF/FBX bone coordinate convention, while the meshes are already bound through Skin. Long orange bones outside the arms are authored IK/control bones (`Head_Cam`, hand IK and pole targets), not detached deformation bones.

## Weapon feel

Recoil, bolt cycling and the muzzle flash are tuned per weapon through exports on `WeaponBase` (`Recoil profile` and `Muzzle flash` categories), overridden for the pistol in `scripts/weapons/weapon_manager.gd`. The shot animation is compressed to exactly one bolt cycle per round (`speed_scale = clip_length / fire_interval`, restarted with a `seek` on every shot), so at 650 RPM the AK's bolt runs at 3.4× and stays in sync with the shots instead of finishing once per three or four rounds. An uncompensated 30-round AK magazine walks the aim about 49° up and 8° right; the pistol snaps about 1° per shot and recovers between rounds.

The project includes user-provided animated first-person AK and pistol assets, hitscan combat, bodycam movement, the dev test grid level, a graphics menu and a daytime HDRI environment. See `ASSET_CREDITS.md` and `USER_ASSET_REPORT.md` before redistribution.
