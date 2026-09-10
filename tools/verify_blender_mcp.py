#!/usr/bin/env python3
"""Exercise the EXISTING Blender MCP over stdio, without installing another server.

Run with ~/.local/share/blender-mcp/venv/bin/python tools/verify_blender_mcp.py
Requires the existing Blender addon to be listening. Does not save the .blend or
change the selected objects. Temporary datablocks are removed in a finally block.
This verifies LOCAL Blender MCP, NOT Higgsfield authentication or its Bridge.
"""
import asyncio
import json
from pathlib import Path
import uuid

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def verify() -> None:
    server = Path.home() / ".local/share/blender-mcp/venv/bin/blender-mcp"
    if not server.is_file():
        raise FileNotFoundError(f"Existing server not found: {server}; not installing a replacement")
    params = StdioServerParameters(
        command=str(server),
        env={"BLENDER_MCP_DISABLE_TELEMETRY": "1", "BLENDER_HOST": "127.0.0.1", "BLENDER_PORT": "9876"},
    )
    name = "ZERO_FRAME_MCP_TEST_" + uuid.uuid4().hex
    async with stdio_client(params) as (reader, writer):
        async with ClientSession(reader, writer) as session:
            initialized = await session.initialize()
            print("MCP_INITIALIZED", initialized.serverInfo.model_dump_json(), flush=True)
            names = set()
            cursor = None
            while True:
                listing = await session.list_tools(cursor=cursor)
                names.update(tool.name for tool in listing.tools)
                cursor = listing.nextCursor
                if not cursor:
                    break
            required = {"execute_blender_code", "get_object_info", "get_scene_info"}
            if not required <= names:
                raise RuntimeError(f"Missing MCP tools: {required - names}")
            print("MCP_TOOLS", len(names), "required tools present", flush=True)

            async def call(tool: str, arguments: dict) -> str:
                result = await session.call_tool(tool, arguments)
                text = "\n".join(c.text for c in result.content if c.type == "text")
                print(tool, text, flush=True)
                if result.isError or text.startswith(("Error", "Rejected")):
                    raise RuntimeError(text)
                return text

            async def execute(code: str, marker: str) -> str:
                text = await call("execute_blender_code", {"code": code})
                if marker not in text:
                    raise RuntimeError(f"Blender did not confirm {marker}")
                return text

            await execute('''import bpy, json, addon_utils
print("BLENDER_INSPECT", json.dumps({
    "version": bpy.app.version_string,
    "background": bpy.app.background,
    "file": bpy.data.filepath,
    "dirty": bpy.data.is_dirty,
    "objects": len(bpy.data.objects),
    "collections": [c.name for c in bpy.data.collections],
    "enabled_addons": list(bpy.context.preferences.addons.keys()),
    "higgsfield_modules": [m.__name__ for m in addon_utils.modules()
        if "higgsfield" in (m.__name__ + str(getattr(m, "bl_info", {}))).lower()],
    "unit_system": bpy.context.scene.unit_settings.system,
    "unit_scale": bpy.context.scene.unit_settings.scale_length,
}))''', "BLENDER_INSPECT")
            try:
                await execute(f'''import bpy
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
material.diffuse_color = (0.18, 0.32, 0.12, 1.0)
material.node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value = 0.83
mesh.materials.append(material)
bpy.context.view_layer.update()
assert tuple(obj.location) == (1.25, -2.5, 0.75)
assert tuple(obj.dimensions) == (0.5, 1.0, 1.5)
print("MCP_CREATE_OK", obj.name)
''', "MCP_CREATE_OK")
                observed = await call("get_object_info", {"object_name": name})
                info = json.loads(observed)
                if info.get("name") != name or info.get("location") != [1.25, -2.5, 0.75]:
                    raise RuntimeError(f"Independent object readback mismatch: {info}")
                await execute(f'''import bpy
obj = bpy.data.objects[{name!r}]
assert obj.data.materials[0].name == {name!r}
assert abs(obj.data.materials[0].node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value - 0.83) < 0.00001
assert tuple(obj.scale) == (0.25, 0.5, 0.75)
assert obj.users_collection[0].name == {name!r}
print("MCP_READBACK_OK")''', "MCP_READBACK_OK")
            finally:
                await execute(f'''import bpy
name = {name!r}
for blocks in (bpy.data.objects, bpy.data.meshes, bpy.data.materials, bpy.data.collections):
    block = blocks.get(name)
    if block is not None:
        blocks.remove(block, do_unlink=True)
assert all(blocks.get(name) is None for blocks in (bpy.data.objects, bpy.data.meshes, bpy.data.materials, bpy.data.collections))
print("MCP_CLEANUP_OK")''', "MCP_CLEANUP_OK")
            print("LOCAL_BLENDER_MCP_RESULT PASS; HIGGSFIELD NOT VERIFIED", flush=True)


if __name__ == "__main__":
    asyncio.run(asyncio.wait_for(verify(), timeout=120.0))
