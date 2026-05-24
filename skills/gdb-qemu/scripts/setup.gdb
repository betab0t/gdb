# GDB Setup Script for Live Tracing (QEMU stub mode)
# Sourced automatically after gdb_start.sh connects via "target remote :PORT".

# 1. Disable pagination to prevent blocking on long output
set pagination off

# 2. Disable confirmation prompts (e.g., "Delete all breakpoints? (y or n)")
#    Critical for pipe-based workflows where the confirmation answer
#    arrives as a separate command and causes "Undefined command" errors.
set confirm off

# 3. Configure logging to capture output to a file
# Note: 'set logging on' is deprecated in newer GDBs, using 'enabled on'
set logging file trace.log
set logging enabled on

# 4. Optional: formatting
set print pretty on
