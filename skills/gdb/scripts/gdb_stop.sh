#!/bin/bash
# gdb_stop.sh - Cleanly stop a GDB session started by gdb_start.sh.
#
# Kills the target process, GDB (or gdb-multiarch), the QEMU stub (if any),
# and the tail feeder, then removes session files.
# Safe to call multiple times (idempotent).
#
# Usage:
#   ./scripts/gdb_stop.sh
#
# Environment:
#   GDB_PIPE   - pipe path (default: gdb_cmd_pipe)
#   QEMU_PORT  - QEMU stub port to kill (default: 1234); only relevant when
#                USE_QEMU_STUB=1 was used at start time

set -euo pipefail

PIPE="${GDB_PIPE:-gdb_cmd_pipe}"
PID_FILE=".gdb_pid"
QEMU_PORT="${QEMU_PORT:-1234}"

# 1. Kill processes (GDB + its children + tail feeder) BEFORE removing files.
#    This avoids the race where the pipe is removed while GDB is still processing.
if [ -f "$PID_FILE" ]; then
    GDB_PID=$(cat "$PID_FILE")

    # Find and kill the tail feeder (parent of the pipe reader).
    TAIL_PID=$(ps -eo pid,ppid,args 2>/dev/null \
        | grep "tail -f.*${PIPE}" \
        | grep -v grep \
        | awk '{print $1}' \
        | head -1) || true

    # Kill GDB / gdb-multiarch host-side process (also kills the inferior)
    if kill -0 "$GDB_PID" 2>/dev/null; then
        kill "$GDB_PID" 2>/dev/null || true
    fi

    # Kill GDB and gdb-multiarch inside the container
    docker exec gdb-mcp-lab pkill -9 gdb          2>/dev/null || true
    docker exec gdb-mcp-lab pkill -9 gdb-multiarch 2>/dev/null || true

    # Kill QEMU stub if one was started (USE_QEMU_STUB=1 mode)
    docker exec gdb-mcp-lab pkill -9 -f "qemu-x86_64 -g $QEMU_PORT" 2>/dev/null || true

    # Kill the tail feeder
    if [ -n "${TAIL_PID:-}" ] && kill -0 "$TAIL_PID" 2>/dev/null; then
        kill "$TAIL_PID" 2>/dev/null || true
    fi

    # Wait for the host-side GDB wrapper to exit (up to 3 seconds)
    for _ in 1 2 3 4 5 6; do
        if ! kill -0 "$GDB_PID" 2>/dev/null; then
            break
        fi
        sleep 0.5
    done

    # Force kill if still alive
    if kill -0 "$GDB_PID" 2>/dev/null; then
        kill -9 "$GDB_PID" 2>/dev/null || true
    fi
    if [ -n "${TAIL_PID:-}" ] && kill -0 "$TAIL_PID" 2>/dev/null; then
        kill -9 "$TAIL_PID" 2>/dev/null || true
    fi
fi

# 2. Remove session files AFTER processes are dead.
rm -f "$PIPE" "$PID_FILE" trace.log

echo "GDB session stopped and cleaned up."
