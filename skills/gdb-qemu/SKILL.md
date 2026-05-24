---
name: gdb-qemu
description: "Debug and trace x86_64 binaries inside a Docker container on hosts where ptrace is unavailable (e.g. Apple Silicon). Uses QEMU's built-in GDB remote stub instead of ptrace. Works with any container — set GDB_CONTAINER to the target container name."
---

# GDB QEMU Stub Skill

Non-blocking GDB debugging for AI agents, using QEMU's built-in GDB remote stub.
Use this skill when running x86_64 binaries inside Docker on a host where ptrace is
unavailable (e.g. Apple Silicon with `platform: linux/amd64`).

For hosts where ptrace works (native Linux x86_64), use the **gdb** skill instead.

## How It Works

Instead of attaching directly to a process via ptrace, this skill:

1. Launches the binary under `qemu-x86_64 -g <PORT>` inside the container, which exposes a GDB remote stub on that port.
2. Connects `gdb-multiarch` (running inside the same container) to the stub via `target remote :PORT`.
3. All agent interaction goes through a named pipe on the **host** — the agent writes commands to the pipe, never blocks.

The result is identical to the ptrace-based `gdb` skill from the agent's perspective:
the same `gdb_send.sh`, `gdb_trace.sh`, and `gdb_stop.sh` scripts, just pointed at a
different container.

## Prerequisites

- Docker installed on the host
- Container has `gdb-multiarch` and `qemu-user` installed
- Binary is inside the container (see `GDB_REMOTE_DIR`)

```bash
# Install inside the container (Ubuntu/Debian)
apt-get install -y gdb-multiarch qemu-user
```

## Required Environment Variable

| Variable | Description |
|---|---|
| `GDB_CONTAINER` | **Required.** Name of the running Docker container. |

## Optional Environment Variables

| Variable | Default | Description |
|---|---|---|
| `GDB_PIPE` | `gdb_cmd_pipe` | Named pipe path on the host |
| `GDB_REMOTE_DIR` | `/challenges` | Directory inside the container holding the binary |
| `QEMU_PORT` | `1234` | Port QEMU listens on for the GDB stub |
| `GDB_DELAY` | `0.3` | Seconds `gdb_send.sh` waits after each command |

## Workflow

### 1. Start a session

```bash
GDB_CONTAINER=my-container ./scripts/gdb_start.sh ./path/to/binary
# Optional: pass run-time arguments after the binary
GDB_CONTAINER=my-container ./scripts/gdb_start.sh ./binary arg1 arg2
```

Creates `gdb_cmd_pipe`, `.gdb_pid`, and `trace.log` in the current directory.

### 2. Set a tracepoint

```bash
# Unconditional
GDB_CONTAINER=my-container ./scripts/gdb_trace.sh main '"entered main\n"'

# Conditional
GDB_CONTAINER=my-container ./scripts/gdb_trace.sh loop_function '"iter=%d\n", i' 'i == 100'
```

### 3. Send a raw GDB command

```bash
./scripts/gdb_send.sh "info breakpoints"
./scripts/gdb_send.sh "continue"
```

`gdb_send.sh` does not need `GDB_CONTAINER` — it writes directly to the pipe.

### 4. Sample the trace

```bash
tail -n 20 trace.log
```

### 5. Stop and clean up

```bash
GDB_CONTAINER=my-container ./scripts/gdb_stop.sh
```

## Helper Scripts

| Script | Purpose | Needs `GDB_CONTAINER`? |
|---|---|---|
| `gdb_start.sh` | Create pipe, launch QEMU stub, connect gdb-multiarch | Yes |
| `gdb_send.sh` | Write a single GDB command to the pipe | No |
| `gdb_trace.sh` | Interrupt + delete + set dprintf + continue | Yes |
| `gdb_stop.sh` | Kill all processes, remove session files | Yes |

## Example Session

```bash
export GDB_CONTAINER=my-container

# Start
./scripts/gdb_start.sh ./bin/target_binary

# Trace
./scripts/gdb_trace.sh main '"entered main\n"'

# Sample
sleep 2 && tail -n 20 trace.log

# Stop
./scripts/gdb_stop.sh
```

## Limitations

1. **x86_64 binaries only** — `qemu-x86_64` handles only x86_64 ELF binaries. For ARM or other architectures, use the matching QEMU binary and adjust `GDB_REMOTE_DIR` accordingly.
2. **No stdin to the target** — the binary's stdin is `/dev/null` inside QEMU. Programs that read from stdin will get EOF immediately.
3. **Target stdout goes to `/tmp/target_stdout.log`** inside the container, not to `trace.log` on the host. Read it with `docker exec $GDB_CONTAINER cat /tmp/target_stdout.log`.
4. **Zombie processes** — after `gdb_stop.sh`, killed container processes may briefly appear as `<defunct>` if the container's PID 1 doesn't reap children (e.g. `sleep infinity`). They are dead and do not affect subsequent sessions. Use `tini` as the container entrypoint to avoid this.

## Common Pitfalls

### QEMU stub not ready when GDB connects
`gdb_start.sh` waits 0.5s after launching QEMU before connecting. If the container is
slow to schedule, `target remote` fires before the stub is listening and the session
silently fails. Check `trace.log` — if it shows only `(gdb)` prompts with no
`Remote debugging using`, stop and restart.

### Commands dropped after SIGINT
After interrupting gdb-multiarch, wait at least **1 second** before sending commands.
`gdb_trace.sh` handles this automatically.

### Conditional tracepoint on a value that already passed
If `iteration` is already at 200 and you set `condition $bpnum iteration == 100`,
the tracepoint will never fire. Interrupt first, read the current value from `trace.log`,
then set a condition for a value ahead of the current one.
