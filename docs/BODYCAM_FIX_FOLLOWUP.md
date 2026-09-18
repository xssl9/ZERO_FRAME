# Bodycam/viewmodel repair follow-up — 2026-09-17

## Latest clarification: retain the weapon scenes' camera framing

The user clarified that the unwanted view was the **cut ends of the isolated FPS
arms**, and that framing must match `WeaponTuningCamera` in the weapon scenes.
Moving the world/body camera was not the fix for that complaint.

The whole-assembly clearance pass forced *every* arm/stock vertex in front of the
weapon camera. This defeated intentional cropping and even counteracted authored
camera movement. The user's newer AK camera Z edit (`-0.4200892`) was preserved;
neither weapon scene was edited by this fix. With that saved camera, the old
constraint added about **0.749 m in AK idle / 0.366 m in pistol idle**.

`WeaponBase.preserve_authored_framing` now defaults to `true`. The final-pose pass
keeps its correction pivot neutral and clears any old displacement immediately.
Saved camera transform, FOV, aspect mode and clip planes remain authoritative.
ADS, recoil, sway, animations, wall retraction and world-marker mapping remain;
there is no new world-camera movement in this pass. Intentional camera clipping
is retained; this no longer promises that all model vertices remain in front of
the lens. The old all-geometry constraint is available only by explicit opt-in.

`authored_viewmodel_regression.gd` independently loads each saved weapon scene
and compares camera-to-root and camera-to-mesh transforms across **72 animation
samples**, plus projection settings under world-FOV changes, ADS/recoil/retraction
and returning from the optional constraint. Before the fix it reported 516 failed
assertions; afterwards **0 failures**, both headless and real Forward+/Wayland GPU.
Both default correction offsets are zero. New GPU captures are
`build/verification/authored_viewmodel_{0,1}.png`; generated, not visually reviewed.

Existing clearance and recoil/clearance suites now explicitly opt into the old
constraint; their numerical assertions were retained and pass (600 clearance
samples). They are not evidence that default gameplay uses that constraint.
Gameplay and body/weapon regressions also passed. The flashlight fixture's old
fixed `distance > 0.25 m` assumption was incompatible with the user's AK camera
(the rail measured about 0.2246 m away). It now verifies the exact nonzero authored
rail offset in world-camera space, with 0.01 mm tolerance, rather than moving the
camera or the light to satisfy an arbitrary minimum distance.

```sh
godot --headless --path . --script scripts/tools/authored_viewmodel_regression.gd
godot --path . --display-driver wayland --rendering-method forward_plus --script scripts/tools/authored_viewmodel_regression.gd -- --capture
```

## Second pass: actual chest placement after user feedback

The first pass did **not** validate visual placement. The user reported
that the camera did not appear chest-mounted. A subsequent surface probe found the
idle lens about 11.1 cm ahead of the vest along player Z. This did not confirm the
literal description "behind the player", and screenshots have not been visually
reviewed. The old bone-offset equality test could not establish skin attachment.

`ChestCameraMount` now selects a front-facing vest triangle at the requested idle
X/Y, stores its barycentric position and the three vertices' bind influences,
then skins only those vertices each frame. The lens is 6 cm outside that surface
along its deformed normal (room for the existing 2.5 cm compliance and 2 cm near
plane). It follows blended vest skinning rather than a capsule-derived offset on
Spine2. Mouse yaw/pitch, both weapon cameras, their FOV and weapon transforms are
unchanged. The local body uses the same non-interpolated render-frame transform as
the world camera; remote bodies are untouched.

New `bodycam_mount_probe.gd` intersects independent CPU-baked torso triangles:
144 failures with the old attachment, then **0 failures / 144 samples** after the
change. It covers 12 clips; final headless/GPU checks also vary player position,
yaw and pitch, check the active world camera and retained input orientation.
This is geometric verification, not visual acceptance of the first-person image.

The old single-bone equality assertion in the clearance test was replaced with a
surface-attachment assertion; independent triangle checks are in the new probe.
Gameplay (headless/GPU), clearance (headless), camera-motion (headless), and
body/weapon (headless) regressions were rerun successfully after this second pass.

A 15-FPS run reproduced a timing flaw in the death-camera test: it compared the
last render-frame camera against a newer physics pose, producing 0.131 m error.
The test now monitors **every rendered frame after PlayerController**, tightens
the positional tolerance from 10 cm to 1 mm and requires at least one sample.
It passes at normal speed and fixed 15 FPS. A low-FPS run also reported 14 ObjectDB
instances / 6 resources still in use on shutdown; a verbose repeat did not
reproduce it. Shutdown cleanup under that stress remains unresolved, not claimed
fixed by the camera work.

```sh
godot --headless --path . --script scripts/tools/bodycam_mount_probe.gd
godot --path . --display-driver wayland --rendering-method forward_plus --script scripts/tools/bodycam_mount_probe.gd -- --capture
```

Six new diagnostic images at 1709×961 show idle/crouch/sprint from side and front:
`build/verification/chest_mount_<clip>_<side|front>.png`. A green box marks the
actual WorldCamera and a yellow segment its optical axis. Gameplay captures in
that directory were refreshed too. Images were generated with the real GPU but
still need human review; they are not claimed to have been inspected by the agent.

## First pass: starting state and changes

The checked-out `scripts/network/network_game.gd` contained AK scene text, not
GDScript. A real headless editor run reported `Unexpected "[" in class body` and
failed to create the autoload, despite returning exit code 0.

- Restored match orchestration from the preceding Git revision, then restored
  the contracts used by the current `SoldierAvatar`: client pose/sound submission,
  host distribution without client relay, synchronized health for late joiners,
  and disconnected-owner shot-cooldown cleanup. No transport change.
- Bodycam recoil now banks only pitch actually applied after the look-limit clamp.
  Previously firing upwards against the limit created nonexistent recoil debt;
  automatic recovery pulled the view below its original aim, even after manual
  compensation.
- Weapon-manager sway/drag and weapon recoil now integrate in steps of at most
  1/120 s, consuming up to 250 ms per render frame. The old manager took one
  unstable Euler step; weapon recoil discarded all time beyond 1/30 s. Existing
  amplitudes, stiffness/damping, ADS transforms and clearance constraints remain.
- Added `scripts/tools/bodycam_motion_regression.gd`. Before the motion fixes it
  reported **6 failures**. It checks pitch-limit recovery/compensation and compares
  one 250 ms frame against thirty 1/120 s frames, including both weapons with ADS
  and final camera clearance. Afterwards it reports **0 failures**.

Authored weapon camera/mesh transforms and FOV were **not** changed. In this
checkout the AK camera is **58.114532 degrees**, not the 96 degrees described in
the earlier report/README. Measured idle clearance correction is approximately
**0.208 m AK / 0.366 m pistol**; settled AK ADS correction is effectively zero.
The earlier report's zero AK idle correction no longer describes this checkout.
Conservative stress corrections reach about **0.953 m / 1.220 m**. Numerical
clearance is not approval of the resulting framing or arm/body seams.

## Executed checks

Godot 4.7.2, Linux. Every check below was executed in this follow-up:

| Check | Result |
| --- | --- |
| Headless editor import after repair | Exit 0, no script/autoload errors |
| `bodycam_motion_regression.gd`, headless and GPU | `BODYCAM_MOTION_RESULT failures=0` |
| `viewmodel_clearance_regression.gd`, headless and GPU | `CLEARANCE_RESULT failures=0 samples=600` |
| `gameplay_regression.gd`, headless and GPU | `GAMEPLAY_REGRESSION failures=0` |
| `body_weapon_regression.gd`, headless | `BODY_WEAPON_RESULT failures=0` |
| `multiplayer_regression.gd`, headless | `MULTIPLAYER_REGRESSION failures=0` |
| `python3 tools/run_network_regression.py` | All 9 processes PASS across 2/3/4-player fixtures, relay disabled |
| `all_maps_smoke_test.gd`, headless | All four maps grounded, spawn XZ error 0, authored weapon camera active |

The first GPU attempt on the default display driver repeatedly failed Vulkan
swapchain creation (`VkResult -3`). It is **not a successful rendering check**,
even though its numerical assertions and exit code were zero. Repeating with
`--display-driver wayland --rendering-method forward_plus` succeeded on Vulkan /
RTX 3070. The remaining Wayland warning concerns unavailable window-icon protocol.
No project renderer settings were changed to work around the display issue.

```sh
godot --headless --path . --script scripts/tools/bodycam_motion_regression.gd
godot --path . --display-driver wayland --rendering-method forward_plus --script scripts/tools/viewmodel_clearance_regression.gd -- --capture
godot --path . --display-driver wayland --rendering-method forward_plus --script scripts/tools/gameplay_regression.gd -- --capture
```

GPU captures are in ignored `build/verification/`: `bodycam_*` at 2467×1388 and
look-down/running/crouching/pistol/pause captures at 1709×961. They were saved but
not visually reviewed: this session has no image-display tool. Human review of
bodycam feel, sights, arm/body seams and corrective displacement remains pending.
Real Steam-account networking and exported builds were not tested. Local ENet
fixtures are not a substitute for either.
