#!/bin/bash
# gdb_start.sh - Start a GDB+QEMU stub session with named pipe control.
#
# Runs the target binary under qemu-x86_64's built-in GDB remote stub
# inside a Docker container, then connects gdb-multiarch to it via the
# host-side named pipe.
#
# Usage:
#   ./scripts/gdb_start.sh ./my_executable [run-args...]
#
# Creates:
#   gdb_cmd_pipe  - named pipe for sending commands
#   .gdb_pid      - file containing the host-side pipeline PID
#   trace.log     - GDB output (captured from docker exec stdout)
#
# Environment:
#   GDB_CONTAINER  - Docker container name (required)
#   GDB_REMOTE_DIR - path inside container where binaries live (default: /challenges)
#   QEMU_PORT      - GDB stub port (default: 1234)
#   GDB_PIPE       - pipe path (default: gdb_cmd_pipe)

set -euo pipefail

PIPE="${GDB_PIPE:-gdb_cmd_pipe}"
PID_FILE=".gdb_pid"
QEMU_PORT="${QEMU_PORT:-1234}"
REMOTE_DIR="${GDB_REMOTE_DIR:-/challenges}"

if [ -z "${GDB_CONTAINER:-}" ]; then
    echo "Error: GDB_CONTAINER is not set. Set it to your Docker container name." >&2
    echo "  Example: GDB_CONTAINER=my-container $0 ./binary" >&2
    exit 1
fi

if [ $# -lt 1 ]; then
    echo "Usage: $0 <executable> [run-args...]" >&2
    exit 1
fi

EXECUTABLE="$1"
shift
RUN_ARGS=("$@")
BASENAME=$(basename "$EXECUTABLE")

# Clean up any previous session
rm -f "$PIPE" "$PID_FILE" trace.log
docker exec "$GDB_CONTAINER" pkill -9 -f "qemu-x86_64 -g $QEMU_PORT" 2>/dev/null || true
docker exec "$GDB_CONTAINER" pkill -9 gdb-multiarch 2>/dev/null || true
sleep 0.3

# Create named pipe
mkfifo "$PIPE"

# Start the binary under QEMU's built-in GDB stub (no ptrace needed)
ARGS_STR=""
if [ ${#RUN_ARGS[@]} -gt 0 ]; then
    ARGS_STR="${RUN_ARGS[*]}"
fi
docker exec -d "$GDB_CONTAINER" bash -c \
    "qemu-x86_64 -g $QEMU_PORT ${REMOTE_DIR}/$BASENAME $ARGS_STR >/tmp/target_stdout.log 2>&1"
sleep 0.5

# Verify QEMU started
if ! docker exec "$GDB_CONTAINER" pgrep -f "qemu-x86_64 -g $QEMU_PORT" >/dev/null 2>&1; then
    rm -f "$PIPE"
    echo "Error: QEMU failed to start. Check that ${REMOTE_DIR}/$BASENAME exists inside the container." >&2
    echo "  Copy it with: docker cp $EXECUTABLE $GDB_CONTAINER:${REMOTE_DIR}/" >&2
    exit 1
fi

# Connect gdb-multiarch to the QEMU stub via the host pipe
tail -f "$PIPE" | docker exec -i "$GDB_CONTAINER" gdb-multiarch -q > trace.log 2>&1 &
GDB_PID=$!
echo "$GDB_PID" > "$PID_FILE"
sleep 1

# Initialize GDB settings via the pipe (no -x setup.gdb because gdb-multiarch
# connects bare; we send the config commands directly)
echo "set pagination off"           > "$PIPE"; sleep 0.3
echo "set confirm off"              > "$PIPE"; sleep 0.3
echo "set print pretty on"          > "$PIPE"; sleep 0.3
echo "set architecture i386:x86-64" > "$PIPE"; sleep 0.3
echo "target remote :$QEMU_PORT"    > "$PIPE"; sleep 1

echo "GDB started successfully (QEMU stub mode)."
echo "  PID:       $GDB_PID (saved to $PID_FILE)"
echo "  Pipe:      $PIPE"
echo "  Log:       trace.log"
echo "  Container: $GDB_CONTAINER"
echo "  Port:      $QEMU_PORT"
echo ""
echo "The program is stopped at the entry point. Use 'continue' (not 'run') to start it."
