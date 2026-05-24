<!-- AGENT: DO NOT READ OR USE THIS FILE. It is for human testers only. -->

# GDB QEMU Skill — Demo Prompts

> **For humans only.** Copy-paste prompts for manually testing the gdb-qemu skill.

---

## Setup

Make sure the container is running and `GDB_CONTAINER` is exported:
```bash
export GDB_CONTAINER=my-container
```

---

## Scenario: Dynamic Tracing via QEMU Stub

### Prompt 1 — Setup and Initial Trace

> I want to test your GDB QEMU debugging skills.
> The target container is called `my-container` and the binary is `/challenges/first_blood`.
> Start a GDB session using the QEMU stub mode, set a tracepoint on `main` that prints
> "entered main", then let the program run.

### Prompt 2 — Dynamic Modification

> Remove the previous tracepoint and set a new one on `loop_function` that fires when
> `iteration == 50` and prints the iteration number. Keep the program running.

### Prompt 3 — Multitasking (Distractor)

> While we wait for iteration 50, can you quickly explain the difference between
> `dprintf` and a regular GDB breakpoint?

### Prompt 4 — Verification

> Did we hit iteration 50 yet? Show me the relevant part of trace.log.

### Prompt 5 — Cleanup

> Clear all tracepoints but keep the program running. Verify it's still alive.

### Prompt 6 — Termination

> Stop the GDB session and clean up everything.
