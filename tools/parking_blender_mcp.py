#!/usr/bin/env python3
"""Run a reviewed local authoring script through the existing Blender MCP stdio server.
No addon installation, cloud service, credentials or direct socket workaround.
Usage: existing MCP venv python tools/parking_blender_mcp.py SCRIPT.py EXPECTED_MARKER
"""
import asyncio
from pathlib import Path
import sys
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def main() -> None:
    script = Path(sys.argv[1]).resolve()
    root = Path(__file__).resolve().parent
    if script.parent != root or script.suffix != ".py":
        raise ValueError("Authoring scripts must be reviewed .py files in project tools/")
    marker = sys.argv[2]
    params = StdioServerParameters(
        command=str(Path.home() / ".local/share/blender-mcp/venv/bin/blender-mcp"),
        env={"BLENDER_MCP_DISABLE_TELEMETRY": "1", "BLENDER_HOST": "127.0.0.1", "BLENDER_PORT": "9876"})
    async with stdio_client(params) as (reader, writer):
        async with ClientSession(reader, writer) as session:
            await session.initialize()
            response = await session.call_tool("execute_blender_code", {"code": script.read_text()})
            text = "\n".join(c.text for c in response.content if c.type == "text")
            print(text, flush=True)
            if response.isError or marker not in text:
                raise RuntimeError("Authoring did not confirm " + marker + "; inspect Blender before retrying")
    print("PARKING_MCP_CALL PASS", script.name, marker, flush=True)


if __name__ == "__main__":
    asyncio.run(asyncio.wait_for(main(), timeout=300.0))
