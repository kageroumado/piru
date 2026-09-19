<div align="center">

<img src=".github/piru-icon.png" alt="Piru icon" width="128" height="128">

[![piru](https://readme-typing-svg.demolab.com/?font=DotGothic16&weight=400&size=22&duration=3800&pause=900&color=EB4470&center=true&vCenter=true&width=820&height=60&lines=a%20dose%20journal%20and%20notebook%20%E2%99%A1;a%20dose%20is%20not%20a%20confession;write%20it%20down.%20the%20title%20can%20wait.;rx%20no.%20007%20%E3%83%BB%20%E6%9C%8D%E7%94%A8%E8%A8%98%E9%8C%B2%20%E3%83%BB%20%E8%B5%B7%E3%81%8D%E3%81%9F%E3%81%93%E3%81%A8%E3%82%92%E3%80%81%E6%9B%B8%E3%81%8D%E3%81%A8%E3%82%81%E3%82%8B)](https://kagerou.glass)

# piru

<a href="README.md">English</a> ・ <a href="README.zh-Hans.md">简体中文</a>


[![kagerou.glass](https://img.shields.io/badge/kagerou.glass-EB4470?style=for-the-badge&logo=safari&logoColor=white)](https://kagerou.glass/piru/)
[![TestFlight](https://img.shields.io/badge/TestFlight-join%20the%20beta-0D96F6?style=for-the-badge&logo=testflight&logoColor=white)](https://testflight.apple.com/join/4vcA7dY3)
[![Discord](https://img.shields.io/badge/Discord-join%20us-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/hbpMZhPSdx)

<table>
  <tr>
    <td align="center"><img src=".github/piru-journal.png" alt="The Journal, with the day's doses on a timeline" width="290"></td>
    <td align="center"><img src=".github/piru-session.png" alt="A session with its doses and notes" width="290"></td>
  </tr>
</table>

</div>

> A dose is not a confession. Piru assumes you already know what you're doing and want a record of
> it: what you took, when, and what you noticed. It's a question of dose, not of goodness. ♡

---

A dose journal and notebook for iPhone, with an offline reference library.

- **Journal.** Log what you took, when, and how much. Tablet strengths, daily routines, and
  reminders sit beside the day's timeline, and the curves on it are estimates.
- **Sessions and check-ins.** Write a note during a session or come back to it later. Each note
  keeps its own timestamp, mood, intensity, and effects. With permission, Apple Health adds heart
  rate and blood pressure to the timeline.
- **Library.** An offline reference in English, 简体中文, and 繁體中文. Each entry shows the sources
  behind its fields, and you choose which source wins when they differ.
- **Looking back.** Review your entries and your medication calendar, keep count of your supply,
  and export your records or a session as a report.

The journal is stored on your device. No account, ads, or analytics.

## Get the beta

Free on [TestFlight](https://testflight.apple.com/join/4vcA7dY3), for iOS 26 or later. Questions and
bug reports go to the [Discord](https://discord.gg/hbpMZhPSdx).

## Building

Open `Piru.xcodeproj` in Xcode 26 or later. The substance database is fetched, so run
`pipeline/fetch-db.sh` after cloning and before the first build. Style and tooling are in
[CONTRIBUTING.md](CONTRIBUTING.md#style).

## The name

**Piru** (ピル) is Japanese for *pill*, hence the smiling capsule. The name and mascot come from the
app's original author, [pharmacykitty](https://github.com/pharmacykitty);
[@kageroumado](https://x.com/kageroumado) continues it as **rx no. 007** at
[kagerou.glass](https://kagerou.glass).

## Acknowledgements

The library draws on [substance.wiki](https://substance.wiki) and its
[SubFxOnEx](https://github.com/Di-lemma/SubFxOnEx) ontology (LGPL-2.1),
[PsychonautWiki](https://psychonautwiki.org) (CC BY-SA 4.0), [FreeOD Wiki](https://freeodwiki.org)
(CC BY-SA 4.0), [dose.wiki](https://dose.wiki) (CC0 1.0), [TripSit](https://tripsit.me),
[DailyMed](https://dailymed.nlm.nih.gov), [PubChem](https://pubchem.ncbi.nlm.nih.gov),
[Wikidata](https://www.wikidata.org), and the peer-reviewed literature cited in the app.

## License

Piru is free software under the **GNU General Public License v3**. See [LICENSE](LICENSE).

> **服用注意 ・ Piru is not medical advice.** Its models are estimates. ♡
