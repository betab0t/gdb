#!/bin/bash
# gdb_start.sh - Start a GDB session with named pipe control.
#
# Usage:
#   ./scripts/gdb_start.sh ./my_executable
#   ./scripts/gdb_start.sh ./my_executable scripts/custom_setup.gdb
#
# Creates:
#   gdb_cmd_pipe  - named pipe for sending commands
#   .gdb_pid      - file containing the GDB process PID
#   trace.log     - GDB trace output (created by setup.gdb)
#
# Environment:
#   GDB_PIPE  - pipe path (default: gdb_cmd_pipe)
#   GDB_BIN   - gdb binary (default: gdb-multiarch, falls back to gdb)

set -euo pipefail

PIPE="${GDB_PIPE:-gdb_cmd_pipe}"
PID_FILE=".gdb_pid"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SETUP="${2:-${SCRIPT_DIR}/setup.gdb}"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <executable> [setup.gdb path]" >&2
    exit 1
fi

EXECUTABLE="$1"

if [ ! -f "$EXECUTABLE" ]; then
    echo "Error: Executable '$EXECUTABLE' not found." >&2
    exit 1
fi

# Determine GDB binary
if [ -n "${GDB_BIN:-}" ]; then
    GDB="$GDB_BIN"
elif command -v gdb-multiarch &>/dev/null; then
    GDB="gdb-multiarch"
elif command -v gdb &>/dev/null; then
    GDB="gdb"
else
    echo "Error: Neither gdb-multiarch nor gdb found." >&2
    exit 1
fi

# Clean up any previous session
rm -f "$PIPE" "$PID_FILE" trace.log

# Create named pipe
mkfifo "$PIPE"

# Start GDB in background, reading from the pipe
tail -f "$PIPE" | "$GDB" -q -x "$SETUP" --args "$EXECUTABLE" &
GDB_PID=$!

echo "$GDB_PID" > "$PID_FILE"
sleep 1

echo "GDB started successfully."
echo "  PID:   $GDB_PID (saved to $PID_FILE)"
echo "  Pipe:  $PIPE"
echo "  Log:   trace.log"
echo "  Binary: $GDB"
