# Taskbar Architecture & Design Document

This document provides a comprehensive technical breakdown of **Taskbar** architecture. It details the modular theming engine, built-in presets, external JSON theme loader, pinned applications bar, multi-resolution icon sanitization, view recycling, observer lifecycle hardening, work area clamping, focus isolation, and multi-display synchronization.

---

## 1. High-Level Architectural Overview

Taskbar is a native macOS agent application (`LSUIElement`) built using Apple frameworks (`AppKit`, `ApplicationServices`, `CoreGraphics`, `os`). Private WindowServer and SkyLight SPIs (`_AXUIElementGetWindow`, `_SLPSSetFrontProcessWithOptions`) are strictly isolated inside `PrivateAPI.swift` with safe public fallbacks, zero screen capture permissions, and zero polling loops.

```mermaid
flowchart TD
    subgraph Core ["TaskbarCore (Pure Swift / Cross-Platform Foundation)"]
        BC[BuildConfiguration]
        TL[TaskbarLogger]
        TD[ThemeDefinition & Tokens]
        PR[Presets: Modern, Retro, Luna, Dark]
        FL[ThemeFileLoader ~/.config/taskbar/themes]
        TR[ThemeRegistry Singleton]
        PA[PinnedApp Model]
        ST[Settings Persistence]
        WS[WindowStore & WindowInfo]
        WF[WindowFilter Rules]
        WM[WorkAreaMath Clamping]
        SA[ScreenAssignment Partitioning]
    end

    subgraph Kit ["TaskbarKit (macOS AppKit & Accessibility Engine)"]
        AP[AccessibilityPermission]
        AT[AppTracker & AXThread]
        AO[AXAppObserver Lifecycle]
        WE[WorkAreaEnforcer]
        DC[DockController]
        SM[ScreenManager Multi-Monitor Coordinator]
        TP[TaskbarPanel Floating Window]
        TV[TaskbarView Layout & Button Recycling]
        SB[StartButton]
        PB[PinnedButton Quick Launch]
        TB[TaskButton Window Button]
        OB[OverflowButton Chevron]
        IC[IconCache Multi-Resolution Sanitizer]
        MN[StatusMenu Dynamic Menu]
        WA[WindowActions Launcher & Activator]
    end

    subgraph App ["TaskbarApp (Executable)"]
        M[main.swift Entry Point]
    end

    subgraph Tests ["Test Targets"]
        UT[TaskbarCoreTests - Unit Tests]
        IT[TaskbarIntegrationTests - Swift Testing Suite]
    end

    M --> Kit
    Kit --> Core
    UT --> Core
    IT --> Kit
    IT --> Core
```

---

## 2. Modular Target Hierarchy

The codebase adheres strictly to a three-tiered library/executable structure to guarantee complete test isolation and zero binary circularity:

1. **`TaskbarCore` (Library Target):**
   - Independent of UI view hierarchies and `NSView` lifecycles.
   - Houses mathematical models, multi-edge placement domain models (`TaskbarEdge`), pure horizontal layout calculation engines (`TaskbarLayoutEngine`, `ButtonLayout`), window grouping and ordering logic (`WindowGroupingLogic`, `WindowOrderingLogic`), window filtering rules, coordinate clamping math (`WorkAreaMath`), configuration encoders/decoders, theme definitions and presets, file-based theme discovery, pinned application domain models, thread-safe `ThemeRegistry`, and unified `TaskbarLogger`.
   - 100% covered by headless unit tests in `TaskbarCoreTests` using modern `Swift Testing`.

2. **`TaskbarKit` (Library Target):**
   - Contains all macOS system integration and UI view code:
     - **Tracking & System:** `AppTracker` (delta-driven 3-tier AX router, circuit breaker, live AX recovery), `AXAppObserver`, `AXThread`, `WorkAreaEnforcer` (single-timer 3-pass settle, monotonic clock, zero GCD contention), `AppEnvironment` (dependency injection), `PrivateAPI` (isolated SkyLight/HIServices SPIs).
     - **UI Subsystems:**
       - **Buttons:** `BaseTaskbarButton` (with full VoiceOver `NSAccessibility` button role/label/press), `TaskButton`, `StartButton`, `PinnedButton`, `OverflowButton`.
       - **Panels & Popups:** `TaskbarPanel`, `TaskbarView` (single-pass change set pipeline, view recycling), `TaskbarDragCoordinator` (deduplicated drag kinds), `GroupWindowPopup`, `GroupWindowContentView`, `GroupWindowRowsView`, `BevelDrawing`.
       - **Menu:** `StatusMenu` (reactive settings subscription, zero NSStatusItem leaks).
       - **Management & Extensions:** `ScreenManager`, `NSScreen+DisplayID`, `NSColor+RGBA`, `IconCache` (multi-resolution raster cache with LRU eviction), `VisualEffectMapping`.
     - **Actions & System:** `WindowActions` (isolated process activation), `DockController` (in-process CFPreferences reader, serial queue writer, dirty sentinel crash recovery), `Launcher`, `AccessibilityPermission`, `AppDelegate`.
   - Publicly exported for deterministic integration testing in `TaskbarIntegrationTests` using `Swift Testing`.

3. **`TaskbarApp` (Executable Target):**
   - Lightweight executable wrapper containing only `main.swift`.
   - Installs POSIX signal handlers (`SIGINT`, `SIGTERM`, `SIGHUP`) and `atexit` hooks for guaranteed system Dock restoration, instantiates `AppDelegate`, and initiates `NSApplication.shared.run()`.

---

## 3. Modular Theming Engine & Preset Architecture

In v0.2.0, theming was refactored from monolithic definitions into modular, single-responsibility files under `Sources/TaskbarCore/Config/Theme/`:

```mermaid
flowchart LR
    TD[ThemeDefinition] --> TP[ThemePalette<br/>RGBAColor Tokens]
    TD --> TM[ThemeMetrics<br/>Padding, Radii, Sizing]
    TD --> MT[ThemeMaterials<br/>Vibrancy & Translucency]
    
    TR[ThemeRegistry Singleton] -->|Manages| TD
    TR -->|Built-in| MH["ModernHybridTheme"]
    TR -->|Built-in| RC["RetroClassicTheme"]
    TR -->|Built-in| XL["WindowsXPLunaTheme"]
    TR -->|Built-in| DM["DarkMinimalTheme"]
    TR -->|Runtime Scanned| TFL["ThemeFileLoader (~/.config/taskbar/themes/*.json)"]
```

### 3.1 Built-in Presets
1. **Modern Hybrid (`modern-hybrid`):** Native macOS frosted glass vibrancy (`NSVisualEffectView`), rounded pill buttons, subtle hover translucency, and `SF Pro` system typography.
2. **Retro Classic (`retro-classic`):** Authentic Windows 95/98 `#C0C0C0` solid gray background, 1pt white highlight border, classic 3D beveled borders (`BevelDrawing`), and retro typography.
3. **Windows XP Luna (`windows-xp-luna`):** Authentic Windows XP Luna classic blue (`#245EDC` / `#1642A5`), signature emerald green Start button (`#388E3C` / `#43A047`) with gold accent, royal blue active buttons (`#1941A5`) with border bevels, and sky-blue hover highlights.
4. **Dark Minimal (`dark-minimal`):** Pitch black (`#121212`) background with subtle border delimiter, flat minimal hover rectangles, active indicator border (`#00BCD4` cyan), and distraction-free typography.

### 3.2 User Custom Theme Loader (`ThemeFileLoader`)
- **Canonical Storage:** `~/.config/taskbar/themes/` (with fallback to `~/Library/Application Support/Taskbar/Themes/`).
- **Discovery Lifecycle:**
  - Auto-discovers all `*.json` files on startup and upon on-demand "Reload Themes from Disk" requests.
  - Validates non-empty `id` and skips collisions with built-in preset IDs to prevent overriding default presets.
  - Deserializes gracefully with structured error logging without interrupting app execution or crashing.
  - Automatically injects discovered themes into `ThemeRegistry` and marks them with `isCustom: true`.
- **Export Facility:** Exports any currently active theme as a formatted, pretty-printed JSON file directly to disk or via an interactive save panel.

---

## 4. Pinned Applications & Quick Launch Bar

Version `0.2.0` introduces a native Quick Launch bar providing instant access to pinned applications directly from the taskbar on all connected displays.

```mermaid
flowchart TD
    subgraph Data ["Data & Persistence"]
        PA[PinnedApp Model<br/>bundleID, displayName, customPath]
        ST[Settings Persistence<br/>pinnedApps: PinnedApp]
    end

    subgraph Management ["Multi-Display Coordination"]
        SM[ScreenManager]
        SM -->|Synchronizes| P1[TaskbarPanel Screen 1]
        SM -->|Synchronizes| P2[TaskbarPanel Screen 2]
    end

    subgraph UI ["Component Hierarchy"]
        TV[TaskbarView]
        SB[Start Button]
        PB[PinnedButton Quick Launch Items]
        TB[TaskButton Dynamic Window Items]
        OV[Overflow Chevron]
        
        TV --> SB
        TV --> PB
        TV --> TB
        TV --> OV
    end

    ST --> SM
    PA --> ST
```

### 4.1 Horizontal Geometry & Layout
On every connected display, `TaskbarView` arranges subviews horizontally:
1. **Start Button:** Fixed width at `x = buttonSpacing`.
2. **Pinned Apps Bar:** Fixed compact square buttons ($w = \text{height} - 2 \times \text{padding}$) for each pinned application, separated by `pinnedButtonSpacing = 2.0pt` and followed by `pinnedSectionTrailingMargin = 6.0pt`.
3. **Dynamic Task Buttons:** Auto-stretching or shrinking task buttons for open windows on that display.
4. **Overflow Chevron (`»`):** Appears automatically if window density forces buttons below `minButtonWidth`.

### 4.2 Interaction Mechanics
- **One-Click Launch & Raise:**
  - If target application is not running: Launches via `NSWorkspace.shared.openApplication(at:configuration:)`.
  - If target application is running: Activates process, deminiaturizes minimized windows, and raises the frontmost window.
- **Running Indicator:**
  - A subtle running indicator dot/badge renders at the bottom center of the pinned button whenever one or more windows belonging to that application are open.
  - Theme-adaptive: Dark/black in Retro bevel mode; theme accent color (`#00BCD4`, emerald, or theme highlight) in Modern Hybrid, Luna, and Minimal modes.
- **Context Menus:**
  - **On `PinnedButton`:** "Open <App>", "Unpin from Taskbar", and "Quit <App>" (when running).
  - **On `TaskButton`:** Dynamic "Pin to Taskbar" / "Unpin from Taskbar" toggle item. Pinning or unpinning synchronizes instantly across all connected screens.

### 4.3 High-DPI & Multi-Resolution Icon Sanitization
Application bundles (particularly Electron or older apps like Antigravity) occasionally contain corrupted or uninitialized 16x16 / 32x32 bitmap representations inside their `.icns` file while providing clean high-resolution assets (64px, 128px, 256px, 512px).
- On Retina screens (2.0x), AppKit selects clean `@2x` assets.
- On non-Retina screens (1.0x), AppKit defaults to matching 1x point sizes, drawing corrupt noise.
- **`IconCache.prepareIcon(_:targetSize:)`:** When an icon bundle contains representations $\ge 64\text{px}$, all representations $< 64\text{px}$ are stripped. This forces AppKit to downsample from the pristine high-resolution bitmaps using smooth bilinear anti-aliasing on 1x displays, eliminating visual corruption across mixed-DPI multi-monitor environments.
- **Dimension-Aware Cache Keys:** Cache keys incorporate dimensions (`\(baseKey)_\(width)x\(height)`), ensuring cached representations resize properly when `settings.iconSize` changes.

---

## 5. View Recycling & In-Place Performance

To maintain low memory usage ($< 25\text{ MB}$ typical RSS) and eliminate mouse tracking area flicker during frequent window operations:
- **`TaskButton` Recycling:** `TaskbarView` maintains `groupButtonMap: [String: TaskButton]`. Buttons are recycled in place, preserving existing views and mouse tracking areas.
- **`PinnedButton` Recycling:** `TaskbarView` maintains `pinnedButtonMap: [String: PinnedButton]`, reusing existing pinned button instances across layout updates.
- **Idle CPU:** $\sim 0.0\%$ at idle; no polling loops; state changes driven exclusively by asynchronous event notifications.

---

## 6. Accessibility Observer Lifecycle & Coalescing

- **Dynamic Subrole Filtering:** macOS Accessibility dynamically morphs minimized Cocoa windows into `AXDialog` subroles when minimized to the Dock. `WindowFilter.shouldInclude` allows `AXDialog` subroles when `isMinimized == true` to prevent dropping minimized windows.
- **In-Flight Observer Coalescing & Tiered Routing:** `AppTracker` uses a 3-tier event pipeline (Tier 1 focused window, Tier 2 per-PID targeted diffing via `syncSnapshot(forPID:)`, and Tier 3 periodic background sweep) to eliminate full reconciliation bottlenecks.
- **Clean Notification Teardown:** Explicitly unregisters all window and application notifications via `AXObserverRemoveNotification` prior to clearing run loop sources in `AXAppObserver`.

---

## 7. Multi-Display & Workspace Window Focus Isolation (`WindowActions`)

In multi-window and multi-monitor environments, activating an application using standard AppKit APIs (`NSRunningApplication.activate()`) causes macOS to bring *all* windows belonging to that application to the front across *all* connected displays and desktops. This behavior disrupts user focus (e.g. clicking a browser window on Monitor 2 or in a group list pops background browser windows forward on Monitor 1, burying intervening windows from other applications).

To guarantee strict single-window focus and multi-display isolation:
- **Native Window ID Resolution:** In `AXElement+Attributes.swift`, `windowID` resolves the native `CGWindowID` via dynamic link to `_AXUIElementGetWindow`, ensuring numerical window identifiers match WindowServer.
- **Targeted AX Window Elevation:** `WindowActions.performAction(.focus, for: key)` locates the specific `AXUIElement` window for the requested key, executes `AXUIElementPerformAction(window, kAXRaiseAction)`, and sets `kAXMainAttribute` to `true`.
- **Single-Window Process Activation:** Instead of AppKit's `NSRunningApplication.activate` (which brings the entire application window group forward), `WindowActions.activateSingleWindow` delegates to `PrivateAPI.activateSingleWindow`, targeting the specific window via Carbon and SkyLight WindowServer APIs:
  ```swift
  // 1. Activate process front window only (kSetFrontProcessFrontWindowOnly = 0x0001)
  SetFrontProcessWithOptions(&psn, 1)

  // 2. Target specific window ID in WindowServer (kCPSUserGenerated = 0x200)
  _SLPSSetFrontProcessWithOptions(&psn, windowID, 0x200)
  ```
- **Outcome:** Only the targeted window is raised and given keyboard focus; sibling windows of the same application on any screen remain undisturbed behind intervening windows from other applications in their existing on-screen z-order.

---

## 8. Work Area Clamping Architecture (`WorkAreaEnforcer`)

macOS lacks an official API like Windows' `SHAppBarMessage` or X11's `_NET_WM_STRUT` to reserve screen edge space for third-party docks. `WorkAreaEnforcer` enforces taskbar screen reservation by monitoring window geometry and clamping maximized window heights above the taskbar boundary.

```mermaid
flowchart TD
    AX["AXObserver Event:<br/>Window Moved / Resized"] --> ThreadCheck["AXThread Serial Execution"]
    ThreadCheck --> MouseCheck{"Left Mouse Button<br/>Down CGEventSource?"}
    MouseCheck -- Yes --> Defer["Defer Clamping Until<br/>Mouse Released"]
    MouseCheck -- No --> Debounce["Single-Deadline Debounce<br/>WorkAreaConstants.debounceIntervalSeconds"]
    
    Debounce --> Eval["WorkAreaMath.clampedFrame<br/>Pure Geometry Calculation"]
    Eval --> OverlapCheck{"Window Overlaps<br/>Taskbar Reserved Region?"}
    
    OverlapCheck -- No --> Done["Window Settled"]
    OverlapCheck -- Yes --> Clamp["Apply element.setSize<br/>Record Programmatic Clamp"]
```

### 8.1 Key Engineering Mitigations
1. **Self-Inflicted Notification Filtering:**
   Calling `element.setSize(clampedFrame.size)` triggers an operating system `kAXWindowResizedNotification`. `WorkAreaEnforcer` caches the exact programmatic clamp size and timestamp (`lastSelfNudges`). When incoming resize events match the target size, they are filtered out to prevent feedback loops.
2. **Active Mouse Drag Deferral:**
   During live mouse resizing, WindowServer binds the window edge to the cursor coordinates. Calling `setSize` while the left mouse button is pressed causes visible cursor jitter. `WorkAreaEnforcer` checks `CGEventSource.buttonState(.combinedSessionState, button: .left)` and defers clamping until the mouse is released.
3. **Single-Deadline Settle Verification on AXThread:**
   Debounced event coalescing runs with zero `NSLock` overhead directly on dedicated `AXThread`, coordinating single-deadline clamping passes to accommodate animation and frame settle without timer chaining.
4. **Dynamic Screen Descriptors:**
   `ScreenManager` supplies immutable `[ScreenDescriptor]` instances to `WorkAreaEnforcer.updateScreens`, eliminating main-thread `NSScreen` queries on `AXThread`.
5. **Resilient Window Notification Observation:**
   `AXAppObserver` registers `kAXWindowResizedNotification` and `kAXWindowMovedNotification` at the window level, avoiding redundant observation overhead and locking on 60–120Hz window drags.
6. **In-Flight Resize Debounce Protection:**
   When an active resize debounce burst is in-flight (`windowWasResizedInDebounce[winID] == true`), passive move or periodic window reconciliation events (`!isResize`) arriving within the settle window are ignored. This prevents `generationCounters[winID]` from incrementing prematurely, ensuring that Pass 1 (220ms) and Pass 2 (500ms) execution are not cancelled before clamping occurs.
7. **TCC Authorization Polling & Dynamic Observer Attachment:**
   On ad-hoc rebuilt binaries where TCC cdhash trust verification is asynchronous at startup, `AppTracker` polls authorization for up to 30 seconds via a background task. As soon as permission is confirmed, all running applications are immediately tracked. Furthermore, `handleAppActivated` dynamically attaches observers to active applications upon focus, guaranteeing immediate window maximize responsiveness.
8. **Resilient Window Observer Registration:**
   `AXAppObserver` only marks a window as observed (`observedWindows.insert(winID)`) if at least one core AX notification registration succeeds, allowing transparent retry on subsequent events rather than silently abandoning registration.
9. **Startup Configuration Precedence:**
   `WorkAreaEnforcer.shared.configure` is executed prior to `ScreenManager` display panel instantiation, guaranteeing accurate custom taskbar height reservation from the moment of launch.

---

## 9. Custom Theme Engine & Dynamic Layout Metric Adoption

Taskbar provides a modular, data-driven theming architecture supporting both built-in presets (`modern-hybrid`, `retro-classic`, `windows-xp-luna`, `dark-minimal`) and user-authored JSON themes loaded dynamically from disk.

```mermaid
flowchart LR
    Disk["~/.config/taskbar/themes/*.json"] --> Loader["ThemeFileLoader"]
    Loader --> Reg["ThemeRegistry.shared"]
    Reg --> Menu["StatusMenu UI<br/>(Theme Submenu)"]
    
    Menu -- "Click Custom Theme" --> IDChange["onThemeIdChanged(themeId)"]
    IDChange --> Settings["Settings.activeThemeId = themeId"]
    IDChange --> SM["ScreenManager.updateTheme(themeId)"]
    
    SM --> Metrics["Adopt ThemeMetrics:<br/>barHeight, minButtonWidth,<br/>buttonSpacing, fontSize, iconSize"]
    SM --> Panels["TaskbarPanel.apply(settings:theme:)"]
    SM --> Nudger["WorkAreaEnforcer.barHeight = customHeight"]
```

### 9.1 Callback Architecture & Invariant Enforcement
- **Unified Event Flow:** All theme activation flows through `onThemeIdChanged(String)`. In earlier iterations, `StatusMenu` also invoked a legacy `onThemeChanged(ThemeStyle)` callback, which clobbered custom theme selections back to `.modernHybrid` because custom themes are not built-in enum presets.
- **Strict Invariant:** Theme lifecycle events flow exclusively through `onThemeIdChanged(String)`. The legacy `onThemeChanged(ThemeStyle)` callback has been retired from `StatusMenu`, ensuring unified handling across built-in presets and user custom themes with zero enum clobbering.

### 9.2 Dynamic Layout Metric Adoption
- **Extended Theme Metrics (`ThemeMetrics`):** Theme JSON definitions can optionally specify layout dimensions:
  ```json
  "metrics": {
    "barHeight": 64.0,
    "minButtonWidth": 50.0,
    "maxButtonWidth": 250.0,
    "buttonSpacing": 10.0,
    "fontSize": 8.0,
    "iconSize": 48.0,
    "buttonCornerRadius": 25.0,
    "is3DBeveled": true
  }
  ```
- **Panel & Work Area Propagation:** When switching to a custom theme, `ScreenManager.updateTheme` adopts the theme's custom `fontSize`, `iconSize`, `barHeight`, `minButtonWidth`, `maxButtonWidth`, and `buttonSpacing`:
  1. Updates `settings` and persists to `UserDefaults`.
  2. Updates `WorkAreaEnforcer.shared.barHeight` so maximized windows clamp to the new taskbar height.
  3. Calls `refreshPanels()` to resize panels across all connected displays.
  4. Synchronizes Status Menu checkmarks and submenus (`barHeight`, `fontSize`, `iconSize`, `minButtonWidth`).

### 9.3 Dynamic Visual Effect Materials & Blending Modes (`ThemeMaterials`)
- **AppKit Vibrancy Decoupling:** In `TaskbarCore`, `ThemeMaterials` decodes `useTranslucency`, optional `material: String?`, and optional `blendingMode: String?` without coupling the core data layer to AppKit.
- **Dynamic Resolution (`VisualEffectMapping`):** `TaskbarKit` normalizes and resolves theme tokens to native AppKit visual effect properties:
  - `NSVisualEffectView.Material`: `"hudWindow"`, `"windowBackground"`, `"popover"`, `"sidebar"`, `"menu"`, `"headerView"`, `"sheet"`, `"selection"`, `"titlebar"`, `"toolTip"`, `"contentBackground"`, `"underPageBackground"`, `"fullScreenUI"`, defaulting safely to `.underWindowBackground`.
  - `NSVisualEffectView.BlendingMode`: `"behindWindow"` (samples desktop wallpaper and underlying windows) or `"withinWindow"` (samples content within the taskbar window itself), defaulting to `.behindWindow`.
- **Runtime Application:** `TaskbarView.applyTheme()` dynamically updates `visualEffectView.material`, `visualEffectView.blendingMode`, and `visualEffectView.isHidden` across all display panels immediately upon theme selection without requiring an application restart.

---

## 10. Application Window Grouping & Lightweight Popup Architecture

Taskbar provides configurable application window grouping to declutter the taskbar in multi-window workflows while maintaining instantaneous window switching.

```mermaid
flowchart TD
    Store["WindowStore.windows(forScreenID)"] --> WGL["WindowGroupingLogic.groupWindows()"]
    Mode["WindowGroupingMode:<br/>.always | .whenCrowded | .never"] --> WGL
    WGL --> Groups["[WindowGroup]"]
    CustomOrder["WindowStore.customOrders[screenID]"] --> WOL["WindowOrderingLogic.applyCustomOrder()"]
    Groups --> WOL
    WOL --> Ordered["Ordered [WindowGroup]"]
    Ordered --> TV["TaskbarView (groupButtonMap Recycling)"]
    TV --> TB["TaskButton (Badge Pill / Ridge Bevel)"]
    
    TB -- "Click (count > 1)" --> Popup["GroupWindowPopup (NSPanel)"]
    Popup -- "Select Row / Enter" --> Focus["WindowActions.restoreAndFocusWindow()"]
    Popup -- "Click Close (✕)" --> Close["WindowActions.closeWindow()"]
```

### 10.1 Grouping Modes & Pure Business Logic
- **`WindowGroupingMode` (`TaskbarCore`):**
  - `.always`: Groups all windows sharing the same `bundleID` into a single button.
  - `.whenCrowded`: Dynamically computes total required width (`count * minWidth + (count - 1) * spacing`). If required width exceeds available taskbar width, automatically groups multi-window applications to prevent button truncation.
  - `.never`: Disables grouping entirely; preserves 1-to-1 window buttons.
- **`WindowGroup` (`TaskbarCore`):**
  - Immutable value type encapsulating `id`, `bundleID`, `appName`, `windows: [WindowInfo]`, and `isGrouped`.
  - Provides computed states (`isFocused(focusedKey:frontmostPID:)`, `isMinimized`, `isAppHidden`, `displayTitle`).
  - Single windows use `id = "win_<pid>_<id>"`; multi-window groups use `id = "group_<bundleID>"`.
- **`WindowGroupingLogic` (`TaskbarCore`):**
  - Pure function mapping `([WindowInfo], WindowGroupingMode, availableWidth) -> [WindowGroup]`.
  - Allocates zero AppKit views; 100% unit tested in `WindowGroupingLogicTests`.

### 10.2 Lightweight Window List Popup (`GroupWindowPopup`)
- **Panel Characteristics & Visual Layer Separation:**
  - Lightweight borderless `NSPanel` (`.nonactivatingPanel`, floating above desktop).
  - Uses an explicit two-layer subview hierarchy: a background `NSVisualEffectView` maintaining frosted glass vibrancy, and a distinct foreground `GroupWindowContentView` hosting interactive `GroupWindowRowView` subviews to eliminate subview clobbering.
  - Anchored dynamically above the clicked group button on the target screen.
  - Renders application icon, document/window title (truncated with ellipsis), active window dot indicator, and dedicated close button (`✕`).
- **Immediate Single-Click Responsiveness:**
  - `GroupWindowRowView` and close buttons override `acceptsFirstMouse(for:) -> true`, ensuring first clicks immediately activate and focus the chosen window or trigger window closure without requiring an initial focus click.
- **Auto-Dismissal & Event Monitoring:**
  - Dismisses cleanly on `Escape`, row selection, or loss of key window focus (`windowDidResignKey`).
  - Active global and local event monitors detect clicks outside the popup bounds and immediately close the panel.
- **Keyboard Navigation & Accessibility:**
  - `Up` / `Down` arrow keys navigate and highlight rows.
  - `Return` / `Enter` focuses and raises the selected window, dismissing the popup.
- **Context Menu Integration:** Right-clicking a grouped button offers "Close All Windows", "Quit Application", and "Pin to Taskbar" / "Unpin from Taskbar".

---

## 11. Interactive Drag-and-Drop Slot Reordering Architecture

Taskbar implements real-time horizontal drag-and-drop reordering with live visual feedback, insertion indicator bars, and strict multi-display isolation.

```mermaid
sequenceDiagram
    participant User as User Interaction
    participant Button as BaseTaskbarButton
    participant View as TaskbarView
    participant Logic as WindowOrderingLogic
    participant Store as WindowStore / Settings

    User->>Button: mouseDown & mouseDragged (> 4pt threshold)
    Button->>View: onDragStarted & onDragged(location)
    View->>View: Compute insertion slot via TaskbarLayoutEngine
    View->>View: Update insertionIndicatorView frame (Option B)
    User->>Button: mouseUp (Drop)
    Button->>View: onDragEnded(cancelled: false)
    View->>Logic: moveItem(items, fromIndex, toIndex)
    View->>Store: Commit orderMap to WindowStore (Task) or Settings (Pinned)
    View->>View: Re-layout taskbar with updated button slots
```

### 11.1 Drag Session Lifecycle & UX (Option B: Insertion Bar)
- **Threshold Detection:** `BaseTaskbarButton` initiates drag sessions only after cursor movement exceeds `TaskbarConstants.Drag.activationThreshold` (4.0pt), distinguishing rapid click/focus interactions from intentional drags.
- **Insertion Indicator Bar:** `TaskbarView` renders a high-contrast insertion bar (`insertionIndicatorView`) positioned at slot boundaries calculated via `TaskbarLayoutEngine.taskInsertionIndicatorX` and `pinnedInsertionIndicatorX`.
- **Dragged Button Visuals:** The dragged button shifts opacity to `draggedButtonAlpha` (0.85) and elevates its layer `zPosition` to render smoothly above neighboring items during motion.
- **Session Cancellation:** Moving the cursor vertically beyond `TaskbarConstants.Drag.verticalEscapeThreshold` (30.0pt) or pressing the `Escape` key immediately cancels the drag session, smoothly restoring buttons to their original slots.

### 11.2 Storage & Multi-Display Isolation
- **Running Task Buttons:**
  - Strongly-typed custom ordering dictionaries (`[OrderKey: Int]`) are maintained per physical display in `WindowStore.customOrders[screenID]`.
  - When committing drops, `orderMap` indexes both `WindowGroup.id` and all constituent window keys (`TaskbarConstants.Identifiers.windowID`), ensuring consistent ordering regardless of grouping mode transitions.
  - Moving a window to another screen in macOS migrates the window without disrupting either display's custom slot order.
- **Quick Launch Pinned Buttons:**
  - Pinned applications are global launchers. Dragging a pinned button on any monitor reorders `settings.pinnedApps`, immediately writes to disk, and broadcasts the new pinned order across all connected displays via `ScreenManager.updatePinnedApps` in lockstep.
