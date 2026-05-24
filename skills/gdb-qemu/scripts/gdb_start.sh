#!/bin/bash
# gdb_start.sh - Start a QEMU-stub GDB session with named pipe control.
#
# Usage:
#   GDB_CONTAINER=my-container ./scripts/gdb_start.sh ./my_executable [run-args...]
#
# Creates:
#   gdb_cmd_pipe  - named pipe for sending commands
#   .gdb_pid      - file containing the gdb-multiarch process PID
#   trace.log     - GDB trace output (captured from docker exec stdout)
#
# Environment:
#   GDB_CONTAINER   - (required) Docker container name running the target
#   GDB_PIPE        - pipe path (default: gdb_cmd_pipe)
#   GDB_REMOTE_DIR  - directory inside the container holding the binary (default: /challenges)
#   QEMU_PORT       - QEMU GDB stub port (default: 1234)

set -euo pipefail

CONTAINER="${GDB_CONTAINER:?GDB_CONTAINER must be set to the Docker container name}"
PIPE="${GDB_PIPE:-gdb_cmd_pipe}"
PID_FILE=".gdb_pid"
REMOTE_DIR="${GDB_REMOTE_DIR:-/challenges}"
QEMU_PORT="${QEMU_PORT:-1234}"

if [ $# -lt 1 ]; then
    echo "Usage: GDB_CONTAINER=<container> $0 <executable> [run-args...]" >&2
    exit 1
fi

EXECUTABLE="$1"
shift
RUN_ARGS=("$@")
BASENAME=$(basename "$EXECUTABLE")

# Clean up any previous session
rm -f "$PIPE" "$PID_FILE" trace.log
docker exec "$CONTAINER" pkill -9 -f "qemu-x86_64 -g $QEMU_PORT" 2>/dev/null || true
docker exec "$CONTAINER" pkill -9 gdb-multiarch 2>/dev/null || true
sleep 0.3

# Create named pipe
mkfifo "$PIPE"

# Start the binary under QEMU's built-in GDB stub (no ptrace needed)
docker exec -d "$CONTAINER" bash -c \
    "qemu-x86_64 -g ${QEMU_PORT} ${REMOTE_DIR}/${BASENAME} ${RUN_ARGS[*]:-} >/tmp/target_stdout.log 2>&1"
sleep 0.5

# Connect gdb-multiarch to the QEMU stub via the host pipe
tail -f "$PIPE" | docker exec -i "$CONTAINER" gdb-multiarch -q > trace.log 2>&1 &
GDB_PID=$!
echo "$GDB_PID" > "$PID_FILE"
sleep 1

echo "set pagination off"            > "$PIPE"; sleep 0.3
echo "set confirm off"               > "$PIPE"; sleep 0.3
echo "set print pretty on"           > "$PIPE"; sleep 0.3
echo "set architecture i386:x86-64"  > "$PIPE"; sleep 0.3
echo "target remote :$QEMU_PORT"     > "$PIPE"; sleep 1

echo "GDB (QEMU stub) started successfully."
echo "  Container: $CONTAINER"
echo "  PID:       $GDB_PID (saved to $PID_FILE)"
echo "  Pipe:      $PIPE"
echo "  Log:       trace.log"
echo "  QEMU port: $QEMU_PORT"
