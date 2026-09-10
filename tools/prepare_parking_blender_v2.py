#!/usr/bin/env python3
"""Prepare an isolated authoring scene from the geometry actually used by Godot.

Uses the MCP client bundled in the installed official Higgsfield plugin. Keeps
all previous Blender scenes/datablocks and refuses to overwrite a v2 .blend.
This is PASS 4 preparation, NOT a photorealistic rebuild or a Godot integration.
Run using ~/.local/share/blender-mcp/venv/bin/python.
"""
import asyncio
import json
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

from verify_higgsfield_blender import DEFAULT_PACKAGES, DEFAULT_PYTHON

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets/environment/parking/parking_garage.gltf"
OUTPUT = ROOT / "assets/environment/parking_v2/source/parking_garage_v2.blend"

# This code executes inside the running Blender through the official local bridge.
CODE = '''import bpy
from mathutils import Vector
source = SOURCE_PATH
output = OUTPUT_PATH
scene_name = "ZERO_FRAME_Parking_V2"
assert bpy.data.scenes.get(scene_name) is None, "Working scene already exists; will not replace it"
previous_scene = bpy.context.window.scene
scene = bpy.data.scenes.new(scene_name)
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene["zero_frame_stage"] = "PASS_4_IMPORTED_BASELINE_NOT_FINAL"
scene["zero_frame_source"] = source
bpy.context.window.scene = scene

# Import God's Y-up glTF into Blender's Z-up coordinates exactly once.
status = bpy.ops.import_scene.gltf(filepath=source)
assert "FINISHED" in status
roots = {}
for name in ("ENV_STRUCTURE", "ENV_INTERIOR", "ENV_PROPS", "ENV_DECALS",
             "ENV_LIGHTS", "ENV_COLLISION", "ENV_GAMEPLAY", "ENV_BACKGROUND"):
    col = bpy.data.collections.new(name)
    scene.collection.children.link(col)
    roots[name] = col

def child(parent, name):
    col = bpy.data.collections.new(name)
    parent.children.link(col)
    return col

structure = {name: child(roots["ENV_STRUCTURE"], name)
             for name in ("Walls", "Floors", "Ceilings", "Columns", "Stairs", "Doors")}
services = child(roots["ENV_INTERIOR"], "Services")
fixtures = child(roots["ENV_LIGHTS"], "Fixtures")
for name in ("Cars", "Containers", "Barrels", "Shelves", "Carts", "Tools", "Electrical"):
    child(roots["ENV_PROPS"], name)
for name in ("Parking", "Dirt", "Warning", "Graffiti", "Damage"):
    child(roots["ENV_DECALS"], name)
for name in ("Player", "Static", "Vehicle"):
    child(roots["ENV_COLLISION"], name)

families = {
    "Floor_Parking": structure["Floors"], "Floor_Annex": structure["Floors"],
    "Walls_Concrete": structure["Walls"], "Walls_Plaster": structure["Walls"],
    "Ceiling": structure["Ceilings"], "Entrance_Shutter": structure["Doors"],
    "Services": services, "Fixtures": fixtures,
}
meshes = [obj for obj in scene.objects if obj.type == "MESH"]
assert len(meshes) == 8, "Unexpected source geometry; inspect rather than silently dropping objects"
found = set()
for obj in meshes:
    family = next((name for name in families if obj.name == name or obj.name.startswith(name + ".")), None)
    assert family is not None, "Unknown imported mesh: " + obj.name
    assert family not in found, "Duplicate source family"
    found.add(family)
    obj["surface_family"] = family
    obj.name = "V2_" + family
    target = families[family]
    target.objects.link(obj)
    for collection in list(obj.users_collection):
        if collection != target:
            collection.objects.unlink(obj)
assert found == set(families)
# Remove only the import's now-empty top-level collection from THIS scene.
for collection in list(scene.collection.children):
    if collection not in roots.values() and not collection.all_objects:
        scene.collection.children.unlink(collection)
        if collection.users == 0:
            bpy.data.collections.remove(collection)

bpy.context.view_layer.update()
points = [obj.matrix_world @ Vector(point) for obj in meshes for point in obj.bound_box]
low = [min(p[i] for p in points) for i in range(3)]
high = [max(p[i] for p in points) for i in range(3)]
# Height MUST match the gameplay glTF, not the incorrect 86 m Services source.
assert -0.31 <= low[2] <= -0.29 and 3.39 <= high[2] <= 3.41, (low, high)
assert 86.70 < high[0] - low[0] < 86.80
assert 40.50 < high[1] - low[1] < 40.70
triangles = 0
for obj in meshes:
    assert len(obj.data.uv_layers) > 0, obj.name
    obj.data.calc_loop_triangles()
    triangles += len(obj.data.loop_triangles)
assert not any("ZERO_FRAME_HIGGSFIELD_TEST_" in o.name or "ZERO_FRAME_MCP_TEST_" in o.name for o in scene.objects)
# Write ONLY this scene and its dependencies. Never save the prior user's scenes.
bpy.data.libraries.write(output, {scene}, path_remap="ABSOLUTE", fake_user=True)
for area in bpy.context.screen.areas:
    if area.type == "VIEW_3D":
        region = next(r for r in area.regions if r.type == "WINDOW")
        with bpy.context.temp_override(area=area, region=region):
            bpy.ops.view3d.view_all(center=False)
result = {"stage": "PASS_4_IMPORTED_BASELINE_NOT_FINAL", "output": output,
          "scene": scene.name, "previous_scene_preserved": previous_scene.name,
          "objects": len(scene.objects), "triangles": triangles,
          "blender_bounds_low": low, "blender_bounds_high": high,
          "collections": [c.name for c in scene.collection.children]}
'''


async def main() -> None:
    if OUTPUT.exists():
        raise FileExistsError(f"Refusing to overwrite artist work: {OUTPUT}")
    if not SOURCE.is_file() or not OUTPUT.parent.is_dir():
        raise FileNotFoundError("Source glTF or prepared output directory is missing")
    params = StdioServerParameters(
        command=str(DEFAULT_PYTHON), args=["-m", "blmcp", "--transport", "stdio"],
        env={"PYTHONPATH": str(DEFAULT_PACKAGES), "BLENDER_MCP_HOST": "127.0.0.1", "BLENDER_MCP_PORT": "9877"},
    )
    async with stdio_client(params) as (reader, writer):
        async with ClientSession(reader, writer) as session:
            await session.initialize()
            response = await session.call_tool("execute_blender_code", {
                "code": CODE.replace("SOURCE_PATH", repr(str(SOURCE))).replace("OUTPUT_PATH", repr(str(OUTPUT)))})
            text = "\n".join(c.text for c in response.content if c.type == "text")
            print(text, flush=True)
            if response.isError:
                raise RuntimeError("MCP failed; inspect active working scene before retrying")
            payload = json.loads(text)
            if payload.get("status") != "ok":
                raise RuntimeError("Blender preparation failed; inspect working scene before retrying")
            assert OUTPUT.is_file() and OUTPUT.stat().st_size > 0
            print("PARKING_V2_BASELINE_SAVED", OUTPUT, flush=True)


if __name__ == "__main__":
    asyncio.run(asyncio.wait_for(main(), 150.0))
