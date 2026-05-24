#!/bin/bash
# gdb_trace.sh - Set a conditional dprintf tracepoint on a running session.
#
# Handles the full interrupt -> delete old -> set new -> continue cycle.
#
# Usage:
#   # Unconditional trace:
#   ./scripts/gdb_trace.sh loop_function '"iteration=%d\n", iteration'
#
#   # Conditional trace (only when iteration == 20):
#   ./scripts/gdb_trace.sh loop_function '"haha\n"' 'iteration == 20'
#
#   # Delete all tracepoints without setting new ones:
#   ./scripts/gdb_trace.sh --clear
#
# Environment:
#   GDB_PIPE  - pipe path (default: gdb_cmd_pipe)

set -euo pipefail

PIPE="${GDB_PIPE:-gdb_cmd_pipe}"
PID_FILE=".gdb_pid"
DELAY=0.3

send_cmd() {
    echo "$1" > "$PIPE"
    sleep "$DELAY"
}

get_gdb_pid() {
    if [ ! -f "$PID_FILE" ]; then
        echo "Error: PID file '$PID_FILE' not found. Run gdb_start.sh first." >&2
        exit 1
    fi
    cat "$PID_FILE"
}

interrupt_gdb() {
    local pid
    pid=$(get_gdb_pid)
    kill -INT "$pid" 2>/dev/null || true
    # GDB needs time to fully stop the inferior after SIGINT.
    # 0.5s is often not enough — commands sent too early are silently dropped.
    sleep 1
}

# --- Handle --clear flag ---
if [ "${1:-}" = "--clear" ]; then
    interrupt_gdb
    send_cmd "delete"
    send_cmd "continue"
    echo "All breakpoints/tracepoints removed. Program continuing."
    exit 0
fi

# --- Normal trace flow ---
if [ $# -lt 2 ]; then
    echo "Usage: $0 <location> <format_and_args> [condition]" >&2
    echo "       $0 --clear" >&2
    exit 1
fi

LOCATION="$1"
FORMAT_ARGS="$2"
CONDITION="${3:-}"

# 1. Interrupt
interrupt_gdb

# 2. Delete previous tracepoints
send_cmd "delete"

# 3. Set new dprintf
send_cmd "dprintf ${LOCATION}, ${FORMAT_ARGS}"

# 4. Apply condition if provided
if [ -n "$CONDITION" ]; then
    # Use $bpnum - GDB's convenience variable for the last breakpoint set.
    # This works because we're sending it directly to GDB (not through shell expansion).
    send_cmd "condition \$bpnum ${CONDITION}"
fi

# 5. Continue
send_cmd "continue"

echo "Tracepoint set on '${LOCATION}'."
[ -n "$CONDITION" ] && echo "  Condition: ${CONDITION}"
echo "Program continuing. Check trace.log for output."
