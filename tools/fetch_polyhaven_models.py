#!/usr/bin/env python3
"""Downloads Poly Haven models (glTF plus their textures) into assets/props/<slug>_<res>/.

The models endpoint returns a file node per resolution whose "include" map lists every
dependent file - the .bin and every texture - with its own URL and the relative path the
glTF expects. Both have to be written or Godot imports a mesh with missing images.

Usage: python3 tools/fetch_polyhaven_models.py cardboard_box_01 barrel_03 ...
"""
import json
import os
import sys
import urllib.request

API = "https://api.polyhaven.com/files/"
UA = {"User-Agent": "ZeroFrame-assetfetch/1.0 (+godot)"}
ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "props")
RES = "1k"


def fetch_json(slug):
    request = urllib.request.Request(API + slug, headers=UA)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def download(url, destination):
    if os.path.exists(destination):
        return True
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    try:
        request = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(request, timeout=180) as response, open(destination, "wb") as handle:
            handle.write(response.read())
        return True
    except Exception as error:  # noqa: BLE001
        print("   FAIL  ", url, error)
        if os.path.exists(destination):
            os.remove(destination)
        return False


def main(slugs):
    for slug in slugs:
        print("[model]", slug)
        try:
            info = fetch_json(slug)
        except Exception as error:  # noqa: BLE001
            print("   skip (api):", error)
            continue
        node = info.get("gltf", {}).get(RES, {}).get("gltf")
        if not node:
            print("   no gltf at", RES, "- has", list(info.get("gltf", {}).keys()))
            continue
        folder = os.path.join(ROOT, f"{slug}_{RES}")
        written = 0
        if download(node["url"], os.path.join(folder, os.path.basename(node["url"]))):
            written += 1
        for relative, dependency in (node.get("include") or {}).items():
            if download(dependency["url"], os.path.join(folder, relative)):
                written += 1
        print(f"   {written} files -> {folder}")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or ["cardboard_box_01"]))
