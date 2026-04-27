# TODOS

## ~~Navigation refactor (Phase 1.5)~~ DONE — see MIGRATION_NAV_PHASE_1_5.md



**What:** Migrate the app from top-tab navigation to a `NavigationSplitView` sidebar with
6 fixed destinations: Home / Tune / Plans / Freeplay / Progress / Settings.
**Why:** Per `LESSON_PRIMITIVES.md`, 12 exercise primitives are planned. Current top-tab
nav puts each primitive on its own tab and has no path to scale. The `.etplan` lesson
plan system (Phase 2) requires a Plans destination. The new sidebar architecture is fixed
at 6 items regardless of how many primitives ship.
**Spec:** `DESIGN_SYSTEM.md` "App architecture" and "Navigation" sections.
**Migration plan:** see `MIGRATION_NAV_PHASE_1_5.md` (4 sequential steps, each independently
shippable). Do them in order; do not bundle.
**Depends on:** nothing — this is a chassis change with no upstream blockers.
**Unblocks:** Phase 2 (LessonRunner, `.etplan` loader, default plan bundling).

---

## ExerciseViewModel pitch detection unit tests

**What:** Unit tests for the two-note detection logic in ExerciseViewModel.
**Why:** The detection pipeline (stability window, silence detection, grade flow) has no
test coverage. This is the hardest path in the app and the one most likely to regress
when LessonRunner starts orchestrating it.
**Context:** `ExerciseViewModel.swift` lines 96-188 contain `waitForStableNote()` and
`waitForSilence()`. These use a 10-second timeout, 3-frame stability window, and 25-cent
spread. Tests would mock the audio input stream. Requires extracting `MicListening`
protocol first (planned as part of lesson architecture work).
**Depends on:** `AudioPlaying` + `MicListening` protocol extraction (lesson architecture PR).

---

## App Sandbox entitlements for audiologist view

**What:** Add `.entitlements` file with `com.apple.security.files.user-selected.read-only`
and configure security-scoped bookmarks for NSOpenPanel in the audiologist view.
**Why:** Without the entitlement, NSOpenPanel works in development but fails on a
notarized/sandboxed build. Security-scoped bookmarks are required for the app to
re-open the selected folder across sessions.
**Context:** Audiologist view opens a patient's session data folder via NSOpenPanel.
Patient zips and emails `~/Library/Application Support/EarTrainCI/`. Audiologist
unzips and opens it. This needs read-only file access to the selected directory tree.
Without sandbox configuration, this will fail silently on a distributed build.
**How to start:** Add `EarTrain.entitlements` file to the Xcode project with
`com.apple.security.app-sandbox = true` and `com.apple.security.files.user-selected.read-only = true`.
Test with `Product → Archive` and check Console for sandbox denials.
**Depends on:** Audiologist view implementation.
