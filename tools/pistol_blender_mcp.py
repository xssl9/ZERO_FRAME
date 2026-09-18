"""Execute a project authoring script using the locally cached Blender MCP.

Usage: uvx --offline --from blender-mcp python tools/pistol_blender_mcp.py SCRIPT MARKER
No downloads, addon installation or changes to Blender preferences.
"""
import asyncio
from pathlib import Path
import sys
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def main():
    script = Path(sys.argv[1]).resolve()
    if script.parent != Path(__file__).resolve().parent or script.suffix != ".py":
        raise ValueError("Expected an authoring script in tools/")
    params = StdioServerParameters(
        command=str(Path(sys.executable).parent / "blender-mcp"),
        env={"BLENDER_MCP_DISABLE_TELEMETRY": "1", "BLENDER_HOST": "127.0.0.1", "BLENDER_PORT": "9876"},
    )
    async with stdio_client(params) as (reader, writer):
        async with ClientSession(reader, writer) as session:
            await session.initialize()
            code = "PROJECT_ROOT = " + repr(str(script.parent.parent)) + "\n" + script.read_text()
            response = await session.call_tool("execute_blender_code", {"code": code})
            text = "\n".join(c.text for c in response.content if c.type == "text")
            print(text, flush=True)
            if response.isError or sys.argv[2] not in text:
                raise RuntimeError("Blender did not confirm " + sys.argv[2])


if __name__ == "__main__":
    asyncio.run(asyncio.wait_for(main(), timeout=300))
