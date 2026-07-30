---
id: SCR-move-to-session
type: screen
description: Sheet to move a dose entry between sessions — a third card idiom distinct from SessionCardView's themeCard.
edges:
  - {rel: variant_of, target: SCR-session-detail}
metadata:
  screenshot: null
---

# Move to Session (`MoveToSessionView`)

**Route**: presented from `SessionDetailView.swift:531-534` via the `sessionEditingService`
channel (not `AppNavigator`). `.presentationDetents([.medium, .large])`. **File**:
`Piru/Views/Journal/Session/MoveToSessionView.swift` (304 ln).

## States
Empty: `ContentUnavailableView("Nowhere to Move", "arrow.right.arrow.left", ...)` (`:53-58`) when
there's no new-session option and no targets.

## Tokens
Uses `.listRowBackground(CardBackground())` — a **third card idiom** in the Session folder,
distinct from `SessionCardView`'s `.themeCard()`. Negative-spacing overlap technique
`HStack(spacing: -5)` (`:233`) for target dots — unique to this file.
