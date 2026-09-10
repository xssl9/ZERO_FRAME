#!/usr/bin/env python3
"""Test the MCP client BUNDLED with the installed official Higgsfield plugin.

Run with ~/.local/share/blender-mcp/venv/bin/python tools/verify_higgsfield_blender.py
No install, login, token access, generation or .blend save. This tests the official
plugin's LOCAL execution bridge, not the hosted bridge.higgsfield.ai HTTP transport.
The original ahujasid Blender MCP on 9876 is not replaced or reconfigured.
"""
import argparse
import asyncio
import json
from pathlib import Path
import uuid

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

HOME = Path.home()
DEFAULT_PYTHON = HOME / ".local/share/Steam/steamapps/common/Blender/5.2/python/bin/python3.13"
DEFAULT_PACKAGES = HOME / ".config/blender/5.2/extensions/.local/lib/python3.13/site-packages"


async def verify(python: Path, packages: Path, port: int) -> None:
    if not python.is_file() or not (packages / "blmcp/__main__.py").is_file():
        raise FileNotFoundError("Installed official plugin runtime not found; nothing installed automatically")
    params = StdioServerParameters(
        command=str(python), args=["-m", "blmcp", "--transport", "stdio"],
        env={"PYTHONPATH": str(packages), "BLENDER_MCP_HOST": "127.0.0.1",
             "BLENDER_MCP_PORT": str(port)},
    )
    name = "ZERO_FRAME_HIGGSFIELD_TEST_" + uuid.uuid4().hex
    async with stdio_client(params) as (reader, writer):
        async with ClientSession(reader, writer) as session:
            initialized = await session.initialize()
            print("HIGGSFIELD_BUNDLED_MCP_INITIALIZED", initialized.serverInfo.model_dump_json(), flush=True)
            names = set()
            cursor = None
            while True:
                page = await session.list_tools(cursor=cursor)
                names.update(tool.name for tool in page.tools)
                cursor = page.nextCursor
                if not cursor:
                    break
            assert "execute_blender_code" in names
            print("HIGGSFIELD_BUNDLED_TOOLS", len(names), flush=True)

            async def execute(code: str) -> dict:
                response = await session.call_tool("execute_blender_code", {"code": code})
                text = "\n".join(c.text for c in response.content if c.type == "text")
                if response.isError:
                    raise RuntimeError(text)
                value = json.loads(text)
                if value.get("status") != "ok":
                    raise RuntimeError(f"Blender execution failed: {value}")
                return value["result"]

            before = await execute('''import bpy
result = {"scene": bpy.context.scene.name, "objects": sorted(o.name for o in bpy.data.objects),
          "meshes": len(bpy.data.meshes), "materials": len(bpy.data.materials),
          "collections": len(bpy.data.collections), "selected": sorted(o.name for o in bpy.context.selected_objects),
          "higgsfield_enabled": "bl_ext.user_default.higgsfield_blender" in bpy.context.preferences.addons}
''')
            assert before["higgsfield_enabled"]
            try:
                made = await execute(f'''import bpy
name = {name!r}
assert bpy.data.objects.get(name) is None
collection = bpy.data.collections.new(name)
bpy.context.scene.collection.children.link(collection)
mesh = bpy.data.meshes.new(name)
mesh.from_pydata([(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),
                  (-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)], [],
                 [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])
mesh.update()
obj = bpy.data.objects.new(name, mesh)
collection.objects.link(obj)
obj.location = (1.25, -2.5, 0.75)
obj.scale = (0.25, 0.5, 0.75)
material = bpy.data.materials.new(name)
material.use_nodes = True
material.node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value = 0.83
mesh.materials.append(material)
bpy.context.view_layer.update()
result = {{"created": obj.name}}
''')
                assert made["created"] == name
                print("HIGGSFIELD_LOCAL_CREATE_OK", flush=True)
                observed = await execute(f'''import bpy
obj = bpy.data.objects[{name!r}]
result = {{"name": obj.name, "location": list(obj.location), "scale": list(obj.scale),
          "dimensions": list(obj.dimensions), "collection": obj.users_collection[0].name,
          "material": obj.data.materials[0].name,
          "roughness": obj.data.materials[0].node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value}}
''')
                assert observed["location"] == [1.25, -2.5, 0.75]
                assert observed["scale"] == [0.25, 0.5, 0.75]
                assert observed["dimensions"] == [0.5, 1.0, 1.5]
                assert observed["collection"] == observed["material"] == name
                assert abs(observed["roughness"] - 0.83) < 0.00001
                print("HIGGSFIELD_LOCAL_INDEPENDENT_READBACK_OK", json.dumps(observed), flush=True)
            finally:
                clean = await execute(f'''import bpy
name = {name!r}
for blocks in (bpy.data.objects, bpy.data.meshes, bpy.data.materials, bpy.data.collections):
    block = blocks.get(name)
    if block is not None:
        blocks.remove(block, do_unlink=True)
result = {{"removed": all(blocks.get(name) is None for blocks in
          (bpy.data.objects, bpy.data.meshes, bpy.data.materials, bpy.data.collections))}}
''')
                assert clean["removed"]
                print("HIGGSFIELD_LOCAL_CLEANUP_OK", flush=True)
            after = await execute('''import bpy
result = {"scene": bpy.context.scene.name, "objects": sorted(o.name for o in bpy.data.objects),
          "meshes": len(bpy.data.meshes), "materials": len(bpy.data.materials),
          "collections": len(bpy.data.collections), "selected": sorted(o.name for o in bpy.context.selected_objects),
          "higgsfield_enabled": "bl_ext.user_default.higgsfield_blender" in bpy.context.preferences.addons}
''')
            assert after == before, "Test must preserve original datablocks, active scene and selection"
            print("HIGGSFIELD_LOCAL_BRIDGE_RESULT PASS; HOSTED_HTTP_BRIDGE NOT VERIFIED", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--python", type=Path, default=DEFAULT_PYTHON)
    parser.add_argument("--site-packages", type=Path, default=DEFAULT_PACKAGES)
    parser.add_argument("--port", type=int, default=9877)
    args = parser.parse_args()
    asyncio.run(asyncio.wait_for(verify(args.python, args.site_packages, args.port), 120.0))
