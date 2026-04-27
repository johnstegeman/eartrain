import SwiftUI

/// First-launch name capture screen.
/// Shown once, after mic permission is granted, before the main app UI.
/// Stores the user's preferred name in UserDefaults; marks onboarding complete.
///
/// The name is optional — tapping "Skip" is fine and produces no personalisation.
struct OnboardingView: View {
    @ObservedObject var companion: CompanionEngine
    @State private var nameInput: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Avatar / branding
            VStack(spacing: 12) {
                AudiePNGImage(size: 120)
                Text("Hi! I'm Audie.")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(EarTrainColors.textPrimary)
                Text("I'll be your ear training partner.\nI'll play intervals, track your progress, and cheer you on.")
                    .font(.system(size: 14))
                    .foregroundColor(EarTrainColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            // Name field
            VStack(spacing: 8) {
                Text("What should I call you?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(EarTrainColors.textPrimary)

                TextField("Your name or nickname", text: $nameInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundColor(EarTrainColors.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(EarTrainColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: 260)
                    .focused($fieldFocused)
                    .onSubmit { finish() }
            }

            // CTA buttons
            VStack(spacing: 12) {
                Button(nameInput.trimmingCharacters(in: .whitespaces).isEmpty
                       ? "Let's go!"
                       : "Let's go, \(nameInput.trimmingCharacters(in: .whitespaces))!") {
                    finish()
                }
                .buttonStyle(AccentButtonStyle())
                .frame(width: 180)

                Button("Skip") { skip() }
                    .font(.system(size: 13))
                    .foregroundColor(EarTrainColors.textDisabled)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EarTrainColors.bg)
        .onAppear { fieldFocused = true }
    }

    private func finish() {
        let trimmed = nameInput.trimmingCharacters(in: .whitespaces)
        companion.userName = trimmed
        companion.hasCompletedOnboarding = true
    }

    private func skip() {
        companion.userName = ""
        companion.hasCompletedOnboarding = true
    }
}
