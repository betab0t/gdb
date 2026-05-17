#!/bin/bash
# gdb_stop.sh - Cleanly stop a GDB+QEMU stub session started by gdb_start.sh.
#
# Kills gdb-multiarch, the QEMU stub, and the tail feeder, then removes
# session files. Safe to call multiple times (idempotent).
#
# Usage:
#   ./scripts/gdb_stop.sh
#
# Environment:
#   GDB_CONTAINER  - Docker container name (required)
#   GDB_PIPE       - pipe path (default: gdb_cmd_pipe)
#   QEMU_PORT      - QEMU stub port to kill (default: 1234)

set -euo pipefail

PIPE="${GDB_PIPE:-gdb_cmd_pipe}"
PID_FILE=".gdb_pid"
QEMU_PORT="${QEMU_PORT:-1234}"

if [ -z "${GDB_CONTAINER:-}" ]; then
    echo "Error: GDB_CONTAINER is not set. Set it to your Docker container name." >&2
    exit 1
fi

# 1. Kill container-side processes unconditionally (even if .gdb_pid is missing)
docker exec "$GDB_CONTAINER" pkill -9 gdb-multiarch 2>/dev/null || true
docker exec "$GDB_CONTAINER" pkill -9 -f "qemu-x86_64 -g $QEMU_PORT" 2>/dev/null || true

# 2. Kill host-side processes if PID file exists
if [ -f "$PID_FILE" ]; then
    GDB_PID=$(cat "$PID_FILE")

    TAIL_PID=$(ps -eo pid,ppid,args 2>/dev/null \
        | grep "tail -f.*${PIPE}" \
        | grep -v grep \
        | awk '{print $1}' \
        | head -1) || true

    # Kill host-side pipeline process (tail | docker exec)
    if kill -0 "$GDB_PID" 2>/dev/null; then
        kill "$GDB_PID" 2>/dev/null || true
    fi

    if [ -n "${TAIL_PID:-}" ] && kill -0 "$TAIL_PID" 2>/dev/null; then
        kill "$TAIL_PID" 2>/dev/null || true
    fi

    # Wait for the host-side process to exit (up to 3 seconds)
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

# 3. Remove session files AFTER processes are dead.
rm -f "$PIPE" "$PID_FILE" trace.log

echo "GDB session stopped and cleaned up."
