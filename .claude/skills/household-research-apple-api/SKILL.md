---
name: household-research-apple-api
description: Verify an Apple API's current shape, availability, and entitlement needs from official documentation before coding against it. Use for SwiftData, Foundation Models, WidgetKit, App Intents, Swift Testing, Charts, LocalAuthentication, or any API you have not verified in this repo.
---

# household-research-apple-api

1. State the API/question precisely.
2. Consult official Apple Developer documentation first (developer.apple.com/documentation, WWDC session pages,
   release notes). Anthropic docs for Claude Code questions. Blogs/snippets only to interpret, never to override.
3. Record: minimum OS, Xcode/Swift version, entitlement or capability required (flag anything needing paid
   membership per §11.2), availability conditions (device, Apple Intelligence state), deprecations, fallback path.
4. Implement only against the verified shape. If docs are ambiguous, write a small compile-only probe and let CI
   confirm it before building on it.
5. Append the decision to `docs/research/apple-api-decisions.md`; add unknowns to `docs/research/open-questions.md`.
