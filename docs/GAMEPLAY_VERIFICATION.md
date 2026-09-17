# Player, damage and pause repair — 2026-09-17

## Changes

- `SoldierModel` creates cached private animation libraries. For all 32 moving
  clips it removes hip translation along the gait direction, preserving lateral
  sway, vertical motion, bone rotations and authored death movement. The source
  GLB is unchanged. This feeds both local legs and network avatars/hitboxes.
  The airborne loop now names the actual `jump_loop` asset.
- First-person visibility uses a separate skinned triangle mesh. The follow-up
  [body/weapon changes](BODY_WEAPON_VERIFICATION.md) extend it from legs to waist
  and lower vest, with actual downward-frustum checks. No bone is scaled towards zero. The full body is shadow-only locally; remote
  bodies remain complete. Existing weapon cameras, first-person arms and hand
  attachments are retained; no new animation/IK assets were invented.
- `ShotBallistics` traces eye-to-muzzle clearance, then from the real authored
  muzzle to the camera's aim point. Host validation also checks chest-to-eye
  cover and rejects non-finite or implausibly distant muzzle coordinates.
  Inside-solid hits block the shot without creating zero-normal decals.
- Existing head/torso/limb multipliers (2.5/1/0.7) remain server-owned. Rifle
  damage falls from 34 after 35 m to 65% at 120 m; pistol damage falls from 25
  after 15 m to 40% at 120 m. This is a gameplay approximation, not a physical
  wound simulator. Flesh hits no longer spawn concrete chips/metal impacts.
- Esc opens a CanvasLayer menu above the bodycam overlay. Offline SceneTree is
  paused; online it is never paused. Local movement/look/fire/ADS/reload/switch/
  flashlight/lean input is gated while open. The crouch stance is retained.
  A held menu click cannot fire on resume without release and a new press.
- Graphics, world FOV, sensitivity, volume and fullscreen apply in-session.
  Exit is separate and confirmed, with a host warning. Death/respawn does not
  close an online menu. Both peers must run this version: the shot RPC gained
  a muzzle-position argument.

## Actual checks in this session

Godot 4.7.2 on Linux; Forward+ / Vulkan on NVIDIA RTX 4060.

| Check | Observed result |
| --- | --- |
| Headless editor import/script compilation | Exit 0 |
| `multiplayer_regression.gd`, headless and Forward+ | `MULTIPLAYER_REGRESSION failures=0` |
| `gameplay_regression.gd`, headless and Forward+ capture | `GAMEPLAY_REGRESSION failures=0` |
| `realism_regression.gd`, headless and Forward+ | `REALISM_RESULT failures=0`, all four maps |
| `all_maps_smoke_test.gd` | All four maps grounded, spawn XZ error 0, authored AK camera active |
| `recoil_measure.gd` | Exit 0; actual 30-round AK measurement (diagnostic, not a pass/fail recoil target) |
| `network_roundtrip.gd`, two real ENet processes | Server PASS and client PASS |

The expanded animation test samples three seconds per direction, all four
moving gaits, checking hip bounds every frame across loops and transitions.
The gameplay test covers leg triangles, unmodified bone scales, isolation of the
remote mesh, looking down, both weapon viewports, actual Esc events, live
settings, input gating, trigger release, low cover, a barrel past thin cover,
near misses, self-exclusion and distance/zone damage ordering.

The two-process test checks real synchronizers, client movement while the host
menu is open, positional audio, shots from both authored muzzle positions,
headshot health, death, and five-second respawn with both menus still open.
Its old test position was inside `WallDivider`; the new cover check exposed
that invalid fixture, and the test now runs in the open at z=18.

## Reproduction

```sh
godot --headless --path . --editor --quit
godot --headless --path . --script scripts/tools/multiplayer_regression.gd
godot --headless --path . --script scripts/tools/gameplay_regression.gd
godot --headless --path . --script scripts/tools/realism_regression.gd
godot --headless --path . --script scripts/tools/all_maps_smoke_test.gd
# Start in separate terminals, server first:
godot --headless --path . --script scripts/tools/network_roundtrip.gd -- --server
godot --headless --path . --script scripts/tools/network_roundtrip.gd -- --client
# GPU execution/captures:
godot --path . --rendering-method forward_plus --script scripts/tools/gameplay_regression.gd -- --capture
godot --path . --rendering-method forward_plus --script scripts/tools/multiplayer_regression.gd -- --capture
godot --path . --rendering-method forward_plus --script scripts/tools/realism_regression.gd
```

## Screenshots and limits

Generated local artifacts (ignored `build/verification/`, not committed):

- `look_down.png` — rifle, looking down.
- `running_legs.png` — looking down during sprint.
- `crouching_legs.png` — crouched body view.
- `pistol_look_down.png` — pistol and legs.
- `pause_settings.png` — in-game settings menu.
- `soldier.png` — third-person soldier and rifle.

The gameplay captures were actually rendered at **1068 × 600**, as reported by
viewport readback (desktop tiling, not a claimed 1280 × 720 benchmark). These
are generated screenshots, **not human visual approval**: this agent session
cannot display the binary images through its tools. Open them locally to review
appearance and grip/transition quality. Full map traversal and every combination
of lean, crouch, wall proximity and animation pose are not exhaustively verified.

**Remaining warning:** the full Forward+ realism run exits successfully but
reports **21 Texture RIDs leaked** at renderer shutdown. A separate one-cycle
`rendering_lifecycle.gd -- --map=parking_garage` run reproduces **14** with the
exposure meter enabled and **14** with `--no-meter`. Disabling the meter does not
remove it. The focused gameplay and soldier capture runs do not report the
warning. Exact texture ownership is unresolved; this work does not claim a
leak-free renderer.

**Not verified:** a real two-account Steam/relay/internet session, high-latency
hit registration, artistic visual quality, exhaustive traversal or exported
builds. The transport-level regression uses localhost ENet, not Steam.
Movement and inventory authority remain as in the existing project; this is not
full anti-cheat, lag compensation/rewind, penetration, armor or bullet-flight
simulation. Settings are not persisted across application restarts.
