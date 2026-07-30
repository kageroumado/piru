---
id: PAT-disclosure-tier
type: pattern
description: A user-set Casual/Curious/Pharma-Nerd tier (UserProfile) gates how much reference density a screen shows, reused across Library and Insights.
edges:
  - {rel: used_by, target: SCR-substance-detail}
  - {rel: used_by, target: SCR-substance-data-page}
  - {rel: used_by, target: SCR-insight-tolerance}
metadata: {}
---

# Disclosure-tier gating

**Where**: `UserProfile`'s tier (Casual/Curious/Pharma Nerd) drives: Substance Detail's reference
sections (inline at Pharma Nerd, collapsed to `ShowAllRow`s at lower tiers, grouped under a "For
the curious" header only at Casual — `SubstanceDetailLayout.swift:126-201`); `ToleranceCard`'s
contributor-chip/safety-note/footer density (`ToleranceCard.swift:18,26,38`); `SubstanceDataPageView`
deliberately **forces** `.pharmaNerd` regardless of the live setting, since a deep link "must stay
valid if the tier changes" (`SubstanceDataPageView.swift:18-19`).

**Convention for new screens**: if a screen shows pharmacology/reference depth that could
overwhelm a casual user, gate it through this same `DisclosurePolicy`/tier mechanism rather than
inventing a new density switch — it's already threaded through `SubstanceDetailModel` and
`UserProfile`.
