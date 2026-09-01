#!/usr/bin/env python3
"""Download curated CC0 assets from PolyHaven for the abandoned-building level.

All PolyHaven assets are CC0. Each asset is validated through the JSON API
(https://api.polyhaven.com/files/<slug>) before download; missing maps/slugs are
skipped rather than aborting. Textures are pulled as 2K JPG with the ARM
(AO/Rough/Metal) pack so a single Godot material setup covers every surface.

Usage: python3 tools/fetch_polyhaven.py
"""
import json
import os
import sys
import urllib.request

API = "https://api.polyhaven.com/files/"
UA = {"User-Agent": "ZeroFrame-assetfetch/1.0 (+godot)"}
ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "polyhaven")

# slug -> map keys to fetch. "arm" packs AO(R)/Rough(G)/Metal(B).
TEXTURES = {
    "brick_wall_006": ["Diffuse", "nor_gl", "arm"],
    "concrete_wall_008": ["Diffuse", "nor_gl", "arm"],
    "plastered_wall_03": ["Diffuse", "nor_gl", "arm"],
    "worn_planks": ["Diffuse", "nor_gl", "arm"],
    "rusty_metal_04": ["Diffuse", "nor_gl", "arm"],
    "corrugated_iron_02": ["Diffuse", "nor_gl", "arm"],
    "rocky_terrain_02": ["Diffuse", "nor_gl", "arm"],
}

RES = "2k"
FMT = "jpg"


def fetch_json(slug):
    req = urllib.request.Request(API + slug, headers=UA)
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def download(url, dest):
    if os.path.exists(dest):
        print("   exists", os.path.basename(dest))
        return True
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=120) as r, open(dest, "wb") as f:
            f.write(r.read())
        print("   ok    ", os.path.basename(dest), f"({os.path.getsize(dest)//1024} KB)")
        return True
    except Exception as e:  # noqa: BLE001
        print("   FAIL  ", url, e)
        if os.path.exists(dest):
            os.remove(dest)
        return False


def main():
    ok = 0
    for slug, maps in TEXTURES.items():
        print(f"[texture] {slug}")
        try:
            info = fetch_json(slug)
        except Exception as e:  # noqa: BLE001
            print("   skip (api):", e)
            continue
        for m in maps:
            node = info.get(m, {}).get(RES, {}).get(FMT)
            if not node or "url" not in node:
                print("   skip map", m)
                continue
            suffix = {"Diffuse": "diff", "nor_gl": "nor_gl", "arm": "arm"}.get(m, m.lower())
            dest = os.path.join(ROOT, "textures", slug, f"{slug}_{suffix}_{RES}.{FMT}")
            if download(node["url"], dest):
                ok += 1
    print(f"\nDownloaded/verified {ok} files into {ROOT}")


if __name__ == "__main__":
    sys.exit(main())
