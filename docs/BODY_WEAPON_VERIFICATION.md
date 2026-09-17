# Bodycam, weapon feel, ragdoll and effects — 2026-09-17

## Implemented

1. **Weapon light:** compact rail housing on both guns; receiver-bone attachment
   follows authored reloads, recoil and sway. The world SpotLight uses the same
   camera-relative mount transform, not the eye position. Cover between camera
   and mount suppresses light; shadows block illumination through walls. Remote
   avatars derive the beam from their weapon's physical mount too.
2. **Bodycam:** chest position `(0.10, 1.42, -0.04)` metres. The existing cached
   skinned mesh now retains hips and lower spine weights as well as legs, but
   excludes head/arms/upper chest. The full model still casts shadows. Tests
   require waist vertices actually inside the frustum at -55° and -78°, not
   merely present in a mesh. No zero-scale bones or stretched triangles.
3. **Ragdoll:** 13 unit-scale rigid bodies, 12 cone/twist-limited joints, world
   collision and inherited locomotion velocity. Animation/aim stop driving the
   skeleton on death. The local camera follows the chest; respawn releases the
   physics nodes and restores camera/input/collision. Offline respawn is five
   seconds; online timing and health still belong to the host.
4. **Recoil:** 65% (AK) / 85% (pistol) of each kick directly affects aim; only the
   remainder enters free aim. Random pitch and signed yaw apply to first shots
   and ADS too. Recovery delay/rate are 0.28 s / 8°/s; mouse compensation still
   retires recovery debt. Before/after diagnostic samples: AK 25.2° → 46.8° over
   30 rounds; pistol peak 0.5° → total 31.6° over 15 fast shots. Stochastic results
   differ between runs; these are not promises of fixed trajectories.
5. **Proportions:** AK assembly uniformly normalized from 1.395 m to 0.942 m;
   hands, skeleton and authored muzzle stay together. Removed the separate
   third-person scale correction. Pistol length is 0.220 m; its previously
   misplaced muzzle marker is now at the actual tip. Both weapon cameras use
   96° vertical FOV. Geometry tests compare first/third-person dimensions.
6. **Effects:** procedural lit noise smoke/dust with soft silhouettes and scene
   depth fading; rising muzzle gas persists after release, and old clouds remain
   in world coordinates through turns/holstering. 1.8 s lifetime, 12 slots with
   0.18 s minimum interval, preventing live-puff overwrite. Dust grows/decelerates;
   fewer small faceted fragments replace blocky chips. Sparks now have a soft
   radial mask. Rain uses tapered antialiased streaks, wind direction, surface
   depth fading and shorter exposure length; roof/splash collision logic remains.

## Real verification

Godot **4.7.2**, Linux; GPU runs use **Vulkan Forward+ / NVIDIA RTX 4060**.

- `gameplay_regression.gd`: headless and GPU, `failures=0` (camera/body visibility,
  pause/settings, input gating, cover and hitscan integration).
- `body_weapon_regression.gd`: headless and GPU, `failures=0` (light attachment
  including reload, randomized real recoil, manual compensation, smoke lifetime
  and world anchoring, actual physical fall on a sloped collision floor, all
  joints connected, skinning follows physics, repeated death, camera restoration
  and actual five-second offline timer respawn).
- `weapon_geometry_measure.gd`: `WEAPON_GEOMETRY_RESULT failures=0` (real baked
  weapon bounds, muzzle-tip position, matching first/third-person dimensions).
- `multiplayer_regression.gd`: headless and GPU capture, `failures=0`.
- `realism_regression.gd`: headless and GPU, `failures=0`, **all four maps**.
- `surface_regression.gd`: headless, `failures=0`.
- `network_roundtrip.gd`: two actual localhost ENet processes; server/client
  both report PASS and exit 0, including death/respawn with menus open.

The prior leg-only upper-height assertion was intentionally replaced by both a
lower/upper torso-height bound and frustum visibility assertions for the new
requirement. The old four-puff assertion now tests the 12-slot cap **and** that
pool reuse time exceeds lifetime. Ragdoll skinning is sampled from the engine's
`modification_processed` signal: outside that signal Godot restores the original
animation poses, which is not the pose rendered by the modifier.

```sh
godot --headless --path . --editor --import
godot --headless --path . --script res://scripts/tools/gameplay_regression.gd
godot --headless --path . --script res://scripts/tools/body_weapon_regression.gd
godot --headless --path . --script res://scripts/tools/weapon_geometry_measure.gd
godot --headless --path . --script res://scripts/tools/multiplayer_regression.gd
godot --headless --path . --script res://scripts/tools/surface_regression.gd
godot --headless --path . --script res://scripts/tools/realism_regression.gd
godot --path . --rendering-method forward_plus --script res://scripts/tools/gameplay_regression.gd -- --capture
godot --path . --rendering-method forward_plus --script res://scripts/tools/body_weapon_regression.gd -- --capture
godot --path . --rendering-method forward_plus --script res://scripts/tools/realism_regression.gd
# Two separate terminals, server first:
godot --headless --path . --script res://scripts/tools/network_roundtrip.gd -- --server
godot --headless --path . --script res://scripts/tools/network_roundtrip.gd -- --client
```

## Captures and limitations

GPU captures are local ignored artifacts under `build/verification/`:
`look_down.png`, `running_legs.png`, `crouching_legs.png`, `pistol_look_down.png`,
`muzzle_smoke_0.png`, `muzzle_smoke_1.png`, `rain_streaks.png`, `impact_dust.png`,
`ragdoll_slope.png`, `soldier.png`. The impact capture stages an isolated dust cloud; the
ballistics regression separately checks real cover intersections.

**Visual quality remains UNVERIFIED by human review.** GPU shader execution and
image readback passed, but this session cannot display the binary captures.
Desktop tiling changed actual viewport sizes (1068×600 and 949×533 observed), so
these are not controlled-resolution benchmarks. Review the game in motion for
waist framing, arm/hand transitions, weapon-light placement and effect density;
no claim of matching CS2/Bodycam fidelity or measured frame-time budget is made.

**Renderer shutdown warning remains unresolved:** full GPU realism reports
**21 Texture RIDs leaked**. On `parking_garage_rework`, two lifecycle cycles with
`--no-rain` reproduce 21, including with `--no-meter`. Adding `--no-player` to
both exclusions removes the warning. This narrows reproduction to a path with
the player/viewmodel present, but does not identify exact texture ownership.
Focused body/weapon GPU tests exit without that warning. No claim of a leak-free
renderer is made; an earlier verification document already records 21 RIDs.

Ragdolls are **cosmetic local simulations**: death state is authoritative, but
final corpse poses are not replicated or deterministic across peers. Corpses do
not block players or participate in damage, disappear at respawn, and do not
include bullet-specific force impulses or anatomical hinge limits. Existing
animation/weapon assets were retained; no new hand IK or body animations were
created. Steam/Internet latency, exported builds, exhaustive traversal, visual
occlusion at every lean/crouch pose and artistic acceptance remain unverified.
