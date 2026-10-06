# Performance Invariants & Architectural Thresholds

This document codifies the non-negotiable performance invariants and resource thresholds for the Taskbar application. Any proposed optimization or architectural change must honor these rules.

---

## 1. Concurrency & Threading Invariants

1. **Zero Main Thread AX Calls:**
   - No function from `<ApplicationServices/ApplicationServices.h>` prefixed with `AXUIElement` or `AXObserver` may execute on `@MainActor`.
   - All accessibility IPC calls must be serialized onto `AXThread.shared` or managed via background tasks.
2. **Mandatory AX Timeouts:**
   - Every `AXUIElementRef` must have an explicit timeout configured:
     ```swift
     AXUIElementSetMessagingTimeout(element, 0.3)
     ```
   - This ensures hung or misbehaving third-party apps never block the tracking thread for more than 300ms.
3. **Display Refresh Frame Coalescing:**
   - High-frequency window notifications must be coalesced into a **16ms window** (`TaskbarConstants.Timing.frameRenderDebounce = 0.016`).
   - Reconciliations must never be dispatched to the main thread faster than display frame intervals (60Hz / 120Hz).
4. **Thread-Safe AX Callback Lifetime Isolation:**
   - `AXObserver` C callbacks (`refcon`) must not retain or dereference deallocating host objects.
   - Host instances must pass an isolated `AXObserverContext` containing a `weak var target` and synchronize unmanaged releases via `AXThread.shared.async` after run loop source unregistration.

---

## 2. Memory & View Lifecycle Invariants

1. **In-Place View Recycling (`buttonMap`):**
   - Updates in `TaskbarView.updateWindows` and `updatePinnedButtons` must reuse existing subview instances (`TaskButton`, `PinnedButton`).
   - In-place recycling prevents:
     - Memory allocation spikes and garbage collection churn.
     - Tracking area flicker and cursor hitching.
     - Layout re-measurement cascades.
2. **Icon Cache Singleton & Deduplication:**
   - Icons must be cached per `bundleIdentifier` or file path in `IconCache`.
   - Multi-resolution sanitization must discard corrupt bitmaps ($< 64\text{px}$) without keeping multiple duplicate representations in RAM.
3. **Resident Set Size (RSS) Ceilings:**
   - Baseline idle RSS: $18\text{ MB} - 25\text{ MB}$.
   - Heavy load ceiling (100 windows, multiple displays): $< 45\text{ MB}$.
   - Any commit pushing baseline RSS above $45\text{ MB}$ will fail CI verification via `./scripts/test-functional.sh --stress`.

---

## 3. Clamping & Event Loop Invariants

1. **Self-Inflicted Notification Suppression:**
   - `WorkAreaEnforcer` must cache the sizes and timestamps of its programmatic `setSize` adjustments in `lastSelfNudges`.
   - Incoming `kAXWindowResizedNotification` events matching the target size within 350ms must be discarded to prevent infinite debounce loops.
2. **Active Drag Deferral:**
   - Clamping must be deferred when the left mouse button is pressed (`CGEventSource.buttonState`). WindowServer owns window geometry during live user dragging; attempting programmatic resizing during a drag causes cursor stutter and recursion limit exhaustion.
3. **Passive Move Protection:**
   - While an active resize debounce burst is in-flight (`windowWasResizedInDebounce[winID] == true`), passive move or periodic 16ms reconcile events (`!isResize`) must not bump debounce generation counters, guaranteeing settle passes (150ms / 400ms) execute without interruption.
