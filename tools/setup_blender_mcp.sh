#!/usr/bin/env bash
# Installs and enables the BlenderMCP addon in whatever Blender is on PATH, so Claude can
# drive Blender over the Model Context Protocol.
#
# The MCP server itself lives in a venv at ~/.local/share/blender-mcp/venv and is already
# registered with Claude Code (`claude mcp list` shows it as `blender`). This script only
# does the Blender half: copy the addon into Blender's addon directory and switch it on.
#
# Usage: tools/setup_blender_mcp.sh [path/to/blender]
#
# With no argument it takes `blender` from PATH, and failing that the Steam install, since
# the Steam build is the same official Blender but never lands on PATH.
set -euo pipefail

ADDON="$HOME/.local/share/blender-mcp/addon.py"
STEAM_BLENDER="$HOME/.local/share/Steam/steamapps/common/Blender/blender"

BLENDER="${1:-}"
if [[ -z "$BLENDER" ]]; then
	if command -v blender >/dev/null 2>&1; then
		BLENDER="$(command -v blender)"
	elif [[ -x "$STEAM_BLENDER" ]]; then
		BLENDER="$STEAM_BLENDER"
	fi
fi

if [[ -z "$BLENDER" || ! -x "$BLENDER" ]]; then
	echo "no Blender found. Install it with  sudo pacman -S blender  (or from Steam)," >&2
	echo "then pass the binary explicitly:  tools/setup_blender_mcp.sh /path/to/blender" >&2
	exit 1
fi
if [[ ! -f "$ADDON" ]]; then
	echo "addon missing at $ADDON" >&2
	echo "fetch it with:  curl -fsSL -o \"$ADDON\" https://raw.githubusercontent.com/ahujasid/blender-mcp/main/addon.py" >&2
	exit 1
fi

echo "blender: $("$BLENDER" --version | head -1)  [$BLENDER]"
"$BLENDER" --background --python-expr "
import bpy
bpy.ops.preferences.addon_install(filepath='$ADDON', overwrite=True)
bpy.ops.preferences.addon_enable(module='addon')
bpy.ops.wm.save_userpref()
enabled = 'addon' in bpy.context.preferences.addons
print('BLENDER_MCP_ADDON_ENABLED=%s' % enabled)
" 2>&1 | grep -E "BLENDER_MCP_ADDON_ENABLED|Error|Traceback" || true

cat <<'NEXT'

Next, in Blender:
  1. open it normally (not headless)
  2. press N in the 3D viewport to show the sidebar
  3. open the "MCP for Blender" tab and press Connect
     (the addon listens on 127.0.0.1:9876; the MCP server dials that)

Then restart the Claude session: MCP servers are only picked up at startup.
NEXT
