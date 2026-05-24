#!/bin/bash
# gdb_stop.sh - Cleanly stop a GDB session started by gdb_start.sh.
#
# Kills the target process, GDB, and the tail feeder, then removes session files.
# Safe to call multiple times (idempotent).
#
# Usage:
#   ./scripts/gdb_stop.sh
#
# Environment:
#   GDB_PIPE  - pipe path (default: gdb_cmd_pipe)

set -euo pipefail

PIPE="${GDB_PIPE:-gdb_cmd_pipe}"
PID_FILE=".gdb_pid"

# 1. Kill processes (GDB + its children + tail feeder) BEFORE removing files.
#    This avoids the race where the pipe is removed while GDB is still processing.
if [ -f "$PID_FILE" ]; then
    GDB_PID=$(cat "$PID_FILE")

    # Find and kill the tail feeder (parent of the pipe reader).
    # It shares the same parent PID and reads from the pipe.
    TAIL_PID=$(ps -eo pid,ppid,args 2>/dev/null \
        | grep "tail -f.*${PIPE}" \
        | grep -v grep \
        | awk '{print $1}' \
        | head -1) || true

    # Kill GDB (this also kills the inferior/target process)
    if kill -0 "$GDB_PID" 2>/dev/null; then
        kill "$GDB_PID" 2>/dev/null || true
    fi

    # Kill the tail feeder
    if [ -n "${TAIL_PID:-}" ] && kill -0 "$TAIL_PID" 2>/dev/null; then
        kill "$TAIL_PID" 2>/dev/null || true
    fi

    # Wait for processes to exit (up to 3 seconds)
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
