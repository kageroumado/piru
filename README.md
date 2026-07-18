<div align="center">

<a href="README.md">English</a> ・ <a href="README.zh-Hans.md">简体中文</a>

[![piru](https://readme-typing-svg.demolab.com/?font=DotGothic16&weight=400&size=22&duration=3800&pause=900&color=EB4470&center=true&vCenter=true&width=820&height=60&lines=a%20dose%20journal%20and%20a%20pharmacopeia%20%E2%99%A1;what%20you%20took%20%E2%80%94%20and%20what%20it%27s%20still%20doing;1%2C900%2B%20substances%20%E3%83%BB%20every%20claim%20cited%20to%20its%20source;rx%20no.%20007%20%E3%83%BB%20%E6%9C%8D%E7%94%A8%E8%A8%98%E9%8C%B2%20%E3%83%BB%20%E4%BD%95%E3%82%92%E6%91%82%E3%81%A3%E3%81%A6%E3%80%81%E3%81%84%E3%81%BE%E3%81%A9%E3%81%86%E5%8A%B9%E3%81%84%E3%81%A6%E3%81%84%E3%82%8B%E3%81%8B)](https://kagerou.glass)

<img src=".github/piru-icon.png" alt="Piru icon" width="128" height="128">

# piru

**rx no. 007 ・ pi·ru ・ a dose journal and a pharmacopeia ♡**

[![kagerou.glass](https://img.shields.io/badge/kagerou.glass-EB4470?style=for-the-badge&logo=safari&logoColor=white)](https://kagerou.glass/piru/)
[![TestFlight](https://img.shields.io/badge/TestFlight-join%20the%20beta-0D96F6?style=for-the-badge&logo=testflight&logoColor=white)](https://testflight.apple.com/join/4vcA7dY3)
[![Discord](https://img.shields.io/badge/Discord-join%20us-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/hbpMZhPSdx)
[![@kageroumado](https://img.shields.io/badge/@kageroumado-76e6e0?style=for-the-badge&logo=x&logoColor=0d0a10)](https://x.com/kageroumado)
[![iOS 26+](https://img.shields.io/badge/iOS-26%2B-0d0a10?style=for-the-badge&logo=apple&logoColor=white)](#requirements)
[![简体中文](https://img.shields.io/badge/%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-README-EB4470?style=for-the-badge)](README.zh-Hans.md)

<table>
  <tr>
    <td align="center"><img src=".github/piru-journal.png" alt="Piru Journal — a live session graph with overlaid pharmacokinetic curves for caffeine, alcohol, and melatonin, above a list of past sessions grouped by day" width="380"><br><sub><b>the journal</b> ・ what you took, drawn as it rises and clears</sub></td>
    <td align="center"><img src=".github/piru-pharmacology.png" alt="Piru pharmacology card for cocaine — a triple monoamine reuptake inhibitor with a serotonin–dopamine balance slider, receptor target table, and source attribution" width="380"><br><sub><b>the pharmacopeia</b> ・ mechanism, binding, and citations for 1,900+ substances</sub></td>
  </tr>
</table>

</div>

> **服用注意 ・ a dose is not a confession.**
>
> Most tracking apps are built to make you take less. Piru isn't. It assumes you already know what
> you're doing and just want to *see* it — what you took, when, and what it's still doing to you
> right now — so it keeps a clean ledger and draws the pharmacology over it: the curve rising and
> clearing, the second dose stacking on the first, the interaction window opening. It's a question
> of dose, not of goodness. ♡

---

Piru is an iOS dose journal and pharmacology reference for anyone who takes things — prescriptions,
supplements, or recreational substances. Log a dose in two taps and Piru draws the pharmacokinetics
over your day: what's still active, what stacks into a dangerous pair, how tolerance builds and
fades. Everything stays on your device.

## Get the beta

Piru ships through **TestFlight**, Apple's beta app. Two-minute setup:

1. Tap the invite link: **[testflight.apple.com/join/4vcA7dY3](https://testflight.apple.com/join/4vcA7dY3)**
2. Under **Step 1 – Get TestFlight**, tap **View in App Store** and install TestFlight (skip if you already have it).
3. Back on the invite page, under **Step 2 – View Piru Beta**, tap **View in TestFlight**.
4. TestFlight opens the Piru page — tap **Install**.
5. When it's done, tap **Open**, or launch Piru from your home screen.

That's it. New builds arrive as a notification, and updating is one tap inside TestFlight.

Questions, bug reports, or just want to hang out? **[Join the Discord →](https://discord.gg/hbpMZhPSdx)**

## Features

- **A journal that draws itself.** Every dose becomes a pharmacokinetic curve. Doses within a window
  group into **sessions**, and the session graph overlays each substance so you can read the whole
  night at a glance — what's peaking, what's fading, what's about to come back around.
- **1,900+ substances, cited.** Dose ladders (threshold → light → common → strong → heavy), routes,
  onset/peak/offset durations, half-lives, mechanism of action, receptor binding, and subjective
  effects — resolved per-field from **17 data sources** and linked back to each one.
- **Interaction warnings.** Class-based danger rules (MAOI + stimulant, opioid + depressant, serotonergic
  stacks, and more) surface inline as you log and paint a danger window onto the timeline.
- **Tolerance & effect forecasting.** A tolerance model tracks how sensitivity builds and recovers;
  for stimulants and cathinones a calibrated pharmacodynamic engine forecasts how the session will
  *feel* — its rush, its plateau, its crash. See [below](#where-piru-is-different).
- **Adjustable depth.** Choose **Casual**, **Curious**, or **Pharma Nerd** and the whole app dials in
  to match — from plain dose ladders and top-line warnings up to receptor-binding tables, biased
  agonism, and CYP metabolism with citations down to the DOI.
- **A toolbox.** Half-life calculator, volumetric dosing, benzodiazepine and opioid equivalence
  converters, inventory tracking, and an interaction checker.
- **Live Activity & widgets.** Active doses on the Lock Screen and Dynamic Island with time remaining;
  Home Screen widgets for the current session and last dose.
- **Insights.** Usage trends, an adherence calendar, a per-substance tolerance readout, and a live
  "in your system" estimate.
- **Share a session.** Export the current state of your body as a clean image, a PDF report with the
  PK charts, or a Markdown summary — for a doctor, a friend, or your own notes.

## Where Piru is different

Most dose trackers draw one generic bell curve for everything. Piru models three things they don't.

### It predicts how a stimulant will feel — *when*, not how much

For **amphetamine, methylphenidate, and the cathinones (2-/3-/4-MMC)**, Piru runs a real
pharmacodynamic model instead of a stored curve. It treats what you *feel* as the gap between the
dopamine a dose forces and how fast your brain compensates for it — and the whole shape falls out of
that one idea. The same drug gives a rush intravenously but barely orally, because the rush tracks
how *fast* dopamine rises, not how high it peaks. Euphoria fades on a plateau as your brain catches
up, until residual drug feels like nothing. The comedown gets deeper with a bigger dose, then curves
back toward baseline — and it isn't a dopamine dip but an over-correction: the brake still clamped
down after dopamine has already returned to normal.

The model is calibrated on human PET and primate microdialysis, not eyeballed — **Breier et al.
(PNAS 1997)** for the dopamine-to-effect transfer function, **Volkow (2001, 2023)** for the rate
hypothesis, and **Kuczenski & Segal (1997)** for the releaser-vs-blocker split that makes amphetamine
hit harder and crash worse than methylphenidate. It forecasts **shape and sign, not milligrams** —
when the effect lands, when it fades, when the crash arrives. Any substance the model can't ground
falls back to the standard curve.

### Your heart rate, mapped to each dose

Connect Apple Health and Piru overlays your **heart rate and blood pressure** right on the session
timeline — then reads how your body answered *each* dose: the resting rate before it, the peak after,
and the delta. Read-only, and the numbers never leave your device.

<div align="center">
<img src=".github/piru-heart-rate.png" alt="A session timeline with a red heart-rate band and a blood-pressure marker under the pharmacokinetic curves, and per-dose chips showing 64→75, 70→83, and 81→97 bpm" width="330">
</div>

### Alcohol, modeled the way it clears

Alcohol doesn't decay like everything else. Its clearing enzyme saturates almost immediately, so it
comes off at a **constant grams-per-hour** — *zero-order* elimination — which means **duration scales
with the dose** and the decline is a straight line, not the usual exponential tail. Enter a drink by
**volume × ABV** and Piru draws it correctly:

<table>
  <tr>
    <td align="center"><img src=".github/piru-alcohol-beer.png" alt="A 330 mL 5% beer — 13 g of ethanol — peaking and clearing in about two hours" width="290"><br><sub><b>a beer</b> ・ 330 mL · 5% → 13 g · clears in ~2 h</sub></td>
    <td align="center"><img src=".github/piru-alcohol-whiskey.png" alt="A 700 mL 40% bottle of whiskey — 221 g of ethanol — declining as a straight line over about 34 hours" width="290"><br><sub><b>a bottle of whiskey</b> ・ 700 mL · 40% → 221 g · ~34 h, ruler-straight</sub></td>
  </tr>
</table>

Seventeen times the ethanol takes roughly seventeen times as long to clear — the curve just gets
wider, not taller-and-shorter. And because elimination tracks liver and body mass, Piru scales it by
**your body weight**: the *same* bottle clears far faster in a larger body.

<table>
  <tr>
    <td align="center"><img src=".github/piru-alcohol-whiskey.png" alt="The whiskey bottle at 60 kg body weight, clearing in about 34 hours" width="290"><br><sub><b>at 60 kg</b> ・ ~34 h to clear</sub></td>
    <td align="center"><img src=".github/piru-alcohol-whiskey-heavy.png" alt="The same whiskey bottle at 100 kg body weight, clearing in about 20 hours" width="290"><br><sub><b>at 100 kg</b> ・ same bottle, ~20 h</sub></td>
  </tr>
</table>

## The library — 1,900+ substances, every claim cited

Piru bundles an offline SQLite library of **1,900+ substances**. Each field — a dose range, a duration,
a receptor affinity, a mechanism summary — is resolved by **source priority** (which you can reorder)
and carries its own attribution, so a substance sheet ends with a **Data Sources** list that links
straight to each source's page for that compound. Doses and durations come first from
**[drug.community](https://drug.community)** — a dataset curated by a former pharma-industry contributor
and cross-checked in-app — with the volunteer wikis backfilling anything it doesn't cover. Which source
wins a given field, in priority order:

- **Piru's own hand-curated overlay** & **peer-reviewed primary literature** — outrank everything, so a
  verified correction always wins (this is also where genuine upstream dose bugs get overridden)
- **[drug.community](https://drug.community)** — **preferred** dose/duration ladders & reported-effect spectra
- **[PsychonautWiki](https://psychonautwiki.org)** & **[TripSit](https://tripsit.me)** — backfill dose ranges
  and durations, plus effect vocabulary, interaction data, and harm-reduction dosing
- **[FreeODwiki](https://github.com/SalviaSWC/FreeODwiki)** — the substance-profile copy for the **Chinese
  locale** (读中文时的正文来源)
- **[DailyMed](https://dailymed.nlm.nih.gov)** (FDA) & **DEA Orange Book** — prescription labels & scheduling
- **[PubChem](https://pubchem.ncbi.nlm.nih.gov)** & **[Wikidata](https://www.wikidata.org)** — identifiers, chemistry
- **[PDSP K<sub>i</sub> database](https://pdsp.unc.edu)** — receptor binding affinities
- **Erowid PiHKAL/TiHKAL** and other primary literature for the rest

<div align="center">
<img src=".github/piru-sources-zh.png" alt="A substance's Data Sources list — drug.community, FreeOD Wiki, PubMed, Piru's hand-curated overlay, PsychonautWiki, and TripSit, each a tappable link" width="300">
</div>

## Reads in your language

Piru ships a **full localization in English, Simplified Chinese (简体中文), and Traditional Chinese
(繁體中文)** — not just the interface chrome, but the pharmacology summaries, effect names, and safety
copy. Crisis resources are **region-aware**: the *Get Help* screen shows the emergency and crisis
lines for where you actually are.

<table>
  <tr>
    <td align="center"><img src=".github/piru-journal-zh.png" alt="The Journal in Simplified Chinese, showing the current-session graph and past sessions" width="250"><br><sub>日志 ・ the journal, localized</sub></td>
    <td align="center"><img src=".github/piru-pharmacology-zh.png" alt="A pharmacology card in Simplified Chinese explaining cocaine's dopamine transporter blockade" width="250"><br><sub>药理学 ・ the pharmacology, in full</sub></td>
    <td align="center"><img src=".github/piru-help-zh.png" alt="The Get Help screen in Simplified Chinese showing China's 120 ambulance number and a local crisis line" width="250"><br><sub>获取帮助 ・ region-aware crisis lines</sub></td>
  </tr>
</table>

## A closer look

<table>
  <tr>
    <td align="center"><img src=".github/piru-session.png" alt="Session detail — four doses of caffeine, alcohol, and melatonin with individual progress rails and remaining time" width="250"><br><sub><b>session detail</b> ・ every dose, still ticking</sub></td>
    <td align="center"><img src=".github/piru-library.png" alt="The Library browsing substances by effect class — Common, Stimulants, Empathogens, Hallucinogens" width="250"><br><sub><b>library</b> ・ browse by effect class</sub></td>
    <td align="center"><img src=".github/piru-insights.png" alt="Insights — usage bar chart, in-your-system estimate, an adherence calendar, and a tolerance readout" width="250"><br><sub><b>insights</b> ・ usage, adherence, tolerance</sub></td>
  </tr>
  <tr>
    <td align="center"><img src=".github/piru-tools.png" alt="The Tools tab — education, interactions, inventory, half-life calculator, volumetric dosing, benzo and opioid equivalence" width="250"><br><sub><b>tools</b> ・ calculators, converters, inventory</sub></td>
    <td align="center"><img src=".github/piru-help.png" alt="The Get Help screen — grounding suggestions and US emergency, crisis, and poison-control lines" width="250"><br><sub><b>get help</b> ・ one tap away, always</sub></td>
    <td align="center"><img src=".github/piru-share.png" alt="The Share Session sheet offering a session image, a PDF report, and a Markdown summary" width="250"><br><sub><b>share</b> ・ image, PDF, or Markdown</sub></td>
  </tr>
</table>

## Private by design

Piru is built for sensitive data, so the default is the safe one: **nothing leaves your device.**

- **On-device only.** Your journal lives locally in SwiftData. No sign-up, no account, no server.
- **No cloud unless you ask.** Backups are opt-in and **end-to-end encrypted** (AES-256-GCM) with a
  device key held in your iCloud Keychain, or a passphrase only you know.
- **No ads, no trackers, no analytics selling.** Your data is yours alone.

## Requirements

- **iOS 26 or later.** The interface is built around Liquid Glass; earlier iOS is not supported.
- **Xcode 26+** with Swift 6 to build — clone, open `Piru.xcodeproj`, and Run.
- Distributed via [TestFlight](https://testflight.apple.com/join/4vcA7dY3), not the App Store — see [Get the beta](#get-the-beta).

The bundled substance library is built by an offline, reproducible Python pipeline from committed
source snapshots — see [`pipeline/`](pipeline/). Never hand-edit `Piru/Data/piru-substances.sqlite`;
rebuild it with `pipeline/build.sh`.

## The name

**Piru** (ピル) is Japanese for *pill* — hence the smiling capsule. The name and mascot are inherited
from the app's original author, [pharmacykitty](https://github.com/pharmacykitty). It keeps its shelf
among the other prescriptions at [kagerou.glass](https://kagerou.glass) — **rx no. 007**, the one you
reach for to remember what you took.

## License

Piru is free software under the **GNU General Public License v3** — see [LICENSE](LICENSE).

## Acknowledgements

Originally built by [pharmacykitty](https://github.com/pharmacykitty); continued by
[@kageroumado](https://x.com/kageroumado), dispensed at [kagerou.glass](https://kagerou.glass).
Pharmacology data courtesy of [FreeODwiki](https://github.com/SalviaSWC/FreeODwiki),
[PsychonautWiki](https://psychonautwiki.org), [TripSit](https://tripsit.me), the NIH's
[DailyMed](https://dailymed.nlm.nih.gov), [PubChem](https://pubchem.ncbi.nlm.nih.gov), the
[PDSP K<sub>i</sub> database](https://pdsp.unc.edu), and the peer-reviewed literature cited throughout the app.

> **服用注意 ・ Piru is not medical advice.** It will not stop you from making a bad decision, and its
> models are estimates, not measurements. Get a test kit, dose low, and keep a sober friend. ♡
