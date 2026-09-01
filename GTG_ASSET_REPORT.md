# GTGAssetKit report

Date checked: 2026-07-12.

## Search result

Checked the required paths and all directories under `~/Загрузки` whose names contain `GTG`, `GTGAssetKit`, or `GTG Asset Kit`.

**Result: supplied as** `/home/tux/Загрузки/GtgAssetsKit-GD4---Photorealism-61f6b75518d4471deb18b49fe6458b49a3c50e06.zip`.

## Imported assets

Imported selected 1K assets only: Concrete019, Metal042A, PaintedPlaster001, Road007 PBR color/normal/roughness maps; metal tool chest; power box; and the local sky panorama. They were copied to `assets/gtg/` and the original ZIP was not modified.

## Existing project assets used

The existing user-provided Warehouse FBX continues to be used for the test scene. Its license is not included with the archive; see `ASSET_CREDITS.md`.

## Deferred work

Skipped the rest of the kit to avoid importing a large unused collection. No HDRI skybox is present in the supplied archive, so the project uses Godot's optimized procedural evening sky.

## License

The supplied GtgAssetsKit archive includes an MIT License, copyright (c) 2024 ghgltggamer. A copy should remain in `third_party_licenses` when distributing the project.
