# Documentation & Plan Synchronization Guide

Use this runbook to audit documentation, specifications, and project plans against the actual codebase, preventing drift, staleness, and broken links across milestones.

---

## 1. Documentation Inventory & Scope

The Taskbar documentation matrix consists of three primary tiers:

| Tier | Directory / File | Key Responsibilities |
|---|---|---|
| **User & Contributor Gateway** | `README.md`, `CHANGELOG.md` | Feature highlights, quickstart commands, release notes, engineering principles. |
| **Architectural & Test Guides** | `docs/` | In-depth architecture, concurrency models, configuration schemas, conventions, testing taxonomy. |
| **Planning & Postmortems** | `plans/` | Project roadmap, milestone deliverables, bug postmortems, technical analysis documents. |

---

## 2. Synchronization Audit Steps

### Step 1: Version Numbers & Build Identifiers
Verify that the active version string is strictly identical across:
1. `config/build.env` (`APP_VERSION`, `BUILD_NUMBER`)
2. `Resources/Info.plist` (`CFBundleShortVersionString`, `CFBundleVersion`)
3. `Sources/TaskbarCore/Config/BuildConfiguration.swift` (`BuildConfiguration.appVersion`, `buildNumber`)
4. `CHANGELOG.md` (Top-level release heading)

---

### Step 2: Test Counts & Specification Traceability
Verify that reported test counts in documentation match reality:
1. Run `./scripts/test-functional.sh --all` and note total unit and integration tests.
2. Check that the test counts in:
   - `README.md` (e.g. `104 tests`)
   - `docs/TESTING.md` (Breakdown: Unit + Integration per suite)
   - `docs/TEST_SPECIFICATIONS.md` (Complete list of `TC-*` entries)
   accurately reflect the executed test count.
3. Verify that every test in `TEST_SPECIFICATIONS.md` is mapped in the **Requirements Traceability Matrix**.

---

### Step 3: Architecture & Mitigation Documentation
When new engineering mitigations, algorithms, or architectural patterns are introduced:
1. Update `docs/ARCHITECTURE.md` with:
   - Updated Mermaid diagrams illustrating event flow.
   - Specific engineering mitigations in relevant sections (e.g. Section 8 for `WorkAreaEnforcer`).
2. Update `docs/CONVENTIONS.md` if any new coding rules, concurrency guidelines, or safety patterns are established.

---

### Step 4: Configuration & Build Guide Alignment
Verify configuration references against actual code:
1. `docs/CONFIGURATION.md`:
   - Are all settings keys in `Sources/TaskbarCore/Config/Settings.swift` documented with default values and types?
   - Are all JSON theme keys (`ThemeDefinition`, `ThemePalette`, `ThemeMetrics`, `ThemeMaterials`) up to date?
2. `docs/BUILD_AND_RELEASE.md`:
   - Are all CLI flags for `build-app.sh`, `package-release.sh`, and `test-functional.sh` accurate?

---

### Step 5: Roadmap & Implementation Plans Alignment
1. `plans/roadmap.md`:
   - Mark completed milestone items as `[x]`.
   - Update current status, release versions, and timeline notes.
2. Milestone implementation plans (`plans/<milestone>/<milestone>_implementation_plan.md`):
   - Link all dedicated technical postmortems and analysis documents.
   - Update verification checklists with passing benchmark status.

---

### Step 6: Agent Skills Staleness Audit & Synchronization
Audit all skills under `.agents/skills/`:
1. Check that `SKILL.md` and reference runbooks in `.agents/skills/*/references/` reflect current architectural structures, target names, class hierarchies, and invariants.
2. Check that test counts and benchmark thresholds in skills match active project baselines (e.g. 112+ tests, $\le 45\text{ MB}$ RSS, $\sim 0.0\%$ idle CPU).
3. If new architectural patterns are introduced (e.g. `AXObserverContext`, `BaseTaskbarButton`, `TaskbarLayoutEngine`), ensure skill instructions do not prescribe obsolete patterns (e.g. direct unretained self unmanaged pointers or legacy callbacks).
4. Update stale skill markdown files directly to maintain accuracy for future pairing and autonomous agent tasks.
