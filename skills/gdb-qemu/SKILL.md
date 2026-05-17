---
name: gdb-qemu
description: "Debug and trace x86-64 binaries inside Docker using QEMU's built-in GDB stub. Use when ptrace is unavailable — typically Docker on Apple Silicon — or when you need cross-architecture debugging with qemu-user."
---

# GDB + QEMU Stub Skill

Non-blocking GDB debugging through QEMU's built-in GDB remote stub. Use this
when ptrace is unavailable — typically Docker Desktop on Apple Silicon (M1/M2/M3)
where the Linux kernel runs under Virtualization.framework and ptrace doesn't
work for cross-architecture debugging.

> **Prerequisite**: Familiarity with the **gdb** skill's core concepts (named
> pipe, `dprintf`, log sampling) is helpful but not required. This document is
> self-contained for the QEMU stub workflow.

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
3. Uses a named-pipe approach for non-blocking control — the agent sends GDB
   commands by writing to the pipe and reads results from `trace.log`.

## Prerequisites & Setup

### Requirements
- Docker with a running container (any name — set via `GDB_CONTAINER`)
- Inside the container: `qemu-x86_64` (from `qemu-user`), `gdb-multiarch`
- Target binaries accessible inside the container at `$GDB_REMOTE_DIR/<name>`

### Container Setup Example
```bash
docker run -d --name my-lab ubuntu:22.04 sleep infinity
docker exec my-lab apt-get update
docker exec my-lab apt-get install -y qemu-user gdb-multiarch
docker cp ./my_binary my-lab:/challenges/
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GDB_CONTAINER` | *(required)* | Docker container name |
| `GDB_REMOTE_DIR` | `/challenges` | Path inside container where binaries live |
| `QEMU_PORT` | `1234` | TCP port for the QEMU GDB stub |
| `GDB_PIPE` | `gdb_cmd_pipe` | Named pipe path |
| `GDB_DELAY` | `0.3` | Seconds to wait after sending a command (`gdb_send.sh`) |

## Workflow

Run all commands from the directory containing `./scripts/`. Session files
(`gdb_cmd_pipe`, `.gdb_pid`, `trace.log`) are created in the current directory.

### 1. Copy the Binary into the Container

```bash
docker cp ./crackme my-lab:/challenges/
```

The binary must exist at `$GDB_REMOTE_DIR/<basename>` inside the container
(default: `/challenges/<basename>`).

### 2. Start a Session

```bash
export GDB_CONTAINER=my-lab
./scripts/gdb_start.sh ./crackme
```

After this, the program is **stopped at the entry point** inside QEMU.

### 3. Set Tracepoints (`dprintf`)

Set tracepoints **before** continuing — otherwise you'll miss early functions
like `main`:

```bash
./scripts/gdb_trace.sh main '"reached main\n"'
./scripts/gdb_trace.sh loop_func '"iteration=%d\n", i' 'i == 10'
```

`gdb_trace.sh` handles the full interrupt-delete-set-continue cycle
automatically. It interrupts `gdb-multiarch` inside the container via
`docker exec pkill -INT`.

**Do NOT use** `kill -INT $(cat .gdb_pid)` — the PID file contains the
host-side pipeline PID, not the container's GDB process.

### 4. Start / Resume Execution

Use `continue` — **not** `run`. The binary is already loaded by QEMU; `run`
would try to restart it through GDB which doesn't work in stub mode.

```bash
./scripts/gdb_send.sh "continue"
```

Note: `gdb_trace.sh` already sends `continue` after setting the tracepoint,
so this step is only needed if you want to resume without changing tracepoints.

### 5. Sample the Log

```bash
tail -n 20 trace.log
```

`trace.log` captures all GDB output (including prompts and command echoes).
Look for your `dprintf` output lines among the noise.

### 6. Stop the Session

```bash
./scripts/gdb_stop.sh
```

Kills `gdb-multiarch`, the QEMU stub, and the tail feeder, then removes
session files.

## Helper Scripts

| Script | Purpose | Needs `GDB_CONTAINER`? |
|--------|---------|----------------------|
| `gdb_start.sh` | Launch QEMU stub + connect `gdb-multiarch` | Yes |
| `gdb_send.sh` | Send a GDB command via the named pipe | No (local pipe) |
| `gdb_trace.sh` | Interrupt + delete + set dprintf + continue | Yes |
| `gdb_stop.sh` | Kill all processes, remove session files | Yes |

## Agent Guidance (Reducing Tool Calls)

### Setting a tracepoint and starting execution
When the program hasn't been continued yet, combine in **one call**:
```bash
./scripts/gdb_trace.sh loop_func '"iteration=%d\n", i' 'i == 10' \
  && ./scripts/gdb_send.sh "continue"
```

### Sampling the log after a tracepoint
Give the program time to reach the tracepoint, then read:
```bash
sleep 5 && tail -n 20 trace.log
```

### Interrupting manually
**Always** use the script or `docker exec` — never `kill -INT` on the host PID:
```bash
docker exec "$GDB_CONTAINER" pkill -INT gdb-multiarch
sleep 1
./scripts/gdb_send.sh "info breakpoints"
sleep 1 && tail -n 15 trace.log
./scripts/gdb_send.sh "continue"
```

### Inspecting state (interrupt + query + resume)
Batch into a **single shell call**:
```bash
docker exec "$GDB_CONTAINER" pkill -INT gdb-multiarch && sleep 1 \
  && ./scripts/gdb_send.sh "info registers" \
  && sleep 1 && tail -n 15 trace.log \
  && ./scripts/gdb_send.sh "continue"
```

## Common Pitfalls

### 1. Using `run` instead of `continue`
QEMU already loaded the binary. Sending `run` through GDB will fail or behave
unexpectedly. Always use `continue` after `gdb_start.sh`.

### 2. Using `kill -INT` on the host PID
`.gdb_pid` contains the PID of the host-side `tail | docker exec` pipeline —
**not** `gdb-multiarch` inside the container. Sending SIGINT to it kills the
pipe feeder and breaks the session. Use `docker exec pkill -INT gdb-multiarch`
or just use `gdb_trace.sh` which handles this correctly.

### 3. Binary not found (silent QEMU failure)
If the binary doesn't exist at `$GDB_REMOTE_DIR/<name>` inside the container,
QEMU fails silently (it runs in the background). `gdb_start.sh` verifies QEMU
is running and will error if it's not — but check the path if you see this.

### 4. Commands dropped after interrupt
After interrupting GDB, wait at least **1 second** before sending the next
command. Commands sent too soon are silently dropped. The helper scripts
already account for this.

### 5. Log output appears delayed
`trace.log` is written via shell redirection. After a `dprintf` fires, the
result may not appear immediately. Wait **1-2 seconds** before reading.

## Key Differences from the Base gdb Skill

| Aspect | Base gdb | gdb-qemu |
|--------|----------|----------|
| Execution | Local `gdb` / `gdb-multiarch` | `docker exec` into container |
| Target launch | GDB `--args` (ptrace) | `qemu-x86_64 -g <port>` (GDB stub) |
| Connection | Direct | `target remote :<port>` |
| Start program | `run` | `continue` (already loaded by QEMU) |
| Interrupt | `kill -INT` on host PID | `docker exec pkill -INT` inside container |
| Cleanup | Kill local processes | Kill container processes + host pipeline |
| Architecture | Native | Sets `i386:x86-64` explicitly |
| Log capture | GDB `set logging` | Shell redirection (`> trace.log 2>&1`) |

## Limitations

1. **QEMU stub mode only supports x86-64** — the architecture is set explicitly
   to `i386:x86-64`.
2. **Arguments with spaces** are not robustly handled when passed through to
   the QEMU command line. Stick to simple arguments.
3. All limitations from the base **gdb** skill also apply (Linux only, signal
   handling caveats, log buffering delays).
