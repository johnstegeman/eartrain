import Foundation

/// All of Audie's spoken copy in one place — easy to edit, tune, or localise.
///
/// Strings use `{name}` as a placeholder:
///   • With a name  → ", John"
///   • Without name → "" (omitted entirely)
///
/// Keep the tone: warm, real, slightly casual — like a good private music tutor.
/// No jargon: no "semitone", "MIDI", "register", "interval class".
public enum FeedbackCopy {

    // MARK: - Positive / streak (shown after 3+ consecutive correct)

    static let streak: [String] = [
        "Three in a row{name}. That's real progress.",
        "You're really getting this{name}. Keep going.",
        "Nice streak{name}! You're on a roll.",
        "That's the sound of it clicking into place.",
        "Solid{name}. You're building something real here.",
        "Your ears are getting sharper{name}.",
        "That's the groove right there{name}. Stay in it.",
        "Trust what you're hearing{name}. It's working.",
        "Good listening{name}. That was clean.",
    ]

    // MARK: - Struggle / empathy (3+ consecutive wrong)

    static let struggleEmpathy: [String] = [
        "That one's genuinely tricky{name}. You're not alone.",
        "This is where the real training happens{name} — the hard ones.",
        "These can be tough{name}. Don't get discouraged.",
        "Even experienced players get tripped up here{name}.",
        "Tricky stuff{name}. Give yourself some grace.",
        "Ear training is hard. You're doing the work{name} — that's what matters.",
        "This takes time. You're building something that sticks{name}.",
    ]

    static let offerLowerDifficulty: [String] = [
        "Want me to make it a bit easier for now?",
        "I can back things off while you build confidence here.",
        "Starting easier is sometimes the smart move — want me to adjust?",
        "No shame in stepping back{name} — it's how you build up solid.",
        "Want to try a slightly wider range? Sometimes that helps things click.",
    ]
    static let offerLowerDifficultyButton = "Yes, ease up a bit"

    static let offerSwitchContour: [String] = [
        "Want to switch to Contour mode for a while? It's simpler — just higher, lower, or same.",
        "Maybe a change of pace? Contour is a good reset.",
        "Sometimes it helps to take a step back to Contour{name}. Want to try?",
        "Contour mode might be a good reset right now — just up, down, or same. Interested?",
    ]
    static let offerSwitchContourButton = "Switch to Contour"

    static let offerBreak: [String] = [
        "Sometimes a short break helps more than another rep. No rush.",
        "Come back when you're ready{name}. The notes will wait.",
        "Your brain needs rest too{name}. Even five minutes helps.",
        "Step away for a bit{name}. You'll come back sharper.",
    ]

    // MARK: - Mastery at max difficulty (streak + accuracy gate, already at level 5)

    static let masteryAtMaxDifficulty: [String] = [
        "You've got this{name}. That's the hardest level and you're nailing it. Want to keep going or try a different exercise?",
        "Max difficulty, high accuracy{name}. That's real mastery. Consider switching to a new exercise to keep pushing.",
        "You're crushing it at level 5{name}. There's nowhere left to go here — maybe it's time for a new challenge.",
        "Honestly{name}? You've nailed this. The hardest level and you're consistent. Time to explore something new.",
    ]

    // MARK: - Area-specific struggle (shown when wrong answers cluster in one register)
    // {area} is replaced with the human-readable area name, e.g. "the high register"

    static let offerFocusArea: [String] = [
        "You seem to be struggling with {area}{name}. Want to focus there for a while?",
        "A lot of those misses are coming from {area}{name}. Want to drill that specifically?",
        "Looks like {area} is giving you trouble{name}. Want to spend some time there?",
        "I'm noticing {area} is the tricky spot{name}. Want to zoom in on that?",
    ]

    static let didFocusArea: [String] = [
        "Got it{name}. Focusing on {area} for now.",
        "Done — I'll keep the exercises in {area} for a bit.",
        "Let's zero in on {area}{name}. You'll get it.",
    ]

    static let didDeclineFocus: [String] = [
        "Fair enough{name}. Keeping the full range.",
        "No problem — staying broad{name}.",
        "Got it{name}. Staying the course.",
    ]

    // MARK: - Raise difficulty offer (shown after a strong streak)

    static let offerRaiseDifficulty: [String] = [
        "You're really on fire{name}. Want me to step it up a notch?",
        "This is starting to look easy{name}. Ready for a bigger challenge?",
        "You've been crushing it{name}. Want to raise the bar?",
    ]
    static let offerRaiseDifficultyButton = "Step it up"

    static let didRaiseDifficulty: [String] = [
        "Dialing it up{name}. Let's see how you handle this.",
        "Stepping it up. You asked for it{name}!",
        "Challenge accepted{name}. Here we go.",
    ]

    static let didDeclineRaise: [String] = [
        "No problem{name}. Staying at the current level.",
        "Fair enough{name}. Keep crushing it.",
    ]

    // MARK: - Personal best

    static let newPersonalBest: [String] = [
        "New personal best{name} — {count} in a row!",
        "That's your longest streak yet{name}. {count} in a row.",
        "{count} in a row{name} — you just beat your own record.",
    ]

    // MARK: - Difficulty confirmations (Audie's reply after action is taken)

    static let didLowerDifficulty: [String] = [
        "Done — I've made it a bit easier. Let's keep going.",
        "Backed off a notch. You've got this{name}.",
        "Easier it is. Build that confidence up.",
        "Done{name}. We'll work back up from here.",
        "Adjusted. No shame in that — it's how you get better.",
    ]

    static let didDeclineEase: [String] = [
        "Fair enough{name}. Let's keep pushing.",
        "Got it — staying the course.",
        "Noted{name}. Respect.",
        "I like the attitude{name}. Let's go.",
    ]

    // MARK: - Session transitions

    static let firstSession: [String] = [
        "Let's start easy and see where you are{name}.",
        "Welcome{name}! We'll start simple and build from there.",
        "Good to meet you{name}. Let's find out where your ears are.",
        "Hi{name}! Let's start somewhere comfortable and go from there.",
    ]

    static let welcomeBack: [String] = [
        "Welcome back{name}! Let's shake off the rust.",
        "Good to see you again{name}. Ready to pick up where we left off?",
        "Back at it{name}. Let's go.",
        "Hey{name}! Let's pick right back up.",
        "You came back{name}. That's what it takes.",
        "Good timing{name}. Let's get those ears warmed up.",
    ]
}
