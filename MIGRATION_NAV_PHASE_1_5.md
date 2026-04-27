# Migration: Phase 1.5 — Navigation Refactor

**Status: COMPLETE — landed 2026-04-27.**

| Step | Commit |
|---|---|
| 1 — Sidebar replaces top tabs | `ca5d7ea` |
| 2 — Freeplay destination, primitive consolidation | `5012c1a` |
| 3 — Plans destination placeholder | `55d282d` |
| 4 — Home rebuilt as launcher | `c472926` |

**For the agent doing the work.** Read this entire document, then `DESIGN_SYSTEM.md`, then `LESSON_PRIMITIVES.md`, before touching any code. The plan below tells you what to change; `DESIGN_SYSTEM.md` is the authoritative spec for the target architecture.

---

## Context (read first)

The Audie macOS SwiftUI app currently uses a top tab bar with 7 destinations: Home, Tune, Contour, Intervals, Identify, Progress, Settings. Three of those tabs (Contour, Intervals, Identify) are exercise primitives — internal building blocks that should not be top-level destinations. With 12 primitives planned (see `LESSON_PRIMITIVES.md`), per-primitive navigation will not scale.

The target is a `NavigationSplitView` sidebar with 6 fixed destinations: **Home / Tune / Plans / Freeplay / Progress / Settings**. Primitives surface only inside Freeplay (direct testing) or active sessions launched from Plans/Home. This sidebar shape is final — adding new primitives never grows the sidebar.

Full architecture rationale is in `DESIGN_SYSTEM.md` "App architecture" and "Navigation" sections. Phase 2 work (LessonRunner, `.etplan` parsing, default plan bundling) is tracked separately in `PLAN.md` Phase 2 and is **not** part of this migration.

## Project facts

- Repo root: `/Users/jstegeman/.superset/worktrees/eartrain/translucent-bluebell`
- Current branch: `translucent-bluebell`
- Build: `cd EarTrain && swift build` (must pass after every step)
- This project uses **git**, not jujutsu. Use `git`, never `jj`.
- Commit cadence: one commit per migration step. Commit messages include `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>`.

## Ground rules

1. **Each of the 4 steps below is independently shippable.** After step N, the app must build and run with no broken flows. If you can't verify a step, stop and ask.
2. **Read `DESIGN_SYSTEM.md` before each step.** The spec is the source of truth; this migration plan is operational guidance only.
3. **Don't bundle steps.** One step = one commit. Don't merge step 2 into step 1 even if it seems convenient.
4. **Don't touch primitive view internals.** `ContourView`, `ExerciseView`, `IdentificationView` keep their existing exercise logic. Migration only changes how they're reached.
5. **Don't introduce new tokens, fonts, or colors.** Use what's in `EarTrainColors`. Anything that needs a new component goes in `DESIGN_SYSTEM.md` first.
6. **Don't fix unrelated bugs or refactor adjacent code.** If you spot something, add it to `TODOS.md` and move on.
7. **Build after each edit.** `swift build` from the `EarTrain/` directory. If it fails, fix before continuing.

---

## Step 1 — Replace top tabs with NavigationSplitView sidebar

**Goal:** Convert `ContentView`'s top tab bar to a left sidebar (`NavigationSplitView`). All 7 current destinations remain reachable. Pure structural change, zero behavioral changes.

**Files to read first:**
- `EarTrain/Sources/EarTrainLib/ContentView.swift` (current top-tab implementation, `modePicker` ViewBuilder, `AppMode` enum)
- `DESIGN_SYSTEM.md` "Navigation" section

**Changes:**

1. In `ContentView.swift`, replace the current `VStack { modePicker; modeContent }` body with:
   ```swift
   NavigationSplitView {
       sidebarList            // new ViewBuilder
   } detail: {
       modeContent
   }
   .navigationSplitViewStyle(.balanced)
   ```

2. Implement `sidebarList` as a `List(selection: $mode)`:
   - Iterate `AppMode.allCases`
   - Each row is a `Label(mode.label, systemImage: mode.icon)`
   - Use `.tag(mode)` for selection binding
   - Set sidebar width: `.navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)`
   - Background: `EarTrainColors.bg` for the sidebar surface

3. Delete the `modePicker` ViewBuilder entirely — it's replaced by the sidebar.

4. Sidebar item ordering (keep current `AppMode.allCases` order for now): Home, Tune, Contour, Intervals, Identify, Progress, Settings.

**Acceptance:**
- App launches with a left sidebar showing 7 items, each with icon + label.
- Selecting a sidebar row swaps the detail area to that destination.
- All 7 existing flows (start a session in each exercise mode, open Settings, view Progress, use Tuner) work identically to before.
- Active row in the sidebar is visually distinguished using `EarTrainColors.accent` (SwiftUI's default selection styling on macOS uses the system accent — verify it reads as amber; if not, customize the row background).
- Sidebar uses SF Symbol icons from `AppMode.icon` (already defined).
- No top tab bar remnants.

**Verify:**
```bash
cd EarTrain && swift build 2>&1 | grep -E "error:|Build complete"
```
Then launch the app and click through every sidebar item. Start a session in Contour, Intervals, and Identify each. Confirm all return to home/exit cleanly.

**Commit:**
```
refactor(nav): replace top tab bar with NavigationSplitView sidebar

Pure structural change — sidebar shows the same 7 destinations as the
previous tab bar. Behavioral parity preserved. Foundation for the
Plans/Freeplay consolidation in subsequent migration steps.

See DESIGN_SYSTEM.md "Navigation" and MIGRATION_NAV_PHASE_1_5.md step 1.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

---

## Step 2 — Add Freeplay destination, consolidate primitive entries

**Goal:** Replace the three direct primitive sidebar items (Contour, Intervals, Identify) with a single Freeplay destination that lists every built primitive and launches them.

**Files to read first:**
- `LESSON_PRIMITIVES.md` (canonical primitive list — only `built` status today: `contour`, `interval-id`, `interval-playback`)
- `EarTrain/Sources/EarTrainLib/ContourView.swift`, `IdentificationView.swift`, `ExerciseView.swift` (existing entry points)
- `EarTrain/Sources/EarTrainLib/ContentView.swift` (after step 1)
- `DESIGN_SYSTEM.md` "Freeplay" section

**Changes:**

1. Edit `AppMode` enum in `ContentView.swift`:
   - Remove cases: `.contour`, `.intervals`, `.identification`
   - Add case: `.freeplay`
   - Update `label`, `icon`, `exerciseDescription` accordingly. Suggested icon: `"square.grid.2x2"` or `"dial.medium"`. Label: "Freeplay".
   - New `AppMode.allCases` order: `.home`, `.tuner`, `.freeplay`, `.progress`, `.settings`.

2. Create new file `EarTrain/Sources/EarTrainLib/FreeplayView.swift`:
   - Public struct `FreeplayView: View`
   - Init takes the same dependencies the three primitive views currently take (probably `session: AppSession` or the individual VMs + audio + companion + activeMode + selectedDuration bindings — check `ContentView.modeContent` to see how they're constructed today, mirror that)
   - Body: a card grid (or `LazyVGrid`) listing the three built primitives. Each card shows:
     - Primitive display name ("Contour", "Interval ID", "Interval Playback")
     - One-line description (steal from `LESSON_PRIMITIVES.md` "What it trains" lines)
     - SF Symbol icon
     - "Start" button → routes to the corresponding existing view
   - Routing: maintain a `@State private var activePrimitive: BuiltPrimitive?` enum and present the existing view as a full-cover (`.fullScreenCover` or by swapping content). Each primitive launching sequence should reuse the existing `ExerciseReadyView` pattern that ContourView/ExerciseView/IdentificationView already wrap.
   - Layout principles: dark background (`EarTrainColors.bg`), surface cards (`EarTrainColors.surface`), corner radius 12. Follow `DESIGN_SYSTEM.md` spacing and typography rules.
   - Section header at top: `Text("FREEPLAY").textCase(.uppercase)` + tagline "Pick a primitive to drill directly. Sessions log to your stats but don't affect any active plan."

3. Update `ContentView.modeContent` to route `.freeplay` to `FreeplayView`. Remove the `case .contour:`, `case .intervals:`, `case .identification:` branches.

4. Verify all references to the removed enum cases are gone. Search the codebase: `grep -rn "AppMode\.contour\|AppMode\.intervals\|AppMode\.identification" EarTrain/Sources/`. Update any callers (probably onboarding or recommendation logic in `HomeView`/`ProgressStore`).

   **If the recommendation system in `HomeView` references the removed cases**, update it to route through `.freeplay` (and pass the desired primitive as a parameter) or to start a session another way. Specifics depend on what's there — read first, then decide. If this gets non-trivial, defer recommendation routing to step 4 and put a `// TODO step 4: route through Home launcher` comment.

**Acceptance:**
- Sidebar shows 5 items: Home, Tune, Freeplay, Progress, Settings.
- Clicking Freeplay shows a screen with three primitive cards.
- Clicking each card enters that primitive's existing flow (ready screen → active session → end-of-session sheet).
- All three exercise flows work identically to before.
- No reference to `.contour`, `.intervals`, or `.identification` remains in `AppMode`.
- The app builds cleanly: `swift build` returns "Build complete!" with no warnings new in this step.

**Verify:**
- `swift build` → pass
- Launch app, click Freeplay → see three primitives → click each, run a few trials, end session, return to Freeplay
- `grep -rn "\.contour\|\.intervals\|\.identification" EarTrain/Sources/` should only match unrelated uses (e.g., `Interval.intervals`, contour-related model logic, etc. — not `AppMode` cases)

**Commit:**
```
feat(nav): add Freeplay destination, consolidate primitive entries

Replaces the three direct primitive sidebar items (Contour, Intervals,
Identify) with a single Freeplay destination listing all built primitives.
Future primitives auto-appear in this grid without sidebar growth.

Sidebar: Home, Tune, Freeplay, Progress, Settings (5 items, pre-Plans).

See DESIGN_SYSTEM.md "Freeplay" and MIGRATION_NAV_PHASE_1_5.md step 2.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

---

## Step 3 — Add Plans destination with placeholder library

**Goal:** Add the Plans sidebar destination and a placeholder Plans library view. The actual `.etplan` parsing and `LessonRunner` are Phase 2 work — this step delivers only the navigation surface and a card-grid skeleton.

**Files to read first:**
- `DESIGN_SYSTEM.md` "Plans library" section
- `PLAN.md` Phase 2 (so you understand what Plans will eventually do)

**Changes:**

1. Edit `AppMode` enum:
   - Add case: `.plans`
   - Suggested icon: `"book.closed"` or `"list.bullet.rectangle"`. Label: "Plans".
   - Updated `AppMode.allCases` order: `.home`, `.tuner`, `.plans`, `.freeplay`, `.progress`, `.settings`.

2. Create new file `EarTrain/Sources/EarTrainLib/PlansView.swift`:
   - Public struct `PlansView: View`
   - Init takes `@Binding var activeMode: AppMode` (and any deps for showing stats — keep minimal)
   - Body shows two sections:
     - "Active Plan" card at the top — placeholder reading "No active plan yet" with a subtitle "Plan running comes in Phase 2 — for now, use Freeplay or Drill My Misses."
     - "Available Plans" — a grid of two placeholder cards: "Beginner CI" and "Intermediate". Each card shows the plan name, a fake step count ("12 steps · ~6 sessions"), and a tagline. Tapping a card opens a sheet with a placeholder message "Plan running coming in Phase 2 (see PLAN.md). For now, try Freeplay or Drill My Misses on Home."
   - Use the design system: surface cards, accent for headlines, secondary text for descriptions.
   - Section header: `Text("Plans").textCase(.uppercase)` style.

3. Update `ContentView.modeContent` to route `.plans` to `PlansView`.

**Acceptance:**
- Sidebar shows 6 items in order: Home, Tune, Plans, Freeplay, Progress, Settings.
- Plans destination renders without errors.
- Two placeholder plan cards appear; clicking one shows the "coming in Phase 2" sheet, which is dismissible.
- No regressions in any other flow.

**Verify:**
- `swift build` → pass
- Launch, click Plans, click a plan card, dismiss sheet, navigate elsewhere, come back. No crashes, no broken state.

**Commit:**
```
feat(nav): add Plans destination with placeholder library

Adds the Plans sidebar entry and a card-grid library view. Active plan
slot and bundled plan placeholders are stubbed; actual .etplan loading
and LessonRunner arrive in Phase 2 (see PLAN.md).

Sidebar reaches its final shape: Home, Tune, Plans, Freeplay, Progress,
Settings (6 items, fixed forever).

See DESIGN_SYSTEM.md "Plans library" and MIGRATION_NAV_PHASE_1_5.md step 3.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

---

## Step 4 — Rebuild Home as multi-mode launcher

**Goal:** Replace the centered Audie-avatar Home screen with a launcher dashboard. Two states: with-active-plan (Continue is the spine) and no-active-plan (Drill My Misses is the spine). Today, the no-plan state is the default since plans don't run yet — that's fine; the with-plan state can be stubbed and wired up in Phase 2.

**Files to read first:**
- `EarTrain/Sources/EarTrainLib/HomeView.swift` (current implementation)
- `designs/wireframes.html` (the home wireframe — for stats row layout reference)
- `DESIGN_SYSTEM.md` "Home: multi-mode launcher" section
- `EarTrain/Sources/EarTrainLib/ProgressStore.swift` (for what stats are available — `stats.totalSessions`, `stats.totalTrials`, `overallAccuracy`, etc. — read the file to confirm field names)

**Changes:**

1. Strip from `HomeView`:
   - The compact `header` HStack with `AudiePNGImage(size: 44)` + "Audie" + tagline. **Remove entirely.** No avatar on Home.
   - The current `recommendationCard` styling can stay but reframe it as the "Today's Focus" section per the spec. The card body changes based on plan state.

2. Add the **stats row**: 4 stat cards in an `HStack(spacing: 12)` showing:
   - "Sessions" (count from `store.stats.totalSessions`)
   - "Best Interval" (highest-accuracy interval in cumulative data — if none yet, show "—")
   - "Needs Work" (lowest-accuracy bucket with ≥5 trials — if none, show "—")
   - "Practice Time" (total minutes formatted, with "of 12h milestone" subtitle if under 12h)
   - Each card: `EarTrainColors.surface` background, corner radius 10, label + value layout. Reuse the existing `statPill` pattern in `HomeView.swift` (already defined).
   - Hide entire row if `store.stats.totalSessions == 0`. Show a single empty-state line instead: "Practice a session to see your stats."

3. Add the **action grid** below stats:
   - Row of buttons: `[Continue Plan]` (placeholder, disabled with subtitle "Coming in Phase 2"), `[Drill My Misses]` (enabled if `store.hasDrillableData`, else disabled with "Practice a few sessions first"), `[Freeplay]` (always enabled, sets `activeMode = .freeplay`), `[Browse Plans]` (always enabled, sets `activeMode = .plans`).
   - Each button is a card-style button (use `.buttonStyle(.plain)` with a custom card background). Layout: 2x2 grid on smaller widths, single row on wider. Use `LazyVGrid` with `[GridItem(.adaptive(minimum: 200))]`.
   - Active CTA (Drill My Misses if no plan; Continue Plan if plan active) should have `EarTrainColors.accent` accent border or background — visually distinguished.

4. Add the **recent sessions list** (only if `store.stats.totalSessions > 0`):
   - Up to 3 most recent sessions
   - Each row: date · duration · accuracy. Accuracy colored via `EarTrainColors.accuracy(_:)`.
   - If `ProgressStore` doesn't expose recent sessions yet, leave this section out and add a TODO comment + entry in `TODOS.md`. Don't invent persistence logic.

5. Update the body layout:
   ```swift
   VStack(spacing: 16) {
       todaysFocus            // recommendation/continue card
       if store.stats.totalSessions > 0 { statsRow }
       actionGrid
       if hasRecentSessions { recentSessionsList }
       Spacer(minLength: 0)
   }
   .padding(24)
   .frame(maxWidth: 600)            // slightly wider than current 480 to accommodate stats row
   .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
   ```
   Do NOT wrap in `ScrollView`. Content must fit in the default window without scrolling.

6. Update window default size in `EarTrainApp.swift` if needed — the previous bump to `height: 920` should still be sufficient, but verify after the Home rebuild.

**Acceptance:**
- No Audie avatar on Home.
- New users (zero sessions) see: "Today's Focus" empty state + action grid (Drill disabled, Freeplay/Browse Plans enabled) + a "practice to see stats" line.
- Returning users (with sessions) see: stats row, action grid (Drill enabled if eligible), recent sessions if available.
- All four action buttons route correctly.
- Home content fits within the 1000×920 default window with no scrolling on either state.
- Continue Plan button is present but disabled with a clear "coming in Phase 2" subtitle (or hidden — your call, but document the choice in a code comment).

**Verify:**
- `swift build` → pass
- Launch as a fresh user (delete `~/Library/Application Support/EarTrain/` first if needed, or just inspect the empty-state branches in code)
- Run a session, return to Home, verify stats row appears
- Click each action button; confirm routing
- Resize window between 1000×920 and 1200×1000; verify layout adapts and never overflows

**Commit:**
```
feat(home): rebuild as multi-mode launcher with stats and action grid

Removes the Audie avatar branding header. Adds stats row (4 cards),
action grid (Drill / Freeplay / Browse Plans / Continue Plan placeholder),
and recent sessions list. Two states supported: with-plan (Continue is
primary) and no-plan (Drill My Misses is primary).

Continue Plan is a disabled placeholder until LessonRunner ships in Phase 2.

See DESIGN_SYSTEM.md "Home: multi-mode launcher" and MIGRATION_NAV_PHASE_1_5.md step 4.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

---

## After all 4 steps

**Verify the full migration:**
1. `cd EarTrain && swift build` → "Build complete!"
2. Launch the app. Sidebar shows 6 items: Home, Tune, Plans, Freeplay, Progress, Settings.
3. Run through each destination. No crashes, no broken flows.
4. Run a Contour session via Freeplay. Run an Identify session. Run an Intervals session. Confirm all three exercise flows are intact.
5. From Home, click each action button — Drill, Freeplay, Browse Plans — and confirm they route correctly.
6. Confirm `git log --oneline -5` shows 4 distinct commits, one per step, in order.
7. `git status` clean.

**Update the migration doc:**
After all 4 steps land, edit `MIGRATION_NAV_PHASE_1_5.md`:
- Add a "Status" header at the top: `**Status: COMPLETE — landed [date].**`
- Note the commit SHAs for each step under each step's section.
- Don't delete the file; future agents may need to understand what changed.

**Update `TODOS.md`:**
Mark the "Navigation refactor (Phase 1.5)" entry as done, or remove it.

**What's NOT in scope for this migration:**
- LessonRunner protocol or implementation
- `.etplan` file parsing or `LessonPlanValidator`
- Default plan bundling (`default-ci.etplan`)
- Onboarding completion → default-plan-loaded handoff
- Adaptive difficulty wiring through plan steps
- Audiologist view

All of the above are tracked in `PLAN.md` Phase 2 and beyond. Stay in scope.

---

## If you get stuck

- **Build fails after a step:** read the error carefully. Most likely a missing case in a `switch` over `AppMode` somewhere outside `ContentView`. Search `grep -rn "AppMode" EarTrain/Sources/` to find all switches.
- **Sidebar styling looks wrong:** SwiftUI's macOS `NavigationSplitView` has limited styling hooks. Don't fight it. Apply `.background(EarTrainColors.bg)` on the list, use `.foregroundColor(.accent)` on selected rows. If selection styling is genuinely broken, document the limitation and move on — visual polish on the sidebar can ship in a follow-up.
- **A flow breaks that doesn't seem related to the migration:** stop. Don't fix it. Add an entry to `TODOS.md` and continue the migration as planned. Mixing migration work with bug fixes makes the commits unreviewable.
- **You're tempted to refactor a primitive view:** don't. Primitive view internals are out of scope. Migration only changes how those views are reached.
- **You hit a confusing piece of state in `ProgressStore`, `CompanionEngine`, or `AudioEngineManager`:** read the file, not the conversation. Read `LEARNINGS.md` if there's a documented gotcha. If still confused, leave it alone and route around it.

If you need to ask a question, write it as a comment in the relevant step of this file (`// AGENT QUESTION: ...`) and stop work. The user will respond.
