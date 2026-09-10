# Deck fixture detail pass — 2026-09-08

First additive geometry package, **not a completed photorealism overhaul**.
Loaded by `FixtureDetails` in `scenes/levels/parking_garage.tscn`.

## Delivered

- 40 housings around the **existing** deck emissive strips, placed from the actual
  gameplay glTF, not the older Blender source with mismatched Services transforms.
- Bevelled side rails and end caps, top covers, diffuser retaining straps, ceiling
  mounts. Bevel width 2.5 mm; 360 closed parts, 21,600 base triangles, five row meshes,
  ten PBR surfaces. Godot import enables generated LODs and shadow meshes.
- Dielectric powder coat (roughness 0.62) and metal clips (roughness 0.38).
  These are constant PBR finishes, not a completed photographic wear-texture pass.
- Bounds in Godot metres: approximately `(-26.937, 2.913, -18.111)` to
  `(26.737, 3.100, 18.111)`. Mounts terminate at the deck ceiling at y = 3.1 m.
- `deck_fixture_housings.blend`: editable isolated authoring scene.
- `deck_fixture_housings.glb`: runtime export with UVs/normals and PBR materials.
- `manifest.json`: input hashes, fixture positions, bounds and Blender counts.

No additional light, emission, textures, collision or runtime generation script.
The original emissive boxes remain the diffusers. Annex/corridor fixtures are not
included. The eleven displaced Room/AnnexFill lights have not been moved.

## Actual checks in this session

Godot 4.7.2, NVIDIA RTX 3070, Vulkan Forward+; local Blender 5.2.1 LTS.

| Check | Observed result |
|---|---|
| Existing local MCP create/read/material/cleanup | `LOCAL_BLENDER_MCP_RESULT PASS` |
| Blender modelling and export over MCP | `FIXTURE_MCP_RESULT PASS`, prior active scene restored |
| Godot editor import | exit 0, GLB import completed |
| Fixture integration, headless | `FIXTURE_RESULT failures=0 gpu=false`, 40 fixtures / 21,600 triangles / 10 surfaces |
| Fixture integration, GPU | `FIXTURE_RESULT failures=0 gpu=true`, four 1280 × 720 captures |
| Existing realism regression, headless and GPU | `REALISM_RESULT failures=0`, all three maps in each run |
| Existing surface regression, headless and GPU | `SURFACE_RESULT failures=0` in both runs |
| Existing parking scene generator | executed with seed 7 into `.godot/fixture_generator_test.tscn`; new resource/node present, authored scene hash unchanged |
| Python compile and diff whitespace check | exit 0 |

Fixture regression checks imported bounds/axis conversion, mount height, UVs,
normals, PBR response after existing material binding, light positions/count,
source-file hashes, absence of added collisions, player/inventory initialization,
and reuse under a rotated/translated parent.

### Short visibility A/B capture test (not gameplay FPS)

1280 × 720 actual render target, fixed close-up camera, 120 measured frames after
warmup, vsync off. Same scene with `FixtureDetails.visible` toggled. Cached reflection
probes are not rebaked between samples. Other desktop processes and a concurrent
headless regression were present; this is not an isolated performance lab.

| Preset | Detail | Median ms | p95 ms | Mean draw calls |
|---|---|---:|---:|---:|
| HIGH | hidden | 3.32 | 3.90 | 7 |
| HIGH | visible | 3.36 | 3.72 | 9 |
| ULTRA | hidden | 3.29 | 3.61 | 7 |
| ULTRA | visible | 3.32 | 3.64 | 9 |

This close-up only sees one row. These numbers do not establish full-map cost,
worst-case frame time, a speed improvement, or the future 1440p/16.7 ms target.

Captures: `/tmp/zero_frame_fixture_q{2,3}_{before,after}.png`.
Logs: `/tmp/zero_frame_fixture_{mcp,import,headless,gpu}.log`,
`/tmp/zero_frame_after_{headless,gpu}.log`,
`/tmp/zero_frame_surface_{headless,gpu}.log`.
Temporary files are not durable project deliverables; regenerate with the test.

### Remaining acceptance / warnings

- **Visual quality is UNVERIFIED.** Saving a GPU frame is not visual review.
  Inspect the bevel highlights, thin clips at distance and TAA in motion in Godot.
- **Seven Texture RIDs leak on parking-renderer shutdown.** This reproduced in a
  GPU baseline before this package and remains after it. The surface-only GPU test
  completes without that warning. Ownership/root cause is unresolved; this package
  does not claim a warning-free renderer or fix the pre-existing leak.
- No GI bake, unique wear textures, whole-level rebuild, new occlusion volumes,
  full traversal QA or visual approval has been performed in this package.

## Reproduce

From the project directory:

```sh
godot --headless --editor --path . --import
godot --headless --path . --script res://scripts/tools/fixture_details_regression.gd
godot --path . --rendering-method forward_plus --audio-driver Dummy --script res://scripts/tools/fixture_details_regression.gd
godot --headless --path . --script res://scripts/tools/realism_regression.gd
godot --path . --rendering-method forward_plus --audio-driver Dummy --script res://scripts/tools/realism_regression.gd
godot --headless --path . --script res://scripts/tools/surface_regression.gd
godot --path . --rendering-method forward_plus --audio-driver Dummy --script res://scripts/tools/surface_regression.gd
```

Authoring: `~/.local/share/blender-mcp/venv/bin/python tools/build_parking_fixture_details.py`.
Requires the existing local MCP addon on port 9876. It intentionally refuses to
replace existing outputs or an existing authoring scene. Preserve artist edits and
choose a new output/scene name for a new revision. No cloud login or install.

The legacy `build_parking_scene.py` now includes this asset, but **do not rerun it
onto the authored level merely to update fixtures**: it also regenerates unrelated
props/lights that differ from the edited scene. Its test output was isolated.

## Disable / rollback

Hide the `FixtureDetails` node for visual comparison; remove just that node and its
resource reference to remove the runtime addition. No original mesh buffer, lamp,
material binding, spawn transform or collision needs to be restored.
