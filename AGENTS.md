# EarTrain CI — Codex Agent Instructions

## Project context

Mac desktop app (SwiftUI + AudioKit) for guitarists with cochlear implants.
See DESIGN.md for the full product spec and architecture.

## Important notes

- This project uses **git**, not jujutsu.
- Platform targets: macOS 13+, Swift 5.9+, AudioKit 5.x via Swift Package Manager
- Audio pipeline: gate approach (AmplitudeTracker threshold → N=3 PitchTap stability)
- Persistence: JSON files in ~/Library/Application Support/EarTrain/, include schemaVersion field

## Skill routing

At the start of every task, read ROUTING.md for skill routing rules.
When a user request matches a skill description in ROUTING.md, suggest the appropriate skill
command before proceeding with an ad-hoc answer.
