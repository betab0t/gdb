#!/bin/bash
# gdb_send.sh - Send a single GDB command to the named pipe.
#
# Usage:
#   ./scripts/gdb_send.sh "dprintf loop_function, \"iteration=%d\\n\", iteration"
#   ./scripts/gdb_send.sh "continue"
#   ./scripts/gdb_send.sh "info breakpoints"
#
# Environment:
#   GDB_PIPE  - path to the named pipe (default: gdb_cmd_pipe)
#   GDB_DELAY - seconds to wait after sending (default: 0.3)

set -euo pipefail

PIPE="${GDB_PIPE:-gdb_cmd_pipe}"
DELAY="${GDB_DELAY:-0.3}"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <gdb-command>" >&2
    exit 1
fi

if [ ! -p "$PIPE" ]; then
    echo "Error: Named pipe '$PIPE' not found. Run gdb_start.sh first." >&2
    exit 1
fi

echo "$1" > "$PIPE"
sleep "$DELAY"
