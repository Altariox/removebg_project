#!/usr/bin/env bash
set -euo pipefail

# Convenience wrapper: continuous scan every 10 seconds.
# Usage:
#   ./watch_removebg.sh [/path/to/input]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_DIR="${1:-/home/altariox/Videos/removebg}"
INPUT_DIR="${1:-/home/altariox/Pictures/removebg}"

WATCH=1 INTERVAL="${INTERVAL:-10}" "$SCRIPT_DIR/run_removebg.sh" "$INPUT_DIR"
