<div align="center">

<img src=".github/piru-icon.png" alt="Piru 图标" width="128" height="128">

[![piru](https://readme-typing-svg.demolab.com/?font=DotGothic16&weight=400&size=22&duration=3800&pause=900&color=EB4470&center=true&vCenter=true&width=820&height=60&lines=%E5%89%82%E9%87%8F%E6%97%A5%E5%BF%97%E4%B8%8E%E7%AC%94%E8%AE%B0%E6%9C%AC%20%E2%99%A1;%E5%89%82%E9%87%8F%E4%B8%8D%E6%98%AF%E4%B8%80%E4%BB%BD%E4%BE%9B%E8%AF%8D;%E5%85%88%E5%86%99%E4%B8%8B%E6%9D%A5%EF%BC%8C%E6%A0%87%E9%A2%98%E5%8F%AF%E4%BB%A5%E7%AD%89%E7%AD%89;rx%20no.%20007%20%E3%83%BB%20%E6%9C%8D%E7%94%A8%E8%A8%98%E9%8C%B2%20%E3%83%BB%20%E8%B5%B7%E3%81%8D%E3%81%9F%E3%81%93%E3%81%A8%E3%82%92%E3%80%81%E6%9B%B8%E3%81%8D%E3%81%A8%E3%82%81%E3%82%8B)](https://kagerou.glass)

# piru

<a href="README.md">English</a> ・ <a href="README.zh-Hans.md">简体中文</a>


[![kagerou.glass](https://img.shields.io/badge/kagerou.glass-EB4470?style=for-the-badge&logo=safari&logoColor=white)](https://kagerou.glass/piru/)
[![TestFlight](https://img.shields.io/badge/TestFlight-%E5%8A%A0%E5%85%A5%E6%B5%8B%E8%AF%95-0D96F6?style=for-the-badge&logo=testflight&logoColor=white)](https://testflight.apple.com/join/4vcA7dY3)
[![Discord](https://img.shields.io/badge/Discord-%E5%8A%A0%E5%85%A5%E6%88%91%E4%BB%AC-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/hbpMZhPSdx)

<table>
  <tr>
    <td align="center"><img src=".github/piru-journal-zh.png" alt="日志，当天的剂量排在时间线上" width="290"></td>
    <td align="center"><img src=".github/piru-session-zh.png" alt="一次会话及其剂量与笔记" width="290"></td>
  </tr>
</table>

</div>

> 剂量不是一份供词。Piru 假定你清楚自己在做什么，只是想留一份记录：摄入了什么、在什么时候、注意到了什么。
> 这是剂量的问题，而非善恶的问题。♡

---

一款 iPhone 上的剂量日志与笔记本，附带离线参考资料库。

- **日志。** 记下你摄入了什么、在什么时候、多少。片剂规格、每日服药安排和提醒都排在当天的时间线旁；
  时间线上的曲线是估算。
- **会话与签到。** 在会话中随手写一条笔记，或事后再补。每条笔记都保留自己的时间戳、心情、强度和效应。
  经你授权，Apple 健康可以把心率和血压加到时间线上。
- **资料库。** 离线参考资料，提供 English、简体中文和繁體中文。每个条目都标明各字段的出处，
  出处不一致时由你决定以哪个为准。
- **回顾。** 查看你的记录和服药日历，清点库存，并把记录或一次会话导出为报告。

日志存储在你的设备上。没有账户、广告或分析。

## 获取测试版

在 [TestFlight](https://testflight.apple.com/join/4vcA7dY3) 上免费获取，需要 iOS 26 或更高版本。
问题和错误报告请发到 [Discord](https://discord.gg/hbpMZhPSdx)。

## 构建

用 Xcode 26 或更高版本打开 `Piru.xcodeproj`。物质数据库需要单独获取：克隆后、首次构建前运行
`pipeline/fetch-db.sh`。代码风格和工具见 [CONTRIBUTING.md](CONTRIBUTING.md#style)。

## 关于名字

**Piru**（ピル）在日语里是「药片」的意思，所以有那颗微笑的胶囊。名字和吉祥物来自这款 app 的原作者
[pharmacykitty](https://github.com/pharmacykitty)；[@kageroumado](https://x.com/kageroumado)
以 **rx no. 007** 的身份在 [kagerou.glass](https://kagerou.glass) 延续它。

## 致谢

资料库使用了 [substance.wiki](https://substance.wiki) 及其
[SubFxOnEx](https://github.com/Di-lemma/SubFxOnEx) 本体（LGPL-2.1）、
[PsychonautWiki](https://psychonautwiki.org)（CC BY-SA 4.0）、[FreeOD Wiki](https://freeodwiki.org)
（CC BY-SA 4.0）、[dose.wiki](https://dose.wiki)（CC0 1.0）、[TripSit](https://tripsit.me)、
[DailyMed](https://dailymed.nlm.nih.gov)、[PubChem](https://pubchem.ncbi.nlm.nih.gov)、
[Wikidata](https://www.wikidata.org)，以及 app 中引用的同行评审文献。

## 许可证

Piru 是依据 **GNU 通用公共许可证 v3** 发布的自由软件。见 [LICENSE](LICENSE)。

> **服用注意 ・ Piru 不是医疗建议。** 它的模型只是估算。♡
