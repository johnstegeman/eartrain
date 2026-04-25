# EarTrain CI — Claude Code Instructions

## Project context

Mac desktop app (SwiftUI + AudioKit) for guitarists with cochlear implants.
See DESIGN.md for the full product spec and architecture.

## Important notes

- This project uses **git**, not jujutsu. Do not use `jj` commands.
- Primary working directory: the repo root (where DESIGN.md lives)

## Skill routing

Read ROUTING.md at the start of every session for skill routing rules.
When a user request matches a skill, invoke it via the Skill tool before answering directly.
