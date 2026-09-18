# Pistol uniform material

## Scope and project integration

The game separates the animated first-person weapons (their own SubViewport and
camera) from the soldier used for local body awareness and remote avatars.
`WeaponManager` loads `pistol_viewmodel.tscn`; `SoldierWeapon` uses the same scene
but removes the first-person arms when baking the remote weapon proxy.

The pistol originally had a sandy/brown arm atlas. The soldier's sleeves and
gloves use a dark neutral/blue-grey palette. This change recolors the existing
2048×2048 pistol atlas to sampled soldier sleeve/glove tones, retaining its
original seams, fabric variation, normal map and AO. Skin weights rasterized to
UV space distinguish sleeve and glove finishes; they are not modified.
Roughness is approximately 0.8 for sleeves and 0.74 for gloves, with the original
gloss-map variation retained within a cloth-appropriate range. Metallic is zero.

This is **material matching**, not a replacement garment mesh, transfer of the
soldier's texture atlas, or an exact reproduction of its cut/camouflage pattern.
The AK and the full-body soldier are unchanged.

## Files

- Game asset: `assets/weapons/pistol/pistol_uniform.gltf`.
- Editable source: `assets/weapons/pistol/uniform/pistol_uniform.blend`.
- New albedo, authoring roughness, exported packed AO/roughness and provenance:
  `assets/weapons/pistol/uniform/`.
- Integration: only the PackedScene reference in
  `scenes/weapons/pistol_viewmodel.tscn` changes. Camera, transform, sights and
  muzzle placement are untouched.
- Original `scene.gltf`, `scene.bin` and textures remain intact.

The variant shares the **original binary**. Nodes, meshes, UVs, weights, inverse
bind matrices, animations and accessor metadata are copied verbatim. The Blender
export supplies the new arm material and texture dependencies only; pistol metal
materials also remain unchanged. This avoids animation resampling, changed bone
names or lost tracks during a full Blender-to-Godot round trip.

## Reproduce

Blender 5.2.1 LTS, using the running local Blender MCP addon. The project's older
`~/.local/share/blender-mcp/venv` path was absent; the already-cached MCP package
was available through `uvx --offline`. No addon or package was installed or
updated, and telemetry was disabled.

From the project root, with no existing `PistolUniform` authoring scene:

```sh
uvx --offline --from blender-mcp python tools/pistol_blender_mcp.py tools/blender_prepare_pistol.py PISTOL_IMPORT_READY
uvx --offline --from blender-mcp python tools/pistol_blender_mcp.py tools/blender_build_pistol_uniform.py PISTOL_UNIFORM_EXPORTED
blender --background --factory-startup --python-exit-code 1 --python tools/blender_package_pistol.py
blender --background --factory-startup assets/weapons/pistol/uniform/pistol_uniform.blend --python-exit-code 1 --python tools/blender_verify_pistol_authoring.py
godot --headless --path . --editor --import
```

Preparation adds separate pistol/reference scenes without clearing existing work.
The builder can be rerun in those scenes. Packaging uses a separate factory-startup
Blender process, so the saved source opens directly into the pistol scene without
including the soldier reference or altering the live session. External image
paths in the saved file are relative; original imported images are packed.

The initial intermediate export tried unrelated soldier actions under Blender's
`ACTIONS` default. Restricting it to the active scene and `NLA_TRACKS` corrected
this; the final export contains exactly the five pistol clips. The remaining
sampler warning comes from packing AO and roughness into one image; both source
nodes have the same default sampler. No geometry compression is required.

## Verification observed in this session

Godot 4.7.2; GPU runs: Vulkan Forward+ on RTX 4060.

| Real check | Result |
| --- | --- |
| Godot editor import | Exit 0; existing pistol specular/glossiness conversion warning |
| Reopen saved `.blend`, load textures, validate five actions, source hashes and glTF invariants | `AUTHORING_VERIFY_OK` |
| `pistol_uniform_regression.gd`, headless | `failures=0`, 65 pose samples across all five clips |
| Same regression with `--capture`, GPU | `failures=0`, 65 pose samples; seven saved captures |
| `weapon_geometry_measure.gd`, headless | `failures=0` |
| `authored_viewmodel_regression.gd`, headless | `failures=0`, 72 samples |
| `ads_regression.gd`, headless and GPU | Both `failures=0`, 438 samples |
| `gameplay_regression.gd`, headless | `failures=0` |
| `multiplayer_regression.gd`, headless | `failures=0` |
| `body_weapon_regression.gd`, headless | **FAILED**, 14 `skinned bone follows rigid body` assertions |

The body/weapon failure was investigated by temporarily restoring the **original
pistol scene reference** and rerunning the same check: the same 14 ragdoll
assertions failed. The uniform reference was then restored. This pre-existing
body-ragdoll issue is not fixed here; tests/assertions were not weakened.

The dedicated regression compares actual imported mesh arrays, bind poses, all
animation key values/times and evaluated skeleton poses against the original.
It also verifies that the runtime material pass keeps the new finish instead of
substituting the AK arm roughness fallback.

```sh
godot --headless --path . --script res://scripts/tools/pistol_uniform_regression.gd
godot --path . --rendering-method forward_plus --script res://scripts/tools/pistol_uniform_regression.gd -- --capture
```

Captures (ignored local artifacts) are under `build/verification/`:
`uniform_FPS_Pistol_Idle.png`, `uniform_FPS_Pistol_Walk.png`,
`uniform_FPS_Pistol_Fire.png`, `uniform_FPS_Pistol_Reload_easy.png`,
`uniform_FPS_Pistol_Reload_full.png`, `uniform_ads.png`, `uniform_body.png`.

**Artistic acceptance remains unverified:** images were rendered and saved, but
not visually reviewed in this session. Review sleeve brightness and the wrist
transition in motion and under the intended map lighting. Internet/Steam play
and an exported release build were not tested by this task.
