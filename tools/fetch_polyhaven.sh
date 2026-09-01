#!/usr/bin/env bash
set -euo pipefail

# Thin reproducible entry point. The Python implementation validates every
# slug through api.polyhaven.com and skips unavailable maps without leaving
# partial files behind.
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$project_root/tools/fetch_polyhaven.py" "$@"
