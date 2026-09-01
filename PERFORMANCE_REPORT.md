# Performance Report

- Renderer defaults to Compatibility for broad Linux/headless reliability; switch to Forward+ in Godot for desktop release if Vulkan is available.
- Headless smoke test: `scripts/tools/all_maps_smoke_test.gd` covers the dev test grid; re-run it after any level change (not re-run since the map rewrite).
- The dev test grid is 23 static box bodies sharing three `ShaderMaterial` instances, so its draw-call and collision cost is negligible; no enemies are spawned.
- Bullet impact nodes expire after 8 seconds.
- Architecture uses low-cost box collision, shared procedural material patterns and a compact footprint.
- Recommended target: Medium preset, 1080p, 60 FPS. Imported weapon textures are the dominant VRAM cost; downscale 8K source maps to 2K for lower-end GPUs.
