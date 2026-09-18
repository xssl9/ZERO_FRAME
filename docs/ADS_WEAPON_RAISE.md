# Fixed-camera weapon raise — 2026-09-18

RMB now brings the weapon's iron sights to the existing lens, not the lens to the
weapon. The saved camera transforms/FOVs and weapon mesh transforms present at
the start of this pass were retained. Existing uncommitted bodycam/network work
was not reverted.

## Changes

- Recalibrated AK rear-notch/front-post markers against CPU-skinned idle geometry;
  the previous markers were about 18 mm from the sight geometry. Added the missing
  pistol markers (previously it used a generic positional fallback).
- Both sight markers attach to the animated receiver alongside the muzzle and
  flashlight. RearSight's Y axis defines sight-up, allowing alignment to correct
  cant as well as the front/rear line. The entire weapon/arms assembly moves;
  the source skeleton and meshes are not separately rotated or scaled.
- ADS retains the authored rear-sight depth instead of moving it to a universal
  0.62 m. In this checkout the rear depths are approximately 0.262 m for AK and
  0.202 m for pistol; assembly translation upwards is about 0.107/0.105 m.
  Both camera transforms and projection settings are unchanged by ADS.
- The local vest keeps its normal locomotion state rather than switching to an
  aiming clip that would displace the skin-mounted lens. Remote SoldierAvatar
  aiming animation/replication is unchanged. Gait, crouch, look, lean and firing
  recoil can still move the body camera normally; this is not a frozen camera.
- ADS immediately stops targeting the sprint-lowered weapon pose even while
  movement is decelerating. Recoil, lag, wall retraction and reload remain layers
  over the raised pose. Release/reload/holster restore the normal weapon pose.

## Executed verification

Godot 4.7.2 on Linux, in this session:

| Check | Observed result |
| --- | --- |
| Headless editor import before changes | Exit 0, no script/autoload errors |
| Final headless editor import, repeated | **Not clean**: two native `!is_inside_tree()` / `get_global_transform` errors despite exit 0 |
| New ADS regression before changes | 8 failures: local chest state, incorrect/missing sights, forced depth |
| `ads_regression.gd`, headless | `ADS_RESULT failures=0 samples=438` |
| `ads_regression.gd`, Forward+/Wayland, RTX 3070 | `ADS_RESULT failures=0 samples=438` |
| `authored_viewmodel_regression.gd`, headless | `AUTHORED_VIEWMODEL_RESULT failures=0 samples=72` |
| `bodycam_motion_regression.gd`, headless | `BODYCAM_MOTION_RESULT failures=0` |
| `gameplay_regression.gd`, headless | `GAMEPLAY_REGRESSION failures=0` |
| `body_weapon_regression.gd`, headless | `BODY_WEAPON_RESULT failures=0` |
| `multiplayer_regression.gd`, headless | `MULTIPLAYER_REGRESSION failures=0` |
| `viewmodel_clearance_regression.gd`, headless | `CLEARANCE_RESULT failures=0 samples=600` |

ADS tests exercise both weapons at 15/60/144 FPS, unchanged world/weapon cameras
and FOV, exact sight alignment, retained depth/scale, release, reload, holster,
recoil/retraction composition, and sprint-to-aim. They also compare markers with
independently skinned sight meshes and intersect a ray just above the front-post
tip against the skinned weapon and arms to check that they do not obscure it.

Two verification issues were investigated rather than accepted as passes:

- BoneAttachment3D consumes a new skeleton pose on a subsequent frame. The new
  test now waits for that update after seeking idle before sampling markers.
- Rebuilding the pistol arms as an ArrayMesh via the existing bake helper produced
  custom-channel format errors. The visibility test instead skins positions
  directly, including the arms, without rebuilding mesh surfaces; its final run
  has no such errors. The unrelated bake helper was not changed.

The optional **all-geometry clearance** suite initially failed its old expectation
that AK ADS needs less than 1 cm correction. That assumption depended on the old
62 cm weapon displacement. With authored depth and intentional stock/arm cropping,
this opt-in mode needs about 0.338 m. The assertion now checks the exact correction
required by animated bounds; all 600 geometry checks remain. Default gameplay
keeps this mode off, and separate ADS/framing tests require zero correction.

```sh
godot --headless --path . --script scripts/tools/ads_regression.gd
godot --path . --display-driver wayland --rendering-method forward_plus \
  --script scripts/tools/ads_regression.gd -- --capture
```

GPU captures were saved as `build/verification/ads_hip_{0,1}.png` and
`build/verification/ads_{0,1}.png`. Rendering and numerical checks succeeded;
images were **not visually reviewed** in this session (no image-display tool).
Human review of the sight picture, cropped arms and transition feel is still
required. The GPU run warns only that the Wayland window-icon protocol is absent.
Final editor import consistently reports two native `get_global_transform`
errors after restoring the editor layout, without a GDScript backtrace. This
remains unresolved: a clean editor/import check is **UNVERIFIED**, not implied
by the runtime tests. A diagnostic `--recovery-mode` attempt was unusable because
it disables the required Steam GDExtension, producing missing Steam identifiers.
Normal mode was restored and ADS rerun afterwards: exit 0, no errors, 438 samples.
No project configuration was changed to hide either diagnostic.

Exported builds and real multi-account Steam sessions were not verified here.
