# ZERO FRAME

Playable Godot 4.7 first-person warehouse test experience.

Open `project.godot` in Godot and press F6/F5. The warehouse test range starts directly; there is no story level.

Controls: WASD, mouse, Shift sprint, C crouch, LMB fire, RMB aim, R reload, 1/2 switch weapon, F flashlight, Esc menu.

## Editing weapon transforms

Open `scenes/weapons/ak_viewmodel.tscn` or `pistol_viewmodel.tscn` and edit only the `ModelAndArms` node. Its scale is normalized to `1,1,1` for both weapons. Do not rotate the imported `Skeleton3D` separately: the apparent opposite bone gizmo direction is the glTF/FBX bone coordinate convention, while the meshes are already bound through Skin. Rotating `ModelAndArms` moves the gun, hands, skeleton, and animations together.

For a correct first-person preview, select `FPSPreviewCamera` and enable Camera Preview in the 3D editor. Do not use Left/Right Orthogonal view for placement. `FORWARD_minus_Z` marks the same forward axis used by the player camera. Long orange bones outside the arms are authored IK/control bones (`Head_Cam`, hand IK and pole targets), not detached deformation bones.

The project includes user-provided animated first-person AK and pistol assets, five armed enemies in the main level, hitscan combat, bodycam movement, a test range, graphics menu, fog and wet late-evening environment. See `ASSET_CREDITS.md` and `USER_ASSET_REPORT.md` before redistribution.
