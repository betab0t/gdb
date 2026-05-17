#!/bin/bash
# gdb_start.sh - Start a GDB session with named pipe control.
#
# Usage:
#   ./scripts/gdb_start.sh ./my_executable
#
# Creates:
#   gdb_cmd_pipe  - named pipe for sending commands
#   .gdb_pid      - file containing the GDB process PID
#   trace.log     - GDB trace output (captured from docker exec stdout)
#
# Environment:
#   GDB_PIPE  - pipe path (default: gdb_cmd_pipe)

set -euo pipefail

PIPE="${GDB_PIPE:-gdb_cmd_pipe}"
PID_FILE=".gdb_pid"
# Set USE_QEMU_STUB=1 when ptrace is unavailable (e.g. Docker on Apple Silicon).
# GDB stub port defaults to 1234; override with QEMU_PORT.
USE_QEMU_STUB="${USE_QEMU_STUB:-0}"
QEMU_PORT="${QEMU_PORT:-1234}"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <executable> [run-args...]" >&2
    echo "  USE_QEMU_STUB=1  use qemu-x86_64 GDB stub (required on Apple Silicon)" >&2
    exit 1
fi

EXECUTABLE="$1"
shift
RUN_ARGS=("$@")
BASENAME=$(basename "$EXECUTABLE")

# Clean up any previous session
rm -f "$PIPE" "$PID_FILE" trace.log
docker exec gdb-mcp-lab pkill -9 -f "qemu-x86_64 -g $QEMU_PORT" 2>/dev/null || true
docker exec gdb-mcp-lab pkill -9 gdb 2>/dev/null || true
sleep 0.3

# Create named pipe
mkfifo "$PIPE"

if [ "$USE_QEMU_STUB" = "1" ]; then
    # Start the binary under QEMU's built-in GDB stub (no ptrace needed)
    docker exec -d gdb-mcp-lab bash -c \
        "qemu-x86_64 -g $QEMU_PORT /challenges/$BASENAME ${RUN_ARGS[*]:-} >/tmp/target_stdout.log 2>&1"
    sleep 0.5

    # Connect gdb-multiarch to the QEMU stub via the host pipe
    tail -f "$PIPE" | docker exec -i gdb-mcp-lab gdb-multiarch -q > trace.log 2>&1 &
    GDB_PID=$!
    echo "$GDB_PID" > "$PID_FILE"
    sleep 1

    echo "set pagination off"                        > "$PIPE"; sleep 0.3
    echo "set confirm off"                           > "$PIPE"; sleep 0.3
    echo "set print pretty on"                       > "$PIPE"; sleep 0.3
    echo "set architecture i386:x86-64"              > "$PIPE"; sleep 0.3
    echo "target remote :$QEMU_PORT"                 > "$PIPE"; sleep 1
else
    # Original mode: GDB starts and controls the process directly (requires ptrace)
    tail -f "$PIPE" | docker exec -i gdb-mcp-lab gdb -q --args "/challenges/$BASENAME" "${RUN_ARGS[@]}" > trace.log 2>&1 &
    GDB_PID=$!
    echo "$GDB_PID" > "$PID_FILE"
    sleep 1

    echo "set pagination off"  > "$PIPE"; sleep 0.3
    echo "set confirm off"     > "$PIPE"; sleep 0.3
    echo "set print pretty on" > "$PIPE"; sleep 0.3
fi

echo "GDB started successfully."
echo "  PID:   $GDB_PID (saved to $PID_FILE)"
echo "  Pipe:  $PIPE"
echo "  Log:   trace.log"
[ "$USE_QEMU_STUB" = "1" ] && echo "  Mode:  QEMU stub (port $QEMU_PORT, no ptrace)"
