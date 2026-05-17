---
name: gdb-qemu
description: "Debug and trace x86-64 binaries inside Docker on Apple Silicon (or any environment where ptrace is unavailable) using QEMU's built-in GDB stub. Extends the base gdb skill with QEMU user-mode emulation support."
---

# GDB + QEMU Stub Skill

Non-blocking GDB debugging through QEMU's built-in GDB remote stub. Use this
when ptrace is unavailable — typically Docker Desktop on Apple Silicon (M1/M2/M3)
where the Linux kernel runs under Virtualization.framework and ptrace doesn't
work for cross-architecture debugging.

> **Prerequisite**: Read the **gdb** skill first. This skill reuses the same
> core concepts (named pipe, `dprintf`, log sampling, interrupt pattern) and
> only documents what differs for the QEMU stub workflow.

## When to Use This Skill

- You are debugging **x86-64 binaries** inside a **Docker container** on an
  **Apple Silicon** Mac (or any ARM host).
- `ptrace` is unavailable or restricted inside the container.
- The container has `qemu-x86_64` and `gdb-multiarch` installed.

If you are on a native x86-64 Linux host with ptrace available, use the base
**gdb** skill instead.

## How It Works

Instead of GDB launching and controlling the process directly (which requires
ptrace), this skill:

1. Runs the target binary under `qemu-x86_64 -g <port>`, which exposes a GDB
   remote stub on a TCP port inside the container.
2. Connects `gdb-multiarch` to that stub via `target remote :<port>`.
3. Uses the same named-pipe approach as the base skill for non-blocking control.

The agent interacts with GDB exactly the same way — write commands to the pipe,
read results from `trace.log`. The only difference is how the session starts and
how processes are cleaned up.

## Prerequisites & Setup

### Requirements
- Docker with a running container named `gdb-mcp-lab`
- Inside the container: `qemu-x86_64`, `gdb-multiarch`
- Target binaries placed under `/challenges/` inside the container

### Container Setup
```bash
# Example: build a container with the required tools
docker run -d --name gdb-mcp-lab ubuntu:22.04 sleep infinity
docker exec gdb-mcp-lab apt-get update
docker exec gdb-mcp-lab apt-get install -y qemu-user gdb-multiarch
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `USE_QEMU_STUB` | `0` | Set to `1` to use QEMU stub mode |
| `QEMU_PORT` | `1234` | TCP port for the QEMU GDB stub |
| `GDB_PIPE` | `gdb_cmd_pipe` | Named pipe path (same as base skill) |

## Workflow

### 1. Start a Session

**QEMU stub mode** (no ptrace needed):
```bash
USE_QEMU_STUB=1 ./scripts/gdb_start.sh ./my_binary
```

**Direct mode** (ptrace available inside the container):
```bash
./scripts/gdb_start.sh ./my_binary
```

Both modes create the same session files: `gdb_cmd_pipe`, `.gdb_pid`, `trace.log`.

### 2. Send Commands, Set Tracepoints, Sample the Log

Identical to the base gdb skill:
```bash
./scripts/gdb_send.sh "info registers"
./scripts/gdb_trace.sh loop_function '"iteration=%d\n", iteration' 'iteration == 10'
tail -n 20 trace.log
```

### 3. Stop the Session

```bash
./scripts/gdb_stop.sh
```

This kills GDB, `gdb-multiarch`, the QEMU stub process, and the tail feeder,
then removes session files.

## Key Differences from the Base gdb Skill

| Aspect | Base gdb | gdb-qemu |
|--------|----------|----------|
| Execution | Local `gdb` / `gdb-multiarch` | `docker exec` into `gdb-mcp-lab` container |
| Target launch | GDB `--args` (ptrace) | `qemu-x86_64 -g <port>` (GDB stub) |
| Connection | Direct | `target remote :<port>` |
| Interrupt | `kill -INT` on host PID | `docker exec pkill -INT` inside container |
| Cleanup | Kill local processes | Kill container processes (`gdb`, `gdb-multiarch`, `qemu-x86_64`) |
| Architecture | Native | Sets `i386:x86-64` explicitly |

## Helper Scripts

Same script names and interface as the base skill, but adapted for the Docker +
QEMU environment:

| Script | Purpose |
|--------|---------|
| `gdb_start.sh` | Start QEMU stub + connect `gdb-multiarch` (or direct GDB mode) inside the container |
| `gdb_send.sh` | Send a GDB command via the named pipe (identical behavior to base) |
| `gdb_trace.sh` | Interrupt + delete + set dprintf + continue (signals via `docker exec`) |
| `gdb_stop.sh` | Kill all container processes + host-side feeder, remove session files |
| `setup.gdb` | GDB init script for logging and non-blocking settings |

## Limitations

1. **Container name is hard-coded** to `gdb-mcp-lab` in the scripts. Change it
   if your container has a different name.
2. **Binary path is hard-coded** to `/challenges/<basename>` inside the container.
3. **QEMU stub mode only supports x86-64** — the architecture is set explicitly
   to `i386:x86-64`.
4. All limitations from the base **gdb** skill also apply (Linux only, signal
   handling caveats, log buffering delays).
