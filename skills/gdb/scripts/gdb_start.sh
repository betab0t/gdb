#!/bin/bash
# gdb_start.sh - Start a GDB session with named pipe control (ptrace mode).
#
# Usage:
#   GDB_CONTAINER=my-container ./scripts/gdb_start.sh ./my_executable [run-args...]
#
# Creates:
#   gdb_cmd_pipe  - named pipe for sending commands
#   .gdb_pid      - file containing the GDB process PID
#   trace.log     - GDB trace output (captured from docker exec stdout)
#
# Environment:
#   GDB_CONTAINER  - (required) Docker container name running the target
#   GDB_PIPE       - pipe path (default: gdb_cmd_pipe)
#   GDB_REMOTE_DIR - directory inside the container holding the binary (default: /challenges)

set -euo pipefail

CONTAINER="${GDB_CONTAINER:?GDB_CONTAINER must be set to the Docker container name}"
PIPE="${GDB_PIPE:-gdb_cmd_pipe}"
PID_FILE=".gdb_pid"
REMOTE_DIR="${GDB_REMOTE_DIR:-/challenges}"

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
docker exec "$CONTAINER" pkill -9 gdb 2>/dev/null || true
sleep 0.3

# Create named pipe
mkfifo "$PIPE"

# Start GDB inside the container, reading from the pipe.
# GDB stdout is captured to trace.log on the host.
tail -f "$PIPE" | docker exec -i "$CONTAINER" gdb -q --args "${REMOTE_DIR}/${BASENAME}" "${RUN_ARGS[@]}" > trace.log 2>&1 &
GDB_PID=$!

echo "$GDB_PID" > "$PID_FILE"
sleep 1

# Send essential setup commands through the pipe
echo "set pagination off"  > "$PIPE"; sleep 0.3
echo "set confirm off"     > "$PIPE"; sleep 0.3
echo "set print pretty on" > "$PIPE"; sleep 0.3

echo "GDB started successfully."
echo "  Container: $CONTAINER"
echo "  PID:       $GDB_PID (saved to $PID_FILE)"
echo "  Pipe:      $PIPE"
echo "  Log:       trace.log"
