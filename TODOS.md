# TODOS

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
