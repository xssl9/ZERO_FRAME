# Parking — Blender MCP material/light pass

## Scope and saved state

The user confirmed work on the currently open `parking_zoned.blend`, scene
`ZERO_FRAME_Parking_FULL_REWORK`. Changes were performed through the existing
Blender MCP stdio server and its `execute_blender_code` tool, not a direct socket.
Blender reported 5.2.1 LTS; the actual Cycles renders used the RTX 3070 via OptiX.

Work directory:
`../ZERO_FRAME_backups/parking_finish_20260908T185805Z/`

- `before.blend`: snapshot of the unsaved live scene before changes.
- `parking_photoreal.blend`: edited scene, now open in Blender.
- `baseline.json`, `finish_report.json`, `uv_precision_report.json`, `validation.json`:
  structured audit and results.
- `before/` and `after/`: matching GP_Overview, REVIEW_UpperDeck and
  REVIEW_RestoredDuct PNGs, 1280 × 720, 48 samples, denoised Cycles.
  Both render status files reached `COMPLETE` (three views each).

## Implemented

- Nine copied architectural materials assigned to 124 existing objects. Original
  materials remain available; effective object material overrides were respected.
- Connected actual Poly Haven OpenGL normal maps, decoded as Non-Color data and
  packed into the new blend. Concrete and plaster remain dielectric.
- Added metric tangent UVs while retaining authored world-space patch/dust masks.
  Patch normals and roughness now follow the same mask as the existing color blend.
- Retained the original pore bump as a subtle secondary layer instead of using it
  as the only surface relief. Original baked AO explicitly references its old UV map.
- Slight circuit-correlated energy variation on 80 existing deck lamps; neutral
  warm lower-deck / cool upper-deck light. No lights moved or added. Daylight sources,
  exposure and world settings retained.
- Reprojected 180 thin imported bevel/Boolean polygons using face-local float64
  coordinates. This avoids collapsed tangent UVs caused by float32 world coordinates.
  No mesh vertices, topology or transforms were changed.
- Cars, both storeys, ramp, fences, services, rust materials, colored pipes and
  existing decals/marks retained.

## Checks actually executed

- Local MCP read-only connection: `LOCAL_MCP_READ_ONLY_CHECK PASS`.
- Authoring: `PHOTOREAL_FINISH_APPLIED`, 124 objects / 9 materials / 80 lights.
- Independent Blender validation: `PHOTOREAL_VALIDATION_PASS`, 31,061 assertions,
  all 1,291 original objects retained. Checks include exact geometry hashes,
  transforms, visibility, collection membership, protected material assignments,
  tangent UVs, normal-map decoding, light readback and real ramp/upper-floor rays.
- Backup SHA-256 unchanged; saved scene read successfully from a byte-identical
  temporary copy (Blender cannot open its current file as a library).
- Both three-view Cycles render jobs completed and wrote PNGs.
- Existing Godot 4.7.2 headless tests rerun: realism regression (four maps),
  surface regression, fixture-details regression and all-maps smoke test: exit 0.
  The realism run still emits the pre-existing imported AK Camera3D interpolation
  warning. Those tests cover the EXISTING Godot scenes, not this new Blender source.

## Investigated failures

- First authoring attempt stopped on a lazy image-load assertion before assigning
  materials to objects. Reading image dimensions forces decoding; the same 2048px
  validation was retained. The unused incomplete material copy was removed.
- Tangent UV validation detected collapsed sliver polygons. UV generation was
  repaired; the assertion was not removed or weakened.
- Saved-file readback initially hit Blender's same-file library restriction.
  Validation now checks a byte-identical temporary copy without reloading the GUI.
- Audit clarification: empty architectural material slots were unused, and old AO
  references on newly built floors already had zero contribution. Neither was
  presented as a repaired visual defect.

## Not complete / not verified

This is a verified technical Blender material/light pass, NOT a claim of finished
photorealism. The generated images have not received visual/artistic approval.
There is no new GI bake, full gameplay route acceptance or performance benchmark.

No Godot level, menu entry or gameplay asset has been replaced. This live two-storey
source contains procedural world-space materials and overlays that require baking
or equivalent Godot shaders; ordinary GLB export can lose their appearance. Export,
collision integration and real Forward+ visual acceptance of the new source remain
outstanding. Passing the unchanged game's headless tests is not evidence of that
integration.

Reusable session scripts are `tools/blender_photoreal_*.py`, invoked with the
existing `tools/parking_blender_mcp.py` wrapper. The authoring sequence used was
checkpoint → before render (wait for COMPLETE) → finish → UV precision repair →
validation → after render (wait for COMPLETE). The scripts deliberately refuse to
stack the finish pass or overwrite an existing render directory.
