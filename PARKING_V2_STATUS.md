# Parking v2 — blocked at the official Higgsfield gate

Status: **NOT COMPLETE**. No replacement parking has been authored or integrated.
Audit and checks performed on 2026-09-07 UTC. Existing uncommitted rendering,
player, weapon and shader work was retained. No commit, push or MR was made.

## Verified connections

- Existing Steam Blender: **5.2.1 LTS**, Linux, interactive GUI (`background=false`).
- Existing `~/.local/share/blender-mcp/venv`: blender-mcp **1.9.1**, MCP SDK **1.29.1**.
- Existing Blender addon: version **1.6**, protocol **5**, localhost **9876**.
- Local MCP: **PASS**, through a stdio MCP ClientSession, not merely the addon socket.
  Initialized the server, enumerated all 28 tools, created a temporary collection,
  cube and Principled material, changed location/scale, independently read the
  object with `get_object_info`, checked roughness and collection membership,
  removed object/mesh/material/collection and asserted their absence.
- No second addon installation was performed. Telemetry disabled for these MCP clients.
- Reusable check: `tools/verify_blender_mcp.py`. Requires the existing venv and
  running addon; it never installs software or saves the open `.blend`.

```sh
~/.local/share/blender-mcp/venv/bin/python tools/verify_blender_mcp.py
```

## HIGGSFIELD MCP STATUS: AWAITING OAUTH — NOT VERIFIED

Update after the user installed the plugin:

- **Higgsfield 1.5.50** is enabled in the running Blender, verified through local MCP.
- Its installed manifest explicitly supports **linux-x64** and Blender **>=5.1**.
  The earlier website guide's Windows/macOS / 4.2–5.1 restriction is superseded
  for this installed package; no Blender downgrade is needed on that basis.
- Runtime reports `environment=prod`, official connector URL, service and bridge
  subprocess both `running`. A live subprocess alone does not prove cloud connectivity.
- Local addon remains on 9876; the official plugin also listens on 9877.
- The earlier Claude Code registration was a client-selection mistake. The agent
  removed that local entry successfully; it did not provide MCP tools to Duo.
- Installed **GitLab Duo CLI 9.17.0** was inspected. Following GitLab's official
  MCP client documentation, the agent created the native user configuration at
  `/home/tuxpc/.config/gitlab/duo/mcp.json` (selected by XDG_CONFIG_HOME).
  It registers `blender-local` using the existing venv and `higgsfield-bridge`
  using the official HTTP URL. No blanket `approvedTools` or secret headers.
- JSON syntax, expected entries and the existing executable path were checked.
  **Native Duo loading is UNVERIFIED until the client is restarted.** An actual
  unauthenticated Bridge initialize still returned HTTP 401; config validity is
  not evidence of an authenticated connection.
- The local MCP cube/material/readback/cleanup test passed again with Higgsfield enabled.

Official sources:

- https://higgsfield.ai/plugins/blender
- https://higgsfield.ai/blog/higgsfield-blender-plugin
- Bridge: https://bridge.higgsfield.ai/mcp

### Required manual action

Restart **GitLab Duo**, not Claude Code, to load the native MCP config. For this
project the CLI command is `duo -C /home/tuxpc/game/ZERO_FRAME`. Ask Duo to connect
to `higgsfield-bridge` and perform a harmless Blender test, completing the OAuth
and tool-approval prompts issued by Duo. Current session tools cannot be hot-added
through the available tool interface. If GitLab blocks external MCP tools, a group
owner must enable them in GitLab Duo settings; no permission bypass was configured.

The earlier Claude OAuth terminal process is no longer present at its recorded
PID and its MCP entry has been removed. Do not use the earlier Claude login steps.
Native configuration reference:
https://docs.gitlab.com/user/gitlab_duo/model_context_protocol/mcp_clients/

Authentication, credits, generation and actual Bridge scene actions remain
**UNVERIFIED** until login and a real MCP action succeed. No credentials or
account-storage files were read. Do not paste passwords or tokens into chat.

## Backup / rollback

External directory (not imported by Godot):

`/home/tuxpc/game/ZERO_FRAME_backups/parking_original_20260907T194201Z/`

- `parking_original.tar`: 144 files, 10,711,040 bytes.
- `sha256.json`: SHA-256 for every archived file; archive contents independently
  read back and matched before any Blender test.
- Includes original parking scene, entire parking asset directory including
  `.blend`, `.blend1`, glTF/bin, AO and import settings, project.godot, scripts,
  shaders, player/weapon scenes and the four original pipeline tools.
- Shared external props/textures were not duplicated into this archive and have
  not been changed. This is a parking/source-code snapshot, not a whole-project
  backup of all third-party assets.
- Original `parking_garage.tscn`, assets and generators remain in place.
  Restore only selected archived paths if needed; do not overwrite unrelated
  ongoing user work by extracting the entire archive over the repository.

## Audit findings relevant to v2

- Preserve `build_parking_scene.py`, `blockout_boxes.py`, `prop_layout.py` and
  `setup_blender_mcp.sh`. Layout placement uses extracted glTF box components,
  oriented prop footprints, actual asset origins and floor height, with collision
  rejection; replacing this with random scatter would be a regression.
- `blockout_boxes` is restricted to axis-aligned geometry and skips rotated nodes.
  It must not be used as a general collision/navigation verifier for new meshes.
- Main deck 60 × 40 m, ceiling 3.1 m; annex width 26 m, ceiling 3.0 m.
  glTF world bounds: approximately (-30.30, -0.30, -20.30) to (56.45, 3.40, 20.30).
- Partition openings are documented as 2.6 m wide with 2.15 m lintels. The existing
  generator leaves the annex strip beyond z=16 empty because it has no doorway.
  Loading dock is 1.1 m above floor. Passage/stair traversal needs real physics QA.
- Player capsule: height 1.75 m, radius 0.35 m. Walk/sprint/crouch speeds:
  4.2 / 7.0 / 2.2 m/s. Lean clearance ray: 0.62 m. Current controller has no jump
  action/impulse or capsule-height reduction for crouch; do not claim these exist.
- Structural collision is runtime trimesh for named solid meshes. Large props use
  one measured BoxShape3D. Decorative objects intentionally have no collision.
- Current generated scene has `standing_water=0.9`, WetGround, wet surface capacity,
  neon accents, repeated covered cars and procedural marking/tag shaders.
  This is not the requested dry abandoned visual baseline.
- Keep PhotorealEnvironment, WetnessManager, RealismManager and both camera worlds.
  `standing_water=0` can express a dry interior using existing logic; PHOTOREAL
  and SCAN_FLAT must remain distinct. Existing presets control TAA, SSIL, SSR,
  SSAO, SDFGI, probes, volumetric fog and shadow quality. `allow_sdfgi` exists.
- Existing glTF import has root scale 1, generated LODs/shadow meshes, tangents,
  and light-baking UV settings. Direct `.blend` import is disabled in project.godot.
  No authored LOD0–LOD3 hierarchy or new modular GLB was produced in this session.
- Setup shell script masks addon command failures using `|| true`; do not use its
  success exit as acceptance. The separate MCP verifier checks actual operations.

## Blender baseline

Loaded the original `.blend` scene through local MCP into the existing GUI without
saving over the source or deleting the prior scene. Active imported scene:
`Scene.001`, direct collection `Collection.001`, **8 mesh objects**, **13,068 base
mesh triangles**. This excludes Godot-instanced cars/props and any modifier output.
Objects: Floor_Parking, Floor_Annex, Walls_Concrete, Walls_Plaster, Ceiling,
Services, Fixtures, Entrance_Shutter. All reported unit object scales and one UV
layer; shutter has two material slots, others one. No Higgsfield assets used.

**Source discrepancy:** Services has Blender dimensions approximately
(0.90, 20.71, 86.30) m, while exported glTF bounds stay at building height. The
source and gameplay export must be reconciled before regenerating. Full normals,
origins, UV quality and visual correctness are not yet approved.

First viewport framing attempt failed because `view_all` lacked a WINDOW region.
Corrected its context override, reused the already loaded scene (no duplicate
append), reran successfully: `PARKING_VIEWPORT_OK`, followed by independent
`get_scene_info` confirming eight objects.

## Godot baseline — actual executions

Godot **4.7.2**, Vulkan **1.4.341**, Forward+, **NVIDIA GeForce RTX 3070**.
Commands below run from the project directory (or use `--path`).

```sh
godot --headless --path . --script res://scripts/tools/realism_regression.gd
godot --path . --rendering-method forward_plus --script res://scripts/tools/realism_regression.gd
godot --path . --rendering-method forward_plus --script res://scripts/tools/realism_benchmark.gd
godot --path . --rendering-method forward_plus --script res://scripts/tools/rendering_lifecycle.gd -- --map=parking_garage --cycles=3
godot --path . --rendering-method forward_plus --script res://scripts/tools/rendering_lifecycle.gd -- --map=parking_garage --cycles=3 --no-meter
```

- Headless regression: `REALISM_RESULT failures=0 gpu=false`, all three maps.
- Windowed regression: `REALISM_RESULT failures=0 gpu=true`, all three maps.
  Covers grounding/spawn movement, inventory, both weapons firing, world flash,
  smoke pools, active weapon camera, shared exposure, weather state and presets.
  It is NOT a complete route traversal, flashlight/lean test or visual approval.
- Benchmark: `BENCH_COMPLETE`, exit 0. Actual viewport reported **1710 × 1386**
  (desktop window management), NOT a controlled 1280 × 720 comparison.
- Parking-only lifecycle: three load/free cycles with metering, three without;
  both completed with exit 0.

Parking-only rows of the existing benchmark (120 measured frames after warmup,
small yaw sweep near spawn; existing wet interior, not a dry v2):

| Preset | Median frame ms | p95 ms | Mean draw calls | Reported video memory MiB |
|---|---:|---:|---:|---:|
| PERFORMANCE | 3.59 | 3.88 | 24 | 1499 |
| HIGH | 6.66 | 7.91 | 29 | 1682 |
| ULTRA | 6.50 | 7.20 | 33 | 1712 |

These are not worst-case gameplay FPS or per-pass GPU timings. The short sample
cannot establish that ULTRA is faster than HIGH. Visible triangles/instances,
texture-only memory, average FPS, CPU/GPU split, shadow and GI costs are not
captured by this existing benchmark and remain **UNVERIFIED**.

### Baseline warnings (not hidden by passing assertions)

- GPU regression and benchmark: **7 Texture RIDs leaked** at renderer shutdown.
- Parking-only lifecycle reproduces the same seven with exposure metering enabled
  AND disabled. It is not isolated to the meter; exact ownership remains unresolved.
- Benchmark also emitted a weapon Camera3D physics-interpolation warning on pvp_linse.
- No existing runtime source was changed to silence these warnings.

Logs and MCP transcripts are beside the backup archive. GPU regression wrote its
existing `/tmp/zero_frame_<map>_weather<N>.png` captures. Their creation does not
constitute visual review; no seven-zone visual QA has been approved.

## Pending acceptance

Official Higgsfield install/auth/Bridge action, generated reusable props, Blender
architectural rebuild, dry PBR/damage/decals/lighting passes, named ENV collections,
modular GLB export, explicit LOD/collision/occlusion work, Godot v2 integration,
full traversal/flashlight/lean/bodycam visual QA, all seven viewpoints and complete
performance profiling. No claim of completion or photorealistic final quality.
