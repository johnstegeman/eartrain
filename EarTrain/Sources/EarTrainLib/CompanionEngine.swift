import SwiftUI

// MARK: - DifficultyAdjustable

/// Implemented by each exercise ViewModel so CompanionEngine can adjust
/// difficulty without knowing which exercise is active.
@MainActor
public protocol DifficultyAdjustable: AnyObject {
    var difficultyLevel: Int { get }
    func lowerDifficulty()
    func raiseDifficulty()
}

// MARK: - Message model

public struct CompanionMessage: Identifiable {
    public let id = UUID()
    public let text: String
    public let action: CompanionAction?
    public let actionLabel: String?
    /// Set to true once the user taps the action button — disables re-tapping.
    public var actionHandled: Bool = false

    public init(text: String, action: CompanionAction? = nil, actionLabel: String? = nil) {
        self.text = text
        self.action = action
        self.actionLabel = actionLabel
    }
}

public enum CompanionAction {
    case lowerDifficulty
    case raiseDifficulty
    case suggestMode(AppMode)
    case suggestBreak
    case declineEase          // "No thanks, keep it hard"
    case declineRaise         // "Stay at current level"
    case focusArea(String)    // Drill a specific problem area
    case declineFocus         // "Keep going with the full range"
}

/// Carries information about what a trial tested — so Audie can spot area-specific patterns.
public struct TrialContext {
    public let areaName: String  // Human-readable, e.g. "the low register"
    public init(areaName: String) { self.areaName = areaName }
}

// MARK: - CompanionEngine

/// Owns Audie's personality: tracks streaks, decides when to speak,
/// surfaces messages in a chat-style list, and handles action buttons.
///
/// Owned by AppSession; injected into exercise views as an ObservableObject.
@MainActor
public final class CompanionEngine: ObservableObject {

    // MARK: - Published

    /// Accumulated chat history for the current session. Cleared on session start.
    @Published public var messages: [CompanionMessage] = []

    // MARK: - User identity

    public var userName: String {
        get { UserDefaults.standard.string(forKey: "userDisplayName") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "userDisplayName") }
    }

    public var hasCompletedOnboarding: Bool {
        get { _hasCompletedOnboarding }
        set {
            objectWillChange.send()
            _hasCompletedOnboarding = newValue
            UserDefaults.standard.set(newValue, forKey: "onboardingComplete")
        }
    }
    private var _hasCompletedOnboarding: Bool =
        UserDefaults.standard.bool(forKey: "onboardingComplete")

    // MARK: - Wiring (set by the active view / ContentView)

    /// The currently active exercise's difficulty knob. Set in each exercise view's onAppear.
    public weak var difficultyDelegate: (any DifficultyAdjustable)?

    /// Called when Audie suggests switching to a different exercise mode.
    public var onSwitchMode: ((AppMode) -> Void)?

    /// Called when the user accepts a "focus on this area" offer. Passes the area name
    /// so the exercise VM can pin its register rotation to that bucket.
    public var onFocusArea: ((String) -> Void)?

    // MARK: - Streak state

    /// The live running streak count. Views read this to record personal bests.
    public private(set) var currentStreak: Int = 0

    private var consecutiveCorrect: Int {
        get { currentStreak }
        set { currentStreak = newValue }
    }
    private var consecutiveWrong = 0
    private var trialsSinceLastMessage = 0
    private static let minTrialsBetweenMessages = 5
    /// Prevents the raise-difficulty offer from firing more than once per streak run.
    private var hasOfferedRaiseDifficulty = false
    /// Prevents the personal-best announcement from firing more than once per session.
    private var hasAnnouncedPersonalBest = false

    // Per-level accuracy tracking — resets whenever the difficulty level changes.
    // Used to gate the raise-difficulty offer: streak alone isn't enough.
    private var trackedLevel: Int = -1
    private var trialsAtLevel: Int = 0
    private var correctAtLevel: Int = 0

    /// Ring buffer of the last few wrong-trial contexts (max 5).
    /// Used to detect area-specific struggle patterns.
    private var recentWrongContexts: [TrialContext] = []

    private var lastSessionDate: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: "lastSessionTimestamp")
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0,
                                      forKey: "lastSessionTimestamp")
        }
    }

    public init() {}

    // MARK: - Session lifecycle

    /// Call when the user taps "Start" on a ready screen.
    public func sessionStarted() {
        messages = []
        consecutiveCorrect = 0
        consecutiveWrong   = 0
        trialsSinceLastMessage = 0
        hasOfferedRaiseDifficulty = false
        hasAnnouncedPersonalBest = false
        trackedLevel = -1
        trialsAtLevel = 0
        correctAtLevel = 0
        recentWrongContexts = []

        let neverHadSession = !UserDefaults.standard.bool(forKey: "hadAnySession")
        let returningAfterBreak = lastSessionDate.map {
            Date().timeIntervalSince($0) > 3 * 24 * 3600
        } ?? false

        if neverHadSession {
            UserDefaults.standard.set(true, forKey: "hadAnySession")
            addMessage(pick(FeedbackCopy.firstSession))
        } else if returningAfterBreak {
            addMessage(pick(FeedbackCopy.welcomeBack))
        }

        lastSessionDate = Date()
    }

    // MARK: - Trial outcome

    /// Call after every graded trial — regardless of result.
    /// Pass `context` to let Audie spot area-specific struggle patterns.
    public func recordOutcome(correct: Bool, context: TrialContext? = nil) {
        // Sync per-level counters; reset if the difficulty changed since last trial.
        let level = difficultyDelegate?.difficultyLevel ?? 0
        if level != trackedLevel {
            trackedLevel = level
            trialsAtLevel = 0
            correctAtLevel = 0
            hasOfferedRaiseDifficulty = false
            consecutiveCorrect = 0
            consecutiveWrong   = 0
        }
        trialsAtLevel += 1
        if correct { correctAtLevel += 1 }

        if correct {
            consecutiveCorrect += 1
            consecutiveWrong   = 0
        } else {
            consecutiveWrong   += 1
            consecutiveCorrect = 0
            hasOfferedRaiseDifficulty = false
            if let ctx = context {
                recentWrongContexts.append(ctx)
                if recentWrongContexts.count > 5 { recentWrongContexts.removeFirst() }
            }
        }
        trialsSinceLastMessage += 1

        guard trialsSinceLastMessage >= Self.minTrialsBetweenMessages else { return }

        let atMaxDifficulty = level >= 5
        let accuracyAtLevel = trialsAtLevel > 0
            ? Double(correctAtLevel) / Double(trialsAtLevel) : 0
        let readyToRaise = consecutiveCorrect >= 8
            && trialsAtLevel >= 20
            && accuracyAtLevel >= 0.75

        if readyToRaise && !hasOfferedRaiseDifficulty {
            trialsSinceLastMessage = 0
            hasOfferedRaiseDifficulty = true
            if atMaxDifficulty {
                addMessage(pick(FeedbackCopy.masteryAtMaxDifficulty))
            } else {
                addMessage(pick(FeedbackCopy.offerRaiseDifficulty),
                           action: .raiseDifficulty,
                           actionLabel: FeedbackCopy.offerRaiseDifficultyButton)
            }
        } else if consecutiveCorrect >= 3 {
            trialsSinceLastMessage = 0
            addStreakMessage(count: consecutiveCorrect)
        } else if consecutiveWrong >= 3 {
            consecutiveWrong = 0
            trialsSinceLastMessage = 0
            showStruggleMessage()
        }
    }

    /// Call when the user just set a new personal best streak.
    /// Only fires if the streak is meaningful (≥ 5) and at most once per session.
    public func announcePersonalBest(streak: Int) {
        guard streak >= 5, !hasAnnouncedPersonalBest else { return }
        hasAnnouncedPersonalBest = true
        let word = streakWord(streak)
        var text = pick(FeedbackCopy.newPersonalBest)
        text = text.replacingOccurrences(of: "{count}", with: word)
        addMessage(text)
    }

    // MARK: - Action handling

    /// Called when the user taps an action button inside a chat bubble.
    public func handleAction(for messageID: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageID }),
              let action = messages[idx].action else { return }

        messages[idx].actionHandled = true

        switch action {
        case .lowerDifficulty:
            difficultyDelegate?.lowerDifficulty()
            addMessage(pick(FeedbackCopy.didLowerDifficulty))

        case .raiseDifficulty:
            difficultyDelegate?.raiseDifficulty()
            hasOfferedRaiseDifficulty = false
            addMessage(pick(FeedbackCopy.didRaiseDifficulty))

        case .declineEase:
            addMessage(pick(FeedbackCopy.didDeclineEase))

        case .declineRaise:
            addMessage(pick(FeedbackCopy.didDeclineRaise))

        case .focusArea(let area):
            onFocusArea?(area)
            var text = pick(FeedbackCopy.didFocusArea)
            text = text.replacingOccurrences(of: "{area}", with: area)
            addMessage(text)

        case .declineFocus:
            addMessage(pick(FeedbackCopy.didDeclineFocus))

        case .suggestMode(let mode):
            onSwitchMode?(mode)

        case .suggestBreak:
            break
        }
    }

    // MARK: - Private helpers

    private func streakWord(_ count: Int) -> String {
        switch count {
        case 3:  return "Three"
        case 4:  return "Four"
        case 5:  return "Five"
        case 6:  return "Six"
        case 7:  return "Seven"
        case 8:  return "Eight"
        case 9:  return "Nine"
        case 10: return "Ten"
        default: return "\(count)"
        }
    }

    private func addStreakMessage(count: Int) {
        let word = streakWord(count)
        let templates = [
            "\(word) in a row{name}. That's real progress.",
            "\(word) correct in a row{name}! You're on a roll.",
            "You're really getting this{name}. \(word) in a row!",
            "Nice work{name} — \(word) straight.",
            "\(word) and counting{name}. Don't stop now.",
            "Locked in{name}. \(word) in a row.",
            "That's \(word) correct{name}. Trust your ears.",
        ]
        addMessage(pick(templates))
    }

    private func showStruggleMessage() {
        let empathy = pick(FeedbackCopy.struggleEmpathy)

        // If 2+ of the last 3 wrong answers share an area, call it out specifically.
        if let dominantArea = dominantWrongArea() {
            addMessage(empathy)
            var offerText = pick(FeedbackCopy.offerFocusArea)
            offerText = offerText.replacingOccurrences(of: "{area}", with: dominantArea)
            addMessage(offerText,
                       action: .focusArea(dominantArea),
                       actionLabel: "Focus on \(dominantArea)")
            return
        }

        // Generic: randomly offer one of lower difficulty, switch mode, or break.
        let roll = Int.random(in: 0..<3)
        switch roll {
        case 0:
            addMessage(empathy)
            addMessage(pick(FeedbackCopy.offerLowerDifficulty),
                       action: .lowerDifficulty,
                       actionLabel: FeedbackCopy.offerLowerDifficultyButton)
        case 1:
            addMessage(empathy)
            addMessage(pick(FeedbackCopy.offerSwitchContour),
                       action: .suggestMode(.contour),
                       actionLabel: FeedbackCopy.offerSwitchContourButton)
        default:
            addMessage(empathy)
            addMessage(pick(FeedbackCopy.offerBreak))
        }
    }

    /// Returns the name of an area that dominates recent wrong answers (≥ 2 of last 3),
    /// or nil if wrong answers are spread across different areas.
    private func dominantWrongArea() -> String? {
        guard recentWrongContexts.count >= 2 else { return nil }
        let recent = recentWrongContexts.suffix(3).map(\.areaName)
        let grouped = Dictionary(grouping: recent, by: { $0 })
        guard let (area, instances) = grouped.max(by: { $0.value.count < $1.value.count }),
              instances.count >= 2 else { return nil }
        return area
    }

    private func addMessage(_ text: String,
                             action: CompanionAction? = nil,
                             actionLabel: String? = nil) {
        let msg = CompanionMessage(text: formatted(text), action: action, actionLabel: actionLabel)
        messages.append(msg)
        if messages.count > 30 { messages.removeFirst() }
    }

    /// Randomly pick one entry from the pool.
    private func pick(_ pool: [String]) -> String {
        pool.randomElement() ?? pool[0]
    }

    /// Replace `{name}` with `, [userName]` or "" if no name is set.
    private func formatted(_ template: String) -> String {
        let insert = userName.isEmpty ? "" : ", \(userName)"
        return template.replacingOccurrences(of: "{name}", with: insert)
    }
}

// MARK: - Chat UI

/// Persistent chat strip shown at the bottom of each exercise screen.
/// Messages accumulate; Audie's action buttons live inside her bubbles.
public struct AudieChatPanel: View {
    @ObservedObject var companion: CompanionEngine

    public init(companion: CompanionEngine) {
        self.companion = companion
    }

    public var body: some View {
        if companion.messages.isEmpty { EmptyView() } else {
            VStack(spacing: 0) {
                Divider().background(Color(hex: "#2d2d2d"))
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(companion.messages) { msg in
                                AudieBubble(message: msg) {
                                    companion.handleAction(for: msg.id)
                                }
                                .id(msg.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .onChange(of: companion.messages.count) { _ in
                        if let last = companion.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .top) }
                        }
                    }
                }
            }
            .frame(maxHeight: 160)
            .background(EarTrainColors.surface)
        }
    }
}

private struct AudieBubble: View {
    let message: CompanionMessage
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                AudieAvatarView(size: 18)
                Text("Audie")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(EarTrainColors.accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundColor(EarTrainColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let label = message.actionLabel, !message.actionHandled {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(EarTrainColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                        .onTapGesture { onAction() }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(EarTrainColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 340, alignment: .leading)
        }
    }
}
