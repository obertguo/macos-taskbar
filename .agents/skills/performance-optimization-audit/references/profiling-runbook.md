# macOS Performance Profiling Runbook & Tooling Reference

This runbook details command-line and GUI profiling tools available on macOS for auditing the Taskbar application for CPU spikes, memory leaks, heap churn, and IPC overhead.

---

## 1. Quick Terminal Profiling Commands

### 1.1 Process Status & Resource Footprint
Check resident memory (RSS in KB) and CPU utilization:
```bash
PID=$(pgrep -x Taskbar || pgrep -f "build/Taskbar.app" || true)
if [ -n "$PID" ]; then
    ps -o pid,rss,%cpu,%mem,time,comm -p "$PID"
fi
```
- **RSS Target:** $< 45{,}000\text{ KB}$ ($< 45\text{ MB}$). Normal baseline is $\sim 18{,}000 - 24{,}000\text{ KB}$.
- **CPU Target:** $\sim 0.0\%$ at idle.

---

### 1.2 Call Tree Sampling (`sample`)
Collect call stack samples across all threads to identify hot methods and bottlenecks:
```bash
# Samples the target process for 10 seconds at 10ms intervals
sample Taskbar 10 10 -file /tmp/taskbar_profile.txt

# Inspect the top functions in the sample report
head -n 60 /tmp/taskbar_profile.txt
```
Look for:
- Main thread blocked waiting on locks or semaphores.
- Unexpected AppKit drawing passes inside `drawRect:`.
- Mach IPC messaging (`mach_msg_trap`) executing on the main thread instead of `AXThread`.

---

### 1.3 Memory Leak Detection (`leaks`)
Scan the running process heap for leaked memory allocations and dangling cycles:
```bash
leaks Taskbar
```
- If leaks are reported, view detailed root references:
  ```bash
  leaks --referenceTree Taskbar
  ```

---

### 1.4 Virtual Memory Analysis (`vmmap`)
Analyze memory zones (dirty vs clean memory, heaps, images, mapped files):
```bash
vmmap --summary Taskbar
```
Pay attention to:
- `MALLOC_TINY`, `MALLOC_SMALL`, `MALLOC_LARGE`: Excessive sizes indicate allocation churn.
- `CG image` / `IOKit`: High numbers indicate un-evicted or duplicated icon bitmaps.

---

### 1.5 Unified Logger Trace (`os_log`)
Filter and stream real-time diagnostic logs from Taskbar subsystems:
```bash
# Stream all Taskbar logs
log stream --predicate 'subsystem == "com.local.taskbar"' --level debug

# Stream only Work Area Nudger clamping activity
log stream --predicate 'subsystem == "com.local.taskbar" AND category == "WorkArea"'

# Stream only AX Observer events
log stream --predicate 'subsystem == "com.local.taskbar" AND category == "Tracking"'
```

---

## 2. Xcode Instruments Profiling Runbook

To perform deep profiling via Xcode Instruments:

1. **Launch Instruments with Time Profiler:**
   ```bash
   xcrun xctrace record --template 'Time Profiler' --attach Taskbar --time-limit 15s --output /tmp/Taskbar_Time.trace
   ```
2. **Launch Instruments with Allocations & Leaks:**
   ```bash
   xcrun xctrace record --template 'Allocations' --attach Taskbar --time-limit 15s --output /tmp/Taskbar_Alloc.trace
   ```
3. **Open Trace in Instruments:**
   ```bash
   open /tmp/Taskbar_Time.trace
   ```

### What to Inspect in Instruments:
- **Heaviest Stack Trace:** Identify functions consuming the most CPU cycles.
- **Allocation Invert Tree:** Verify that transient heap allocations during window resize/move bursts settle back to baseline.
- **Generations:** Take baseline snapshot $\rightarrow$ perform 100 window operations $\rightarrow$ take second snapshot. Net growth should approach zero.
