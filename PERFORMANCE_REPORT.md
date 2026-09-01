# Performance Report

- Renderer defaults to Compatibility for broad Linux/headless reliability; switch to Forward+ in Godot for desktop release if Vulkan is available.
- Headless smoke test: `scripts/tools/all_maps_smoke_test.gd` covers the dev test grid; re-run it after any level change. Last run on Godot 4.7.2 passed with no parser or runtime errors (player on floor, spawn error 0.0, `AK_74M_WeaponCamera` current).
- The dev test grid is 23 static box bodies sharing three `ShaderMaterial` instances, so its draw-call and collision cost is negligible; no enemies are spawned.
- Audio: each weapon holds 8 non-positional `AudioStreamPlayer` shot voices and the player holds 4 footstep voices plus one landing voice. Positional players cannot be used for the viewmodel — the weapon `SubViewport` uses `own_world_3d` and has no 3D audio listener, so an `AudioStreamPlayer3D` inside it is silent.
- Bullet impact nodes expire after 45 seconds and each carries a decal (or quad on Compatibility), two one-shot `GPUParticles3D` and one `AudioStreamPlayer3D`; cap sustained fire in stress tests accordingly.
- Muzzle flash is procedural and allocated once per weapon at load: three unshaded `QuadMesh` instances (two crossed petals plus a bloom disc) sharing one `ShaderMaterial` on `shaders/muzzle_flash.gdshader`, plus one shadowless `OmniLight3D`. Each shot only flips visibility, writes two shader uniforms and sets a light energy — no allocation, no tweens, no particles. The flash lives 45 ms, so at 650 RPM (92 ms per round) at most one is on screen at a time. The shader uses `blend_premul_alpha`, `depth_draw_never` and `unshaded`, so it is fill-rate only, over a few hundred pixels.
- Recoil and viewmodel kick are two scalar springs integrated in `WeaponBase._process` plus three in `BodycamPhysics`, sub-stepped at 120 Hz; cost is constant and independent of fire rate.
- Weapon animation: one `AnimationPlayer` per weapon with `speed_scale` compression instead of blend trees or additive layers, so a full-auto burst costs the same as idle.
- Architecture uses low-cost box collision, shared procedural material patterns and a compact footprint.
- Recommended target: Medium preset, 1080p, 60 FPS. Imported weapon textures are the dominant VRAM cost; downscale 8K source maps to 2K for lower-end GPUs.
