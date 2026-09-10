#!/usr/bin/env python3
"""Author additive ceiling-fixture housings through the existing local Blender MCP.

Run with ~/.local/share/blender-mcp/venv/bin/python. No cloud/install required.
Never regenerates parking_garage.tscn, changes old assets, or saves the open file.
Refuses existing outputs; inspect artist work before choosing a new output folder.
The old emissive strips remain the diffusers. This pass adds NO lights/emission.
"""
import asyncio
import hashlib
import json
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

from blockout_boxes import boxes

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets/environment/parking/parking_garage.gltf"
OUTPUT = ROOT / "assets/environment/parking/fixture_details"

CODE = r'''
import bpy, bmesh, json
from pathlib import Path
from mathutils import Vector
payload = json.loads(PAYLOAD_JSON)
output = Path(payload["output"])
assert bpy.data.scenes.get("ZERO_FRAME_FixtureDetails") is None, "Authoring scene already exists"
previous = bpy.context.window.scene
scene = bpy.data.scenes.new("ZERO_FRAME_FixtureDetails")
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene["source_sha256"] = payload["source_sha256"]
scene["stage"] = "deck_fixture_housings_only"
collection = bpy.data.collections.new("ZF_DeckFixtureHousings")
scene.collection.children.link(collection)
bpy.context.window.scene = scene

def material(name, color, metallic, roughness):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat

paint = material("ZF_Fixture_PowderCoat", (0.22, 0.235, 0.215), 0.0, 0.62)
steel = material("ZF_Fixture_GalvanizedClips", (0.43, 0.46, 0.48), 1.0, 0.38)
rows = {}
parts = 0
# Build in metres: game (x,y,z) -> Blender (x,-z,y), exactly once.
# Every box is closed, bevelled, UV mapped, and outside the existing diffuser.
def box(bm, centre, size, slot):
    global parts
    result = bmesh.ops.create_cube(bm, size=1.0)
    for v in result["verts"]:
        v.co = Vector((centre[0] + v.co.x * size[0],
                       centre[1] + v.co.y * size[1],
                       centre[2] + v.co.z * size[2]))
    for face in {f for v in result["verts"] for f in v.link_faces}:
        face.material_index = slot
    parts += 1

try:
    for item in payload["fixtures"]:
        rows.setdefault(round(item["centre"][2], 3), []).append(item)
    for row_index, (row_z, fixtures) in enumerate(sorted(rows.items())):
        bm = bmesh.new()
        for item in fixtures:
            x, height, z = item["centre"]
            # 0.16 m diffuser width: rails inner faces at +/-0.081 m.
            for side in (-1, 1):
                box(bm, (x, -z + side * 0.096, height), (1.84, 0.030, 0.09), 0)
                box(bm, (x + side * 0.919, -z, height), (0.036, 0.222, 0.09), 0)
            # Top cover starts above original strip, without coplanar faces.
            box(bm, (x, -z, height + 0.049), (1.80, 0.162, 0.016), 0)
            for end in (-1, 1):
                # Thin retaining strap across the underside, connected to rails.
                box(bm, (x + end * 0.63, -z, height - 0.049), (0.024, 0.222, 0.016), 1)
                # Ceiling surface at y=3.1 m; mount ends exactly at that plane.
                low, high = height + 0.057, payload["ceiling_y"]
                assert high > low
                box(bm, (x + end * 0.63, -z, (low + high) * 0.5),
                    (0.055, 0.10, high - low), 1)
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=0.0025, segments=2,
                        affect='EDGES', clamp_overlap=True)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        assert all(len(e.link_faces) == 2 for e in bm.edges), "Non-manifold housing"
        mesh = bpy.data.meshes.new("ZF_FixtureRow%02d" % row_index)
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(paint)
        mesh.materials.append(steel)
        obj = bpy.data.objects.new(mesh.name, mesh)
        collection.objects.link(obj)
        obj["fixture_count"] = len(fixtures)
        obj["game_row_z"] = row_z
        # Keep row-local coordinates for precision and useful editor origins.
        origin = Vector((0.0, -row_z, payload["ceiling_y"]))
        for v in mesh.vertices:
            v.co -= origin
        obj.location = origin
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        with bpy.context.temp_override(object=obj, active_object=obj):
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.uv.smart_project(island_margin=0.02)
            bpy.ops.object.mode_set(mode='OBJECT')
        mesh.calc_loop_triangles()
        assert len(mesh.uv_layers) == 1
    bpy.context.view_layer.update()
    meshes = list(collection.objects)
    assert len(meshes) == 5 and parts == 360, (len(meshes), parts)
    triangles = sum(len(o.data.loop_triangles) for o in meshes)
    assert 0 < triangles < 60000, triangles
    points = [o.matrix_world @ Vector(p) for o in meshes for p in o.bound_box]
    # Report in Godot coordinates, independently checked after import.
    game_points = [(p.x, p.z, -p.y) for p in points]
    low = [min(p[i] for p in game_points) for i in range(3)]
    high = [max(p[i] for p in game_points) for i in range(3)]
    assert 2.90 < low[1] < 2.93 and abs(high[1] - 3.1) < 0.0001
    status = bpy.ops.export_scene.gltf(filepath=str(output / "deck_fixture_housings.glb"),
        export_format='GLB', use_active_scene=True, export_yup=True,
        export_texcoords=True, export_normals=True, export_materials='EXPORT',
        export_animations=False, export_cameras=False, export_lights=False, export_extras=True)
    assert 'FINISHED' in status, status
    # Only this new scene + dependencies, never the user's open .blend.
    bpy.data.libraries.write(str(output / "deck_fixture_housings.blend"), {scene},
                             path_remap='ABSOLUTE', fake_user=True)
    report = {**payload, "blender_version": bpy.app.version_string,
              "mesh_count": len(meshes), "fixture_count": len(payload["fixtures"]),
              "parts": parts, "triangles": triangles, "bounds_low": low, "bounds_high": high}
    report.pop("output")
    (output / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    print("FIXTURE_DETAILS_EXPORTED", json.dumps({k: report[k] for k in
        ("mesh_count", "fixture_count", "parts", "triangles", "bounds_low", "bounds_high")}))
finally:
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.context.window.scene = previous
    assert bpy.context.window.scene == previous
    print("PREVIOUS_BLENDER_SCENE_RESTORED")
'''


def payload() -> dict:
    gltf = json.loads(SOURCE.read_text())
    node = next(n for n in gltf["nodes"] if n.get("name") == "Fixtures")
    # boxes() is intentionally limited. Do not silently accept changed transforms.
    assert not any(key in node for key in ("matrix", "rotation", "scale", "children"))
    assert gltf["scenes"][gltf.get("scene", 0)]["nodes"].count(gltf["nodes"].index(node)) == 1
    fixtures = [b for b in boxes(SOURCE) if b.mesh == "Fixtures" and b.high[0] < 30.0]
    assert len(fixtures) == 40
    records = []
    for b in sorted(fixtures, key=lambda b: (round(b.low[2], 3), round(b.low[0], 3))):
        assert all(abs(a - e) < 0.0001 for a, e in zip(b.size, (1.8, 0.08, 0.16)))
        centre = [(b.low[i] + b.high[i]) * 0.5 for i in range(3)]
        assert abs(centre[1] - 2.97) < 0.0001
        records.append({"centre": centre, "size": list(b.size)})
    return {"output": str(OUTPUT), "source": str(SOURCE.relative_to(ROOT)),
            "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
            "buffer_sha256": hashlib.sha256(SOURCE.with_suffix('.bin').read_bytes()).hexdigest(),
            "ceiling_y": 3.1, "fixtures": records}


async def main() -> None:
    data = payload()
    files = [OUTPUT / name for name in ("deck_fixture_housings.glb", "deck_fixture_housings.blend", "manifest.json")]
    if any(path.exists() for path in files):
        raise FileExistsError("Refusing to overwrite authored fixture assets")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    server = Path.home() / ".local/share/blender-mcp/venv/bin/blender-mcp"
    params = StdioServerParameters(command=str(server), env={
        "BLENDER_MCP_DISABLE_TELEMETRY": "1", "BLENDER_HOST": "127.0.0.1", "BLENDER_PORT": "9876"})
    async with stdio_client(params) as (reader, writer):
        async with ClientSession(reader, writer) as session:
            await session.initialize()
            response = await session.call_tool("execute_blender_code", {
                "code": CODE.replace("PAYLOAD_JSON", repr(json.dumps(data)))})
            text = "\n".join(c.text for c in response.content if c.type == "text")
            print(text, flush=True)
            if response.isError or "FIXTURE_DETAILS_EXPORTED" not in text or "PREVIOUS_BLENDER_SCENE_RESTORED" not in text:
                raise RuntimeError("Blender authoring failed; inspect working scene before retrying")
    assert all(path.is_file() and path.stat().st_size > 0 for path in files)
    report = json.loads(files[-1].read_text())
    assert report["fixture_count"] == 40 and report["mesh_count"] == 5
    assert payload() == data, "Source changed during authoring"
    print("FIXTURE_MCP_RESULT PASS", OUTPUT, flush=True)


if __name__ == "__main__":
    asyncio.run(asyncio.wait_for(main(), timeout=150.0))
