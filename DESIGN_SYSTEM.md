# Audie Design System

Design reference for the Audie macOS app (SwiftUI). Keep this file current whenever tokens, components, or patterns change. Agents and contributors should consult it before writing any UI code.

---

## Guiding principles

- **Dark-first.** The app is always dark. Never introduce light-mode branches or adaptive colors.
- **Amber as the single accent.** `EarTrainColors.accent` (`#f5a623`) is the only interactive highlight color. Avoid introducing secondary accent colors.
- **Minimal chrome.** Hidden title bar, no toolbars. UI is content-first.
- **Accessible interactivity.** Every tappable element must be a `Button`, never a `Text` with `.onTapGesture`. This enables keyboard navigation, `.disabled()`, and `AccentButtonStyle`'s disabled-opacity logic.

---

## Color tokens

All tokens live in `ContentView.swift` as `public enum EarTrainColors`.

| Token | Hex | Use |
|---|---|---|
| `bg` | `#1a1a1a` | Window / screen background |
| `surface` | `#232323` | Cards, panels, input fields, button backgrounds |
| `accent` | `#f5a623` | Primary interactive color — buttons, icons, highlights |
| `success` | `#4ade80` | Correct answers, in-tune indicator |
| `inTuneFlash` | `#86efac` | Brighter green for the sustained in-tune flash in TunerView only |
| `error` | `#ef4444` | Wrong answers, errors, out-of-range indicator |
| `textPrimary` | `#e0e0e0` | Body text, labels, primary content |
| `textSecondary` | `#888888` | Supporting text, subtitles, metadata |
| `textDisabled` | `#555555` | Placeholder dashes, inactive controls |

**Accuracy color helper** — returns one of the three semantic colors based on a `Double` (0–1):

```swift
EarTrainColors.accuracy(value)  // ≥0.80 → success, ≥0.50 → accent, <0.50 → error
```

Never hardcode hex values. If you need a one-off shade, use `.opacity()` on an existing token.

---

## Typography

No custom fonts. All text uses `.system(size:weight:design:)`.

| Role | Size | Weight | Notes |
|---|---|---|---|
| Large display (interval name) | 64–72 | `.black` | `ExerciseView`, `IdentificationView` |
| Screen title | 26 | `.bold` | `ExerciseReadyView` heading |
| Section heading | 20 | `.bold` | Sheets, drill-down headers |
| Body / label | 14–16 | `.regular` / `.semibold` | General UI text |
| Caption / metadata | 11–13 | `.regular` | Supporting info, counts |
| Monospaced data | 14 | `.semibold`, `design: .monospaced` | Score display |
| Section label (all-caps) | 10–11 | `.semibold` | `.tracking(0.8)` + `.textCase(.uppercase)` |

**Section labels** always use the token color `textSecondary` and `.textCase(.uppercase)` — never hardcode uppercase strings for section headers.

---

## Spacing and corner radii

Consistent spacing prevents visual noise. Use these values; don't invent new ones.

| Context | Value |
|---|---|
| Screen edge padding | 24 |
| Card internal padding | 16–24 |
| Between major sections | 24–32 |
| Between related items | 8–12 |
| Between tight items (dots, chips) | 3–6 |

| Shape | Radius | Where |
|---|---|---|
| Cards / panels | 12 | Surface cards in all exercise and progress views |
| Buttons, pills, rows | 8–10 | Mode cards, duration pills, streak records |
| Inline badges / chips | 5–6 | `AccentButtonStyle`, Audie action buttons, End Session button |

**Always use** `.clipShape(RoundedRectangle(cornerRadius: N))`. The `.cornerRadius()` modifier is soft-deprecated — never use it.

---

## Interactive states

### `AccentButtonStyle` (primary CTA)

Defined in `ContentView.swift`. Amber background, black text, `cornerRadius: 6`.

```swift
Button("Start") { … }
    .buttonStyle(AccentButtonStyle())
```

Disabled state is handled automatically via `@Environment(\.isEnabled)` — just call `.disabled(condition)` on the button. Do not manually set opacity.

### Plain tappable rows and cards

Use `.buttonStyle(.plain)` when you need a custom visual but still want button semantics:

```swift
Button { … } label: { … }
    .buttonStyle(.plain)
    .background(EarTrainColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 10))
```

### Never do this

```swift
// ❌ onTapGesture bypasses Button semantics
Text("Start").onTapGesture { … }

// ❌ manual disabled opacity — use .disabled() instead
.opacity(isEnabled ? 1 : 0.4)  // only acceptable when Button can't be used (rare)
```

---

## Shared components

These components are already written. Use them; don't rebuild them.

### `AccentButtonStyle`
`ContentView.swift` — primary CTA button. Amber fill, black label, auto-disabled opacity.

### `ExerciseSessionBar`
`ExerciseReadyView.swift` — header bar for all running exercise sessions.  
Props: `volume`, `difficultyLevel`, `difficultyDescriptions`, `timeRemainingSeconds`, `onDifficultyChange`, `onEnd`.  
Used by `ExerciseView`, `ContourView`, `IdentificationView`.

### `ExerciseReadyView`
`ExerciseReadyView.swift` — pre-exercise start screen. Shows Audie avatar, mode description, duration picker, volume slider, and Start button. Used by all three exercise modes.

### `DifficultyDots`
`ExerciseReadyView.swift` — five-dot difficulty indicator. Prop: `level: Int` (1–5).

### `DifficultyControl`
`ExerciseReadyView.swift` — tappable `DifficultyDots` with a popover to select level. Used inside `ExerciseSessionBar`.

### `VolumeSlider`
`ExerciseReadyView.swift` — speaker icon + `Slider` bound to `AudioEngineManager.outputVolume`. Used on both the ready screen and the session bar.

### `AudieChatPanel`
`CompanionEngine.swift` — scrollable chat strip docked at the bottom of each exercise screen. Renders `AudieBubble` messages from `CompanionEngine`. Renders nothing when `companion.messages` is empty.

### `AudiePNGImage`
`AudieAvatar.swift` — Audie's face from the bundled PNG/ICNS. Use for the ready screen, onboarding, and anywhere you need the avatar at 40pt+. Prop: `size: CGFloat` (default 120).

### `AudieAvatarView`
`AudieAvatar.swift` — programmatic fallback avatar for small sizes and Xcode Previews. Used at 18pt inside chat bubbles (`AudieBubble`).

### `EndOfSessionView`
`EndOfSessionView.swift` — post-session stats sheet. Presented as `.sheet(item: $sessionSummary)`. Accepts a `SessionEndSummary` and a `ProgressStore`.

---

## Animation patterns

### Phase-driven status panels

Status panels that switch between enum phases with associated values cannot use the enum directly as an animation value. Use the `phaseIndex: Int` pattern:

```swift
private var phaseIndex: Int {
    switch vm.phase {
    case .idle:           return 0
    case .playing:        return 1
    case .awaitingAnswer: return 2
    case .result:         return 3
    }
}

private var statusPanel: some View {
    Group {
        switch vm.phase {
        case .playing:
            HStack { … }.transition(.opacity)
        case .result(let correct):
            resultBadge(correct).transition(.opacity)
        // …
        }
    }
    .animation(.easeInOut(duration: 0.2), value: phaseIndex)
}
```

All exercise views (`ExerciseView`, `ContourView`, `IdentificationView`) use this pattern. Follow it for any new exercise mode.

### Standard easing

Use `.easeInOut(duration: 0.2)` for panel/badge transitions. Use `.linear(duration: 0.05)` for real-time level meters.

---

## Screen anatomy

Every running exercise screen follows the same structure:

```
VStack(spacing: 0) {
    ExerciseSessionBar         // volume · difficulty dots · timer · End Session
    VStack(spacing: 28–32) {   // main content
        scorePanel             // trailing "N/M (X%)" readout
        [mode-specific content]
        statusPanel            // phase-driven status (Listen… / Is this… / result badge)
        answerButtons
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    AudieChatPanel             // collapses when empty
}
```

The ready screen (`ExerciseReadyView`) is shown when the VM's phase is `.idle` — the exercise view switches between it and the active layout based on that flag.

---

## Progress / accuracy display

- Use `EarTrainColors.accuracy(value)` for any accuracy-colored text or fill.
- Cells or rows with fewer than 5 trials are "muted": show `textDisabled` color and a "few" label. Do not show a percentage.
- Heatmap cells: `height: 52`, `cornerRadius: 8`, color fill at `opacity(0.85)`.
- Bar charts / progress bars: `height: 8`, `RoundedRectangle(cornerRadius: 4)`.

---

## What to avoid

| Anti-pattern | Correct alternative |
|---|---|
| Hardcoded hex colors (`Color(hex: "#…")`) | `EarTrainColors.*` token |
| `.cornerRadius(N)` | `.clipShape(RoundedRectangle(cornerRadius: N))` |
| `Text(…).onTapGesture { }` | `Button { } label: { }.buttonStyle(.plain)` |
| Manual `.opacity(0.4)` for disabled state | `.disabled(true)` on a `Button` with `AccentButtonStyle` |
| Duplicate `accuracyColor` / `formatTime` helpers | `EarTrainColors.accuracy(_:)` · `ExerciseSessionBar.formatTime` |
| Introducing `warning` or secondary accent colors | Use `accent`, `success`, or `error` |
| `.textCase(.uppercase)` omitted on section headers | Always pair raw section label text with `.textCase(.uppercase)` |
| Uppercase strings hardcoded in source (`"BEST STREAKS"`) | `"Best Streaks".uppercased()` via `.textCase(.uppercase)` |
