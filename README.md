<div align="center">

<img src=".github/piru-icon.png" alt="Piru icon" width="128" height="128">

[![piru](https://readme-typing-svg.demolab.com/?font=DotGothic16&weight=400&size=22&duration=3800&pause=900&color=EB4470&center=true&vCenter=true&width=820&height=60&lines=a%20dose%20journal%20and%20a%20pharmacopeia%20%E2%99%A1;what%20you%20took%20%E2%80%94%20and%20what%20it%27s%20still%20doing;1%2C900%2B%20substances%20%E3%83%BB%20every%20claim%20cited%20to%20its%20source;rx%20no.%20007%20%E3%83%BB%20%E6%9C%8D%E7%94%A8%E8%A8%98%E9%8C%B2%20%E3%83%BB%20%E4%BD%95%E3%82%92%E6%91%82%E3%81%A3%E3%81%A6%E3%80%81%E3%81%84%E3%81%BE%E3%81%A9%E3%81%86%E5%8A%B9%E3%81%84%E3%81%A6%E3%81%84%E3%82%8B%E3%81%8B)](https://kagerou.glass)

# piru

<a href="README.md">English</a> ・ <a href="README.zh-Hans.md">简体中文</a>


[![kagerou.glass](https://img.shields.io/badge/kagerou.glass-EB4470?style=for-the-badge&logo=safari&logoColor=white)](https://kagerou.glass/piru/)
[![TestFlight](https://img.shields.io/badge/TestFlight-join%20the%20beta-0D96F6?style=for-the-badge&logo=testflight&logoColor=white)](https://testflight.apple.com/join/4vcA7dY3)
[![Discord](https://img.shields.io/badge/Discord-join%20us-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/hbpMZhPSdx)

<table>
  <tr>
    <td align="center"><img src=".github/piru-journal.png" width="380"></td>
    <td align="center"><img src=".github/piru-session.png” width="380"></td>
  </tr>
</table>

</div>

> Piru assumes you already know what
> you're doing and just want to *see* it — what you took, when, and what it's still doing to you
> right now. It's a question of dose, not of goodness. ♡

---

Log a dose in two taps. Piru draws the pharmacokinetics over your day: what's still active, what
stacks into a dangerous pair, how tolerance builds and fades. 1,700+ substances, all local.

## Get the beta

Piru ships through **TestFlight**. Two-minute setup:

1. Tap the invite link: **[testflight.apple.com/join/4vcA7dY3](https://testflight.apple.com/join/4vcA7dY3)**
2. Under **Step 1 – Get TestFlight**, tap **View in App Store** and install TestFlight (skip if you already have it).
3. Back on the invite page, under **Step 2 – View Piru Beta**, tap **View in TestFlight**.
4. TestFlight opens the Piru page — tap **Install**.

Questions, bug reports, or just want to hang out? **[Join the Discord →](https://discord.gg/hbpMZhPSdx)**

## Where Piru is different

Most dose trackers draw one generic bell curve for everything. Piru models three things they don't.

### It predicts how a stimulant will feel

For **amphetamine, methylphenidate, and the cathinones**, Piru runs a pharmacodynamic model: what
you *feel* is the gap between the dopamine a dose forces and how fast your brain compensates. The
same drug gives a rush intravenously but barely orally, because the rush tracks how *fast* dopamine
rises, not how high. Euphoria fades on a plateau as the brain catches up; the comedown is an
over-correction — the brake still clamped after dopamine has already returned to normal.

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

## More than a logger

<table>
  <tr>
    <td align="center"><img src=".github/piru-pill.png" alt="Logging Concerta in Quick Log — the dose editor offers its real tablet strengths as chips (18, 27, 36, 54 mg) with a tablet-count stepper reading '1 tablet = 18 mg'" width="380"><br><sub><b>log the pill, not the milligram</b> ・ pick a brand like <b>Concerta</b> and Piru offers its real tablet strengths</sub></td>
    <td align="center"><img src=".github/piru-routine.png" alt="A daily medication routine named Daily, scheduled for 9:00 AM with a reminder, holding Vitamin D3 4000 IU and Magnesium 350 mg" width="380"><br><sub><b>prescriptions & routines</b> ・ group daily meds, give them a time, and a reminder opens Quick Log pre-filled</sub></td>
  </tr>
</table>

## The library — 1,700+ substances, cited

An offline SQLite library where each field — a dose range, a duration, a receptor affinity, a
mechanism summary — is resolved by **source priority** (which you can reorder) and carries its own
attribution.

**Piru curated overlay** & **primary literature** → **[drug.community](https://drug.community)** →
**[PsychonautWiki](https://psychonautwiki.org)** & **[TripSit](https://tripsit.me)** →
**[FreeODwiki](https://github.com/SalviaSWC/FreeODwiki)** (中文正文来源) →
**[DailyMed](https://dailymed.nlm.nih.gov)** & **DEA Orange Book** →
**[PubChem](https://pubchem.ncbi.nlm.nih.gov)** & **[Wikidata](https://www.wikidata.org)** →
**[PDSP K<sub>i</sub>](https://pdsp.unc.edu)** →
**[SubFxOnEx](https://github.com/Di-lemma/SubFxOnEx)** (subjective-effects ontology) →
**Erowid PiHKAL/TiHKAL** and the rest

## A closer look

<table>
  <tr>
    <td align="center"><img src=".github/piru-insights.png” width="380"></td>
    <td align="center"><img src=".github/piru-tools.png" width="380"></td>
  </tr>
</table>

## Reads in your language

Full localization in **English, Simplified Chinese (简体中文), and Traditional Chinese (繁體中文)** —
not just the interface, but pharmacology summaries, effect names, and safety copy.

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

## The name

**Piru** (ピル) is Japanese for *pill* — hence the smiling capsule. The name and mascot are inherited
from the app's original author, [pharmacykitty](https://github.com/pharmacykitty). It keeps its shelf
among the other prescriptions at [kagerou.glass](https://kagerou.glass) — **rx no. 007**, the one you
reach for to remember what you took.

## License

Piru is free software under the **GNU General Public License v3** — see [LICENSE](LICENSE).

## Requirements

- **iOS 26 or later.** The interface is built around Liquid Glass; earlier iOS is not supported.
- **Xcode 26+** with Swift 6 to build — clone, open `Piru.xcodeproj`, and Run.

The bundled substance library is built by an offline, reproducible Python pipeline from committed
source snapshots — see [`pipeline/`](pipeline/).

## Acknowledgements

Originally built by [pharmacykitty](https://github.com/pharmacykitty); continued by
[@kageroumado](https://x.com/kageroumado), dispensed at [kagerou.glass](https://kagerou.glass).
Pharmacology data courtesy of [FreeODwiki](https://github.com/SalviaSWC/FreeODwiki),
[PsychonautWiki](https://psychonautwiki.org), [TripSit](https://tripsit.me), the NIH's
[DailyMed](https://dailymed.nlm.nih.gov), [PubChem](https://pubchem.ncbi.nlm.nih.gov), the
[PDSP K<sub>i</sub> database](https://pdsp.unc.edu), and the peer-reviewed literature cited throughout the app.

> **服用注意 ・ Piru is not medical advice.** It will not stop you from making a bad decision, and its
> models are estimates. ♡
