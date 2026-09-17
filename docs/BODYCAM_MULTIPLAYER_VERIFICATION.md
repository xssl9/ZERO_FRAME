# Bodycam, viewmodel clearance and multi-peer replication — 2026-09-17

## Runtime audit and causes

The workspace already contained an unfinished chest attachment and a clearance
helper when this continuation started. They were inspected before further edits.

1. World rendering uses `Player/BodycamRig/WorldCamera` (`BodycamPhysics`).
   `PlayerController._configure_runtime_body()` overrides the scene's rig position;
   editing `player.tscn` alone did not change the effective camera position.
2. Originally the rig stayed at a fixed capsule-relative position, with a separate
   crouch subtraction. It did not follow the animated vest. First-person triangle
   filtering also removed Spine2-dominated upper-vest geometry.
3. The first-person weapon is genuinely isolated in an `own_world_3d` SubViewport.
   Its renderer is **the imported WeaponTuningCamera**, detached from the weapon
   hierarchy in a deferred operation using the rest transform captured in `_ready`.
   The scene's `WeaponCamera` is the hierarchy root/fallback, not the normal active
   renderer. Source helper bones such as Head_Cam do not drive this camera.
4. CPU skinning measured the old AK receiver/stock reaching about **+0.178 m** in
   camera Z in idle, and its arms about **+0.193 m**. Forward is negative Z: geometry
   was already behind the camera, before procedural recoil. Isolating the viewport
   prevents wall clipping, not clipping against its own camera.
5. ADS used one hardcoded translation for both guns. Procedural recoil moves
   ModelAndArms through the runtime root; source animation, manager sway/free aim,
   camera lag and wall pushback add independent transforms above/below that layer.
6. `NetworkGame` loads the level and builds the same NetworkRoot/Avatars/spawner
   paths before opening the transport. Host-only custom spawns use unique
   `Soldier_<peer_id>` names and set avatar ownership before entering the tree.
   There is a collection, not a single remote-player slot. The spawner supplies
   existing avatars to late connections.
7. **The loaded SteamMultiplayerPeer reports `is_server_relay_supported() == false`.**
   Clients connect only to the host, but every old synchronizer was client-owned,
   and spatial audio also broadcast directly from the client-owned avatar. Host
   reception therefore did not imply client-to-client state/event delivery.
8. The actual imported airborne clip is `jump`, not `jump_loop`. A further live
   respawn test caught AnimationTree returning to idle while the locomotion cache
   still claimed jump/run; this prevented re-entering the desired animation.

## Implementation

- Keep the existing cameras, viewport, movement and animation architecture.
  Calibrate the lens at `(0.055, 1.30, -0.10)` in the actual idle pose and store a
  Spine2-relative mount. The late render-frame pass follows the animated chest,
  including crouch/sprint/airborne transitions, without adding another crouch
  offset. Player yaw and rig pitch still control aim; bone rotation moves the
  attachment point without applying aim twice. World near plane is 2 cm.
- Retain Spine2-weighted vest triangles locally. Head/duplicate arms remain excluded;
  the original full mesh/shadow, remote models, skinning and ragdoll are retained.
  Viewmodel arms supply the local hands. Reduce the duplicate positional gait and
  limit secondary camera translation to 2.5 cm; deliberate lean remains separate.
- Move AK's authored camera out of its stock; do not change the 0.675 assembly
  normalization, gun dimensions, or either camera's 96-degree weapon FOV.
  RearSight/FrontSight markers define an explicit ADS line, rotated and translated
  towards the view axis with 0.62 m rear-sight relief. Smoothly interpolate the
  whole ADS pose; procedural recoil remains underneath it. Reload exits ADS and
  switching resets its pose. Marker placement is an initial geometry-based tune,
  not a claim of human-approved pixel-perfect iron sights.
- `ViewmodelClearance` caches conservative bone-space bounds once. After animation,
  sway, ADS and recoil, constrain the complete assembly to remain at least
  `near + 0.025 m` in front of the actual viewmodel camera. Include skinned arms,
  magazines and physical flashlight; do not hide geometry, change scale or modify
  animation keys. Apply the required correction immediately and release smoothly,
  on a separate pivot so it cannot accumulate in a recoil/ADS spring. Existing
  muzzle/flashlight bone attachments follow the same corrected geometry.
- Ballistic ray direction, spread, free-aim calculation and convergence/cover
  tracing were not changed. Existing world-marker mapping consumes the final pose.
- Avatar ownership remains its unique player ID, while **every synchronizer is
  host-owned**. The existing NetworkGame RPC stack accepts each client's pose at
  up to 30 Hz, selects its avatar from the authenticated sender ID, checks finite
  values and state ranges, and distributes it using the existing synchronizers.
  Clients cannot submit another owner's ID or health/death. Movement simulation
  remains client-side; this is not new server movement simulation or anti-cheat.
- Spatial sound follows client → host → all other peers, excluding playback to the
  original sender. Health is host-owned, included in spawn snapshots, and reliably
  replicated on change. Disconnect removes per-peer shot cooldown as well as
  health/spawn bookkeeping. No new transport, manual client mesh connections,
  Steam lobby policy change, host migration or hardcoded three-player branch.
- Locomotion uses the actual jump clip and reconciles its cached target with real
  playback after respawn, without restarting an already queued transition.

## Verification performed

Godot **4.7.2**, Linux. Real GPU runs used **Forward+ / Vulkan / RTX 4060**.

| Check | Observed result |
| --- | --- |
| Headless editor import | Exit 0 |
| `viewmodel_clearance_regression.gd`, headless and GPU | `CLEARANCE_RESULT failures=0 samples=600` |
| `gameplay_regression.gd`, headless and GPU captures | `GAMEPLAY_REGRESSION failures=0` |
| `multiplayer_regression.gd`, headless | `MULTIPLAYER_REGRESSION failures=0` |
| `body_weapon_regression.gd`, headless | `BODY_WEAPON_RESULT failures=0` |
| Existing two-process `network_roundtrip.gd` | Server PASS and client PASS: shots, damage, audio, movement while host menu is open, death/respawn |
| `run_network_regression.py`, 2 / 3 / 4 real processes | PASS on every process (2 + 3 + 4 reports) with SceneMultiplayer relay disabled |
| `all_maps_smoke_test.gd`, headless | All four maps grounded; spawn XZ error 0; authored AK camera active |
| `realism_regression.gd`, headless | `REALISM_RESULT failures=0`, all four maps |

The new weapon test combines idle/shot/reload animation samples with hip/ADS,
maximum recoil, manager rotation, turn lag and maximum wall pushback. Independent
per-vertex CPU skinning verifies that the cached bounds enclose the actual skin.
It also runs frame-driven recoil and real reload timers after ADS, checks return
transforms, active cameras, sight-axis alignment, and chest attachment across six
animation clips. The existing gameplay test verifies vest vertices in the downward
frustum and preserves explicit assertions excluding head/arm-dominated triangles.
The old lower-vest-only height cutoff was replaced because the task now requires
retaining the upper vest. Mount errors are measured in metres, not inverse-scaled
imported bone units that amplify world-coordinate floating-point rounding.

The network fixture runs the **production** NetworkGame, PlayerController,
SoldierAvatar, MultiplayerSpawner and MultiplayerSynchronizer. Only the transport
is replaced by localhost ENet, with `SceneMultiplayer.server_relay = false` so it
cannot conceal the missing Steam relay. Checks include:

- Each peer has exactly one node per owner and sees all non-local bodies.
- Distinct/changing position, yaw/pitch, velocity, crouch/aim/sprint/airborne,
  weapon/flashlight state, actual animation playback and client-to-client sound.
- Concurrent early clients and a delayed final connection.
- The delayed client receives an already-dead host from its spawn snapshot, then
  observes respawn, despite missing the earlier death RPC.
- A subsequent client death/respawn, disconnect cleanup on all remaining peers,
  and reconnect with a new peer ID and no old avatar/bookkeeping.
- Final completion barriers on all peers; process exit codes **and error logs**
  are checked (Godot's exit code alone did not reliably identify script errors).

Clearance-only microbenchmark, 500 calls per weapon in a GPU run: approximately
**23 µs AK / 22 µs pistol** per final-pose pass. This is not a whole-game frame-time
or internet networking benchmark. AK has **zero corrective displacement in idle
and settled ADS**. The conservative all-arms constraint shifts the pistol by about
**0.366 m in idle** (actual arm vertices extended about 0.25 m behind its original
camera). Stress combinations require larger corrections. This protects geometry
but its visual unobtrusiveness, especially on pistol/reload/near-wall transitions,
needs manual review; do not equate the numerical pass with artistic approval.

## Reproduction

```sh
godot --headless --path . --editor --quit
godot --headless --path . --script scripts/tools/bodycam_runtime_audit.gd
godot --headless --path . --script scripts/tools/viewmodel_clearance_regression.gd
godot --headless --path . --script scripts/tools/multiplayer_regression.gd
godot --headless --path . --script scripts/tools/gameplay_regression.gd
godot --headless --path . --script scripts/tools/body_weapon_regression.gd
python3 tools/run_network_regression.py  # defaults to 2, 3, 4 players
# Real renderer and captures:
godot --path . --rendering-method forward_plus --script scripts/tools/viewmodel_clearance_regression.gd -- --capture
godot --path . --rendering-method forward_plus --script scripts/tools/gameplay_regression.gd -- --capture
```

Generated local artifacts (ignored, not source assets):

- `build/verification/bodycam_0_{idle,ads,reload}.png` — AK.
- `build/verification/bodycam_1_{idle,ads,reload}.png` — pistol.
- `build/verification/{look_down,running_legs,crouching_legs,pistol_look_down}.png`.
- `build/verification/network_star/*_players_slot_*.log` — every network process.

Captures were actually **949 × 533**, determined by viewport readback, not a
claimed 1280 × 720 performance measurement.

## Unverified / remaining acceptance

- **Real 2/3/4-account Steam networking and lobby/invite flow:** not exercised.
  The extension capability was measured; ENet tests are not Steam/internet tests.
  All participants need the same updated version/protocol.
- **Human visual acceptance:** captured images were generated, but this agent has
  no image-display tool. Bodycam feel, arm/body seams, iron-sight placement and
  whether correction is noticeable still need in-game review.
- Exhaustive inputs/FOV/aspect ratios, arbitrary replacement assets, packet loss,
  latency/rewind, all possible joins/leaves, exported builds and whole-match
  performance are not verified. Four total peers were tested, not every possible
  lobby size. Existing Steam lobby capacity remains eight.
- Current movement has no jump input action in `project.godot`; this work preserves
  the controls and checks existing airborne/fall/landing animation paths, rather
  than silently adding a new jumping mechanic.

No commits, pushes or merge requests were created by this continuation.
