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
    <td align="center"><img src=".github/piru-journal.png" alt="The Journal — a live session graph with overlaid pharmacokinetic curves for caffeine, psilocybin, and methylphenidate, with a My Meds card and dose list" width="380"><br><sub><b>the journal</b> ・ what you took, drawn as it rises and clears</sub></td>
    <td align="center"><img src=".github/piru-pharmacology.png" alt="Piru pharmacology card for cocaine — a triple monoamine reuptake inhibitor with a serotonin–dopamine balance slider, receptor target table, and source attribution" width="380"><br><sub><b>the pharmacopeia</b> ・ mechanism, binding, and citations for 1,700+ substances</sub></td>
  </tr>
</table>

</div>

> **服用注意 ・ a dose is not a confession.**
>
> Most tracking apps are built to make you take less. Piru isn't. It assumes you already know what
> you're doing and just want to *see* it — what you took, when, and what it's still doing to you
> right now. It's a question of dose, not of goodness. ♡

---

Log a dose in two taps. Piru draws the pharmacokinetics over your day: what's still active, what
stacks into a dangerous pair, how tolerance builds and fades. 1,700+ substances, each field cited
to its source. Everything stays on your device.

## Get the beta

Piru ships through **TestFlight**, Apple's beta app. Two-minute setup:

1. Tap the invite link: **[testflight.apple.com/join/4vcA7dY3](https://testflight.apple.com/join/4vcA7dY3)**
2. Under **Step 1 – Get TestFlight**, tap **View in App Store** and install TestFlight (skip if you already have it).
3. Back on the invite page, under **Step 2 – View Piru Beta**, tap **View in TestFlight**.
4. TestFlight opens the Piru page — tap **Install**.
5. When it's done, tap **Open**, or launch Piru from your home screen.

Questions, bug reports, or just want to hang out? **[Join the Discord →](https://discord.gg/hbpMZhPSdx)**

## Where Piru is different

Most dose trackers draw one generic bell curve for everything. Piru models three things they don't.

### It predicts how a stimulant will feel

For **amphetamine, methylphenidate, and the cathinones**, Piru runs a pharmacodynamic model: what
you *feel* is the gap between the dopamine a dose forces and how fast your brain compensates. The
same drug gives a rush intravenously but barely orally, because the rush tracks how *fast* dopamine
rises, not how high. Euphoria fades on a plateau as the brain catches up; the comedown is an
over-correction — the brake still clamped after dopamine has already returned to normal.

Calibrated on human PET and primate microdialysis — **Breier et al. (PNAS 1997)**, **Volkow (2001,
2023)**, **Kuczenski & Segal (1997)**. It forecasts **shape and sign** — when the effect lands, when
it fades, when the crash arrives. Substances the model can't ground fall back to the standard curve.

### Your heart rate, mapped to each dose

Connect Apple Health and Piru overlays your **heart rate and blood pressure** on the session
timeline — the resting rate before each dose, the peak after, and the delta.

<div align="center">
<img src=".github/piru-heart-rate.png" alt="A session timeline with a red heart-rate band and a blood-pressure marker under the pharmacokinetic curves, and per-dose chips showing 64→75, 70→83, and 81→97 bpm" width="330">
</div>

### Alcohol, modeled the way it clears

Alcohol's clearing enzyme saturates almost immediately, so it comes off at a **constant
grams-per-hour** — *zero-order* elimination. Duration scales with the dose; the decline is a
straight line. Enter a drink by **volume × ABV** and Piru draws it correctly:

<table>
  <tr>
    <td align="center"><img src=".github/piru-alcohol-beer.png" alt="A 330 mL 5% beer — 13 g of ethanol — peaking and clearing in about two hours" width="290"><br><sub><b>a beer</b> ・ 330 mL · 5% → 13 g · clears in ~2 h</sub></td>
    <td align="center"><img src=".github/piru-alcohol-whiskey.png" alt="A 700 mL 40% bottle of whiskey — 221 g of ethanol — declining as a straight line over about 34 hours" width="290"><br><sub><b>a bottle of whiskey</b> ・ 700 mL · 40% → 221 g · ~34 h, ruler-straight</sub></td>
  </tr>
</table>

Seventeen times the ethanol takes roughly seventeen times as long to clear. And because elimination
tracks liver and body mass, Piru scales it by **your body weight**:

<table>
  <tr>
    <td align="center"><img src=".github/piru-alcohol-whiskey.png" alt="The whiskey bottle at 60 kg body weight, clearing in about 34 hours" width="290"><br><sub><b>at 60 kg</b> ・ ~34 h to clear</sub></td>
    <td align="center"><img src=".github/piru-alcohol-whiskey-heavy.png" alt="The same whiskey bottle at 100 kg body weight, clearing in about 20 hours" width="290"><br><sub><b>at 100 kg</b> ・ same bottle, ~20 h</sub></td>
  </tr>
</table>

## More than a logger

<table>
  <tr>
    <td align="center"><img src=".github/piru-pill.png" alt="Logging Concerta in Quick Log — the dose editor offers its real tablet strengths as chips (18, 27, 36, 54 mg) with a tablet-count stepper reading '1 tablet = 18 mg'" width="380"><br><sub><b>log the pill, not the milligram</b> ・ pick a brand like <b>Concerta</b> and Piru offers its real tablet strengths — 18 / 27 / 36 / 54 mg — and counts by the tablet</sub></td>
    <td align="center"><img src=".github/piru-routine.png" alt="A daily medication routine named Daily, scheduled for 9:00 AM with a reminder, holding Vitamin D3 4000 IU and Magnesium 350 mg" width="380"><br><sub><b>prescriptions & routines</b> ・ group daily meds, give them a time, and a reminder opens Quick Log pre-filled — with supplies that count down to a refill</sub></td>
  </tr>
  <tr>
    <td align="center"><img src=".github/piru-notifications.png" alt="The notifications management screen listing every alert type as an opt-in toggle: routine reminders, ask again, next-dose window, comedown alerts" width="380"><br><sub><b>reminders that fit the dose</b> ・ routine nudges, next-dose windows, comedown alerts, and quiet hours — every type opt-in</sub></td>
    <td align="center"><img src=".github/piru-estimator.png" alt="The Effect Estimator's forecast — a Feeling curve and an Energy curve comparing two stimulants across eight hours, above a Compulsion curve" width="380"><br><sub><b>the effect estimator</b> ・ compare two meds or preview a stack — watch how it might <i>feel</i> over the hours, without logging a thing</sub></td>
  </tr>
</table>

## The library — 1,700+ substances, every claim cited

An offline SQLite library where each field — a dose range, a duration, a receptor affinity, a
mechanism summary — is resolved by **source priority** (which you can reorder) and carries its own
attribution. Doses and durations come first from **[drug.community](https://drug.community)**, with
the volunteer wikis backfilling. The full priority chain:

**Piru curated overlay** & **primary literature** → **[drug.community](https://drug.community)** →
**[PsychonautWiki](https://psychonautwiki.org)** & **[TripSit](https://tripsit.me)** →
**[FreeODwiki](https://github.com/SalviaSWC/FreeODwiki)** (中文正文来源) →
**[DailyMed](https://dailymed.nlm.nih.gov)** & **DEA Orange Book** →
**[PubChem](https://pubchem.ncbi.nlm.nih.gov)** & **[Wikidata](https://www.wikidata.org)** →
**[PDSP K<sub>i</sub>](https://pdsp.unc.edu)** →
**[SubFxOnEx](https://github.com/Di-lemma/SubFxOnEx)** (subjective-effects ontology) →
**Erowid PiHKAL/TiHKAL** and the rest

<div align="center">
<img src=".github/piru-sources-zh.png" alt="A substance's Data Sources list — drug.community, FreeOD Wiki, PubMed, Piru's hand-curated overlay, PsychonautWiki, and TripSit, each a tappable link" width="300">
</div>

## A closer look

<table>
  <tr>
    <td align="center"><img src=".github/piru-journal.png" alt="The Journal in dark mode — session timeline with overlaid PK curves, My Meds card, and dose list" width="380"><br><sub><b>journal</b> ・ dark</sub></td>
    <td align="center"><img src=".github/piru-journal-light.png" alt="The Journal in light mode — the same timeline, meds card, and dose list in a light theme" width="380"><br><sub><b>journal</b> ・ light</sub></td>
  </tr>
</table>

<table>
  <tr>
    <td align="center"><img src=".github/piru-session.png" alt="Session detail — Lake evening: a psilocybin session with check-in notes, mood and energy ratings, Shulgin scale markings, and a PK curve" width="250"><br><sub><b>session notes</b> ・ check-ins with mood, energy, Shulgin scale, and effect descriptors</sub></td>
    <td align="center"><img src=".github/piru-library.png" alt="The Library browsing substances by category — Yours, Common, Stimulants, Empathogens, Hallucinogens — with colorful gradient cards" width="250"><br><sub><b>library</b> ・ browse by category</sub></td>
    <td align="center"><img src=".github/piru-tools.png" alt="The Tools tab — My Meds, inventory with supply levels, interactions, data and backup, education, box identifier, and effect estimator" width="250"><br><sub><b>tools</b> ・ inventory, interactions, calculators</sub></td>
  </tr>
</table>

<table>
  <tr>
    <td align="center"><img src=".github/piru-insights.png" alt="Insights in dark mode — usage bar chart, adherence calendar, in-your-body estimate, tolerance readout, and receptor load" width="380"><br><sub><b>insights</b> ・ dark</sub></td>
    <td align="center"><img src=".github/piru-insights-light.png" alt="Insights in light mode — the same cards in a light theme" width="380"><br><sub><b>insights</b> ・ light</sub></td>
  </tr>
</table>

## Reads in your language

Full localization in **English, Simplified Chinese (简体中文), and Traditional Chinese (繁體中文)** —
not just the interface, but pharmacology summaries, effect names, and safety copy. Crisis resources
are **region-aware**: the *Get Help* screen shows the lines for where you actually are.

<table>
  <tr>
    <td align="center"><img src=".github/piru-journal-zh.png" alt="The Journal in Simplified Chinese, showing the current-session graph and past sessions" width="250"><br><sub>日志 ・ the journal, localized</sub></td>
    <td align="center"><img src=".github/piru-pharmacology-zh.png" alt="A pharmacology card in Simplified Chinese explaining cocaine's dopamine transporter blockade" width="250"><br><sub>药理学 ・ the pharmacology, in full</sub></td>
    <td align="center"><img src=".github/piru-help-zh.png" alt="The Get Help screen in Simplified Chinese showing China's 120 ambulance number and a local crisis line" width="250"><br><sub>获取帮助 ・ region-aware crisis lines</sub></td>
  </tr>
</table>

## Private by design

**Nothing leaves your device.**

- **On-device only.** Your journal lives locally in SwiftData. No sign-up, no account, no server.
- **No cloud unless you ask.** Backups are opt-in and **end-to-end encrypted** (AES-256-GCM) with a
  device key held in your iCloud Keychain, or a passphrase only you know.
- **No ads, no trackers, no analytics.**

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
