# ZERO_FRAME — recovery checkpoint

## Session recovery — 2026-09-07

The task is the user's 40-section PHOTOREALISM OVERHAUL. It is **not complete**.
Work is on `main`, based on `3ed4f1c`, with substantial pre-existing uncommitted changes. Nothing has been reset, committed or pushed in this recovery session.

### Recovered implementation (already on disk before this session)

- `scripts/rendering/`: weather profiles, wetness, exposure controller and GPU meter, weapon lighting/material repair, standard material AO repair, material/debug views.
- Edits to environment/rain/player/weapon integration, LINSE rain and dielectric material repair, bodycam/PBR/puddle shaders, texture import mipmaps.
- `scripts/tools/realism_regression.gd`, `rendering_audit.gd`, `rendering_api_probe.gd`.

### Checks actually run after recovery

- Godot **4.7.2**, real Vulkan Forward+, **RTX 4060** (not the RTX 3070 named in old documentation).
- `godot --headless --path . --script scripts/tools/realism_regression.gd`: exit 0, 3 maps, `failures=0 gpu=false`.
- `godot --path . --audio-driver Dummy --script scripts/tools/realism_regression.gd`: exit 0, 3 maps, `failures=0 gpu=true`; HDR sample counts 25–26 per map. **Shutdown warning: 7 leaked Texture RIDs; investigate.**
- `rendering_audit.gd`: grid 56 meshes / 73,151 triangles; LINSE 20 / 120,486; garage 616 / 2,025,561. Counts include both weapon models and hidden imported LODs; they are not visible draw counts. Garage has 20 reflection probes.
- Images were written by the GPU regression to `/tmp/zero_frame_*_weather*.png`. Saving images is NOT visual approval; motion/photorealism acceptance remains outstanding.

### Audit findings / next work

1. Lighting/exposure/materials: neutral AgX and shared HDR adaptation exist. Garage has no LightmapGI. SDFGI is disabled there deliberately. Several garage lights are displaced tens of metres above the building in committed scene data: investigate provenance before moving them. PhysicalSky haze does not implement actual overcast cloud cover.
2. Wetness/rain: wetness only binds dev_grid + screen puddle shaders; LINSE's diffuse-only scan has no weather material binding. No shelter mask on shared grid materials. Preserve scan lighting baked into albedo; do not pretend it can be fully relit without de-lighting/source PBR data.
3. Geometry/decals: bevels and unique baked AO already exist in garage assets. Do not regenerate the garage wholesale or restore removed floating props. No full dirt/rust/tire decal pass yet.
4. Weapons: authored cameras, SubViewport, recoil, hitscan, reload and audio timing remain. AK PBR maps are reconnected. Local light mirroring exists. Smoke remains unshaded and in isolated viewmodel coordinates; its restart gating still kills prior puffs. World reflection probes cannot automatically cross World3D boundaries.
5. Debug modes exist but need actual mode cycling tests; sampled material channels are not a raw renderer G-buffer.
6. No foliage is instantiated in the three active maps. `GrassField` and grass shader are dormant assets, not a completed vegetation pass.
7. Quality presets differ, but real motion frame-time and temporal stability validation still needed. Old README/PERFORMANCE_REPORT/PHOTOREALISM_PLAN contain obsolete claims.

## Acceptance

No percentage or production-quality claim. Full user acceptance (14 motion scenarios, visual judgement, authored asset refinement) is still pending. Update this file at each coherent checkpoint so a lost chat does not lose the work state.
