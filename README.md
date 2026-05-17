# Agent Skills

![gdb_skill](gdb_skill.png)

A growing collection of reverse engineering skills for AI coding agents.

## Skills

- **[gdb](skills/gdb)** — Non-blocking debugging with the GNU Debugger (GDB). Trace live C/C++/Rust processes without the agent ever blocking on a breakpoint.
- **[gdb-qemu](skills/gdb-qemu)** — GDB + QEMU stub mode for debugging x86-64 binaries inside Docker on Apple Silicon (or any environment where ptrace is unavailable).

## Installation

Browse and install via [agent-skills.md](https://agent-skills.md/skills/betab0t/skills/gdb), or use the CLI:

```
npx add-skill https://github.com/betab0t/skills/gdb
```

Or set it up manually. For example, in Cursor:

```bash
cd your-project
git clone https://github.com/betab0t/skills.git .cursor/skills
```

The agent will automatically pick up any skills under `.cursor/skills/`.

## Supported Agents

Works with any agent that can run shell commands, including Cursor, Claude Code, Gemini CLI, and others.

## License

MIT
