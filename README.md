# ZERO FRAME

Playable Godot 4.7 first-person shooting sandbox.

Open `project.godot` in Godot and press F5. The main menu opens; pick `DEV TEST GRID` to load the test level. There is no story level.

Controls: WASD, mouse, Shift sprint, C crouch, LMB fire, RMB aim, R reload, 1/2 switch weapon, F flashlight, Esc menu.

## Test level

`scenes/levels/dev_test_grid.tscn` is the only map: a 48 × 48 m greybox room with a checkerboard grid floor (`shaders/dev_grid.gdshader`, 1 m per cell, thicker line every 8 m), a walled perimeter, tall and chest-high test walls, cover boxes, stairs onto a raised platform, a 15° ramp, three orange targets on the far wall, and a daytime HDRI sky. Everything is authored geometry and fully editable in the editor — nothing is generated at runtime.

## Editing weapon transforms

Open `scenes/weapons/ak_viewmodel.tscn` or `pistol_viewmodel.tscn` and edit only the `ModelAndArms` node. Its scale is normalized to `1,1,1` for both weapons. Do not rotate the imported `Skeleton3D` separately: the apparent opposite bone gizmo direction is the glTF/FBX bone coordinate convention, while the meshes are already bound through Skin. Rotating `ModelAndArms` moves the gun, hands, skeleton, and animations together.

For a correct first-person preview, select `FPSPreviewCamera` and enable Camera Preview in the 3D editor. Do not use Left/Right Orthogonal view for placement. `FORWARD_minus_Z` marks the same forward axis used by the player camera. Long orange bones outside the arms are authored IK/control bones (`Head_Cam`, hand IK and pole targets), not detached deformation bones.

The project includes user-provided animated first-person AK and pistol assets, hitscan combat, bodycam movement, the dev test grid level, a graphics menu and a daytime HDRI environment. See `ASSET_CREDITS.md` and `USER_ASSET_REPORT.md` before redistribution.
