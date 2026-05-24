#!/bin/bash
# gdb_stop.sh - Cleanly stop a QEMU-stub GDB session started by gdb_start.sh.
#
# Kills the gdb-multiarch host process, the QEMU stub inside the container,
# and the tail feeder, then removes session files.
# Safe to call multiple times (idempotent).
#
# Usage:
#   GDB_CONTAINER=my-container ./scripts/gdb_stop.sh
#
# Environment:
#   GDB_CONTAINER  - (required) Docker container name
#   GDB_PIPE       - pipe path (default: gdb_cmd_pipe)
#   QEMU_PORT      - QEMU stub port to kill (default: 1234)

set -euo pipefail

CONTAINER="${GDB_CONTAINER:?GDB_CONTAINER must be set to the Docker container name}"
PIPE="${GDB_PIPE:-gdb_cmd_pipe}"
PID_FILE=".gdb_pid"
QEMU_PORT="${QEMU_PORT:-1234}"

if [ -f "$PID_FILE" ]; then
    GDB_PID=$(cat "$PID_FILE")

    # Find the tail feeder
    TAIL_PID=$(ps -eo pid,ppid,args 2>/dev/null \
        | grep "tail -f.*${PIPE}" \
        | grep -v grep \
        | awk '{print $1}' \
        | head -1) || true

    # Kill the host-side gdb-multiarch subshell
    if kill -0 "$GDB_PID" 2>/dev/null; then
        kill "$GDB_PID" 2>/dev/null || true
    fi

    # Kill gdb-multiarch and QEMU stub inside the container
    docker exec "$CONTAINER" pkill -9 gdb-multiarch                    2>/dev/null || true
    docker exec "$CONTAINER" pkill -9 -f "qemu-x86_64 -g $QEMU_PORT"  2>/dev/null || true

    # Kill the tail feeder
    if [ -n "${TAIL_PID:-}" ] && kill -0 "$TAIL_PID" 2>/dev/null; then
        kill "$TAIL_PID" 2>/dev/null || true
    fi

    # Wait for host-side process to exit (up to 3 seconds)
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

rm -f "$PIPE" "$PID_FILE" trace.log

echo "GDB session stopped and cleaned up."
