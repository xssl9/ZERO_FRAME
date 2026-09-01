# Performance Report

- Renderer defaults to Compatibility for broad Linux/headless reliability; switch to Forward+ in Godot for desktop release if Vulkan is available.
- Test range and main menu complete headless smoke tests without runtime or GDScript errors.
- Main scene uses only five active enemies. Their expensive visibility decisions run at staggered 0.16–0.30 second intervals.
- Bullet impact nodes expire after 8 seconds. Enemy physics disables 12 seconds after death.
- Architecture uses low-cost box collision, shared procedural material patterns and a compact footprint.
- Recommended target: Medium preset, 1080p, 60 FPS. Imported weapon textures are the dominant VRAM cost; downscale 8K source maps to 2K for lower-end GPUs.

