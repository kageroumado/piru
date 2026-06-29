#!/usr/bin/env python3
"""Apply zh-Hans and zh-Hant translations to a Localizable.xcstrings catalog."""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

# Translations: English -> (Simplified, Traditional)
T = {
    # Pharmacology card hybrid redesign (2026-06-29): nav-bar detail-level (tier) switcher + merged card.
    "Detail level": ("详细程度", "詳細程度"),
    "Pharmacology": ("药理学", "藥理學"),
    # Step 3 — class-specific receptor-panel heroes (opioid / benzo / dissociative).
    "Minor / off-targets": ("次要／脱靶", "次要／脫靶"),
    "Full μ-opioid agonist": ("μ-阿片受体完全激动剂", "μ-阿片受體完全激動劑"),
    "Partial μ-opioid agonist": ("μ-阿片受体部分激动剂", "μ-阿片受體部分激動劑"),
    "μ-opioid antagonist": ("μ-阿片受体拮抗剂", "μ-阿片受體拮抗劑"),
    "GABA-A positive modulator": ("GABA-A 正向调节剂", "GABA-A 正向調節劑"),
    "Amplifies GABA — it doesn't open the channel on its own.": (
        "增强 GABA 的作用——它本身并不打开通道。",
        "增強 GABA 的作用——它本身並不打開通道。",
    ),
    "NMDA channel blocker": ("NMDA 通道阻滞剂", "NMDA 通道阻滯劑"),
    "Lower IC₅₀ / Kᵢ = more potent block.": (
        "IC₅₀／Kᵢ 越低 = 阻断作用越强。",
        "IC₅₀／Kᵢ 越低 = 阻斷作用越強。",
    ),
    "Sedation": ("镇静", "鎮靜"),
    "Anxiolysis": ("抗焦虑", "抗焦慮"),
    "Muscle": ("肌肉松弛", "肌肉鬆弛"),
    "Memory": ("记忆", "記憶"),
    # Step 4 — grouped receptor-literature table: short transporter-mechanism row labels.
    "Release": ("释放", "釋放"),
    "Reuptake": ("再摄取抑制", "再攝取抑制"),
    # Navbar consolidation: Share + one overflow "More" menu (Files-app pattern).
    "More": ("更多", "更多"),
    "Personalize Substance…": ("个性化此物质…", "個人化此物質…"),
    # Pharmacology card round-3 phase-2 (2026-06-28): elimination rows in the Metabolism card render as a
    # plain excretion line instead of a bogus "→ unchanged parent [active]" metabolite.
    "Renal excretion": ("经肾排泄", "經腎排泄"),
    "Biliary excretion": ("经胆汁排泄", "經膽汁排泄"),
    # 5-HT2B valvulopathy flag — plain, drug-relevant copy (dropped fenfluramine / "mechanistic flag").
    "Activates 5-HT2B, which is linked to heart-valve damage (valvulopathy) with chronic or heavy use.": (
        "激活 5-HT2B；长期或大量使用与心脏瓣膜损害（瓣膜病变）相关。",
        "活化 5-HT2B；長期或大量使用與心臟瓣膜損害（瓣膜病變）相關。",
    ),
    # Pharmacology card harmony pass — round 3 (2026-06-28): receptor strength help-sheet copy now
    # spells out the measurement-aware bands.
    "Measures how tightly the drug grips the target (Ki). A smaller number means a tighter grip — under 100 nM is strong, over 1000 nM is weak.": (
        "衡量药物与靶点结合的紧密程度（Ki）。数值越小，结合越紧密——低于 100 nM 为强，高于 1000 nM 为弱。",
        "衡量藥物與靶點結合的緊密程度（Ki）。數值越小，結合越緊密——低於 100 nM 為強，高於 1000 nM 為弱。",
    ),
    "Measures the dose needed to actually switch the target on or block it, rather than just stick to it. These run about 10× higher than binding, so the dots use a matching scale (under 1 µM strong, over 10 µM weak).": (
        "衡量真正激活或阻断靶点（而非仅仅附着其上）所需的剂量。其数值通常比结合亲和力高约 10 倍，因此圆点采用相应的刻度（低于 1 µM 为强，高于 10 µM 为弱）。",
        "衡量真正激活或阻斷靶點（而非僅僅附著其上）所需的劑量。其數值通常比結合親和力高約 10 倍，因此圓點採用相應的刻度（低於 1 µM 為強，高於 10 µM 為弱）。",
    ),
    # Pharmacology card harmony pass — round 2 (2026-06-28): shorter metabolic-modulation headlines
    # (drop substrate + period; we're on the substance's own card) + per-card help-sheet "about" text.
    "Repeated doses build up faster than the dose suggests": (
        "反复用药会比单次剂量所暗示的更快蓄积",
        "反覆用藥會比單次劑量所暗示的更快蓄積",
    ),
    "%@ may raise levels": ("%@ 可能升高其血药浓度", "%@ 可能升高其血藥濃度"),
    "%@ may lower levels": ("%@ 可能降低其血药浓度", "%@ 可能降低其血藥濃度"),
    "How the drug acts in the body — which receptors and transporters it targets, and what it does at each (switches them on, blocks them, and so on). The dots show how strongly it acts at each target.": (
        "药物在体内如何起作用——它作用于哪些受体和转运体，以及在每个靶点上做什么（激活、阻断等）。圆点表示它在各靶点上的作用强度。",
        "藥物在體內如何起作用——它作用於哪些受體和轉運體，以及在每個靶點上做什麼（激活、阻斷等）。圓點表示它在各靶點上的作用強度。",
    ),
    "A summary of how the drug affects the brain's three main signalling chemicals — serotonin, dopamine, and noradrenaline — and whether it releases them or blocks their reuptake. The slider shows which one it leans toward.": (
        "概述药物如何影响大脑三种主要的信号化学物质——5-羟色胺、多巴胺和去甲肾上腺素——以及它是促进释放还是阻断再摄取。滑块显示它更偏向哪一种。",
        "概述藥物如何影響大腦三種主要的訊號化學物質——5-羥色胺、多巴胺和去甲腎上腺素——以及它是促進釋放還是阻斷再攝取。滑桿顯示它更偏向哪一種。",
    ),
    "How your body breaks the drug down — which liver enzymes do the work, what byproducts (metabolites) form, and whether those are still active. The percentage is each enzyme's rough share of clearance.": (
        "身体如何分解药物——由哪些肝酶完成、生成哪些副产物（代谢物），以及这些代谢物是否仍具活性。百分比是每种酶在清除中的大致占比。",
        "身體如何分解藥物——由哪些肝酶完成、生成哪些副產物（代謝物），以及這些代謝物是否仍具活性。百分比是每種酶在清除中的大致占比。",
    ),
    "Everyday things — foods like grapefruit, smoking, or the drug's own buildup over repeated doses — can speed up or slow down how fast it's cleared, which raises or lowers its levels in the body.": (
        "日常因素——如西柚等食物、吸烟，或反复用药导致药物自身蓄积——都可能加快或减慢其清除速度，从而升高或降低其在体内的浓度。",
        "日常因素——如葡萄柚等食物、吸菸，或反覆用藥導致藥物自身蓄積——都可能加快或減慢其清除速度，從而升高或降低其在體內的濃度。",
    ),
    "Estimates from primary literature, not measured for you.": (
        "数据为原始文献中的估计值，并非针对你本人测量。",
        "數據為原始文獻中的估計值，並非針對你本人測量。",
    ),
    "Educated predictions from typical pharmacology, not measured for you.": (
        "根据典型药代动力学作出的推断，并非针对你本人测量。",
        "根據典型藥代動力學作出的推斷，並非針對你本人測量。",
    ),
    # Pharmacology card harmony pass (2026-06-28) — receptor binding/functional tags, PK + receptor
    # plain-language help sheet, "Additional Info" rename. Simple-vocabulary register to match the
    # English (these are the "complex things made understandable" glossary entries).
    "binding": ("结合", "結合"),
    "functional": ("功能", "功能"),
    "Binding": ("结合", "結合"),
    "Functional": ("功能", "功能"),
    "What do these mean?": ("这些是什么意思？", "這些是什麼意思？"),
    "Receptor data": ("受体数据", "受體數據"),
    "Additional Info": ("更多信息", "更多資訊"),
    "Strength dots": ("强度圆点", "強度圓點"),
    "nM (nanomolar)": ("nM（纳摩尔）", "nM（奈莫耳）"),
    "Human vs animal": ("人体与动物数据", "人體與動物數據"),
    "These are population averages from research — your own values vary with genetics, body size, and how the drug is taken.": (
        "这些是研究得出的群体平均值——你的实际数值会因遗传、体型以及用药方式而不同。",
        "這些是研究得出的群體平均值——你的實際數值會因遺傳、體型以及用藥方式而不同。",
    ),
    "Stronger doesn't mean more dangerous — it's just how tightly the drug grips that one target in the lab.": (
        "更强并不代表更危险——它只是表示在实验室中药物与该靶点结合的紧密程度。",
        "更強並不代表更危險——它只是表示在實驗室中藥物與該靶點結合的緊密程度。",
    ),
    "How much of a dose actually reaches your bloodstream. Swallowing a drug usually delivers less than injecting it.": (
        "一次用药中真正进入血液的比例。口服通常比注射进入血液的量更少。",
        "一次用藥中真正進入血液的比例。口服通常比注射進入血液的量更少。",
    ),
    "How long after taking it the level in your blood is highest — roughly when effects peak.": (
        "用药后多久血液中的浓度达到最高——大致也是效果最强的时刻。",
        "用藥後多久血液中的濃度達到最高——大致也是效果最強的時刻。",
    ),
    "The time for your body to clear half of what's left. It takes about five half-lives to clear almost all of it.": (
        "身体清除掉其中一半所需的时间。大约经过五个半衰期才能几乎完全清除。",
        "身體清除掉其中一半所需的時間。大約經過五個半衰期才能幾乎完全清除。",
    ),
    "The share that rides along stuck to blood proteins. Only the unbound rest is free to act.": (
        "附着在血浆蛋白上随之运行的比例。只有未结合的那部分才能发挥作用。",
        "附著在血漿蛋白上隨之運行的比例。只有未結合的那部分才能發揮作用。",
    ),
    "How widely the drug spreads from blood into the rest of the body. A bigger number means it soaks into tissues rather than staying in the blood.": (
        "药物从血液扩散到全身其他部位的广泛程度。数值越大，表示它越多渗入组织而非停留在血液中。",
        "藥物從血液擴散到全身其他部位的廣泛程度。數值越大，表示它越多滲入組織而非停留在血液中。",
    ),
    "How fast your body removes the drug, mostly via the liver and kidneys.": (
        "身体清除药物的速度，主要通过肝脏和肾脏。",
        "身體清除藥物的速度，主要透過肝臟和腎臟。",
    ),
    "The highest concentration reached in the blood after a dose.": (
        "一次用药后血液中达到的最高浓度。",
        "一次用藥後血液中達到的最高濃度。",
    ),
    "A quick read of how potent the drug is at that target — three dots is strong, one is weak. The same scale is used on the Mechanism card.": (
        "快速判断药物对该靶点的作用强度——三个点表示强，一个点表示弱。与「作用机制」卡片使用同一标准。",
        "快速判斷藥物對該靶點的作用強度——三個點表示強，一個點表示弱。與「作用機制」卡片使用同一標準。",
    ),
    "Measures how tightly the drug grips the target (Ki). A smaller number means a tighter grip.": (
        "衡量药物与靶点结合的紧密程度（Ki）。数值越小，结合越紧密。",
        "衡量藥物與靶點結合的緊密程度（Ki）。數值越小，結合越緊密。",
    ),
    "Measures the dose needed to actually switch the target on or block it, rather than just stick to it. Also smaller = more potent.": (
        "衡量真正激活或阻断靶点（而不仅仅是附着其上）所需的剂量。同样是数值越小、作用越强。",
        "衡量真正激活或阻斷靶點（而不僅僅是附著其上）所需的劑量。同樣是數值越小、作用越強。",
    ),
    "The concentration unit these values use. Lower numbers always mean the drug works at smaller amounts.": (
        "这些数值所用的浓度单位。数字越小，表示药物在更低的量下就能起作用。",
        "這些數值所用的濃度單位。數字越小，表示藥物在更低的量下就能起作用。",
    ),
    "Many values come from animal or lab-dish studies. Human data is the most reliable — the source tag tells you which it is.": (
        "许多数值来自动物或体外（培养皿）实验。人体数据最为可靠——来源标签会标明属于哪一种。",
        "許多數值來自動物或體外（培養皿）實驗。人體數據最為可靠——來源標籤會標明屬於哪一種。",
    ),
    # Pharmacology axis — RC-expansion UI: monoamine profile / provenance / contraceptive
    # caution / gabapentinoid ceiling (2026-06-24). Terminology grounded in a Chinese
    # clinical-pharmacology register: 5-羟色胺 (not 血清素), 再摄取 (not 重摄取),
    # 激动剂 (not 兴奋剂), 拮抗剂 for receptors; CYP/DAT/SERT/MDMA/α2δ kept in Latin.
    # MonoamineProfileCard — section header + mechanism labels
    "Monoamine Profile": ("单胺特征", "單胺特徵"),
    "Substrate releaser": ("释放剂（转运体底物）", "釋放劑（轉運體底物）"),
    "Reuptake blocker": ("再摄取抑制剂", "再攝取抑制劑"),
    "Mixed (releaser / blocker)": ("混合型（释放剂／抑制剂）", "混合型（釋放劑／抑制劑）"),
    "Reverses the transporters to pump monoamines out (substrate efflux) — the MDMA/amphetamine-type mechanism.": (
        "逆转转运体方向，将单胺类递质泵出细胞（底物外排）——即 MDMA／苯丙胺类的作用机制。",
        "逆轉轉運體方向，將單胺類遞質泵出細胞（底物外排）——即 MDMA／安非他命類的作用機制。",
    ),
    "Blocks reuptake without triggering release (cocaine/methylphenidate-type) — a different tolerance and redose profile from a releaser.": (
        "阻断再摄取但不促进释放（可卡因／哌甲酯类）——其耐受性与再用药特征与释放剂不同。",
        "阻斷再攝取但不促進釋放（古柯鹼／派醋甲酯類）——其耐受性與再用藥特徵與釋放劑不同。",
    ),
    "Releases at one transporter while blocking another — an intermediate profile; a single α-alkyl or N-ethyl group flips DAT from substrate to blocker.": (
        "在一种转运体上促进释放，在另一种上阻断再摄取——属中间类型；仅一个 α-烷基或 N-乙基取代即可使 DAT 由底物转为阻滞。",
        "在一種轉運體上促進釋放，在另一種上阻斷再攝取——屬中間類型；僅一個 α-烷基或 N-乙基取代即可使 DAT 由底物轉為阻滯。",
    ),
    # MonoamineProfileCard — lean labels
    "Balance not characterized (DAT or SERT data missing)": (
        "未能确定平衡（缺少 DAT 或 SERT 数据）",
        "未能確定平衡（缺少 DAT 或 SERT 資料）",
    ),
    "Serotonin-leaning (entactogenic)": ("偏向 5-羟色胺（致共情类）", "偏向 5-羥色胺（致共情類）"),
    "Balanced — empathogen-like": ("较为均衡——类似促共情剂", "較為均衡——類似促共情劑"),
    "Dopamine-leaning — more stimulant in character": (
        "偏向多巴胺——兴奋作用更突出",
        "偏向多巴胺——興奮作用更突出",
    ),
    "Strongly dopaminergic (SERT-sparing)": (
        "强多巴胺能（对 SERT 作用很弱）",
        "強多巴胺能（對 SERT 作用很弱）",
    ),
    "Serotonin": ("5-羟色胺", "5-羥色胺"),
    "Dopamine": ("多巴胺", "多巴胺"),
    # MonoamineProfileCard — harm-reduction flags + footnote
    "Engages 5-HT2B — the valvular-heart-disease antitarget. Chronic 5-HT2B agonism is what made fenfluramine cardiotoxic, so it is a mechanistic flag for repeated or heavy dosing.": (
        "激动 5-HT2B——与心脏瓣膜病相关的有害脱靶受体。长期激动 5-HT2B 正是芬氟拉明致心脏毒性的原因，因此对反复或大剂量用药，这是机制层面的警示。",
        "激動 5-HT2B——與心臟瓣膜病相關的有害脫靶受體。長期激動 5-HT2B 正是芬氟拉明致心臟毒性的原因，因此對反覆或大劑量用藥，這是機制層面的警示。",
    ),
    "Often mis-sold as MDMA / “molly,” but it is pharmacologically a reuptake blocker — longer, more stimulant and anxiogenic, and more dangerous on an empathogen-style redose.": (
        "常被冒充为 MDMA／“molly”出售，但其药理上是再摄取抑制剂——作用更持久、更偏兴奋和致焦虑，按 empathogen 方式追加剂量时更危险。",
        "常被冒充為 MDMA／「molly」出售，但其藥理上是再攝取抑制劑——作用更持久、更偏興奮和致焦慮，按 empathogen 方式追加劑量時更危險。",
    ),
    "Derived from this substance's graded DAT/NET/SERT bindings. Transporter potencies are mostly within-assay ratios, not absolute cross-platform numbers.": (
        "依据该物质经分级的 DAT/NET/SERT 结合数据得出。转运体效价多为同一实验内的相对比值，而非跨平台的绝对数值。",
        "依據該物質經分級的 DAT/NET/SERT 結合資料得出。轉運體效價多為同一實驗內的相對比值，而非跨平台的絕對數值。",
    ),
    # ProvenanceBadge — method labels + accessibility
    "Human": ("人体", "人體"),
    "Rat": ("大鼠", "大鼠"),
    "Mouse": ("小鼠", "小鼠"),
    "Animal": ("动物", "動物"),
    "In-vitro": ("体外", "體外"),
    "Aggregated": ("综合来源", "綜合來源"),
    "human assay": ("人体实验", "人體實驗"),
    "rat assay": ("大鼠实验", "大鼠實驗"),
    "mouse assay": ("小鼠实验", "小鼠實驗"),
    "animal assay": ("动物实验", "動物實驗"),
    "in-vitro assay": ("体外实验", "體外實驗"),
    "aggregator source": ("综合来源", "綜合來源"),
    "Evidence source: %@, %@": ("数据来源：%@，%@", "數據來源：%@，%@"),
    # ContraceptionCautionBanner
    "May reduce hormonal birth-control efficacy": (
        "可能降低激素类避孕药的效果",
        "可能降低激素類避孕藥的效果",
    ),
    "Induces %@, which clears the hormones in the combined pill, patch, ring, implant and hormonal IUD — lowering their levels. Anyone relying on hormonal contraception should consider a backup method. Often noted on the label, but easy to miss.": (
        "可诱导 %@，加速复方口服避孕药、避孕贴剂、阴道避孕环、皮下埋植剂及含激素宫内节育器中激素的代谢，从而降低其血药浓度。依赖激素类避孕的人群应考虑采用备用避孕措施。说明书中通常有提示，但容易被忽略。",
        "可誘導 %@，加速複方口服避孕藥、避孕貼劑、陰道避孕環、皮下埋植劑及含激素宮內節育器中激素的代謝，從而降低其血藥濃度。依賴激素類避孕的人群應考慮採用備用避孕措施。說明書中通常有提示，但容易被忽略。",
    ),
    # MetabolicModulation catalog — modafinil / armodafinil as CYP3A4 inducers
    "Modafinil": ("莫达非尼", "莫達非尼"),
    "Armodafinil": ("阿莫达非尼", "阿莫達非尼"),
    "Modafinil induces CYP3A4, lowering the levels of drugs cleared by it — including the hormones in systemic contraception.": (
        "莫达非尼可诱导 CYP3A4，降低经其清除的药物的血药浓度——包括全身性激素避孕药中的激素。",
        "莫達非尼可誘導 CYP3A4，降低經其清除的藥物的血藥濃度——包括全身性激素避孕藥中的激素。",
    ),
    "Armodafinil induces CYP3A4, lowering the levels of drugs cleared by it — including the hormones in systemic contraception.": (
        "阿莫达非尼可诱导 CYP3A4，降低经其清除的药物的血药浓度——包括全身性激素避孕药中的激素。",
        "阿莫達非尼可誘導 CYP3A4，降低經其清除的藥物的血藥濃度——包括全身性激素避孕藥中的激素。",
    ),
    # CeilingEffectToolView — gabapentinoid comparison card + readouts
    "Same class, opposite behavior": ("同类药物，行为相反", "同類藥物，行為相反"),
    "Gabapentin vs pregabalin — one absorbing target, two opposite dose curves": (
        "加巴喷丁与普瑞巴林——同一吸收靶点，两条相反的剂量曲线",
        "加巴噴丁與普瑞巴林——同一吸收靶點，兩條相反的劑量曲線",
    ),
    "Gabapentin — falls with dose": ("加巴喷丁——随剂量下降", "加巴噴丁——隨劑量下降"),
    "Pregabalin — flat ~90%": ("普瑞巴林——稳定在约 90%", "普瑞巴林——穩定在約 90%"),
    "Fraction reaching your blood (up the side) against dose (along the bottom, as a multiple of the usual starting dose).": (
        "进入血液的比例（纵轴）随剂量（横轴，以常用起始剂量的倍数表示）的变化。",
        "進入血液的比例（縱軸）隨劑量（橫軸，以常用起始劑量的倍數表示）的變化。",
    ),
    "Bioavailability versus dose: gabapentin falls as the dose rises, pregabalin stays flat.": (
        "生物利用度随剂量的变化：加巴喷丁随剂量升高而下降，普瑞巴林保持平稳。",
        "生物利用度隨劑量的變化：加巴噴丁隨劑量升高而下降，普瑞巴林保持平穩。",
    ),
    "Saturable absorption — exposure climbs slower than dose": (
        "可饱和吸收——暴露量的上升慢于剂量",
        "可飽和吸收——暴露量的上升慢於劑量",
    ),
    "%@× the dose is only about %@× the exposure — past the knee, extra drug mostly isn't absorbed.": (
        "%@ 倍剂量仅约带来 %@ 倍暴露量——越过拐点后，多出的药物大多不再被吸收。",
        "%@ 倍劑量僅約帶來 %@ 倍暴露量——越過拐點後，多出的藥物大多不再被吸收。",
    ),
    # SaturablePharmacology — gabapentinoid comparison + gabapentin/tramadol profiles
    "Tramadol → O-DSMT (M1)": ("曲马多 → O-DSMT (M1)", "曲馬多 → O-DSMT (M1)"),
    "The carrier is already saturating across the normal dose range: bioavailability falls from ~60% at 900 mg/day to ~27% at 4800 mg/day, so each step up buys progressively less.": (
        "在常用剂量范围内该载体就已趋于饱和：生物利用度从 900 mg/日 时的约 60% 降至 4800 mg/日 时的约 27%，因此每加大一档，获益越来越少。",
        "在常用劑量範圍內該載體就已趨於飽和：生物利用度從 900 mg/日 時的約 60% 降至 4800 mg/日 時的約 27%，因此每加大一檔，獲益越來越少。",
    ),
    "There is no fixed milligram knee — the limit (or its absence) is set by your CYP2D6 activity. Poor metabolizers get little opioid effect but keep tramadol's serotonin/seizure risk; ultra-rapid metabolizers blow past the usual ceiling.": (
        "并不存在固定的毫克拐点——其上限（或没有上限）取决于你的 CYP2D6 活性。慢代谢者获得的阿片效应很弱，却仍保留曲马多的 5-羟色胺／癫痫风险；超快代谢者则会突破通常的封顶。",
        "並不存在固定的毫克拐點——其上限（或沒有上限）取決於你的 CYP2D6 活性。慢代謝者獲得的鴉片效應很弱，卻仍保留曲馬多的 5-羥色胺／癲癇風險；超快代謝者則會突破通常的封頂。",
    ),
    "Two drugs that hit the same target behave oppositely as you scale the dose: gabapentin's absorbed fraction falls, pregabalin's stays put.": (
        "两种作用于同一靶点的药物，在加大剂量时表现相反：加巴喷丁吸收的比例下降，普瑞巴林则保持不变。",
        "兩種作用於同一靶點的藥物，在加大劑量時表現相反：加巴噴丁吸收的比例下降，普瑞巴林則保持不變。",
    ),
    "Both bind the α2δ-1 calcium-channel subunit — but gabapentin rides a saturable intestinal carrier (system-L / LAT1), so the fraction absorbed drops as the dose climbs (~60% → ~27%) and exposure flattens out. That's why gabapentin is dosed several times a day and why very large single doses buy little extra. Pregabalin uses the carrier without saturating it, so it stays ~90% absorbed at any dose — predictable, dose-proportional, simpler to titrate. (Pregabalin is also effective at far fewer milligrams, so its line sits at the low end of the dose axis.)": (
        "两者都结合电压门控钙通道的 α2δ-1 亚基——但加巴喷丁依赖一种可饱和的肠道载体（system-L／LAT1），因此随着剂量升高，吸收的比例下降（约 60% → 约 27%），暴露量趋于平缓。这正是加巴喷丁每日需分多次服用、以及单次大剂量收效甚微的原因。普瑞巴林利用同一载体但不会使其饱和，因此在任何剂量下都保持约 90% 的吸收——可预测、与剂量成比例、更易于滴定。（普瑞巴林在低得多的毫克数下即有效，因此其曲线位于剂量轴的低端。）",
        "兩者都結合電壓門控鈣通道的 α2δ-1 亞基——但加巴噴丁依賴一種可飽和的腸道載體（system-L／LAT1），因此隨著劑量升高，吸收的比例下降（約 60% → 約 27%），暴露量趨於平緩。這正是加巴噴丁每日需分多次服用、以及單次大劑量收效甚微的原因。普瑞巴林利用同一載體但不會使其飽和，因此在任何劑量下都保持約 90% 的吸收——可預測、與劑量成比例、更易於滴定。（普瑞巴林在低得多的毫克數下即有效，因此其曲線位於劑量軸的低端。）",
    ),
    "Gabapentin is absorbed by a carrier that runs out of capacity, so the fraction that reaches your blood DROPS as the dose climbs — taking twice as much delivers much less than twice the exposure.": (
        "加巴喷丁由一种容量有限的载体吸收，因此随着剂量升高，进入血液的比例反而下降——服用两倍的量，带来的暴露量远不到两倍。",
        "加巴噴丁由一種容量有限的載體吸收，因此隨著劑量升高，進入血液的比例反而下降——服用兩倍的量，帶來的暴露量遠不到兩倍。",
    ),
    "This is the opposite of the alcohol/phenytoin ceiling: there the clearing enzyme saturates and exposure runs away upward; here the absorbing transporter (system-L / LAT1) saturates and exposure flattens out — a built-in brake, not a danger, though it also caps the benefit of very large single doses and is why gabapentin is dosed several times a day. Pregabalin, the same drug class, uses the transporter differently and stays ~90% absorbed at any dose (dose-linear) — a clean contrast in the same family. Shown as relative shape, not absolute level.": (
        "这与酒精／苯妥英的“封顶”恰好相反：那里是清除酶饱和、暴露量失控上升；而这里是吸收转运体（system-L／LAT1）饱和、暴露量趋于平缓——这是一种内在的制动，而非危险，不过它也限制了单次大剂量的获益，并且正是加巴喷丁每日分多次服用的原因。普瑞巴林虽属同一药物类别，却以不同方式利用该转运体，在任何剂量下都保持约 90% 的吸收（与剂量呈线性）——是同类药物中一个清晰的对照。此处显示的是相对形态，而非绝对水平。",
        "這與酒精／苯妥英的「封頂」恰好相反：那裡是清除酶飽和、暴露量失控上升；而這裡是吸收轉運體（system-L／LAT1）飽和、暴露量趨於平緩——這是一種內在的制動，而非危險，不過它也限制了單次大劑量的獲益，並且正是加巴噴丁每日分多次服用的原因。普瑞巴林雖屬同一藥物類別，卻以不同方式利用該轉運體，在任何劑量下都保持約 90% 的吸收（與劑量呈線性）——是同類藥物中一個清晰的對照。此處顯示的是相對形態，而非絕對水平。",
    ),
    "Tramadol only becomes a strong opioid after CYP2D6 converts it to M1 — and how much you make depends on your genes, not just the dose. Most people plateau; “ultra-rapid metabolizers” have no such cap and can reach dangerous levels at ordinary doses.": (
        "曲马多只有在 CYP2D6 将其转化为 M1 后才成为强效阿片类药物——而生成多少取决于你的基因，而不仅仅是剂量。多数人会达到平台；“超快代谢者”则没有这种上限，在普通剂量下也可能达到危险水平。",
        "曲馬多只有在 CYP2D6 將其轉化為 M1 後才成為強效鴉片類藥物——而生成多少取決於你的基因，而不僅僅是劑量。多數人會達到平台；「超快代謝者」則沒有這種上限，在普通劑量下也可能達到危險水平。",
    ),
    "This is the mirror image of codeine: same CYP2D6 activation step, opposite danger. Two cautions. (1) Repeated dosing raises tramadol's own absorption (first-pass saturates, F climbs ~75%→90–100%), so steady-state levels run higher than a single dose predicts. (2) The opioid limb is carried almost entirely by the metabolite M1/O-DSMT (a potent 3.4 nM µ-agonist), so strong CYP2D6 inhibitors (paroxetine, fluoxetine, bupropion, quinidine) mute the painkilling effect while leaving — or raising — the serotonergic and seizure risk of the parent. “Cleaner” is not “safer.” Described, not drawn.": (
        "这是可待因的镜像：同样的 CYP2D6 活化步骤，危险却相反。两点提醒。(1) 反复给药会提高曲马多自身的吸收（首过代谢饱和，生物利用度由约 75% 升至 90–100%），因此稳态血药浓度高于单次剂量的预测值。(2) 阿片效应几乎完全由代谢物 M1／O-DSMT（一种强效的 3.4 nM µ 受体激动剂）承载，因此强效 CYP2D6 抑制剂（帕罗西汀、氟西汀、安非他酮、奎尼丁）会削弱镇痛作用，同时保留——甚至升高——原药的 5-羟色胺能及致癫痫风险。“更干净”并不等于“更安全”。此处为文字描述，未绘制曲线。",
        "這是可待因的鏡像：同樣的 CYP2D6 活化步驟，危險卻相反。兩點提醒。(1) 反覆給藥會提高曲馬多自身的吸收（首過代謝飽和，生物利用度由約 75% 升至 90–100%），因此穩態血藥濃度高於單次劑量的預測值。(2) 鴉片效應幾乎完全由代謝物 M1／O-DSMT（一種強效的 3.4 nM µ 受體激動劑）承載，因此強效 CYP2D6 抑制劑（帕羅西汀、氟西汀、安非他酮、奎尼丁）會削弱鎮痛作用，同時保留——甚至升高——原藥的 5-羥色胺能及致癲癇風險。「更乾淨」並不等於「更安全」。此處為文字描述，未繪製曲線。",
    ),
    # Pharmacology axis Stage 3b — Combined depression index (2026-06-21)
    "Combined depression": ("综合抑制", "綜合抑制"),
    "Combined respiratory depression peaks around %@.": (
        "综合呼吸抑制约在 %@ 达到峰值。",
        "綜合呼吸抑制約在 %@ 達到峰值。",
    ),
    "Severe": ("严重", "嚴重"),
    "High": ("高", "高"),
    "Moderate": ("中等", "中等"),
    "Predicted from receptor occupancy · %@.": (
        "依据受体占据率预测 · %@。",
        "依據受體佔據率預測 · %@。",
    ),
    "Estimated from effect curves · %@.": (
        "依据效应曲线估算 · %@。",
        "依據效應曲線估算 · %@。",
    ),
    "%lld of %lld substances from receptor occupancy, the rest estimated from effect curves · %@.": (
        "%lld/%lld 种物质来自受体占据率，其余依据效应曲线估算 · %@。",
        "%lld/%lld 種物質來自受體佔據率，其餘依據效應曲線估算 · %@。",
    ),
    "Predicted combined depression · %@.": (
        "预测综合抑制 · %@。",
        "預測綜合抑制 · %@。",
    ),
    "%@ combined depression · predicted (model, %@).": (
        "%@综合抑制 · 预测（模型，%@）。",
        "%@綜合抑制 · 預測（模型，%@）。",
    ),
    # Pharmacology axis Stage 3c — effect attenuation (2026-06-21)
    "serotonin transporter": ("血清素转运体", "血清素轉運體"),
    "Reduced effect": ("效果减弱", "效果減弱"),
    "%@ may feel weaker — %@ blocks the %@ it needs to work.": (
        "%@ 的效果可能减弱——%@ 阻断了它起效所需的%@。",
        "%@ 的效果可能減弱——%@ 阻斷了它起效所需的%@。",
    ),
    "Predicted ~%@ reduced effect · predicted (model, %@). Reduced effect, not a danger warning.": (
        "预测效果减弱约 %@ · 预测（模型，%@）。这是效果减弱，并非危险警告。",
        "預測效果減弱約 %@ · 預測（模型，%@）。這是效果減弱，並非危險警告。",
    ),
    "%@ blocks the %@ that %@ needs to work, so %@ is predicted to feel ~%@ weaker.": (
        "%@ 阻断了 %@，而 %@ 起效需要它，因此预计 %@ 的效果会减弱约 %@。",
        "%@ 阻斷了 %@，而 %@ 起效需要它，因此預計 %@ 的效果會減弱約 %@。",
    ),
    "This is a reduced effect, not a danger warning · predicted (model, %@).": (
        "这是效果减弱，并非危险警告 · 预测（模型，%@）。",
        "這是效果減弱，並非危險警告 · 預測（模型，%@）。",
    ),
    # Pharmacology axis Stage 4a — cross-tolerance readout (2026-06-21)
    "Reduced response predicted — ~%lld%% of rested.": (
        "预计反应减弱——约为静息状态的 %lld%%。",
        "預計反應減弱——約為靜息狀態的 %lld%%。",
    ),
    "Shared %@ tolerance · predicted (model, %@).": (
        "共享的%@耐受 · 预测（模型，%@）。",
        "共享的%@耐受 · 預測（模型，%@）。",
    ),
    "Shared %@ tolerance from %@ · predicted (model, %@).": (
        "来自 %2$@ 的 %1$@ 耐受 · 预测（模型，%3$@）。",
        "來自 %2$@ 的 %1$@ 耐受 · 預測（模型，%3$@）。",
    ),
    # Pharmacology axis Stage 4d — combination metabolite / cocaethylene (2026-06-22)
    "Combination Products": ("组合产物", "組合產物"),
    "Cocaethylene": ("可卡乙烯", "古柯乙烯"),
    "Cocaine and alcohol together form cocaethylene — an active stimulant your body makes only while both are present. It lasts noticeably longer than cocaine, so the stimulant effect (and its strain) is drawn out.": (
        "可卡因与酒精同时使用时，身体会生成可卡乙烯——一种只在两者同时存在时才形成的活性兴奋剂。它的持续时间明显长于可卡因，因此兴奋作用（及其带来的负担）会被拉长。",
        "古柯鹼與酒精同時使用時，身體會生成古柯乙烯——一種只在兩者同時存在時才形成的活性興奮劑。它的持續時間明顯長於古柯鹼，因此興奮作用（及其帶來的負擔）會被拉長。",
    ),
    'Cocaethylene adds extra strain on the heart and liver beyond cocaine alone, so this combination is harder on your body. (The widely-repeated "18–25× sudden death" figure is not supported by the evidence — but the added cardiac and liver strain is real, so it\'s worth avoiding the mix.)': (
        "相比单用可卡因，可卡乙烯会给心脏和肝脏带来额外负担，因此这种组合对身体的伤害更大。（广为流传的“猝死风险增加18–25倍”的说法并无证据支持——但对心脏和肝脏的额外负担是真实的，因此值得避免这种混用。）",
        "相比單用古柯鹼，古柯乙烯會給心臟和肝臟帶來額外負擔，因此這種組合對身體的傷害更大。（廣為流傳的「猝死風險增加18–25倍」的說法並無證據支持——但對心臟和肝臟的額外負擔是真實的，因此值得避免這種混用。）",
    ),
    # Pharmacology axis Stage 4c — metabolic modulation (2026-06-21)
    "%@ may raise %@ levels (%@).": (
        "%1$@ 可能升高 %2$@ 的血药浓度（%3$@）。",
        "%1$@ 可能升高 %2$@ 的血藥濃度（%3$@）。",
    ),
    "%@ may lower %@ levels (%@).": (
        "%1$@ 可能降低 %2$@ 的血药浓度（%3$@）。",
        "%1$@ 可能降低 %2$@ 的血藥濃度（%3$@）。",
    ),
    "%@ may raise %@ levels.": (
        "%1$@ 可能升高 %2$@ 的血药浓度。",
        "%1$@ 可能升高 %2$@ 的血藥濃度。",
    ),
    "%@ may lower %@ levels.": (
        "%1$@ 可能降低 %2$@ 的血药浓度。",
        "%1$@ 可能降低 %2$@ 的血藥濃度。",
    ),
    "Predicted": (
        "预测",
        "預測",
    ),
    "Time to peak": (
        "达峰时间",
        "達峰時間",
    ),
    "Protein binding": (
        "血浆蛋白结合",
        "血漿蛋白結合",
    ),
    "Distribution": (
        "分布容积",
        "分布容積",
    ),
    "Clearance": (
        "清除率",
        "清除率",
    ),
    "Peak level": (
        "峰浓度",
        "峰濃度",
    ),
    "Fraction-of-clearance estimates and major metabolites from primary literature. Which enzymes clear a drug is what grapefruit, smoking, and interacting medications act on — see Metabolism Interactions below.": (
        "清除分数估计值与主要代谢物，来自原始文献。哪些酶负责清除药物，正是西柚、吸烟和相互作用药物所作用的对象——参见下方的“代谢相互作用”。",
        "清除分數估計值與主要代謝物，來自原始文獻。哪些酶負責清除藥物，正是西柚、吸菸和交互作用藥物所作用的對象——參見下方的「代謝交互作用」。",
    ),
    "Repeated %@ doses build up faster than the dose suggests.": (
        "重复服用 %@ 会比剂量显示的更快累积。",
        "重複服用 %@ 會比劑量顯示的更快累積。",
    ),
    "%@ · predicted (model, %@).": (
        "%@ · 预测（模型，%@）。",
        "%@ · 預測（模型，%@）。",
    ),
    "I smoke tobacco regularly": ("我经常吸烟", "我經常吸菸"),
    "Grapefruit dose logging": ("西柚剂量记录", "葡萄柚劑量記錄"),
    "Metabolic Effects": ("代谢影响", "代謝影響"),
    "Metabolism Interactions": ("代谢相互作用", "代謝交互作用"),
    "Had grapefruit with this dose": ("此剂量同服了西柚", "此劑量同服了葡萄柚"),
    "Tobacco smoke speeds up CYP1A2, so it lowers the levels of some drugs (like caffeine and olanzapine). Grapefruit slows down CYP3A4, raising the levels of others — turn on grapefruit logging to mark it on individual doses of affected substances. Both are shown only where they actually change a drug's levels.": (
        "烟草烟雾会加快 CYP1A2，从而降低某些药物（如咖啡因和奥氮平）的血药浓度。西柚会减慢 CYP3A4，升高另一些药物的浓度——开启西柚记录后，可在受影响物质的单次剂量上标记它。两者仅在确实会改变某药物浓度时才显示。",
        "菸草煙霧會加快 CYP1A2，從而降低某些藥物（如咖啡因和奧氮平）的血藥濃度。葡萄柚會減慢 CYP3A4，升高另一些藥物的濃度——開啟葡萄柚記錄後，可在受影響物質的單次劑量上標記它。兩者僅在確實會改變某藥物濃度時才顯示。",
    ),
    "How grapefruit, smoking, and this drug's own metabolism can change its levels. Educational — predicted from typical pharmacokinetics, not measured for you.": (
        "西柚、吸烟以及该药自身的代谢如何改变其血药浓度。仅供参考——根据典型药代动力学预测，并非针对你的实测。",
        "葡萄柚、吸菸以及該藥自身的代謝如何改變其血藥濃度。僅供參考——根據典型藥物動力學預測，並非針對你的實測。",
    ),
    # Stage 4c — modulator catalog display names + notes
    "Grapefruit": ("西柚", "葡萄柚"),
    "Tobacco smoking": ("吸烟", "吸菸"),
    "Ritonavir": ("利托那韦", "利托那韋"),
    "Fluvoxamine": ("氟伏沙明", "氟伏沙明"),
    "Carbamazepine": ("卡马西平", "卡馬西平"),
    "Rifampicin": ("利福平", "利福平"),
    "St John's Wort": ("圣约翰草", "聖約翰草"),
    "MDMA": ("MDMA", "MDMA"),
    "Grapefruit (and related citrus) inhibits intestinal CYP3A4 for roughly 1–3 days, raising the levels of drugs cleared by it.": (
        "西柚（及相关柑橘）会抑制肠道 CYP3A4 约 1–3 天，升高经该酶清除的药物的血药浓度。",
        "葡萄柚（及相關柑橘）會抑制腸道 CYP3A4 約 1–3 天，升高經該酶清除的藥物的血藥濃度。",
    ),
    "Tobacco smoke induces CYP1A2, lowering the levels of drugs cleared by it. Quitting reverses this over about a week and can raise levels.": (
        "烟草烟雾会诱导 CYP1A2，降低经该酶清除的药物的血药浓度。戒烟后约一周内逆转，可能使浓度升高。",
        "菸草煙霧會誘導 CYP1A2，降低經該酶清除的藥物的血藥濃度。戒菸後約一週內逆轉，可能使濃度升高。",
    ),
    "Ritonavir strongly inhibits CYP3A4, sharply raising the levels of drugs cleared by it.": (
        "利托那韦强烈抑制 CYP3A4，显著升高经该酶清除的药物的血药浓度。",
        "利托那韋強烈抑制 CYP3A4，顯著升高經該酶清除的藥物的血藥濃度。",
    ),
    "Fluvoxamine strongly inhibits CYP1A2, raising the levels of drugs cleared by it.": (
        "氟伏沙明强烈抑制 CYP1A2，升高经该酶清除的药物的血药浓度。",
        "氟伏沙明強烈抑制 CYP1A2，升高經該酶清除的藥物的血藥濃度。",
    ),
    "Carbamazepine induces CYP3A4, lowering the levels of drugs cleared by it.": (
        "卡马西平诱导 CYP3A4，降低经该酶清除的药物的血药浓度。",
        "卡馬西平誘導 CYP3A4，降低經該酶清除的藥物的血藥濃度。",
    ),
    "Rifampicin strongly induces CYP3A4, markedly lowering the levels of drugs cleared by it.": (
        "利福平强烈诱导 CYP3A4，明显降低经该酶清除的药物的血药浓度。",
        "利福平強烈誘導 CYP3A4，明顯降低經該酶清除的藥物的血藥濃度。",
    ),
    "St John's Wort induces CYP3A4, lowering the levels of drugs cleared by it (magnitude varies by product).": (
        "圣约翰草诱导 CYP3A4，降低经该酶清除的药物的血药浓度（强度因产品而异）。",
        "聖約翰草誘導 CYP3A4，降低經該酶清除的藥物的血藥濃度（強度因產品而異）。",
    ),
    "MDMA inactivates the CYP2D6 that clears it, so repeated or closely-spaced doses build up disproportionately rather than in proportion to the dose. The enzyme recovers over about 10 days.": (
        "MDMA 会使清除它的 CYP2D6 失活，因此反复或间隔很短的用药会不成比例地累积，而非与剂量成正比。该酶约需 10 天恢复。",
        "MDMA 會使清除它的 CYP2D6 失活，因此反覆或間隔很短的用藥會不成比例地累積，而非與劑量成正比。該酶約需 10 天恢復。",
    ),
    # Antidepressant + empathogen reframed as myth-buster (blunting, not serotonin syndrome) (2026-06-21)
    "SSRIs blunt MDMA — it may feel much weaker or not work. On their own they don't cause serotonin syndrome.": (
        "SSRI 会减弱 MDMA 的效果——可能明显变弱甚至无效。两者单独合用不会引起血清素综合征。",
        "SSRI 會減弱 MDMA 的效果——可能明顯變弱甚至無效。兩者單獨併用不會引起血清素症候群。",
    ),
    "SNRIs blunt MDMA — it may feel weaker. On their own they don't cause serotonin syndrome.": (
        "SNRI 会减弱 MDMA 的效果——可能变弱。两者单独合用不会引起血清素综合征。",
        "SNRI 會減弱 MDMA 的效果——可能變弱。兩者單獨併用不會引起血清素症候群。",
    ),
    "TCAs blunt MDMA — it may feel weaker. On their own they don't cause serotonin syndrome.": (
        "三环类抗抑郁药会减弱 MDMA 的效果——可能变弱。两者单独合用不会引起血清素综合征。",
        "三環類抗憂鬱藥會減弱 MDMA 的效果——可能變弱。兩者單獨併用不會引起血清素症候群。",
    ),
    # Serotonergic special cases — evidence-grounded rules (Foundation-C run, 2026-06-22)
    "SSRIs usually blunt MDMA — it may feel much weaker, so people often redose into trouble (overheating, heart strain). On their own they don't cause serotonin syndrome.": (
        "SSRI 通常会减弱 MDMA 的效果——可能明显变弱，于是人们常常追加剂量而出问题（过热、心脏负担）。两者单独合用不会引起血清素综合征。",
        "SSRI 通常會減弱 MDMA 的效果——可能明顯變弱，於是人們常常追加劑量而出問題（過熱、心臟負擔）。兩者單獨併用不會引起血清素症候群。",
    ),
    "SNRIs usually blunt MDMA — it may feel weaker, so people often redose into trouble (overheating, heart strain). On their own they don't cause serotonin syndrome.": (
        "SNRI 通常会减弱 MDMA 的效果——可能变弱，于是人们常常追加剂量而出问题（过热、心脏负担）。两者单独合用不会引起血清素综合征。",
        "SNRI 通常會減弱 MDMA 的效果——可能變弱，於是人們常常追加劑量而出問題（過熱、心臟負擔）。兩者單獨併用不會引起血清素症候群。",
    ),
    "TCAs usually blunt MDMA rather than boosting it, so people may redose; the bigger concern is added strain on heart rate and blood pressure.": (
        "三环类抗抑郁药通常会减弱 MDMA 等药物的效果，而非增强，因此人们可能追加剂量；更需注意的是对心率和血压的额外负担。",
        "三環類抗憂鬱藥通常會減弱 MDMA 等藥物的效果，而非增強，因此人們可能追加劑量；更需注意的是對心率和血壓的額外負擔。",
    ),
    "Serotonin syndrome risk — these drugs add serotonin on top of an empathogen's surge. Some (tramadol, meperidine) can also trigger seizures.": (
        "血清素综合征风险——这些药物会在摇头丸（MDMA）已升高的血清素之上继续增加。部分药物（曲马多、哌替啶）还可能诱发癫痫发作。",
        "血清素症候群風險——這些藥物會在搖頭丸（MDMA）已升高的血清素之上繼續增加。部分藥物（曲馬多、哌替啶）還可能誘發癲癇發作。",
    ),
    "Serotonin syndrome — potentially fatal. Do not combine.": (
        "血清素综合征——可能致命。请勿合用。",
        "血清素症候群——可能致命。請勿併用。",
    ),
    "Serotonin syndrome risk — two serotonin-raising drugs stacked together.": (
        "血清素综合征风险——两种升高血清素的药物叠加使用。",
        "血清素症候群風險——兩種升高血清素的藥物疊加使用。",
    ),
    "Serotonin syndrome risk — a serotonin-raising drug stacked with an SSRI.": (
        "血清素综合征风险——升高血清素的药物与 SSRI 叠加。",
        "血清素症候群風險——升高血清素的藥物與 SSRI 疊加。",
    ),
    "Serotonin syndrome risk — a serotonin-raising drug stacked with an SNRI.": (
        "血清素综合征风险——升高血清素的药物与 SNRI 叠加。",
        "血清素症候群風險——升高血清素的藥物與 SNRI 疊加。",
    ),
    "Serotonin syndrome risk — a serotonin-raising drug stacked with a tricyclic antidepressant.": (
        "血清素综合征风险——升高血清素的药物与三环类抗抑郁药叠加。",
        "血清素症候群風險——升高血清素的藥物與三環類抗憂鬱藥疊加。",
    ),
    "Increased serotonin syndrome risk — lithium adds to the serotonergic load.": (
        "血清素综合征风险增加——锂会增加血清素负荷。",
        "血清素症候群風險增加——鋰會增加血清素負荷。",
    ),
    # Alpha-2 agonists + beta-blockers (Foundation-C run, 2026-06-22)
    "Heavy sedation with a dangerously slow heart rate and breathing. Naloxone reverses the opioid but NOT the alpha-2 part — give rescue breaths and call for help even after naloxone.": (
        "强烈镇静，伴心率和呼吸危险性减慢。纳洛酮能逆转阿片，但无法逆转 alpha-2 的作用——即使用了纳洛酮，也要进行人工呼吸并呼叫求助。",
        "強烈鎮靜，伴心率和呼吸危險性減慢。納洛酮能逆轉鴉片，但無法逆轉 alpha-2 的作用——即使用了納洛酮，也要進行人工呼吸並呼叫求助。",
    ),
    "Adds up sedation and lowers blood pressure further — expect stronger drowsiness and dizziness. Use less and don't drive.": (
        "镇静叠加并进一步降低血压——困倦和头晕会更明显。减量，且不要开车。",
        "鎮靜疊加並進一步降低血壓——睏倦和頭暈會更明顯。減量，且不要開車。",
    ),
    "Compounded sedation and low blood pressure — stronger drowsiness and dizziness.": (
        "镇静与低血压叠加——困倦和头晕加重。",
        "鎮靜與低血壓疊加——睏倦和頭暈加重。",
    ),
    "Additive sedation and low blood pressure — increased drowsiness and dizziness.": (
        "镇静与低血压叠加——困倦和头晕增加。",
        "鎮靜與低血壓疊加——睏倦和頭暈增加。",
    ),
    "Tricyclics can cancel out clonidine-type blood-pressure lowering, so blood pressure may rise — a medical issue more than an overdose risk.": (
        "三环类抗抑郁药可能抵消可乐定类药物的降压作用，使血压升高——这更多是医疗问题，而非过量风险。",
        "三環類抗憂鬱藥可能抵消可樂定類藥物的降壓作用，使血壓升高——這更多是醫療問題，而非過量風險。",
    ),
    "Don't stop the clonidine-type drug suddenly while on a beta-blocker — it can spike blood pressure to dangerous levels. Taper it slowly.": (
        "在使用 beta 受体阻滞剂期间，不要突然停用可乐定类药物——可能使血压骤升至危险水平。请缓慢减量。",
        "在使用 beta 受體阻滯劑期間，不要突然停用可樂定類藥物——可能使血壓驟升至危險水平。請緩慢減量。",
    ),
    "The old “never mix” warning is largely a medical myth — large reviews found no real harm. Both still strain the heart, so it isn't a green light to combine them.": (
        "“绝不可同用”的旧说法在很大程度上是医学误区——大型综述未发现真正的危害。但两者都会增加心脏负担，因此也并非可以随意同用。",
        "「絕不可同用」的舊說法在很大程度上是醫學迷思——大型綜述未發現真正的危害。但兩者都會增加心臟負擔，因此也並非可以隨意同用。",
    ),
    "Both can lower blood pressure and add to dizziness — you may feel faint, especially standing up.": (
        "两者都会降低血压并增加头晕——可能感到眩晕，尤其是起身时。",
        "兩者都會降低血壓並增加頭暈——可能感到眩暈，尤其是起身時。",
    ),
    # Pharmacology axis Stage 2 — Tolerance tool (2026-06-21)
    "Tolerance": ("耐受性", "耐受性"),
    "Predicted receptor tolerance and recovery": (
        "预测的受体耐受与恢复",
        "預測的受體耐受與恢復",
    ),
    "Psychedelics (5-HT2A)": ("迷幻剂（5-HT2A）", "迷幻劑（5-HT2A）"),
    "Opioids (μ)": ("阿片类（μ）", "鴉片類（μ）"),
    "Stimulants (DAT/NET)": ("兴奋剂（DAT/NET）", "興奮劑（DAT/NET）"),
    "Serotonin releasers (SERT)": ("血清素释放剂（SERT）", "血清素釋放劑（SERT）"),
    "GABA (benzos / alcohol)": ("GABA（苯二氮䓬／酒精）", "GABA（苯二氮平／酒精）"),
    "Dissociatives (NMDA)": ("解离剂（NMDA）", "解離劑（NMDA）"),
    "Cannabinoids (CB1)": ("大麻素（CB1）", "大麻素（CB1）"),
    "Adenosine (caffeine)": ("腺苷（咖啡因）", "腺苷（咖啡因）"),
    "Nicotinic (nAChR)": ("烟碱型（nAChR）", "菸鹼型（nAChR）"),
    "Predicted, not measured": ("预测值，并非实测", "預測值，並非實測"),
    "These are model predictions of how repeated use changes each receptor's responsiveness — never a measurement. Tolerance is shown per mechanism, because one universal “tolerance %” is wrong for some classes (stimulants especially).": (
        "这些是模型对反复使用如何改变各受体反应性的预测——并非实测。耐受性按机制分别显示，因为单一通用的“耐受性百分比”对某些类别（尤其是兴奋剂）是错误的。",
        "這些是模型對反覆使用如何改變各受體反應性的預測——並非實測。耐受性按機制分別顯示，因為單一通用的「耐受性百分比」對某些類別（尤其是興奮劑）是錯誤的。",
    ),
    "Based on an estimated %lld kg body weight — set yours in Settings for accuracy.": (
        "基于估算的 %lld kg 体重——在设置中填写你的体重可更准确。",
        "基於估算的 %lld kg 體重——在設定中填寫你的體重可更準確。",
    ),
    "Nothing to show yet": ("暂无可显示内容", "暫無可顯示內容"),
    "Log doses of substances with receptor data and your predicted tolerance will appear here. Targets you haven't engaged recently read as fully rested.": (
        "记录有受体数据的物质剂量，预测的耐受性就会出现在这里。近期未涉及的靶点会显示为完全休息状态。",
        "記錄有受體資料的物質劑量，預測的耐受性就會出現在這裡。近期未涉及的靶點會顯示為完全休息狀態。",
    ),
    "Shared by %@ — tolerance to one carries to the others.": (
        "由 %@ 共享——对其一的耐受会带到其余。",
        "由 %@ 共享——對其一的耐受會帶到其餘。",
    ),
    "· from %@": ("· 来自 %@", "· 來自 %@"),
    "Predicted response vs. rested: ~%lld%%": (
        "相对于休息状态的预测反应：~%lld%%",
        "相對於休息狀態的預測反應：~%lld%%",
    ),
    "Recovery-state load: low": ("恢复状态负荷：低", "恢復狀態負荷：低"),
    "Recovery-state load: moderate": ("恢复状态负荷：中等", "恢復狀態負荷：中等"),
    "Recovery-state load: high": ("恢复状态负荷：高", "恢復狀態負荷：高"),
    "Stimulant tolerance isn't one number you can multiply a dose by. The fast part is within a session (a redose lands weaker); the slow part is a months-long recovery state, not a “take more” signal.": (
        "兴奋剂耐受不是一个可用来乘剂量的数字。快的部分发生在同一次使用内（再次用药效果更弱）；慢的部分是长达数月的恢复状态，而非“该多用”的信号。",
        "興奮劑耐受不是一個可用來乘劑量的數字。快的部分發生在同一次使用內（再次用藥效果更弱）；慢的部分是長達數月的恢復狀態，而非「該多用」的訊號。",
    ),
    "The slow change here is a SERT-binding association, reversible-leaning — not proven neurotoxicity, and not a dose multiplier. It's a recovery-state indicator.": (
        "这里的慢变化是一种 SERT 结合关联，倾向可逆——并非已证实的神经毒性，也不是剂量乘数。它是一个恢复状态指标。",
        "這裡的慢變化是一種 SERT 結合關聯，傾向可逆——並非已證實的神經毒性，也不是劑量乘數。它是一個恢復狀態指標。",
    ),
    "Nicotine tolerance is mostly fast receptor desensitization that recovers between uses — a single “tolerance %” wouldn't capture it.": (
        "尼古丁耐受主要是受体的快速脱敏，在两次使用之间会恢复——单一的“耐受性百分比”无法体现这一点。",
        "尼古丁耐受主要是受體的快速去敏感化，在兩次使用之間會恢復——單一的「耐受性百分比」無法體現這一點。",
    ),
    "The slow axis here is a recovery-state indicator, not an effect multiplier.": (
        "这里的慢轴是一个恢复状态指标，而不是效果乘数。",
        "這裡的慢軸是一個恢復狀態指標，而不是效果乘數。",
    ),
    "A redose right now would land ~%lld%% as strong — within-session tachyphylaxis, recovers overnight.": (
        "现在再次用药，效果约为 ~%lld%%——同一次使用内的快速耐受，过夜即可恢复。",
        "現在再次用藥，效果約為 ~%lld%%——同一次使用內的快速耐受，過夜即可恢復。",
    ),
    "After a break your opioid tolerance drops — the dose that felt fine before can stop your breathing. Hypoxia is sudden, with no warning. Restart low, and keep naloxone accessible to someone who's with you.": (
        "中断一段时间后，你的阿片类耐受会下降——之前没问题的剂量可能让你停止呼吸。缺氧来得很突然，毫无预兆。请从低剂量重新开始，并让身边的人能随时拿到纳洛酮。",
        "中斷一段時間後，你的鴉片類耐受會下降——之前沒問題的劑量可能讓你停止呼吸。缺氧來得很突然，毫無預兆。請從低劑量重新開始，並讓身邊的人能隨時拿到納洛酮。",
    ),
    "Repeated GABA depressant use builds dependence; abrupt stops after heavy use can be dangerous. Taper rather than quitting cold.": (
        "反复使用 GABA 类镇静剂会形成依赖；大量使用后骤然停用可能很危险。请逐渐减量，而不要突然停用。",
        "反覆使用 GABA 類鎮靜劑會形成依賴；大量使用後驟然停用可能很危險。請逐漸減量，而不要突然停用。",
    ),
    "%@ to ~90%% if you stop now.": (
        "若现在停用，约 %@ 恢复到 ~90%%。",
        "若現在停用，約 %@ 恢復到 ~90%%。",
    ),
    "%@ to clear if you stop now.": (
        "若现在停用，约 %@ 清除。",
        "若現在停用，約 %@ 清除。",
    ),
    "Nearly recovered.": ("已接近恢复。", "已接近恢復。"),
    "~%lld months": ("~%lld 个月", "~%lld 個月"),
    "~%lld weeks": ("~%lld 周", "~%lld 週"),
    "~%lld days": ("~%lld 天", "~%lld 天"),
    "~%lld hours": ("~%lld 小时", "~%lld 小時"),
    "under an hour": ("不到一小时", "不到一小時"),
    # Pharmacology axis Stage 0 — confidence tiers + body-weight UI (2026-06-21)
    "High confidence": ("高可信度", "高可信度"),
    "Medium confidence": ("中等可信度", "中等可信度"),
    "Low confidence": ("低可信度", "低可信度"),
    "Unverified": ("未核实", "未核實"),
    "Body Weight": ("体重", "體重"),
    "Your weight": ("你的体重", "你的體重"),
    "Not set": ("未设置", "未設定"),
    "Source": ("来源", "來源"),
    "Estimated — set your weight for more accurate estimates.": (
        "估算值——设置体重可获得更准确的估算。",
        "估算值——設定體重可獲得更準確的估算。",
    ),
    "Apple Health": ("Apple 健康", "Apple 健康"),
    "Entered manually": ("手动输入", "手動輸入"),
    "Estimated (default 60 kg)": ("估算值（默认 60 kg）", "估算值（預設 60 kg）"),
    "Why we ask": ("我们为何询问", "我們為何詢問"),
    "Your weight is the denominator that turns a dose into an exposure: the same dose hits harder the less you weigh. With it, Piru can estimate things like how strong a drink is for *your* body, and how repeated use builds tolerance. Without it, those numbers fall back to an average adult and are marked estimated.": (
        "体重是把剂量换算成暴露量的分母：体重越轻，同样的剂量作用越强。有了它，Piru 才能估算一杯酒对*你的*身体有多强，以及反复使用如何形成耐受。没有它，这些数字会退回到普通成年人的平均值，并标注为估算。",
        "體重是把劑量換算成暴露量的分母：體重越輕，同樣的劑量作用越強。有了它，Piru 才能估算一杯酒對*你的*身體有多強，以及反覆使用如何形成耐受。沒有它，這些數字會退回到普通成年人的平均值，並標註為估算。",
    ),
    "Set manually": ("手动设置", "手動設定"),
    "Enter a number.": ("请输入数字。", "請輸入數字。"),
    "Enter a weight between 20 and 300 kg.": (
        "请输入 20 至 300 kg 之间的体重。",
        "請輸入 20 至 300 kg 之間的體重。",
    ),
    "Use Apple Health": ("使用 Apple 健康", "使用 Apple 健康"),
    "Updated from Apple Health.": ("已从 Apple 健康更新。", "已從 Apple 健康更新。"),
    "Couldn't read a weight from Health. If you've used Health before, Piru may not have access.": (
        "无法从健康读取体重。如果你以前使用过健康，可能是 Piru 没有访问权限。",
        "無法從健康讀取體重。如果你以前使用過健康，可能是 Piru 沒有存取權限。",
    ),
    "Open Settings": ("打开设置", "打開設定"),
    "Apple Health isn't available on this device.": (
        "此设备不支持 Apple 健康。",
        "此裝置不支援 Apple 健康。",
    ),
    "Piru reads your latest body weight from Health, read-only. You can turn this off anytime in Settings ▸ Health ▸ Data Access.": (
        "Piru 仅以只读方式从健康读取你最新的体重。你可以随时在 设置 ▸ 健康 ▸ 数据访问 中关闭。",
        "Piru 僅以唯讀方式從健康讀取你最新的體重。你可以隨時在 設定 ▸ 健康 ▸ 資料存取 中關閉。",
    ),
    "Use the estimated default": ("使用估算默认值", "使用估算預設值"),
    "Reverts to the average-adult default (60 kg). Estimates will be marked estimated.": (
        "恢复为普通成年人的默认值（60 kg）。估算结果将标注为估算。",
        "恢復為普通成年人的預設值（60 kg）。估算結果將標註為估算。",
    ),
    "Estimated": ("估算", "估算"),
    "Use Body Weight": ("使用体重", "使用體重"),
    "Read your weight from Apple Health so estimates fit your body — a drink hits harder the less you weigh. Read-only; change anytime in Settings.": (
        "从 Apple 健康读取你的体重，让估算贴合你的身体——体重越轻，一杯酒作用越强。仅只读；可随时在设置中更改。",
        "從 Apple 健康讀取你的體重，讓估算貼合你的身體——體重越輕，一杯酒作用越強。僅唯讀；可隨時在設定中更改。",
    ),
    "Weight": ("体重", "體重"),
    "kg": ("kg", "kg"),
    "Couldn't read a weight from Health. You may not have granted access, or haven't recorded a weight there yet.": (
        "无法从健康读取体重。你可能尚未授予访问权限，或还没有在健康中记录过体重。",
        "無法從健康讀取體重。你可能尚未授予存取權限，或還沒有在健康中記錄過體重。",
    ),
    # Bottom-accessory "Log a dose" CTA 2026-06
    "Log a dose": ("记录剂量", "記錄劑量"),
    # Cake (PsychonautWiki 🍰 April-Fools entry) — emoji off the title, joke in detail
    "Made-up drug": ("虚构药物", "虛構藥物"),
    "A fictional drug from a 1997 TV satire on media drug panics — “Cake” isn’t real, and nothing below is either. It supposedly overstimulates “Shatner’s Bassoon,” the part of the brain that governs time. Made in Prague.": (
        "出自 1997 年一部讽刺媒体毒品恐慌的电视节目的虚构药物——“Cake”并不存在，下面的内容也都是假的。据说它会过度刺激控制时间感的大脑区域“夏特纳的巴松管（Shatner’s Bassoon）”。产自布拉格。",
        "出自 1997 年一部諷刺媒體毒品恐慌的電視節目的虛構藥物——「Cake」並不存在，下面的內容也都是假的。據說它會過度刺激控制時間感的大腦區域「夏特納的巴松管（Shatner’s Bassoon）」。產自布拉格。",
    ),
    # Detail-view Design D 2026-06 — merged dose/duration card, Show All effects,
    # Erowid as its own group, two-column Info/Chemistry grids, merged Sources.
    "Dose & Duration": ("剂量与时长", "劑量與時長"),
    # FreeOD Wiki overview section (locale-first Chinese substance descriptions).
    "Overview": ("概述", "概述"),
    "Machine-translated from FreeOD Wiki": ("由 FreeOD Wiki 机器翻译", "由 FreeOD Wiki 機器翻譯"),
    "Read more": ("展开", "展開"),
    "Read less": ("收起", "收起"),
    "+%lld more": ("还有 %lld 项", "還有 %lld 項"),
    "Show All": ("查看全部", "查看全部"),
    "Default route": ("默认途径", "預設途徑"),
    "Experience reports": ("体验报告", "體驗報告"),
    "PubChem CID": ("PubChem CID", "PubChem CID"),
    "First-hand reports from Erowid's Experience Vaults. Opens a search in your browser.": (
        "来自 Erowid 体验库的第一手报告。将在浏览器中打开搜索。",
        "來自 Erowid 體驗庫的第一手報告。將在瀏覽器中開啟搜尋。",
    ),
    "Each link opens this substance's page on that source. Always verify against the original.": (
        "每个链接都会打开该来源中此物质的页面。请始终对照原始来源核实。",
        "每個連結都會開啟該來源中此物質的頁面。請始終對照原始來源核實。",
    ),
    # Detail-view restructure 2026-06 — effects merge + chemistry fold + copyable
    "Search experiences on Erowid": ("在 Erowid 上搜索体验报告", "在 Erowid 上搜尋體驗報告"),
    "All effects": ("全部效应", "全部效應"),
    "All effects (%lld)": ("全部效应（%lld）", "全部效應（%lld）"),
    "Press and hold a value to copy it.": ("长按数值即可复制。", "長按數值即可複製。"),
    # PsychonautWiki effect categories (dynamic LocalizedStringKey — not auto-extracted)
    "Physical": ("身体", "身體"),
    "Cognitive": ("认知", "認知"),
    "Visual": ("视觉", "視覺"),
    "Auditory": ("听觉", "聽覺"),
    "Tactile": ("触觉", "觸覺"),
    "Multisensory": ("多重感官", "多重感官"),
    "Sensory": ("感官", "感官"),
    "Smell and taste": ("嗅觉与味觉", "嗅覺與味覺"),
    "Transpersonal": ("超个人", "超個人"),
    "Disconnective": ("解离", "解離"),
    # DB cleanup 2026-06 — sources/references merge
    "Sources & references": ("来源与参考文献", "來源與參考文獻"),
    "Databases": ("数据库", "資料庫"),
    "Primary literature": ("原始文献", "原始文獻"),
    "The databases and primary literature behind this compound's data. Tap to open; always verify against the original source.": (
        "本化合物数据背后的数据库与原始文献。点按打开；请始终对照原始来源核实。",
        "本化合物資料背後的資料庫與原始文獻。點按開啟；請始終對照原始來源核實。",
    ),
    # DB cleanup 2026-06 — RC taxonomy rename, Other bucket, limited-data badge
    "Other / Miscellaneous": ("其他 / 杂项", "其他 / 雜項"),
    "Everything that doesn't fit a class above.": (
        "不属于以上任何类别的物质。",
        "不屬於以上任何類別的物質。",
    ),
    "Limited data": ("数据有限", "資料有限"),
    # Library redesign — family cards, taxonomy renames, sub-class blurbs
    "Stimulants": ("兴奋剂", "興奮劑"),
    "Empathogens": ("共情剂", "共情劑"),
    "Hallucinogens": ("致幻剂", "致幻劑"),
    "Cannabinoids": ("大麻素", "大麻素"),
    "Opioids": ("阿片类", "阿片類"),
    "Sedatives & Depressants": ("镇静与抑制剂", "鎮靜與抑制劑"),
    "Peptides": ("肽类", "肽類"),
    "Mind & Cognition": ("精神与认知", "精神與認知"),
    "Pharmaceuticals": ("药品", "藥品"),
    "Supplements": ("膳食补充", "膳食補充"),
    "Research Chemicals": ("研究化学品", "研究化學品"),
    "Sedative-Hypnotic": ("镇静催眠药", "鎮靜催眠藥"),
    "Everyday substances, by the names most people know.": (
        "日常物质，以大多数人熟知的名称呈现。",
        "日常物質，以大多數人熟知的名稱呈現。",
    ),
    "Energy, focus, and wakefulness.": ("提升精力、专注与清醒。", "提升精力、專注與清醒。"),
    "Warmth, empathy, and emotional openness.": (
        "温暖、共情与情感开放。",
        "溫暖、共情與情感開放。",
    ),
    "Alter perception, thought, and sense of reality.": (
        "改变知觉、思维与现实感。",
        "改變知覺、思維與現實感。",
    ),
    "Relaxation, euphoria, and altered senses.": (
        "放松、欣快与感官改变。",
        "放鬆、欣快與感官改變。",
    ),
    "Pain relief, euphoria, and sedation.": ("镇痛、欣快与镇静。", "鎮痛、欣快與鎮靜。"),
    "Calm and slow the central nervous system.": (
        "平静并减缓中枢神经系统。",
        "平靜並減緩中樞神經系統。",
    ),
    "GLP-1, healing, and research peptides.": (
        "GLP-1、修复与研究类肽。",
        "GLP-1、修復與研究類肽。",
    ),
    "Mood, psychiatric, and cognitive medications.": (
        "情绪、精神与认知类药物。",
        "情緒、精神與認知類藥物。",
    ),
    "Clinical medications, by therapeutic class.": (
        "临床药物，按治疗类别划分。",
        "臨床藥物，按治療類別劃分。",
    ),
    "Vitamins, minerals, and nutrients.": ("维生素、矿物质与营养素。", "維生素、礦物質與營養素。"),
    "Novel and lesser-characterized compounds.": (
        "新型且研究较少的化合物。",
        "新型且研究較少的化合物。",
    ),
    "Serotonergic — LSD, psilocybin, mescaline.": (
        "5-羟色胺能 — LSD、裸盖菇素、麦司卡林。",
        "血清素能 — LSD、裸蓋菇素、麥司卡林。",
    ),
    "NMDA antagonists — ketamine, DXM, PCP.": (
        "NMDA 拮抗剂 — 氯胺酮、右美沙芬、苯环利定。",
        "NMDA 拮抗劑 — 氯胺酮、右美沙芬、苯環利定。",
    ),
    "Anticholinergic — DPH, datura, Benadryl.": (
        "抗胆碱能 — 苯海拉明、曼陀罗、Benadryl。",
        "抗膽鹼能 — 苯海拉明、曼陀羅、Benadryl。",
    ),
    "Atypical tryptamines — DiPT, 5-MeO-MiPT.": (
        "非典型色胺类 — DiPT、5-MeO-MiPT。",
        "非典型色胺類 — DiPT、5-MeO-MiPT。",
    ),
    "GABA-A modulators — diazepam, alprazolam.": (
        "GABA-A 调节剂 — 地西泮、阿普唑仑。",
        "GABA-A 調節劑 — 地西泮、阿普唑侖。",
    ),
    "GABA-active — GHB, phenibut, gabapentin.": (
        "GABA 活性 — GHB、苯巴胺、加巴喷丁。",
        "GABA 活性 — GHB、苯巴胺、加巴噴丁。",
    ),
    "Barbiturates, sedative-hypnotics, and Z-drugs.": (
        "巴比妥类、镇静催眠药与 Z 类药物。",
        "巴比妥類、鎮靜催眠藥與 Z 類藥物。",
    ),
    "SSRIs, SNRIs, and MAOIs.": ("SSRI、SNRI 与 MAOI。", "SSRI、SNRI 與 MAOI。"),
    "Dopamine antagonists — quetiapine, risperidone.": (
        "多巴胺拮抗剂 — 喹硫平、利培酮。",
        "多巴胺拮抗劑 — 喹硫平、利培酮。",
    ),
    "Racetams, choline, and cognitive aids.": (
        "拉西坦类、胆碱与认知辅助剂。",
        "拉西坦類、膽鹼與認知輔助劑。",
    ),
    "AMPA-receptor positive modulators.": ("AMPA 受体正向调节剂。", "AMPA 受體正向調節劑。"),
    "Wakefulness — modafinil, armodafinil.": (
        "促清醒 — 莫达非尼、阿莫达非尼。",
        "促清醒 — 莫達非尼、阿莫達非尼。",
    ),
    "Non-opioid pain relief — NSAIDs, paracetamol.": (
        "非阿片类镇痛 — NSAID、对乙酰氨基酚。",
        "非阿片類鎮痛 — NSAID、對乙醯氨基酚。",
    ),
    "Allergy and sleep antihistamines.": (
        "抗过敏与助眠抗组胺药。",
        "抗過敏與助眠抗組織胺藥。",
    ),
    "Blood pressure, heart, and cholesterol.": ("血压、心脏与胆固醇。", "血壓、心臟與膽固醇。"),
    "Antibiotics, antivirals, and antifungals.": (
        "抗生素、抗病毒与抗真菌药。",
        "抗生素、抗病毒與抗真菌藥。",
    ),
    "Acid, nausea, and gut motility.": ("胃酸、恶心与胃肠动力。", "胃酸、噁心與胃腸動力。"),
    "Inhalers, decongestants, and cough.": (
        "吸入剂、减充血剂与止咳药。",
        "吸入劑、減充血劑與止咳藥。",
    ),
    "Hormones, thyroid, and metabolic drugs.": (
        "激素、甲状腺与代谢药物。",
        "激素、甲狀腺與代謝藥物。",
    ),
    "Immune modulators and steroids.": ("免疫调节剂与类固醇。", "免疫調節劑與類固醇。"),
    "Seizure and mood-stabilizing drugs.": (
        "抗癫痫与情绪稳定药物。",
        "抗癲癇與情緒穩定藥物。",
    ),
    "Highest overdose risk": ("过量风险最高", "過量風險最高"),
    # Quick-log redesign — dose tray (staging, shared When/Tags/Location, inline editor)
    "%lld min ago": ("%lld 分钟前", "%lld 分鐘前"),
    "Pick date & time…": ("选择日期和时间…", "選擇日期和時間…"),
    "Remove": ("移除", "移除"),
    "When": ("时间", "時間"),
    "Log Dose": ("记录剂量", "記錄劑量"),
    "Log %lld Doses": ("记录 %lld 剂", "記錄 %lld 劑"),
    "Add note…": ("添加备注…", "新增備註…"),
    "Collapse": ("收起", "收合"),
    "Collapses the editor": ("收起编辑器", "收合編輯器"),
    "Shared time": ("统一时间", "統一時間"),
    "Custom…": ("自定…", "自訂…"),
    "Discard staged doses?": ("舍弃待记录的剂量？", "捨棄待記錄的劑量？"),
    "Discard Doses": ("舍弃剂量", "捨棄劑量"),
    "Keep Logging": ("继续记录", "繼續記錄"),
    "Show %lld more doses": ("显示另外 %lld 个剂量", "顯示另外 %lld 個劑量"),
    "Custom dose": ("自定剂量", "自訂劑量"),
    "Active dose details": ("活性剂量详情", "活性劑量詳情"),
    # Quick-log v2 — morphing dock, Daily routine card
    "Add another…": ("再添加一个…", "再新增一個…"),
    "Remove from Tray": ("移除此剂量", "移除此劑量"),
    "Routine": ("日常", "日常"),
    "Log all": ("全部记录", "全部記錄"),
    "%lld left": ("剩 %lld 项", "剩 %lld 項"),
    "Back to staged doses": ("返回待记录剂量", "返回待記錄劑量"),
    "≈%@ %@ active · %@ left": ("体内约 %1$@ %2$@ · 剩 %3$@", "體內約 %1$@ %2$@ · 剩 %3$@"),
    "≈%@ %@ active": ("体内约 %1$@ %2$@", "體內約 %1$@ %2$@"),
    "≈%@ %@ active · %@ ago · %@ left": (
        "体内约 %1$@ %2$@ · %3$@前 · 剩 %4$@",
        "體內約 %1$@ %2$@ · %3$@前 · 剩 %4$@",
    ),
    "≈%@ %@ active · %@ ago": ("体内约 %1$@ %2$@ · %3$@前", "體內約 %1$@ %2$@ · %3$@前"),
    "≈%@ %@ of your %@ %@ dose (%@) is still active — ~%lld%%": (
        "您%5$@服用的 %3$@ %4$@，体内仍约有 %1$@ %2$@（约 %6$lld%%）",
        "您%5$@服用的 %3$@ %4$@，體內仍約有 %1$@ %2$@（約 %6$lld%%）",
    ),
    "Fixed Order": ("固定顺序", "固定順序"),
    "Create custom substance": ("创建自定义物质", "建立自訂物質"),
    "Find a Place…": ("查找地点…", "尋找地點…"),
    "Recents": ("最近", "最近"),
    "Edit Favorites": ("编辑收藏", "編輯收藏"),
    # Routines (multi-routine rework; Routine = 日常, established term)
    "Time for your %@ routine.": ("该进行「%@」日常了。", "該進行「%@」日常了。"),
    "No Routines": ("暂无日常", "暫無日常"),
    "New Routine": ("新建日常", "新增日常"),
    "Unassigned": ("未分组", "未分組"),
    "e.g. Morning, Pre-workout, Night": ("例如：早晨、锻炼前、夜间", "例如：早晨、鍛鍊前、夜間"),
    "Routine Name": ("日常名称", "日常名稱"),
    "Time of day": ("具体时间", "具體時間"),
    "Remind Me": ("提醒我", "提醒我"),
    "A notification repeats daily at this time.": (
        "每天此时重复发送通知。",
        "每天此時重複傳送通知。",
    ),
    "Items": ("项目", "項目"),
    "Edit Item": ("编辑项目", "編輯項目"),
    "Delete Routine": ("删除日常", "刪除日常"),
    "Group the meds and supplements you take together — Pre-workout, Night — and stage a whole set with one tap.": (
        "把一起服用的药物和补充剂分成组——锻炼前、夜间——一键备入整组。",
        "把一起服用的藥物和補充劑分成組——鍛鍊前、夜間——一鍵備入整組。",
    ),
    "Edit Routine…": ("编辑日常…", "編輯日常…"),
    "Manage Routines…": ("管理日常…", "管理日常…"),
    "Clear search": ("清除搜索", "清除搜尋"),
    "Common %@–%@ %@": ("常用 %1$@–%2$@ %3$@", "常用 %1$@–%2$@ %3$@"),
    "Routines": ("日常", "日常"),
    "No Routine Items": ("暂无日常项目", "暫無日常項目"),
    "Add the meds and supplements you take regularly.": (
        "添加你定期服用的药物和补充剂。",
        "新增你定期服用的藥物和補充劑。",
    ),
    "Group items into routines by time of day or purpose — a routine stages everything in it with one tap on the Log screen. Drag items onto a category to assign them.": (
        "按时间或用途将项目分组为日常组合 — 在记录页上点一下即可将整组加入待记。把项目拖到分类上进行归类。",
        "按時間或用途將項目分組為日常組合 — 在記錄頁上點一下即可將整組加入待記。把項目拖到分類上進行歸類。",
    ),
    "%@ — %lld item%@": ("%1$@ — %2$lld 项", "%1$@ — %2$lld 項"),
    "%lld item%@": ("%1$lld 项", "%1$lld 項"),
    "Uncategorized — %lld item%@": ("未分类 — %1$lld 项", "未分類 — %1$lld 項"),
    # Settings restructure — progressive disclosure cleanup
    "My Substances": ("我的物质", "我的物質"),
    "Notifications": ("通知", "通知"),
    "Preferences": ("偏好设置", "偏好設定"),
    "Data": ("数据", "資料"),
    "Day Grouping": ("分日方式", "分日方式"),
    "None yet": ("暂无", "暫無"),
    "No Substance Colors": ("暂无物质配色", "暫無物質配色"),
    "No Substances Yet": ("暂无物质", "暫無物質"),
    "Create or personalize substances — adjust dose ranges, duration, and units to match your own data and tolerance.": (
        "创建或个性化物质——调整剂量范围、作用时长和单位，以匹配你自己的数据和耐受度。",
        "建立或個人化物質——調整劑量範圍、作用時長和單位，以符合你自己的資料和耐受度。",
    ),
    "Doses logged before this hour count toward the previous day — so a 2 AM dose stays with the night before instead of starting a new day at midnight. Set to 12 AM for standard calendar days.": (
        "在此时刻之前记录的剂量将归入前一天——因此凌晨 2 点的剂量会留在前一晚，而不是在午夜开启新的一天。设为午夜 12 点即按标准日历日分组。",
        "在此時刻之前記錄的劑量將歸入前一天——因此凌晨 2 點的劑量會留在前一晚，而不是在午夜開啟新的一天。設為午夜 12 點即按標準日曆日分組。",
    ),
    "Pharmacological data is compiled from the sources above — community harm-reduction databases, FDA labeling, and peer-reviewed literature. Provided for harm-reduction and educational purposes only. Always consult a qualified healthcare professional before making decisions about substance use.": (
        "药理数据汇编自上述来源——社区减害数据库、FDA 药品标签以及同行评审文献。仅供减害与教育用途。在做出任何有关物质使用的决定前，请务必咨询合格的医疗专业人员。",
        "藥理資料彙編自上述來源——社群減害資料庫、FDA 藥品標籤以及同行評審文獻。僅供減害與教育用途。在做出任何有關物質使用的決定前，請務必諮詢合格的醫療專業人員。",
    ),
    "Colors appear here after you log your first entry. Tap one to change it.": (
        "记录第一条条目后，配色会显示在这里。点按即可更改。",
        "記錄第一筆項目後，配色會顯示在這裡。點按即可更改。",
    ),
    "Substances you create or personalize appear here. You can also create them from the Quick Log search.": (
        "你创建或个性化的物质会显示在这里。你也可以在快速记录搜索中创建它们。",
        "你建立或個人化的物質會顯示在這裡。你也可以在快速記錄搜尋中建立它們。",
    ),
    # Session model — Journal grouping, detail, overrides, widget
    "Yesterday": ("昨天", "昨天"),
    "Medications": ("用药", "用藥"),
    "Session": ("本次记录", "本次記錄"),
    "No active session": ("暂无进行中的记录", "暫無進行中的記錄"),
    "No Sessions": ("暂无记录", "暫無記錄"),
    "Move to Session…": ("移至其他记录…", "移至其他記錄…"),
    "Move %@": ("移动 %@", "移動 %@"),
    "New Session": ("新建记录", "新建記錄"),
    "Pull this dose into its own session.": (
        "将这一剂单独归入新记录。",
        "將這一劑單獨歸入新記錄。",
    ),
    "Move To": ("移至", "移至"),
    "Nowhere to Move": ("无处可移", "無處可移"),
    "This is the only session.": ("这是唯一的记录。", "這是唯一的記錄。"),
    "Move": ("移动", "移動"),
    "Set Time": ("设置时间", "設定時間"),
    "New time on %@": ("%@ 的新时间", "%@ 的新時間"),
    "%@ is logged on a different day. Pick a time within this session's day so the session stays a single day.": (
        "%@ 记录于另一天。请在本次记录所在的当天选择一个时间，使其保持在同一天内。",
        "%@ 記錄於另一天。請在本次記錄所在的當天選擇一個時間，使其保持在同一天內。",
    ),
    "Location": ("位置", "位置"),
    "Current Location": ("当前位置", "目前位置"),
    "Results": ("搜索结果", "搜尋結果"),
    "Add Location": ("添加位置", "新增位置"),
    "Change Location": ("更改位置", "變更位置"),
    "Remove location": ("移除位置", "移除位置"),
    "Search for a place or address": ("搜索地点或地址", "搜尋地點或地址"),
    "Location access is off. Turn it on in Settings to use your current location.": (
        "位置访问已关闭。请在“设置”中开启以使用当前位置。",
        "位置存取已關閉。請在「設定」中開啟以使用目前位置。",
    ),
    "Piru Backup": ("Piru 备份", "Piru 備份"),
    "A complete backup you can restore into Piru": (
        "可恢复到 Piru 的完整备份",
        "可還原至 Piru 的完整備份",
    ),
    "PsychonautWiki Format": ("PsychonautWiki 格式", "PsychonautWiki 格式"),
    "For importing into the PsychonautWiki app": (
        "用于导入 PsychonautWiki 应用",
        "用於匯入 PsychonautWiki 應用程式",
    ),
    "Data & Backup": ("数据与备份", "資料與備份"),
    "iCloud Backup": ("iCloud 备份", "iCloud 備份"),
    "Export": ("导出", "匯出"),
    "Encrypted Backup…": ("加密备份…", "加密備份…"),
    "Passphrase-protected — save or send it anywhere": (
        "由口令保护——可保存或发送到任何地方",
        "由通行密語保護——可儲存或傳送到任何地方",
    ),
    "Import & Restore": ("导入与恢复", "匯入與還原"),
    "Import from a File…": ("从文件导入…", "從檔案匯入…"),
    "A Piru or PsychonautWiki JSON file": (
        "Piru 或 PsychonautWiki 的 JSON 文件",
        "Piru 或 PsychonautWiki 的 JSON 檔案",
    ),
    "Restore Encrypted Backup…": ("恢复加密备份…", "還原加密備份…"),
    "A passphrase-protected .piruenc file": (
        "由口令保护的 .piruenc 文件",
        "由通行密語保護的 .piruenc 檔案",
    ),
    "From your automatic iCloud backups": (
        "来自你的自动 iCloud 备份",
        "來自你的自動 iCloud 備份",
    ),
    "Import Failed": ("导入失败", "匯入失敗"),
    "Import Complete": ("导入完成", "匯入完成"),
    "Your data was imported.": ("你的数据已导入。", "你的資料已匯入。"),
    "Export and import your journal under Data & Backup above.": (
        "在上方的“数据与备份”中导出和导入你的记录。",
        "在上方的「資料與備份」中匯出和匯入你的記錄。",
    ),
    "Export, import, and encrypted backups to iCloud or a passphrase-protected file. Backups are optional and off by default.": (
        "导出、导入，以及加密备份到 iCloud 或口令保护的文件。备份为可选项，默认关闭。",
        "匯出、匯入，以及加密備份到 iCloud 或通行密語保護的檔案。備份為可選項，預設關閉。",
    ),
    "Piru and PsychonautWiki files are plain, unencrypted JSON. An encrypted backup is protected by a passphrase you choose — **if you forget it, the file cannot be opened, not even by us.**": (
        "Piru 和 PsychonautWiki 文件是未加密的纯 JSON。加密备份由你设定的口令保护——**若忘记口令，文件将无法打开，我们也不能。**",
        "Piru 和 PsychonautWiki 檔案是未加密的純 JSON。加密備份由你設定的通行密語保護——**若忘記通行密語，檔案將無法開啟，我們也不能。**",
    ),
    "Imported entries are added to your journal (duplicates are skipped). Encrypted restores can merge or replace; iCloud and your own passphrase backups unlock automatically or prompt for the passphrase.": (
        "导入的记录会添加到你的日志中（重复项会被跳过）。加密恢复可选择合并或替换；iCloud 和你自己的口令备份会自动解锁或提示输入口令。",
        "匯入的記錄會新增到你的日誌中（重複項會被略過）。加密還原可選擇合併或取代；iCloud 和你自己的通行密語備份會自動解鎖或提示輸入通行密語。",
    ),
    "Report": ("报告", "報告"),
    "A PDF summary to share with a clinician": (
        "可与医生分享的 PDF 摘要",
        "可與醫師分享的 PDF 摘要",
    ),
    "Permanently removes every dose, session, and setting. A recoverable snapshot is taken first.": (
        "永久删除每一条剂量、记录和设置。删除前会先创建可恢复的快照。",
        "永久刪除每一筆劑量、記錄和設定。刪除前會先建立可還原的快照。",
    ),
    "Delete Failed": ("删除失败", "刪除失敗"),
    # Data storage & recovery (DataStorageView, store-recovery + diagnostics UI)
    "%lld records": ("%lld 条记录", "%lld 筆記錄"),
    "Auto-recovered Data": ("自动恢复的数据", "自動還原的資料"),
    "Before a Restore": ("恢复前", "還原前"),
    "Before You Deleted Everything": ("删除全部数据前", "刪除全部資料前"),
    "Checking for recoverable copies…": ("正在检查可恢复的副本…", "正在檢查可還原的副本…"),
    "Couldn't Prepare Logs": ("无法准备日志", "無法準備記錄檔"),
    "Couldn't prepare the diagnostics file.": ("无法准备诊断文件。", "無法準備診斷檔案。"),
    "Custom Colors": ("自定义颜色", "自訂顏色"),
    "Daily Medications": ("每日用药", "每日用藥"),
    "Doses": ("剂量", "劑量"),
    "Everything Piru stores locally. Your dose data lives only on this device unless you turn on iCloud backup.": (
        "Piru 在本机存储的全部内容。除非开启 iCloud 备份，你的剂量数据只保存在这台设备上。",
        "Piru 在本機儲存的全部內容。除非開啟 iCloud 備份，你的劑量資料只保存在這部裝置上。",
    ),
    "Export & Import": ("导出与导入", "匯出與匯入"),
    "Export…": ("导出…", "匯出…"),
    "From a file, an encrypted backup, or iCloud": (
        "从文件、加密备份或 iCloud",
        "從檔案、加密備份或 iCloud",
    ),
    "Generated by Piru · kagerou.glass/piru": (
        "由 Piru 生成 · kagerou.glass/piru",
        "由 Piru 產生 · kagerou.glass/piru",
    ),
    "Import & Restore…": ("导入与恢复…", "匯入與還原…"),
    "No recoverable copies on this device.": (
        "此设备上没有可恢复的副本。",
        "此裝置上沒有可還原的副本。",
    ),
    "On This Device": ("在此设备上", "在此裝置上"),
    "Piru and PsychonautWiki files are plain, unencrypted JSON. Imported entries are added to your journal (duplicates are skipped). Encrypted restores can merge or replace.": (
        "Piru 和 PsychonautWiki 文件是未加密的纯 JSON。导入的记录会添加到你的日志中（重复项会被跳过）。加密恢复可选择合并或替换。",
        "Piru 和 PsychonautWiki 檔案是未加密的純 JSON。匯入的記錄會新增到你的日誌中（重複項會被略過）。加密還原可選擇合併或取代。",
    ),
    "Piru couldn't open your journal this time, so it's running with temporary storage. **Nothing has been deleted** — your doses and sessions are safe on this device and a future update will restore them automatically.\n\nSending the logs helps us ship that fix faster. They describe the storage problem only — never your dose data.": (
        "Piru 这次未能打开你的日志，目前正以临时存储运行。**没有任何数据被删除**——你的剂量和记录仍安全保存在这台设备上，未来的更新会自动恢复它们。\n\n发送日志能帮助我们更快推出修复。日志只描述存储问题本身——绝不包含你的剂量数据。",
        "Piru 這次未能開啟你的日誌，目前正以暫時儲存空間執行。**沒有任何資料被刪除**——你的劑量和記錄仍安全保存在這部裝置上，未來的更新會自動還原它們。\n\n傳送記錄檔能幫助我們更快推出修正。記錄檔只描述儲存問題本身——絕不包含你的劑量資料。",
    ),
    "Piru never deletes a store outright. Copies set aside automatically (after an upgrade hiccup) or before you deleted or restored data appear here, ready to restore.": (
        "Piru 绝不会直接删除数据存储。系统自动留存的副本（升级出现问题后），或在你删除、恢复数据之前留存的副本，都会显示在这里，随时可以恢复。",
        "Piru 絕不會直接刪除資料儲存。系統自動留存的副本（升級出現問題後），或在你刪除、還原資料之前留存的副本，都會顯示在這裡，隨時可以還原。",
    ),
    "Piru, PsychonautWiki, or an encrypted backup": (
        "Piru、PsychonautWiki 或加密备份",
        "Piru、PsychonautWiki 或加密備份",
    ),
    "Quick-Log Shortcuts": ("快速记录快捷项", "快速記錄快捷項目"),
    "Recoverable Copies": ("可恢复的副本", "可還原的副本"),
    "Recovered Data": ("恢复的数据", "還原的資料"),
    "Restore This Copy?": ("恢复此副本？", "還原此副本？"),
    "Restored": ("已恢复", "已還原"),
    "Saved Copy": ("已保存的副本", "已儲存的副本"),
    "Send Logs to Developer": ("向开发者发送日志", "傳送記錄檔給開發者"),
    "Sessions": ("记录", "記錄"),
    "Store Size": ("存储大小", "儲存空間大小"),
    "Summary": ("摘要", "摘要"),
    "This replaces your current data with the %@ in this copy. A snapshot of your current data is taken first, so it's reversible. Restart Piru afterwards to load it.": (
        "这将用此副本中的 %@ 替换你当前的数据。替换前会先为当前数据创建快照，因此可以撤销。之后请重新启动 Piru 以加载。",
        "這會用此副本中的 %@ 取代你目前的資料。取代前會先為目前資料建立快照，因此可以復原。之後請重新啟動 Piru 以載入。",
    ),
    "unknown date": ("未知日期", "未知日期"),
    "unreadable": ("无法读取", "無法讀取"),
    "When on, Piru encrypts your journal and saves it to your private iCloud Drive each time you leave the app. The key is stored only in your iCloud Keychain, so it's end-to-end encrypted — **neither Apple nor Piru can read it** — and it restores on your other devices signed in to the same Apple Account.": (
        "开启后，每次你离开 App 时，Piru 都会加密你的日志并保存到你的私人 iCloud 云盘。密钥只存储在你的 iCloud 钥匙串中，因此是端到端加密——**Apple 和 Piru 都无法读取**——并且会在登录同一 Apple 账户的其他设备上自动恢复。",
        "開啟後，每次你離開 App 時，Piru 都會加密你的日誌並儲存到你的私人 iCloud 雲碟。金鑰只儲存在你的 iCloud 鑰匙圈中，因此是端對端加密——**Apple 和 Piru 都無法讀取**——並且會在登入同一 Apple 帳號的其他裝置上自動還原。",
    ),
    "Your Data Is Safe": ("你的数据是安全的", "你的資料是安全的"),
    "Your data was restored. Please force-quit and reopen Piru to load it.": (
        "你的数据已恢复。请强制退出并重新打开 Piru 以加载。",
        "你的資料已還原。請強制結束並重新開啟 Piru 以載入。",
    ),
    "Log a dose to start your first session.": (
        "记录一次剂量以开始你的第一段记录。",
        "記錄一次劑量以開始你的第一段記錄。",
    ),
    "Rename Session": ("重命名记录", "重新命名記錄"),
    "Session title": ("记录标题", "記錄標題"),
    "Add Title": ("添加标题", "新增標題"),
    "Rename": ("重命名", "重新命名"),
    "Add Note": ("添加备注", "新增備註"),
    "Edit Note": ("编辑备注", "編輯備註"),
    "Merge with Previous": ("与上一段合并", "與上一段合併"),
    "Note": ("备注", "備註"),
    "Split Session Here": ("在此拆分记录", "在此拆分記錄"),
    "Session Note": ("记录备注", "記錄備註"),
    "Share session log": ("分享记录日志", "分享記錄日誌"),
    "No substances logged in this session.": (
        "本次记录中没有记录任何物质。",
        "本次記錄中沒有記錄任何物質。",
    ),
    "Background medication": ("后台用药", "背景用藥"),
    "Keeps this medication out of your sessions — it joins an active session if one is running, but on its own never starts a new session. Maintenance meds show as a compact “Medications” row in the Journal.": (
        "让这种药物不计入你的记录——如果当前有进行中的记录，它会并入其中，但自身永远不会开启新的记录。维持类用药会在日志中显示为紧凑的“用药”行。",
        "讓這種藥物不計入你的記錄——如果目前有進行中的記錄，它會併入其中，但自身永遠不會開啟新的記錄。維持類用藥會在日誌中顯示為精簡的“用藥”列。",
    ),
    "Current Session": ("本次记录", "本次記錄"),
    "See your current session's doses at a glance.": (
        "一目了然地查看本次记录的剂量。",
        "一目了然地查看本次記錄的劑量。",
    ),
    # Substance detail — consolidated dose/duration card + share
    "Release Window": ("释放窗口", "釋放窗口"),
    "Share drug info": ("分享药物信息", "分享藥物資訊"),
    "Move to Front": ("移到最前", "移到最前"),
    "Move to Back": ("移到最后", "移到最後"),
    "Select": ("选择", "選擇"),
    "Remove from Quick Log": ("从快速记录中移除", "從快速記錄中移除"),
    "Keep Quick-Log Order": ("保持快速记录顺序", "保持快速記錄順序"),
    "icon to log several at once, or long press a dose to remove or reorder it": (
        "图标可一次记录多个，或长按某个剂量以移除或重新排序",
        "圖示可一次記錄多個，或長按某個劑量以移除或重新排序",
    ),
    "Keep your quick-log doses in a fixed order. When off, logging a dose moves it to the front so your most-used doses stay on top.": (
        "让快速记录中的剂量保持固定顺序。关闭时，记录某个剂量会将其移到最前，使常用剂量始终置顶。",
        "讓快速記錄中的劑量保持固定順序。關閉時，記錄某個劑量會將其移到最前，使常用劑量始終置頂。",
    ),
    # Categories (SubstanceCategory)
    "Stimulant": ("兴奋剂", "興奮劑"),
    "Psychedelic": ("致幻剂", "致幻劑"),
    "Dissociative": ("解离剂", "解離劑"),
    "Dysdelic": ("暗幻剂", "暗幻劑"),
    "Opioid": ("阿片类", "阿片類"),
    "Benzodiazepine": ("苯二氮䓬类", "苯二氮䓬類"),
    "GABAergic": ("GABA 类", "GABA 類"),
    "Empathogen": ("共情剂", "共情劑"),
    "Cannabinoid": ("大麻素", "大麻素"),
    "Nootropic": ("益智剂", "益智劑"),
    "AMPAkine": ("安帕金", "安帕金"),
    "Eugeroic": ("促醒剂", "促醒劑"),
    "Depressant": ("抑制剂", "抑制劑"),
    "Antidepressant": ("抗抑郁药", "抗抑鬱藥"),
    "Antipsychotic": ("抗精神病药", "抗精神病藥"),
    "Analgesic": ("镇痛药", "鎮痛藥"),
    "Antihistamine": ("抗组胺药", "抗組胺藥"),
    "Cardiovascular": ("心血管药", "心血管藥"),
    "Antimicrobial": ("抗菌药", "抗菌藥"),
    "Gastrointestinal": ("胃肠药", "胃腸藥"),
    "Respiratory": ("呼吸系统药", "呼吸系統藥"),
    "Endocrine": ("内分泌药", "內分泌藥"),
    "Immunological": ("免疫药", "免疫藥"),
    "Supplement": ("膳食补充", "膳食補充"),
    "Peptide": ("肽类", "肽類"),
    "Anticonvulsant": ("抗惊厥药", "抗驚厥藥"),
    "Other": ("其他", "其他"),
    # Routes of administration
    "Oral": ("口服", "口服"),
    "Sublingual": ("舌下", "舌下"),
    "Insufflation": ("鼻吸", "鼻吸"),
    "Inhalation": ("吸入", "吸入"),
    "Intravenous": ("静脉注射", "靜脈注射"),
    "Intramuscular": ("肌肉注射", "肌肉注射"),
    "Subcutaneous": ("皮下注射", "皮下注射"),
    "Transdermal": ("透皮", "透皮"),
    "Rectal": ("直肠给药", "直腸給藥"),
    # Dose levels
    "Sub-threshold": ("阈下", "閾下"),
    "Threshold": ("阈值", "閾值"),
    "Light": ("轻度", "輕度"),
    "Common": ("常规", "常規"),
    "Strong": ("强效", "強效"),
    "Heavy": ("大剂量", "大劑量"),
    # Binding actions (BindingAction)
    "Agonist": ("激动剂", "激動劑"),
    "Partial Agonist": ("部分激动剂", "部分激動劑"),
    "Antagonist": ("拮抗剂", "拮抗劑"),
    "Inverse Agonist": ("反向激动剂", "反向激動劑"),
    "PAM": ("正向变构调节剂 (PAM)", "正向變構調節劑 (PAM)"),
    "NAM": ("负向变构调节剂 (NAM)", "負向變構調節劑 (NAM)"),
    "Reuptake Inhibitor": ("再摄取抑制剂", "再攝取抑制劑"),
    "Releasing Agent": ("释放剂", "釋放劑"),
    "Enzyme Inhibitor": ("酶抑制剂", "酶抑制劑"),
    "Channel Blocker": ("通道阻滞剂", "通道阻滯劑"),
    "Modulator": ("调节剂", "調節劑"),
    # Phases
    "Onset": ("起效", "起效"),
    "Come-up": ("上升期", "上升期"),
    "Peak": ("巅峰", "巔峰"),
    "Offset": ("下降期", "下降期"),
    "Afterglow": ("余韵", "餘韻"),
    "Effects ended": ("效果已结束", "效果已結束"),
    "Total": ("总计", "總計"),
    "~%@ hours": ("约 %@ 小时", "約 %@ 小時"),
    "~%@ – %@ hours": ("约 %1$@ – %2$@ 小时", "約 %1$@ – %2$@ 小時"),
    "~%lld minutes": ("约 %lld 分钟", "約 %lld 分鐘"),
    "~%lld – %lld minutes": ("约 %1$lld – %2$lld 分钟", "約 %1$lld – %2$lld 分鐘"),
    # Frequencies
    "Daily": ("每日", "每日"),
    "Every other day": ("隔日", "隔日"),
    "Weekly": ("每周", "每週"),
    "Every 2 weeks": ("每两周", "每兩週"),
    "Monthly": ("每月", "每月"),
    "Specific days": ("指定日期", "指定日期"),
    "Every 2 days": ("每两天", "每兩天"),
    "Biweekly": ("两周一次", "兩週一次"),
    "Custom days": ("自定日期", "自定日期"),
    # Navigation / Tabs
    "Journal": ("日志", "日誌"),
    "Library": ("物质库", "物質庫"),
    "Tools": ("工具", "工具"),
    "Insights": ("洞察", "洞察"),
    "Settings": ("设置", "設定"),
    "Calculator": ("计算器", "計算器"),
    "Get Help": ("获取帮助", "獲取幫助"),
    "Substance Library": ("物质库", "物質庫"),
    "Search Library": ("搜索物质库", "搜尋物質庫"),
    "Search Journal": ("搜索日志", "搜尋日誌"),
    "Search entries...": ("搜索记录…", "搜尋記錄…"),
    "Search substances...": ("搜索物质…", "搜尋物質…"),
    "Search": ("搜索", "搜尋"),
    # Search redesign 2026-06 (landing + class grid + journal→library fallback)
    "Recently Searched": ("最近搜索", "最近搜尋"),
    "Browse by class": ("按类别浏览", "按類別瀏覽"),
    "Search Library instead": ("改为搜索物质库", "改為搜尋物質庫"),
    "Help & Safety": ("帮助与安全", "幫助與安全"),
    "Crisis resources, harm-reduction basics, and how Piru works.": (
        "危机求助资源、减害基础知识，以及 Piru 的使用方法。",
        "危機求助資源、減害基礎知識，以及 Piru 的使用方法。",
    ),
    "Class Not Found": ("未找到类别", "未找到類別"),
    "This class isn’t in the library anymore.": (
        "此类别已不在物质库中。",
        "此類別已不在物質庫中。",
    ),
    "Clear": ("清除", "清除"),
    # Common UI actions
    "Add": ("添加", "新增"),
    "Cancel": ("取消", "取消"),
    "Save": ("保存", "儲存"),
    "Delete": ("删除", "刪除"),
    "Edit": ("编辑", "編輯"),
    "OK": ("好", "好"),
    "Done": ("完成", "完成"),
    "Skip": ("跳过", "跳過"),
    "Change": ("更改", "變更"),
    "Copy": ("复制", "複製"),
    "Copied": ("已复制", "已複製"),
    "Reset Filters": ("重置筛选", "重設篩選"),
    "Filter": ("筛选", "篩選"),
    "Filter Journal": ("筛选日志", "篩選日誌"),
    "Jump to Date": ("跳转到日期", "跳轉到日期"),
    "Adjust Time": ("调整时间", "調整時間"),
    # Timeline graph + journal tag filter
    "Expand timeline": ("展开时间轴", "展開時間軸"),
    "Shrink timeline": ("收起时间轴", "收合時間軸"),
    "Tag these logs": ("为这些记录添加标签", "為這些記錄加上標籤"),
    "Tagging with": ("标记为", "標記為"),
    # Settings sections
    "Live Activity": ("实时活动", "即時動態"),
    "Harm Reduction": ("减害", "減害"),
    "Timeline": ("时间轴", "時間軸"),
    "Day Starts At": ("一天起始时间", "一天起始時間"),
    "Session Day": ("会话日", "會話日"),
    "Journal Data": ("日志数据", "日誌數據"),
    "About": ("关于", "關於"),
    "Sources": ("数据来源", "資料來源"),
    "Sources & References": ("数据来源与参考", "資料來源與參考"),
    "Version": ("版本", "版本"),
    "Export Data": ("导出数据", "匯出資料"),
    "Import Data": ("导入数据", "匯入資料"),
    "Refresh Substance Data": ("刷新物质数据", "重新整理物質資料"),
    "Delete Everything": ("删除所有数据", "刪除所有資料"),
    "Custom Substances": ("自定义物质", "自訂物質"),
    "Substance Colors": ("物质颜色", "物質顏色"),
    "Change Substance Colors": ("更改物质颜色", "變更物質顏色"),
    "Phase Notifications": ("阶段通知", "階段通知"),
    "Wellness Reminders": ("健康提醒", "健康提醒"),
    "Stack Redoses": ("叠加重复剂量", "疊加重複劑量"),
    "Interaction Alerts": ("相互作用警报", "相互作用警示"),
    "Comedown Alert": ("缓和期提醒", "緩和期提醒"),
    # Common labels
    "Substance": ("物质", "物質"),
    "Substance name": ("物质名称", "物質名稱"),
    "Substances in Library": ("物质库中的物质", "物質庫中的物質"),
    "Dose": ("剂量", "劑量"),
    "Dosage": ("剂量", "劑量"),
    "Amount": ("剂量", "劑量"),
    "Unit": ("单位", "單位"),
    "Route": ("给药途径", "給藥途徑"),
    "Form": ("盐型", "鹽型"),
    "≈ %@ %@ elemental": ("≈ %@ %@ 元素含量", "≈ %@ %@ 元素含量"),
    "%lld%% elemental": ("%lld%% 元素含量", "%lld%% 元素含量"),
    "Default Route": ("默认途径", "預設途徑"),
    "Category": ("类别", "類別"),
    "Category name": ("类别名称", "類別名稱"),
    "Categories": ("类别", "類別"),
    "All categories": ("全部类别", "全部類別"),
    "Frequency": ("频次", "頻次"),
    "Notes": ("备注", "備註"),
    "Notes (Optional)": ("备注（可选）", "備註（可選）"),
    "Tags": ("标签", "標籤"),
    "Name": ("名称", "名稱"),
    "Color": ("颜色", "顏色"),
    "Time": ("时间", "時間"),
    "Date": ("日期", "日期"),
    "Date & Time": ("日期与时间", "日期與時間"),
    "Date Range": ("日期范围", "日期範圍"),
    "Time Range": ("时间范围", "時間範圍"),
    "Time of Day": ("时段", "時段"),
    "Time Taken": ("服用时间", "服用時間"),
    "Period": ("时段", "時段"),
    "Hours": ("小时", "小時"),
    "hours": ("小时", "小時"),
    "Days": ("天", "天"),
    "Mode": ("模式", "模式"),
    "Section": ("分组", "分組"),
    "Active": ("活跃", "活躍"),
    "Recent": ("最近", "最近"),
    "Count": ("数量", "數量"),
    "Now": ("现在", "現在"),
    "All": ("全部", "全部"),
    "None": ("无", "無"),
    "Custom": ("自定义", "自訂"),
    "Info": ("信息", "資訊"),
    "Action": ("作用", "作用"),
    "Target": ("作用位点", "作用位點"),
    "Classification": ("分类", "分類"),
    "Safety": ("安全性", "安全性"),
    "How it works": ("如何工作", "如何運作"),
    "What is this?": ("这是什么？", "這是什麼？"),
    "From": ("从", "從"),
    "To": ("到", "到"),
    "Avg": ("平均", "平均"),
    "min": ("最小", "最小"),
    "max": ("最大", "最大"),
    "Baseline": ("基线", "基線"),
    # Onboarding
    "Welcome to Piru": ("欢迎使用 Piru", "歡迎使用 Piru"),
    "A few things to set up before you start.": (
        "开始之前需要先设置几项内容。",
        "開始之前需要先設定幾項內容。",
    ),
    "Get Started": ("开始使用", "開始使用"),
    "Track active substances on your Lock Screen and Dynamic Island.": (
        "在锁定屏幕和灵动岛上追踪活跃物质。",
        "在鎖定畫面和動態島上追蹤活躍物質。",
    ),
    "Get hydration and sleep nudges automatically when you log a dose.": (
        "记录剂量时自动收到补水和睡眠提醒。",
        "記錄劑量時自動收到補水和睡眠提醒。",
    ),
    # Loading states
    "Starting...": ("准备中…", "準備中…"),
    "Fetching TripSit data...": ("正在获取 TripSit 数据…", "正在取得 TripSit 資料…"),
    "Fetching clinical drug data...": ("正在获取临床药物数据…", "正在取得臨床藥物資料…"),
    "Enriching half-life data...": ("正在补充半衰期数据…", "正在補充半衰期資料…"),
    "Adding mechanism data...": ("正在加入作用机制数据…", "正在加入作用機制資料…"),
    # Empty states
    "No Results": ("无结果", "無結果"),
    "No Entries": ("无记录", "無記錄"),
    "No Logged Entries": ("无已记录的条目", "無已記錄的條目"),
    "No Custom Substances": ("无自定义物质", "無自訂物質"),
    "No Prescriptions": ("无处方", "無處方"),
    "No Previous Substances": ("无历史物质", "無歷史物質"),
    "No data": ("无数据", "無資料"),
    "No active overlap": ("无活跃重叠", "無活躍重疊"),
    "No known interactions found.": ("未发现已知的相互作用。", "未發現已知的相互作用。"),
    "Try a different search term.": ("尝试其他搜索词。", "嘗試其他搜尋詞。"),
    "Try adjusting your filters.": ("尝试调整筛选条件。", "嘗試調整篩選條件。"),
    "Tap + to log your first entry.": ("点按 + 来记录第一条。", "點按 + 來記錄第一條。"),
    "Search for a substance to log your first entry.": (
        "搜索一个物质开始第一次记录。",
        "搜尋一個物質開始第一次記錄。",
    ),
    "Custom substances you create will appear here. You can also create them from the Quick Log search.": (
        "您创建的自定义物质会显示在这里。也可以在快捷记录搜索中创建。",
        "您建立的自訂物質會顯示在這裡。也可以在快捷記錄搜尋中建立。",
    ),
    "Add prescriptions you take regularly.": ("添加您经常服用的处方。", "新增您經常服用的處方。"),
    "Add prescriptions in Settings to start tracking adherence.": (
        "在设置中添加处方以开始追踪服药情况。",
        "在設定中新增處方以開始追蹤服藥情況。",
    ),
    "No substances logged yet. Colors will appear here after you log your first entry.": (
        "尚未记录任何物质。记录第一条后颜色会显示在这里。",
        "尚未記錄任何物質。記錄第一條後顏色會顯示在這裡。",
    ),
    "Log some entries to see usage stats.": (
        "记录一些条目以查看使用统计。",
        "記錄一些條目以查看使用統計。",
    ),
    "Select a substance to see dose trends": (
        "选择一个物质查看剂量趋势",
        "選擇一個物質查看劑量趨勢",
    ),
    "Custom shades you create will appear here.": (
        "您创建的自定义色调会显示在这里。",
        "您建立的自訂色調會顯示在這裡。",
    ),
    "Log Prescriptions": ("记录处方", "記錄處方"),
    "No substances logged on this day.": ("当天未记录任何物质。", "當天未記錄任何物質。"),
    # Quick Log
    "Quick Log": ("快捷记录", "快捷記錄"),
    "Log Anyway": ("仍要记录", "仍要記錄"),
    "Add as custom substance": ("添加为自定义物质", "新增為自訂物質"),
    "Frequently used": ("常用", "常用"),
    "Favorite": ("收藏", "收藏"),
    "Unfavorite": ("取消收藏", "取消收藏"),
    "Favorites": ("收藏", "收藏"),
    "Relevant to you": ("与您相关", "與您相關"),
    "Recent Doses (24h)": ("近 24 小时剂量", "近 24 小時劑量"),
    "Tap doses to select them, then tap Add to log together.": (
        "点击剂量选择，然后点击「添加」一起记录。",
        "點擊劑量選擇，然後點擊「新增」一起記錄。",
    ),
    "Toggle off any you don't want to log today": (
        "关闭今天不需要记录的项目",
        "關閉今天不需要記錄的項目",
    ),
    "Press the": ("按住", "按住"),
    "icon or long press doses to select multiple at once": (
        "图标或长按剂量以一次选择多个",
        "圖示或長按劑量以一次選擇多個",
    ),
    # Entries
    "New Entry": ("新条目", "新條目"),
    "Edit Entry": ("编辑条目", "編輯條目"),
    "Delete Entry": ("删除条目", "刪除條目"),
    "Delete this entry?": ("删除此条目？", "刪除此條目？"),
    "Show all %lld entries": ("显示全部 %lld 条", "顯示全部 %lld 條"),
    "Entries per day": ("每日条目", "每日條目"),
    "Ingestion time": ("摄入时间", "攝入時間"),
    # Profile & Disclosure Tier
    "Profile": ("个人资料", "個人資料"),
    "Disclosure Tier": ("披露等级", "披露等級"),
    "Casual": ("休闲", "休閒"),
    "Curious": ("好奇", "好奇"),
    "Pharma Nerd": ("药物极客", "藥物極客"),
    "Drag to pan, pinch to zoom, hold to inspect": (
        "拖动平移，捏合缩放，长按查看",
        "拖曳平移，捏合縮放，長按查看",
    ),
    # Database & Settings
    "Substance Database": ("物质数据库", "物質資料庫"),
    "Database Sources": ("数据库来源", "資料庫來源"),
    "Check for Updates": ("检查更新", "檢查更新"),
    # Prescriptions / Daily Doses
    "Prescriptions": ("处方", "處方"),
    "Prescriptions due": ("到期处方", "到期處方"),
    "Add Prescription": ("添加处方", "新增處方"),
    "Edit Prescription": ("编辑处方", "編輯處方"),
    "Current Medications": ("目前用药", "目前用藥"),
    "Daily Reminders": ("每日提醒", "每日提醒"),
    "Reminders": ("提醒", "提醒"),
    "Add Item": ("添加项目", "新增項目"),
    "Add Reminder": ("添加提醒", "新增提醒"),
    "Add Category": ("添加类别", "新增類別"),
    "Rename Category": ("重命名类别", "重新命名類別"),
    "e.g. Morning, Noon, Night": ("例如：早上、中午、晚上", "例如：早上、中午、晚上"),
    "Schedule": ("计划", "排程"),
    "Starting from": ("开始日期", "開始日期"),
    # Form
    "Unit (e.g. mg, ml, µg)": ("单位（如 mg、ml、µg）", "單位（如 mg、ml、µg）"),
    "Custom duration": ("自定义时长", "自訂時長"),
    "Custom half-life": ("自定义半衰期", "自訂半衰期"),
    "Use Custom Half-Life": ("使用自定义半衰期", "使用自訂半衰期"),
    "Dosing Defaults": ("剂量默认值", "劑量預設值"),
    "Dose Reference": ("剂量参考", "劑量參考"),
    "Custom substance (no dose data)": ("自定义物质（无剂量数据）", "自訂物質（無劑量資料）"),
    "Custom substance - enter dose details manually": (
        "自定义物质 — 手动输入剂量详情",
        "自訂物質 — 手動輸入劑量詳情",
    ),
    "Optional notes about this substance for your reference.": (
        "关于此物质的可选备注，供您参考。",
        "關於此物質的可選備註，供您參考。",
    ),
    "Color name (optional)": ("颜色名称（可选）", "顏色名稱（可選）"),
    "Pick a color": ("选择颜色", "選擇顏色"),
    "Pick a color for this substance": ("为此物质选择颜色", "為此物質選擇顏色"),
    "Choose Color": ("选择颜色", "選擇顏色"),
    "Add Color": ("添加颜色", "新增顏色"),
    "Change Color": ("更改颜色", "變更顏色"),
    "Create Custom Shade": ("创建自定义色调", "建立自訂色調"),
    "Your Colors": ("您的颜色", "您的顏色"),
    "New Custom Substance": ("新建自定义物质", "新建自訂物質"),
    "Edit Substance": ("编辑物质", "編輯物質"),
    "Duplicate Name": ("名称重复", "名稱重複"),
    # Help / Alerts
    "Notifications Disabled": ("通知已关闭", "通知已關閉"),
    "Please enable notifications in Settings to use Ramp Down alerts.": (
        "请在「设置」中开启通知以使用缓和期提醒。",
        "請在「設定」中開啟通知以使用緩和期提醒。",
    ),
    "Are you sure you want to delete all your data? This action cannot be undone.": (
        "确定要删除所有数据吗？此操作无法撤销。",
        "確定要刪除所有資料嗎？此操作無法復原。",
    ),
    "Import": ("导入", "匯入"),
    "Cancel Alert": ("取消提醒", "取消提醒"),
    "Cancel Ramp Down?": ("取消缓和期提醒？", "取消緩和期提醒？"),
    "This will cancel the comedown notification.": ("这将取消缓和期通知。", "這將取消緩和期通知。"),
    "Ramp Down": ("缓和期", "緩和期"),
    "Enable Comedown Alert": ("启用缓和期提醒", "啟用緩和期提醒"),
    "Comedown alert": ("缓和期提醒", "緩和期提醒"),
    "Alert scheduled": ("提醒已安排", "提醒已排程"),
    "Comedown window has passed": ("缓和期窗口已过", "緩和期窗口已過"),
    # Notification copy
    "Stay hydrated": ("保持水分", "保持水分"),
    "Hydration check": ("饮水检查", "飲水檢查"),
    "Time to rest": ("该休息了", "該休息了"),
    "Drink some water. Stimulants mask thirst — your body needs more fluids than you realize.": (
        "喝点水。兴奋剂会掩盖口渴感 — 您的身体需要的水分比您意识到的更多。",
        "喝點水。興奮劑會掩蓋口渴感 — 您的身體需要的水分比您意識到的更多。",
    ),
    "Sip some water — a glass every 30-60 minutes. Don't overdo it, just stay steady.": (
        "小口喝水 — 每 30 至 60 分钟一杯。不要过量，保持稳定即可。",
        "小口喝水 — 每 30 至 60 分鐘一杯。不要過量，保持穩定即可。",
    ),
    "Have some water if you can. Your body needs fluids even if you don't feel thirsty.": (
        "尽量喝点水。即使您不觉得渴，身体也需要水分。",
        "盡量喝點水。即使您不覺得渴，身體也需要水分。",
    ),
    "Drink some water. Your body needs it, especially right now.": (
        "喝点水。您的身体需要水分,尤其是现在。",
        "喝點水。您的身體需要水分,尤其是現在。",
    ),
    "Have some water and a snack if you haven't recently. Your body will thank you.": (
        "如果最近还没有,喝点水吃点小食。您的身体会感谢您。",
        "如果最近還沒有,喝點水吃點小食。您的身體會感謝您。",
    ),
    "You've been going for over %lld hours. Try to wind down — dim the lights, put the phone away, and let yourself sleep.": (
        "您已持续超过 %lld 小时。试着放松 — 调暗灯光、放下手机,让自己入睡。",
        "您已持續超過 %lld 小時。試著放鬆 — 調暗燈光、放下手機,讓自己入睡。",
    ),
    "It's been a long session. Your body and brain need sleep to recover. Try to wind down.": (
        "已经持续了很长时间。您的身体和大脑需要睡眠来恢复。试着放松一下。",
        "已經持續了很長時間。您的身體和大腦需要睡眠來恢復。試著放鬆一下。",
    ),
    "Effects should start within %lld-%lld minutes.": (
        "效果应在 %lld 至 %lld 分钟内出现。",
        "效果應在 %lld 至 %lld 分鐘內出現。",
    ),
    "Tracking started. Effects on the way.": (
        "追踪已开始。效果即将出现。",
        "追蹤已開始。效果即將出現。",
    ),
    "First effects starting now. Find your spot.": (
        "初步效果开始出现。找一个舒适的位置。",
        "初步效果開始出現。找一個舒適的位置。",
    ),
    "Peak is hitting. Stay safe and aware.": (
        "巅峰来临。保持安全和警觉。",
        "巔峰來臨。保持安全和警覺。",
    ),
    "{name} wearing off": ("{name} 效果消退中", "{name} 效果消退中"),
    "{name} effects fading": ("{name} 效果减弱中", "{name} 效果減弱中"),
    # Comedown messages
    "Eat a nutritious meal, drink water, and rest. Magnesium and vitamin C may help. Don't fight the tiredness — your body needs recovery.": (
        "吃一顿营养餐、喝水并休息。镁和维生素 C 可能有帮助。不要对抗疲劳 — 您的身体需要恢复。",
        "吃一頓營養餐、喝水並休息。鎂和維生素 C 可能有幫助。不要對抗疲勞 — 您的身體需要恢復。",
    ),
    "The low mood is temporary and normal. Eat light foods, stay warm, and rest. Be kind to yourself over the next few days.": (
        "情绪低落是暂时且正常的。吃清淡食物、保暖、休息。接下来几天善待自己。",
        "情緒低落是暫時且正常的。吃清淡食物、保暖、休息。接下來幾天善待自己。",
    ),
    "You're coming back to baseline. Rest, eat something light. Give yourself time to process the experience.": (
        "您正在回到基线状态。休息、吃些清淡的东西。给自己时间来消化这次体验。",
        "您正在回到基線狀態。休息、吃些清淡的東西。給自己時間來消化這次體驗。",
    ),
    "Stay hydrated and comfortable. Avoid redosing to chase the feeling — reach out if you need support.": (
        "保持水分,让自己舒适。避免再次服用以追求感觉 — 如有需要请寻求支持。",
        "保持水分,讓自己舒適。避免再次服用以追求感覺 — 如有需要請尋求支持。",
    ),
    "Stay somewhere comfortable and safe. Eat and hydrate when you can. Avoid driving.": (
        "留在舒适且安全的地方。能吃喝时就补充水分和食物。避免驾驶。",
        "留在舒適且安全的地方。能吃喝時就補充水分和食物。避免駕駛。",
    ),
    "Rebound anxiety is temporary. Avoid caffeine and alcohol. Breathing exercises: 4 in, 7 hold, 8 out.": (
        "反弹性焦虑是暂时的。避免咖啡因和酒精。呼吸练习:吸气 4 秒、屏住 7 秒、呼气 8 秒。",
        "反彈性焦慮是暫時的。避免咖啡因和酒精。呼吸練習:吸氣 4 秒、屏住 7 秒、呼氣 8 秒。",
    ),
    "Drink water and eat something with electrolytes. Rest in a cool, dark room if your head hurts.": (
        "喝水并吃含电解质的东西。如果头痛,请在凉爽、昏暗的房间里休息。",
        "喝水並吃含電解質的東西。如果頭痛,請在涼爽、昏暗的房間裡休息。",
    ),
    "Drink water, eat something balanced. If foggy, a short walk or fresh air helps clear it.": (
        "喝水、吃均衡的食物。如感到迷糊,短暂散步或呼吸新鲜空气有助清醒。",
        "喝水、吃均衡的食物。如感到迷糊,短暫散步或呼吸新鮮空氣有助清醒。",
    ),
    "Take care of yourself — eat, hydrate, and rest. The effects will fade with time.": (
        "照顾好自己 — 吃饭、补水、休息。效果会随时间消退。",
        "照顧好自己 — 吃飯、補水、休息。效果會隨時間消退。",
    ),
    # Cumulative tips
    "Remember to hydrate, eat, and try to get some sleep. Your heart has been working hard.": (
        "记得补水、吃饭并尝试入睡。您的心脏一直在努力工作。",
        "記得補水、吃飯並嘗試入睡。您的心臟一直在努力工作。",
    ),
    "Your serotonin system is taking a hit. Please rest and take care of yourself.": (
        "您的血清素系统正承受压力。请休息并照顾好自己。",
        "您的血清素系統正承受壓力。請休息並照顧好自己。",
    ),
    "Be very careful. Don't mix with other downers. Have naloxone nearby if possible.": (
        "务必小心。不要与其他抑制剂混用。如果可能,请准备纳洛酮。",
        "務必小心。不要與其他抑制劑混用。如果可能,請準備納洛酮。",
    ),
    "High cumulative benzo doses impair memory and coordination. Stay somewhere safe.": (
        "苯二氮䓬累积剂量较高会损害记忆和协调能力。留在安全的地方。",
        "苯二氮䓬累積劑量較高會損害記憶和協調能力。留在安全的地方。",
    ),
    "Stay somewhere safe. Don't drive. Your coordination and judgment are affected.": (
        "留在安全的地方。不要开车。您的协调能力和判断力受到影响。",
        "留在安全的地方。不要開車。您的協調能力和判斷力受到影響。",
    ),
    "Take it easy. Hydrate, eat, and rest.": (
        "放轻松。补水、吃饭、休息。",
        "放輕鬆。補水、吃飯、休息。",
    ),
    # File operations
    "Export failed: %@": ("导出失败:%@", "匯出失敗:%@"),
    "Import failed: %@": ("导入失败:%@", "匯入失敗:%@"),
    "Delete failed: %@": ("删除失败:%@", "刪除失敗:%@"),
    "Data imported successfully.": ("数据导入成功。", "資料匯入成功。"),
    "Couldn't access the selected file.": ("无法访问所选文件。", "無法存取所選檔案。"),
    # Interactions
    "Interaction Timeline": ("相互作用时间轴", "相互作用時間軸"),
    "Interaction Warning": ("相互作用警告", "相互作用警告"),
    "1 Interaction Found": ("发现 1 个相互作用", "發現 1 個相互作用"),
    "%lld Interactions Found": ("发现 %lld 个相互作用", "發現 %lld 個相互作用"),
    "%lld interaction%@ detected": ("检测到 %1$lld 个相互作用", "偵測到 %1$lld 個相互作用"),
    "%lld Interaction Warnings": ("%lld 个相互作用警告", "%lld 個相互作用警告"),
    "1 interaction": ("1 个相互作用", "1 個相互作用"),
    "%lld interactions": ("%lld 个相互作用", "%lld 個相互作用"),
    "Choose at least 2 substances": ("请至少选择 2 种物质", "請至少選擇 2 種物質"),
    "Both substances active": ("两种物质都在活跃", "兩種物質都在活躍"),
    "At this timing, the substances are not simultaneously active above threshold.": (
        "在此时间点,这些物质未同时高于阈值活跃。",
        "在此時間點,這些物質未同時高於閾值活躍。",
    ),
    "From %@ to %@ (%@ overlap)": ("从 %@ 到 %@(重叠 %@)", "從 %@ 到 %@(重疊 %@)"),
    "This timeline uses a simplified one-compartment PK model with population-average half-lives. Real overlap depends on individual metabolism, dose, route, tolerance, and many other factors. This is not medical advice.": (
        "此时间轴使用简化的一房室药代动力学模型与群体平均半衰期。实际重叠取决于个人代谢、剂量、途径、耐受性等多种因素。这不构成医疗建议。",
        "此時間軸使用簡化的一房室藥動學模型與族群平均半衰期。實際重疊取決於個人代謝、劑量、途徑、耐受性等多種因素。這不構成醫療建議。",
    ),
    # MoA / Pharmacology
    "Mechanism of Action": ("作用机制", "作用機制"),
    # Stage 4 — chemistry card + pharmacokinetics disclosure
    "Pharmacokinetics": ("药代动力学", "藥物動力學"),
    "Metabolism": ("代谢", "代謝"),
    "Population-average pharmacokinetics from primary literature with per-row source attribution. Real values vary with genetics, organ function, and route.": (
        "源自原始文献的群体平均药代动力学数据，每行均标注来源。实际数值因个体遗传、器官功能与给药途径而异。",
        "源自原始文獻的群體平均藥物動力學數據，每列均標註來源。實際數值因個體遺傳、器官功能與給藥途徑而異。",
    ),
    "Physicochemical values are predicted/computed (PubChem, NPS-DataHub), not measured for this preparation.": (
        "理化数值为预测/计算值（PubChem、NPS-DataHub），并非针对此制剂实测。",
        "理化數值為預測/計算值（PubChem、NPS-DataHub），並非針對此製劑實測。",
    ),
    "LD50 is rodent toxicity (order of magnitude) — not a human safe dose.": (
        "LD50 为啮齿动物毒性（数量级参考），并非人体安全剂量。",
        "LD50 為齧齒動物毒性（數量級參考），並非人體安全劑量。",
    ),
    "IUPAC name": ("IUPAC 名称", "IUPAC 名稱"),
    "H-bond acceptors": ("氢键受体", "氫鍵受體"),
    "H-bond donors": ("氢键供体", "氫鍵供體"),
    "Melting point": ("熔点", "熔點"),
    "Boiling point": ("沸点", "沸點"),
    "LD50 (oral, rodent)": ("LD50（口服，啮齿动物）", "LD50（口服，齧齒動物）"),
    "LD50 (dermal, rodent)": ("LD50（皮肤，啮齿动物）", "LD50（皮膚，齧齒動物）"),
    "active": ("有活性", "有活性"),
    "inactive": ("无活性", "無活性"),
    "Subjective Effects": ("主观效果", "主觀效果"),
    "Reported Subjective Effects": ("报告的主观效果", "報告的主觀效果"),
    "Primary Targets: ": ("主要作用位点: ", "主要作用位點: "),
    "Also known as": ("别名", "別名"),
    # Calculator / PK
    "Concentration Curve": ("浓度曲线", "濃度曲線"),
    "Concentration Curves": ("浓度曲线", "濃度曲線"),
    "Elimination Curve": ("消除曲线", "消除曲線"),
    "Current Estimated Amount": ("当前估算剂量", "當前估算劑量"),
    "Peak concentration": ("峰值浓度", "峰值濃度"),
    "Reached after %@": ("%@ 后达到", "%@ 後達到"),
    "Peak ends ~": ("巅峰结束 ~", "巔峰結束 ~"),
    "Peak %@": ("巅峰 %@", "巔峰 %@"),
    "Conc": ("浓度", "濃度"),
    "Estimate Only": ("仅供参考", "僅供參考"),
    "Estimates based on pharmacokinetic modeling. Actual levels may vary.": (
        "基于药代动力学建模的估算。实际水平可能有所不同。",
        "基於藥動學建模的估算。實際水平可能有所不同。",
    ),
    "Pinch to zoom in or out": ("捏合以放大或缩小", "捏合以放大或縮小"),
    "Open in Calculator": ("在计算器中打开", "在計算器中打開"),
    "Half-life data not available for %@.": ("没有 %@ 的半衰期数据。", "沒有 %@ 的半衰期資料。"),
    "Half-life data unavailable for %@": ("无 %@ 的半衰期数据", "無 %@ 的半衰期資料"),
    "%lld with half-life data": ("%lld 个有半衰期数据", "%lld 個有半衰期資料"),
    "No pharmacokinetic data available for this substance and route.": (
        "此物质和途径暂无药代动力学数据。",
        "此物質和途徑暫無藥動學資料。",
    ),
    "Add per-phase timing so this substance gets a Live-Activity timeline like library substances.": (
        "添加分阶段计时,让此物质拥有与库中物质一样的实时活动时间轴。",
        "新增分階段計時,讓此物質擁有與庫中物質一樣的即時動態時間軸。",
    ),
    "Minutes for each phase. Leave a phase blank to skip it; the timeline will interpolate from what you provide.": (
        "每个阶段的分钟数。留空可跳过;时间轴会根据您提供的数据进行插值。",
        "每個階段的分鐘數。留空可跳過;時間軸會根據您提供的資料進行插值。",
    ),
    "eliminated": ("已消除", "已消除"),
    "t½ = %@": ("半衰期 = %@", "半衰期 = %@"),
    "t½ %@": ("半衰期 %@", "半衰期 %@"),
    "%lld%% eliminated": ("%lld%% 已消除", "%lld%% 已消除"),
    # Volumetric dosing
    "Volumetric Dosing": ("容积式给药", "容積式給藥"),
    "Extremely Potent Substance": ("极强效物质", "極強效物質"),
    "Active in microgram (µg) quantities — 1/1000th of a milligram. Volumetric dosing is required at all times for safe and accurate measurement. Never attempt to measure doses by eye or with standard scales.": (
        "微克(µg)量级即有效 — 即一毫克的千分之一。任何时候都必须使用容积式给药以确保安全准确的测量。绝不要靠目测或用普通秤来称量剂量。",
        "微克(µg)量級即有效 — 即一毫克的千分之一。任何時候都必須使用容積式給藥以確保安全準確的測量。絕不要靠目測或用普通秤來秤量劑量。",
    ),
    "Calculate measurements for dissolving substances in liquid solvents.": (
        "计算物质溶于液体溶剂的测量值。",
        "計算物質溶於液體溶劑的測量值。",
    ),
    # Help / Crisis
    "If you need help right now:": ("如果您现在需要帮助:", "如果您現在需要幫助:"),
    "While you wait or if you just need to calm down:": (
        "在等待时,或如果您只是想冷静下来:",
        "在等待時,或如果您只是想冷靜下來:",
    ),
    "Breathe slowly: 4 seconds in, hold for 4, out for 4.": (
        "慢慢呼吸:吸气 4 秒、屏住 4 秒、呼气 4 秒。",
        "慢慢呼吸:吸氣 4 秒、屏住 4 秒、呼氣 4 秒。",
    ),
    "Breathe slowly. 4 seconds in, hold for 4, out for 4. You are safe.": (
        "慢慢呼吸。吸气 4 秒、屏住 4 秒、呼气 4 秒。您是安全的。",
        "慢慢呼吸。吸氣 4 秒、屏住 4 秒、呼氣 4 秒。您是安全的。",
    ),
    "Put your feet flat on the floor. Feel the ground beneath you.": (
        "将双脚平放在地板上。感受脚下的地面。",
        "將雙腳平放在地板上。感受腳下的地面。",
    ),
    "Name 5 things you can see. 4 you can touch. 3 you can hear.": (
        "说出 5 件您看到的事物、4 件能触摸的、3 件能听到的。",
        "說出 5 件您看到的事物、4 件能觸摸的、3 件能聽到的。",
    ),
    "Take a deep breath.": ("深呼吸。", "深呼吸。"),
    "Take a breath.": ("深呼吸。", "深呼吸。"),
    "You are not alone. People care about you and help is available.": (
        "您并不孤单。有人关心您,也有可用的帮助。",
        "您並不孤單。有人關心您,也有可用的幫助。",
    ),
    "Whatever you're experiencing right now, help is available and you don't have to face it alone.": (
        "无论您此刻经历什么,都有可寻求的帮助,您不必独自面对。",
        "無論您此刻經歷什麼,都有可尋求的幫助,您不必獨自面對。",
    ),
    "You're going to be okay": ("一切都会好的", "一切都會好的"),
    "You're going to be okay. This feeling is temporary.": (
        "一切都会好的。这种感觉是暂时的。",
        "一切都會好的。這種感覺是暫時的。",
    ),
    "You're going to be okay. Whatever you're feeling right now is temporary.": (
        "一切都会好的。您现在的任何感受都是暂时的。",
        "一切都會好的。您現在的任何感受都是暫時的。",
    ),
    "Emergency Services": ("紧急服务", "緊急服務"),
    "Emergency Services — %@": ("紧急服务 — %@", "緊急服務 — %@"),
    "Copy Summary for Emergency Services": ("为紧急服务复制摘要", "為緊急服務複製摘要"),
    "Copies a plain-text summary of substances and recent doses to share with emergency responders.": (
        "将物质和最近剂量的纯文本摘要复制到剪贴板,以便与急救人员分享。",
        "將物質和最近劑量的純文字摘要複製到剪貼簿,以便與急救人員分享。",
    ),
    # Recovery / Comedown
    "Recovery Guide": ("恢复指南", "恢復指南"),
    "Recovery — Right Now": ("立即恢复", "立即恢復"),
    "Recovery tips": ("恢复提示", "恢復提示"),
    "Universal recovery basics": ("通用恢复基础", "通用恢復基礎"),
    "Hydrate — water or electrolyte drinks, sip steadily": (
        "补水 — 水或电解质饮料,小口慢饮",
        "補水 — 水或電解質飲料,小口慢飲",
    ),
    "Eat something nutritious — protein, carbs, and fruit": (
        "吃些营养食物 — 蛋白质、碳水化合物和水果",
        "吃些營養食物 — 蛋白質、碳水化合物和水果",
    ),
    "Sleep when your body lets you — don't fight it": (
        "身体允许时就睡 — 不要硬撑",
        "身體允許時就睡 — 不要硬撐",
    ),
    "Fresh air and gentle light help reset your system": (
        "新鲜空气和柔和光线有助于重置身体",
        "新鮮空氣和柔和光線有助於重置身體",
    ),
    "Light movement or stretching — nothing intense": (
        "轻度活动或拉伸 — 不要剧烈运动",
        "輕度活動或拉伸 — 不要劇烈運動",
    ),
    "Put the phone down — screens can amplify restlessness": (
        "放下手机 — 屏幕会加剧躁动感",
        "放下手機 — 螢幕會加劇躁動感",
    ),
    "Reach out to someone you trust if you feel overwhelmed": (
        "如果感到无法承受,向信任的人倾诉",
        "如果感到無法承受,向信任的人傾訴",
    ),
    # InteractionSeverity / Source labels
    "Dangerous": ("危险", "危險"),
    "Unsafe": ("不安全", "不安全"),
    "Caution": ("警告", "警告"),
    "Pharmacological": ("药理学", "藥理學"),
    "TripSit": ("TripSit", "TripSit"),
    "FDA": ("FDA", "FDA"),
    # Adherence status
    "All taken": ("全部已服用", "全部已服用"),
    "Partially taken": ("部分已服用", "部分已服用"),
    "All missed": ("全部漏服", "全部漏服"),
    "Nothing due": ("无到期项", "無到期項"),
    # HelpView reassurance + tips
    "Put on familiar music": ("听熟悉的音乐", "聽熟悉的音樂"),
    "Familiar songs can ground you and bring comfort. Pick something you know well.": (
        "熟悉的歌曲能让您找回脚踏实地的感觉并带来慰藉。选一首您熟悉的吧。",
        "熟悉的歌曲能讓您找回腳踏實地的感覺並帶來慰藉。選一首您熟悉的吧。",
    ),
    "Music you know well is one of the most powerful grounding tools — especially during a psychedelic experience.": (
        "您熟悉的音乐是最强大的接地工具之一 — 尤其是在致幻体验期间。",
        "您熟悉的音樂是最強大的接地工具之一 — 尤其是在致幻體驗期間。",
    ),
    "Call a friend or family member": ("打电话给朋友或家人", "打電話給朋友或家人"),
    "Someone who knows you can help more than you’d expect. You don’t have to explain everything — just hearing a familiar voice helps.": (
        "了解您的人比您想象的更能提供帮助。您不必解释一切 — 只是听到熟悉的声音就有帮助。",
        "了解您的人比您想像的更能提供幫助。您不必解釋一切 — 只是聽到熟悉的聲音就有幫助。",
    ),
    "Emergency (Ambulance)": ("紧急服务(救护车)", "緊急服務(救護車)"),
    "Emergency": ("紧急", "緊急"),
    "Suicide & Crisis Lifeline": ("自杀与危机援助热线", "自殺與危機援助熱線"),
    "Suicide Prevention": ("自杀预防", "自殺預防"),
    "Suicide Prevention Hotline": ("自杀预防热线", "自殺預防熱線"),
    "Suicide Crisis Helpline": ("自杀危机援助热线", "自殺危機援助熱線"),
    "Crisis Line": ("危机援助专线", "危機援助專線"),
    "Crisis Hotline": ("危机援助热线", "危機援助熱線"),
    "Crisis Text Line": ("危机短信专线", "危機簡訊專線"),
    "Lifeline": ("生命线", "生命線"),
    "Lifeline Ukraine": ("乌克兰生命线", "烏克蘭生命線"),
    "Poison Control": ("中毒控制中心", "中毒控制中心"),
    "Poison Centre": ("中毒中心", "中毒中心"),
    "Poisons Centre": ("中毒中心", "中毒中心"),
    "Poisons Information": ("中毒信息", "中毒資訊"),
    "Psychological Help": ("心理援助", "心理援助"),
    "SAMHSA Helpline": ("SAMHSA 援助热线", "SAMHSA 援助熱線"),
    # Interaction descriptions
    "Combined respiratory depression — the leading cause of overdose death.": (
        "联合呼吸抑制 — 过量致死的首要原因。",
        "聯合呼吸抑制 — 過量致死的首要原因。",
    ),
    "Severe respiratory depression — both substances suppress breathing.": (
        "严重呼吸抑制 — 两种物质都会抑制呼吸。",
        "嚴重呼吸抑制 — 兩種物質都會抑制呼吸。",
    ),
    "Respiratory depression and CNS shutdown — potentially fatal combination.": (
        "呼吸抑制及中枢神经停摆 — 可能致命的组合。",
        "呼吸抑制及中樞神經停擺 — 可能致命的組合。",
    ),
    "Risk of fatal serotonin syndrome — do not combine.": (
        "有致命血清素综合征的风险 — 切勿合用。",
        "有致命血清素綜合徵的風險 — 切勿合用。",
    ),
    "Serotonin syndrome — potentially fatal. Allow 2+ week washout.": (
        "血清素综合征 — 可能致命。需 2 周以上的清除期。",
        "血清素綜合徵 — 可能致命。需 2 週以上的清除期。",
    ),
    "Risk of serotonin syndrome and hypertensive crisis.": (
        "有血清素综合征和高血压危象的风险。",
        "有血清素綜合徵和高血壓危象的風險。",
    ),
    "Hypertensive crisis — potentially fatal spike in blood pressure.": (
        "高血压危象 — 血压可能致命性飙升。",
        "高血壓危象 — 血壓可能致命性飆升。",
    ),
    "Risk of serotonin syndrome, especially with meperidine/pethidine, tramadol, and tapentadol.": (
        "有血清素综合征的风险,尤其是与哌替啶、曲马多和他喷他多。",
        "有血清素綜合徵的風險,尤其是與哌替啶、曲馬多和他噴他多。",
    ),
    "Risk of seizures and serotonin toxicity — well-documented dangerous combination.": (
        "有癫痫发作和血清素毒性的风险 — 已有充分记录的危险组合。",
        "有癲癇發作和血清素毒性的風險 — 已有充分記錄的危險組合。",
    ),
    "Respiratory depression and loss of consciousness — very narrow safety margin.": (
        "呼吸抑制和意识丧失 — 安全边际极窄。",
        "呼吸抑制和意識喪失 — 安全邊際極窄。",
    ),
    "Severe respiratory depression — both are GABAergic depressants.": (
        "严重呼吸抑制 — 两者都是 GABA 能抑制剂。",
        "嚴重呼吸抑制 — 兩者都是 GABA 能抑制劑。",
    ),
    "Life-threatening respiratory depression — this combination is a leading cause of overdose death.": (
        "危及生命的呼吸抑制 — 此组合是过量致死的主要原因。",
        "危及生命的呼吸抑制 — 此組合是過量致死的主要原因。",
    ),
    "Enhanced respiratory depression — gabapentinoids increase opioid overdose risk.": (
        "加重的呼吸抑制 — 加巴喷丁类增加阿片过量风险。",
        "加重的呼吸抑制 — 加巴噴丁類增加阿片過量風險。",
    ),
    "Stacking opioids is unpredictable — respiratory depression risk compounds.": (
        "叠加阿片不可预测 — 呼吸抑制风险叠加。",
        "疊加阿片不可預測 — 呼吸抑制風險疊加。",
    ),
    "Additive CNS and respiratory depression — antihistamines potentiate opioid sedation.": (
        "中枢和呼吸抑制相加 — 抗组胺药增强阿片的镇静作用。",
        "中樞和呼吸抑制相加 — 抗組胺藥增強阿片的鎮靜作用。",
    ),
    "Stimulants mask overdose signs — when they wear off, respiratory depression can emerge.": (
        "兴奋剂会掩盖过量的征兆 — 一旦消退,呼吸抑制可能浮现。",
        "興奮劑會掩蓋過量的徵兆 — 一旦消退,呼吸抑制可能浮現。",
    ),
    "Excessive sedation and respiratory depression risk.": (
        "过度镇静和呼吸抑制的风险。",
        "過度鎮靜和呼吸抑制的風險。",
    ),
    "Compounded CNS depression — excessive sedation and impaired breathing.": (
        "叠加的中枢抑制 — 过度镇静和呼吸受损。",
        "疊加的中樞抑制 — 過度鎮靜和呼吸受損。",
    ),
    "Reduced effects and risk of serotonin syndrome — SSRIs block MDMA's mechanism.": (
        "效果减弱并有血清素综合征的风险 — SSRI 会阻断 MDMA 的作用机制。",
        "效果減弱並有血清素綜合徵的風險 — SSRI 會阻斷 MDMA 的作用機制。",
    ),
    "Serotonin syndrome risk — SNRIs block reuptake while empathogens release serotonin.": (
        "有血清素综合征的风险 — SNRI 阻断再摄取,而共感剂释放血清素。",
        "有血清素綜合徵的風險 — SNRI 阻斷再攝取,而共感劑釋放血清素。",
    ),
    "Serotonin toxicity risk from combined serotonergic activity.": (
        "联合的血清素能活性带来血清素毒性的风险。",
        "聯合的血清素能活性帶來血清素毒性的風險。",
    ),
    "Respiratory depression risk — dissociatives can mask overdose signs.": (
        "有呼吸抑制的风险 — 解离剂会掩盖过量的征兆。",
        "有呼吸抑制的風險 — 解離劑會掩蓋過量的徵兆。",
    ),
    "Additive CNS and respiratory depression.": ("中枢和呼吸抑制相加。", "中樞和呼吸抑制相加。"),
    "Increased risk of serotonin syndrome and lithium toxicity.": (
        "血清素综合征和锂中毒的风险增加。",
        "血清素綜合徵和鋰中毒的風險增加。",
    ),
    "Serotonin syndrome risk — especially with DXM and other serotonergic dissociatives.": (
        "有血清素综合征的风险 — 尤其是与 DXM 等血清素能解离剂。",
        "有血清素綜合徵的風險 — 尤其是與 DXM 等血清素能解離劑。",
    ),
    "Cardiovascular strain — combined stimulants increase heart rate and blood pressure.": (
        "心血管压力 — 联合兴奋剂会提高心率和血压。",
        "心血管壓力 — 聯合興奮劑會提高心率和血壓。",
    ),
    "Increased anxiety and vasoconstriction — stimulants can intensify difficult trips.": (
        "焦虑加剧和血管收缩 — 兴奋剂会加重艰难的体验。",
        "焦慮加劇和血管收縮 — 興奮劑會加重艱難的體驗。",
    ),
    "Unpredictable intensification — cannabis can trigger anxiety or thought loops.": (
        "不可预测的强化 — 大麻可能引发焦虑或思维循环。",
        "不可預測的強化 — 大麻可能引發焦慮或思維迴圈。",
    ),
    "Risk of respiratory depression, aspiration, and loss of consciousness.": (
        "有呼吸抑制、误吸和意识丧失的风险。",
        "有呼吸抑制、誤吸和意識喪失的風險。",
    ),
    "Significant respiratory depression risk and profound loss of consciousness.": (
        "显著的呼吸抑制风险和深度意识丧失。",
        "顯著的呼吸抑制風險和深度意識喪失。",
    ),
    "Stacking benzodiazepines dramatically increases sedation and respiratory depression risk.": (
        "叠加苯二氮䓬类会显著增加镇静和呼吸抑制的风险。",
        "疊加苯二氮䓬類會顯著增加鎮靜和呼吸抑制的風險。",
    ),
    "SSRIs typically reduce psychedelic effects but may increase risk with some compounds.": (
        "SSRI 通常会减弱致幻效应,但与某些化合物可能增加风险。",
        "SSRI 通常會減弱致幻效應,但與某些化合物可能增加風險。",
    ),
    "Serotonin accumulation risk — combining serotonergic agents increases toxicity chance.": (
        "血清素累积的风险 — 联合血清素能药物会增加毒性几率。",
        "血清素累積的風險 — 聯合血清素能藥物會增加毒性機率。",
    ),
    "Overlapping serotonin reuptake inhibition — increased serotonin syndrome risk.": (
        "血清素再摄取抑制重叠 — 血清素综合征的风险增加。",
        "血清素再攝取抑制重疊 — 血清素綜合徵的風險增加。",
    ),
    "SSRIs inhibit TCA metabolism — risk of TCA toxicity and serotonin syndrome.": (
        "SSRI 抑制 TCA 代谢 — 有 TCA 中毒和血清素综合征的风险。",
        "SSRI 抑制 TCA 代謝 — 有 TCA 中毒和血清素綜合徵的風險。",
    ),
    "Increased heart rate and blood pressure — cardiovascular strain.": (
        "心率和血压增加 — 心血管压力。",
        "心率和血壓增加 — 心血管壓力。",
    ),
    "Stimulants mask alcohol impairment — risk of overconsumption.": (
        "兴奋剂会掩盖酒精损害 — 有过量饮用的风险。",
        "興奮劑會掩蓋酒精損害 — 有過量飲用的風險。",
    ),
    "Compounded drowsiness and impaired coordination.": (
        "叠加的嗜睡和协调受损。",
        "疊加的嗜睡和協調受損。",
    ),
    "Additive CNS depression — increased sedation and impairment.": (
        "中枢抑制相加 — 镇静和损害加剧。",
        "中樞抑制相加 — 鎮靜和損害加劇。",
    ),
    "Enhanced CNS depression — risk of respiratory depression and death.": (
        "加重的中枢抑制 — 有呼吸抑制和死亡的风险。",
        "加重的中樞抑制 — 有呼吸抑制和死亡的風險。",
    ),
    "Stacking gabapentinoids compounds sedation and respiratory depression risk.": (
        "叠加加巴喷丁类会加重镇静和呼吸抑制的风险。",
        "疊加加巴噴丁類會加重鎮靜和呼吸抑制的風險。",
    ),
    "Compounded dissociation — disorientation and loss of motor control.": (
        "叠加的解离 — 定向障碍和运动控制丧失。",
        "疊加的解離 — 定向障礙和運動控制喪失。",
    ),
    "Serotonin depletion and neurotoxicity risk — allow adequate recovery between uses.": (
        "血清素耗竭和神经毒性的风险 — 使用间隔应足够长以便恢复。",
        "血清素耗竭和神經毒性的風險 — 使用間隔應足夠長以便恢復。",
    ),
    "Risk of seizures and serotonin toxicity — potentially fatal combination.": (
        "有癫痫发作和血清素毒性的风险 — 可能致命的组合。",
        "有癲癇發作和血清素毒性的風險 — 可能致命的組合。",
    ),
    "Risk of serotonin syndrome and lithium toxicity.": (
        "有血清素综合征和锂中毒的风险。",
        "有血清素綜合徵和鋰中毒的風險。",
    ),
    "Some combinations increase serotonin or seizure risk — monitor for symptoms.": (
        "某些组合会增加血清素或癫痫的风险 — 注意监测症状。",
        "某些組合會增加血清素或癲癇的風險 — 注意監測症狀。",
    ),
    "Cardiovascular strain and potential serotonin interaction — monitor heart rate and blood pressure.": (
        "心血管压力和潜在的血清素相互作用 — 监测心率和血压。",
        "心血管壓力和潛在的血清素相互作用 — 監測心率和血壓。",
    ),
    "Combined QTc prolongation risk — monitor cardiac rhythm.": (
        "联合 QTc 延长的风险 — 监测心律。",
        "聯合 QTc 延長的風險 — 監測心律。",
    ),
    "Additive CNS depression — increased sedation and impaired coordination.": (
        "中枢抑制相加 — 镇静加剧、协调受损。",
        "中樞抑制相加 — 鎮靜加劇、協調受損。",
    ),
    "Additive sedation — may increase drowsiness and impaired coordination.": (
        "镇静相加 — 可能加剧嗜睡和协调受损。",
        "鎮靜相加 — 可能加劇嗜睡和協調受損。",
    ),
    "Additive CNS depression — may increase sedation and respiratory depression risk.": (
        "中枢抑制相加 — 可能加剧镇静和呼吸抑制的风险。",
        "中樞抑制相加 — 可能加劇鎮靜和呼吸抑制的風險。",
    ),
    "Serotonin syndrome risk with some opioids (tramadol, meperidine, fentanyl) — monitor for symptoms.": (
        "某些阿片(曲马多、哌替啶、芬太尼)有血清素综合征的风险 — 注意监测症状。",
        "某些阿片(曲馬多、哌替啶、芬太尼)有血清素綜合徵的風險 — 注意監測症狀。",
    ),
    "Additive impairment — increased dizziness, drowsiness, and slowed reaction time.": (
        "损害相加 — 头晕、嗜睡和反应延迟加剧。",
        "損害相加 — 頭暈、嗜睡和反應延遲加劇。",
    ),
    # Non-English-name emergency services — keep as proper nouns
    "113 Zelfmoordpreventie": ("113 Zelfmoordpreventie", "113 Zelfmoordpreventie"),
    "Acil Yardim": ("Acil Yardim", "Acil Yardim"),
    "Alarmnummer": ("Alarmnummer", "Alarmnummer"),
    "Ambulancia": ("Ambulancia", "Ambulancia"),
    "Befrienders": ("Befrienders", "Befrienders"),
    "Befrienders Kenya": ("Befrienders Kenya", "Befrienders Kenya"),
    "CVV (Centro de Valorização da Vida)": (
        "CVV (Centro de Valorização da Vida)",
        "CVV (Centro de Valorização da Vida)",
    ),
    "Centre Antipoison": ("Centre Antipoison", "Centre Antipoison"),
    "Centre Antipoisons": ("Centre Antipoisons", "Centre Antipoisons"),
    "Centro Antiveleni": ("Centro Antiveleni", "Centro Antiveleni"),
    "Centro de Asistencia al Suicida": (
        "Centro de Asistencia al Suicida",
        "Centro de Asistencia al Suicida",
    ),
    "Die Dargebotene Hand": ("Die Dargebotene Hand", "Die Dargebotene Hand"),
    "EKAB": ("EKAB", "EKAB"),
    "ERAN Crisis Line": ("ERAN Crisis Line", "ERAN Crisis Line"),
    "Emergencias": ("Emergencias", "Emergencias"),
    "Emergencias (ECU 911)": ("Emergencias (ECU 911)", "Emergencias (ECU 911)"),
    "Emergenze": ("Emergenze", "Emergenze"),
    "FRANK Drug Helpline": ("FRANK Drug Helpline", "FRANK Drug Helpline"),
    "Giftinformasjonen": ("Giftinformasjonen", "Giftinformasjonen"),
    "Giftnotruf": ("Giftnotruf", "Giftnotruf"),
    "Hatanumero": ("Hatanumero", "Hatanumero"),
    "Intihar Onleme Hatti": ("Intihar Onleme Hatti", "Intihar Onleme Hatti"),
    "Klimaka Crisis Line": ("Klimaka Crisis Line", "Klimaka Crisis Line"),
    "Kriisipuhelin": ("Kriisipuhelin", "Kriisipuhelin"),
    "Linea 113 Salud": ("Linea 113 Salud", "Linea 113 Salud"),
    "Linea de Crisis": ("Linea de Crisis", "Linea de Crisis"),
    "Linea de Emergencias": ("Linea de Emergencias", "Linea de Emergencias"),
    "Linea de Prevencion del Suicidio": (
        "Linea de Prevencion del Suicidio",
        "Linea de Prevencion del Suicidio",
    ),
    "Linea de la Vida": ("Linea de la Vida", "Linea de la Vida"),
    "Linka bezpeci": ("Linka bezpeci", "Linka bezpeci"),
    "Livslinien": ("Livslinien", "Livslinien"),
    "Mental Helse": ("Mental Helse", "Mental Helse"),
    "Mind Sjalvmordslinjen": ("Mind Sjalvmordslinjen", "Mind Sjalvmordslinjen"),
    "Nodnummer": ("Nodnummer", "Nodnummer"),
    "Notruf": ("Notruf", "Notruf"),
    "Numer alarmowy": ("Numer alarmowy", "Numer alarmowy"),
    "Pieta House": ("Pieta House", "Pieta House"),
    "SADAG Crisis Line": ("SADAG Crisis Line", "SADAG Crisis Line"),
    "SAMU": ("SAMU", "SAMU"),
    "SOS Amitie": ("SOS Amitie", "SOS Amitie"),
    "SOS Voz Amiga": ("SOS Voz Amiga", "SOS Voz Amiga"),
    "Salud Responde": ("Salud Responde", "Salud Responde"),
    "Samaritans": ("Samaritans", "Samaritans"),
    "Samaritans of Singapore": ("Samaritans of Singapore", "Samaritans of Singapore"),
    "Samaritans of Thailand": ("Samaritans of Thailand", "Samaritans of Thailand"),
    "Sanitatsnotruf": ("Sanitatsnotruf", "Sanitatsnotruf"),
    "Servicios de Emergencia": ("Servicios de Emergencia", "Servicios de Emergencia"),
    "Telefon Zaufania": ("Telefon Zaufania", "Telefon Zaufania"),
    "Telefono Amico": ("Telefono Amico", "Telefono Amico"),
    "Telefono de la Esperanza": ("Telefono de la Esperanza", "Telefono de la Esperanza"),
    "Telefonseelsorge": ("Telefonseelsorge", "Telefonseelsorge"),
    "Tisnovka": ("Tisnovka", "Tisnovka"),
    "Tox Info Suisse": ("Tox Info Suisse", "Tox Info Suisse"),
    "Urgences": ("Urgences", "Urgences"),
    "Vandrevala Foundation": ("Vandrevala Foundation", "Vandrevala Foundation"),
    "Yorisoi Hotline": ("Yorisoi Hotline", "Yorisoi Hotline"),
    # Insights stat cards
    "Entries": ("条目", "條目"),
    "Substances": ("物质", "物質"),
    "Per day": ("每日", "每日"),
    "Most logged": ("记录最多", "記錄最多"),
    # Time of day chart
    "Morning\n6–12": ("早上\n6–12", "早上\n6–12"),
    "Afternoon\n12–18": ("下午\n12–18", "下午\n12–18"),
    "Evening\n18–0": ("傍晚\n18–0", "傍晚\n18–0"),
    "Night\n0–6": ("夜间\n0–6", "夜間\n0–6"),
    # Volumetric dosing
    "Desired Concentration": ("所需浓度", "所需濃度"),
    "Substance Amount": ("物质剂量", "物質劑量"),
    "Solvent Volume": ("溶剂体积", "溶劑體積"),
    "Solution Concentration": ("溶液浓度", "溶液濃度"),
    "Desired Dose": ("所需剂量", "所需劑量"),
    "Volume to Dose": ("剂量体积", "劑量體積"),
    "Always label solutions with substance name and concentration.": (
        "始终用物质名称和浓度标记溶液。",
        "始終用物質名稱和濃度標記溶液。",
    ),
    "Verify calculations independently before use.": (
        "使用前请独立核对计算。",
        "使用前請獨立核對計算。",
    ),
    "Use a milligram scale and graduated cylinder for accuracy.": (
        "使用毫克秤和量筒以确保精确。",
        "使用毫克秤和量筒以確保精確。",
    ),
    "Store solutions in clearly marked, child-proof containers.": (
        "将溶液存放在标识清楚、儿童无法打开的容器中。",
        "將溶液存放在標識清楚、兒童無法打開的容器中。",
    ),
    # Comedown guide section headers
    "What's happening": ("正在发生什么", "正在發生什麼"),
    "Right now": ("此刻", "此刻"),
    "Over the next hours": ("接下来几小时", "接下來幾小時"),
    "What to avoid": ("应避免的事", "應避免的事"),
    # Comedown guide bullet points — Stimulant
    "Your brain burned through dopamine and norepinephrine faster than usual.": (
        "您的大脑比平时更快地消耗了多巴胺和去甲肾上腺素。",
        "您的大腦比平時更快地消耗了多巴胺和去甲腎上腺素。",
    ),
    "The crash is your nervous system demanding rest and replenishment.": (
        "这次崩溃是您的神经系统在要求休息和补充。",
        "這次崩潰是您的神經系統在要求休息和補充。",
    ),
    "Fatigue, irritability, and low mood are all normal parts of this process.": (
        "疲倦、易怒和情绪低落都是此过程中的正常表现。",
        "疲倦、易怒和情緒低落都是此過程中的正常表現。",
    ),
    "Eat something — even if you're not hungry. Protein and complex carbs help most.": (
        "吃点东西 — 即使您不饿。蛋白质和复合碳水化合物最有帮助。",
        "吃點東西 — 即使您不餓。蛋白質和複合碳水化合物最有幫助。",
    ),
    "Drink water or an electrolyte drink. You've been dehydrating without noticing.": (
        "喝水或电解质饮料。您一直在脱水却没有察觉。",
        "喝水或電解質飲料。您一直在脫水卻沒有察覺。",
    ),
    "Magnesium can help with jaw tension and muscle tightness.": (
        "镁有助于缓解下颌紧绷和肌肉僵硬。",
        "鎂有助於緩解下顎緊繃和肌肉僵硬。",
    ),
    "Vitamin C may support your body's recovery.": (
        "维生素 C 可能有助于身体恢复。",
        "維生素 C 可能有助於身體恢復。",
    ),
    "Don't fight the fatigue — lie down even if sleep doesn't come immediately.": (
        "不要对抗疲劳 — 即使一时无法入睡也躺下休息。",
        "不要對抗疲勞 — 即使一時無法入睡也躺下休息。",
    ),
    "Dark room, comfortable temperature, no screens.": (
        "昏暗的房间、舒适的温度、远离屏幕。",
        "昏暗的房間、舒適的溫度、遠離螢幕。",
    ),
    "A warm shower or light stretching helps your muscles release.": (
        "温水淋浴或轻度拉伸有助于肌肉放松。",
        "溫水淋浴或輕度拉伸有助於肌肉放鬆。",
    ),
    "The low mood is chemical, not a reflection of reality. It lifts.": (
        "情绪低落源于化学变化,并非现实的反映。它会过去。",
        "情緒低落源於化學變化,並非現實的反映。它會過去。",
    ),
    "Don't redose to escape the crash — it only delays and worsens recovery.": (
        "不要为了逃避崩溃而再次服用 — 这只会延迟并加重恢复。",
        "不要為了逃避崩潰而再次服用 — 這只會延遲並加重恢復。",
    ),
    "Skip the caffeine — your cardiovascular system has worked hard enough.": (
        "不要喝咖啡因 — 您的心血管系统已经够累了。",
        "不要喝咖啡因 — 您的心血管系統已經夠累了。",
    ),
    "Don't make important decisions or send emotionally charged messages right now.": (
        "现在不要做重要决定或发送情绪化的信息。",
        "現在不要做重要決定或發送情緒化的訊息。",
    ),
    "Avoid alcohol — it worsens dehydration and disrupts the sleep you need.": (
        "避免酒精 — 它会加重脱水并打乱您所需的睡眠。",
        "避免酒精 — 它會加重脫水並打亂您所需的睡眠。",
    ),
    # Comedown guide — Empathogen
    "Your serotonin reserves are depleted — that's why everything feels flat or low.": (
        "您的血清素储备已耗尽 — 这就是为什么一切感觉平淡或低落。",
        "您的血清素儲備已耗盡 — 這就是為什麼一切感覺平淡或低落。",
    ),
    "This is temporary. Your brain will replenish over the next few days.": (
        "这是暂时的。接下来几天您的大脑会补充。",
        "這是暫時的。接下來幾天您的大腦會補充。",
    ),
    "Some emotional sensitivity and physical fatigue is completely normal.": (
        "一些情绪敏感和身体疲劳完全正常。",
        "一些情緒敏感和身體疲勞完全正常。",
    ),
    "Stay warm — your body's temperature regulation is still off.": (
        "保暖 — 您的体温调节仍未恢复。",
        "保暖 — 您的體溫調節仍未恢復。",
    ),
    "Sip water steadily, but don't overdo it. A glass every 30-60 minutes is fine.": (
        "稳定地小口喝水,但不要过量。每 30 至 60 分钟一杯即可。",
        "穩定地小口喝水,但不要過量。每 30 至 60 分鐘一杯即可。",
    ),
    "Eat light foods: fruit, toast, soup. Your stomach may be sensitive.": (
        "吃清淡食物:水果、吐司、汤。您的胃可能比较敏感。",
        "吃清淡食物:水果、吐司、湯。您的胃可能比較敏感。",
    ),
    "If your jaw is sore, gentle massage and magnesium help.": (
        "如果下颌酸痛,轻柔按摩和镁有帮助。",
        "如果下顎痠痛,輕柔按摩和鎂有幫助。",
    ),
    "Rest in a comfortable, calm space. Soft music or silence both work.": (
        "在舒适、平静的空间里休息。柔和的音乐或安静都可以。",
        "在舒適、平靜的空間裡休息。柔和的音樂或安靜都可以。",
    ),
    "Be patient with yourself for the next 1-3 days. Low mood is the serotonin dip.": (
        "接下来 1 至 3 天对自己耐心点。情绪低落是血清素下降。",
        "接下來 1 至 3 天對自己耐心點。情緒低落是血清素下降。",
    ),
    "Gentle walks in nature can genuinely help when you're ready.": (
        "准备好时,在大自然中轻轻散步真的有帮助。",
        "準備好時,在大自然中輕輕散步真的有幫助。",
    ),
    "Talk to someone you trust — connection helps more than isolation.": (
        "和您信任的人聊聊 — 联结比孤立更有帮助。",
        "和您信任的人聊聊 — 聯結比孤立更有幫助。",
    ),
    "Don't redose — the magic is in spacing. Frequent use causes lasting harm.": (
        "不要再次服用 — 关键在于间隔。频繁使用会造成持久伤害。",
        "不要再次服用 — 關鍵在於間隔。頻繁使用會造成持久傷害。",
    ),
    "Avoid 5-HTP supplements for at least 24 hours after your last dose.": (
        "最后一次服用后至少 24 小时内避免 5-HTP 补充剂。",
        "最後一次服用後至少 24 小時內避免 5-HTP 補充劑。",
    ),
    "Skip intense social situations — you may feel emotionally raw.": (
        "避免激烈的社交场合 — 您可能情绪敏感。",
        "避免激烈的社交場合 — 您可能情緒敏感。",
    ),
    "Don't judge your baseline mood by how you feel right now.": (
        "不要以现在的感受来判断您的基线情绪。",
        "不要以現在的感受來判斷您的基線情緒。",
    ),
    # Comedown guide — Psychedelic
    "Your serotonin receptors are returning to their normal sensitivity.": (
        "您的血清素受体正恢复到正常敏感度。",
        "您的血清素受體正恢復到正常敏感度。",
    ),
    "You may feel emotionally open, contemplative, or just tired.": (
        "您可能感到情感开放、深思,或只是疲倦。",
        "您可能感到情感開放、深思,或只是疲倦。",
    ),
    "Some residual visual or thought patterns can linger — this is normal and fades.": (
        "一些视觉或思维残余可能会持续 — 这是正常的,会消退。",
        "一些視覺或思維殘餘可能會持續 — 這是正常的,會消退。",
    ),
    "You're safe. If the experience was intense, remind yourself: it's temporary.": (
        "您是安全的。如果体验很强烈,请提醒自己:这是暂时的。",
        "您是安全的。如果體驗很強烈,請提醒自己:這是暫時的。",
    ),
    "Eat something grounding — warm food, fruit, or anything that sounds appealing.": (
        "吃些让人安定的东西 — 温热的食物、水果或任何想吃的。",
        "吃些讓人安定的東西 — 溫熱的食物、水果或任何想吃的。",
    ),
    "Drink water. Wrap up in something comfortable.": (
        "喝水。裹上舒适的衣物。",
        "喝水。裹上舒適的衣物。",
    ),
    "Write down anything meaningful before the details fade.": (
        "在细节消失前记下任何有意义的内容。",
        "在細節消失前記下任何有意義的內容。",
    ),
    "Rest. Sleep often comes easily once the peak is past.": (
        "休息。一旦巅峰过去,睡眠通常会比较容易。",
        "休息。一旦巔峰過去,睡眠通常會比較容易。",
    ),
    "Don't try to 'figure it all out' right now. Integration takes days, not hours.": (
        "现在不要试图「想通一切」。整合需要数天,而不是数小时。",
        "現在不要試圖「想通一切」。整合需要數天,而不是數小時。",
    ),
    "Nature, art, or quiet music can help you process gently.": (
        "大自然、艺术或宁静的音乐能温柔地帮助您消化。",
        "大自然、藝術或寧靜的音樂能溫柔地幫助您消化。",
    ),
    "Be easy with yourself — profound experiences need time to settle.": (
        "善待自己 — 深刻的体验需要时间沉淀。",
        "善待自己 — 深刻的體驗需要時間沉澱。",
    ),
    "Don't make big life decisions based on acute revelations — wait a week.": (
        "不要根据急性顿悟做出重大人生决定 — 等一周再说。",
        "不要根據急性頓悟做出重大人生決定 — 等一週再說。",
    ),
    "Avoid screens and doom-scrolling. Your mind is still very impressionable.": (
        "避免使用屏幕和无止境滑动。您的心智仍非常易受影响。",
        "避免使用螢幕和無止境滑動。您的心智仍非常易受影響。",
    ),
    "Don't smoke cannabis unless you know how it interacts with your afterglow.": (
        "不要吸食大麻,除非您了解它与余韵的相互作用。",
        "不要吸食大麻,除非您了解它與餘韻的相互作用。",
    ),
    "Skip intense or crowded environments until you feel grounded.": (
        "在感到稳定前,避开激烈或拥挤的环境。",
        "在感到穩定前,避開激烈或擁擠的環境。",
    ),
    # Comedown guide — Dissociative
    "Your NMDA receptors are returning to baseline, which can feel foggy or unreal.": (
        "您的 NMDA 受体正恢复到基线,可能感觉迷糊或不真实。",
        "您的 NMDA 受體正恢復到基線,可能感覺迷糊或不真實。",
    ),
    "Motor coordination and spatial awareness may still be impaired.": (
        "运动协调和空间感知能力可能仍受影响。",
        "運動協調和空間感知能力可能仍受影響。",
    ),
    "Some dissociative afterglow is common — the world may feel slightly 'off' for a while.": (
        "一些解离性余韵很常见 — 世界可能在一段时间内感觉略有「不对」。",
        "一些解離性餘韻很常見 — 世界可能在一段時間內感覺略有「不對」。",
    ),
    "Stay seated or lying down. Your balance may not be what you think it is.": (
        "保持坐姿或躺下。您的平衡感可能不如您以为的好。",
        "保持坐姿或躺下。您的平衡感可能不如您以為的好。",
    ),
    "Drink water. Eat something simple when your stomach allows.": (
        "喝水。胃部允许时吃些简单的食物。",
        "喝水。胃部允許時吃些簡單的食物。",
    ),
    "Stay somewhere safe with someone you trust if possible.": (
        "如果可能,留在安全的地方,有您信任的人在身边。",
        "如果可能,留在安全的地方,有您信任的人在身邊。",
    ),
    "Avoid stairs, sharp objects, and anything requiring fine motor skills.": (
        "避免楼梯、尖锐物体和任何需要精细动作的事。",
        "避免樓梯、尖銳物體和任何需要精細動作的事。",
    ),
    "Sleep when you can — your brain recovers fastest during rest.": (
        "能睡就睡 — 大脑在休息时恢复最快。",
        "能睡就睡 — 大腦在休息時恢復最快。",
    ),
    "The foggy feeling will clear. Give it hours, not minutes.": (
        "迷糊感会消散。需要数小时,而非数分钟。",
        "迷糊感會消散。需要數小時,而非數分鐘。",
    ),
    "Gentle sensory input (music, soft textures) can help you reconnect.": (
        "温和的感官输入(音乐、柔软质感)有助于重新连结。",
        "溫和的感官輸入(音樂、柔軟質感)有助於重新連結。",
    ),
    "Don't worry if things feel 'weird' — your perception is still recalibrating.": (
        "如果觉得「奇怪」不必担心 — 您的感知仍在重新校准。",
        "如果覺得「奇怪」不必擔心 — 您的感知仍在重新校準。",
    ),
    "Absolutely do not drive or operate machinery.": (
        "绝对不要驾驶或操作机器。",
        "絕對不要駕駛或操作機器。",
    ),
    "Don't mix with depressants (alcohol, benzos, opioids) — respiratory depression risk.": (
        "不要与抑制剂(酒精、苯二氮䓬、阿片)混用 — 有呼吸抑制风险。",
        "不要與抑制劑(酒精、苯二氮䓬、阿片)混用 — 有呼吸抑制風險。",
    ),
    "Avoid hot baths/showers alone — you may not feel temperature accurately.": (
        "避免独自洗热水澡 — 您可能无法准确感知温度。",
        "避免獨自洗熱水澡 — 您可能無法準確感知溫度。",
    ),
    "Don't redose while still dissociated — you can't gauge your level clearly.": (
        "仍在解离时不要再次服用 — 您无法清楚判断自己的状态。",
        "仍在解離時不要再次服用 — 您無法清楚判斷自己的狀態。",
    ),
    # Comedown guide — Opioid
    "Your endorphin system was temporarily overridden. As the drug fades, sensitivity returns.": (
        "您的内啡肽系统暂时被覆盖。药物消退后,敏感度会回归。",
        "您的內啡肽系統暫時被覆蓋。藥物消退後,敏感度會回歸。",
    ),
    "You may feel increased pain sensitivity, restlessness, or mild nausea.": (
        "您可能感到痛觉增强、焦躁或轻度恶心。",
        "您可能感到痛覺增強、焦躁或輕度噁心。",
    ),
    "These effects are proportional to how much and how often you've been using.": (
        "这些影响与您使用的剂量和频率成正比。",
        "這些影響與您使用的劑量和頻率成正比。",
    ),
    "Stay hydrated — opioids are dehydrating and constipating.": (
        "保持水分 — 阿片类会导致脱水和便秘。",
        "保持水分 — 阿片類會導致脫水和便秘。",
    ),
    "Eat something light. Your appetite may be suppressed but food helps.": (
        "吃些清淡的东西。食欲可能受抑制,但食物有帮助。",
        "吃些清淡的東西。食慾可能受抑制,但食物有幫助。",
    ),
    "If you feel nauseous, lie on your side and sip ginger tea or plain water.": (
        "感到恶心时,侧卧并小口喝姜茶或清水。",
        "感到噁心時,側臥並小口喝薑茶或清水。",
    ),
    "Fresh air can help with the foggy, closed-in feeling.": (
        "新鲜空气有助于缓解迷糊和压抑感。",
        "新鮮空氣有助於緩解迷糊和壓抑感。",
    ),
    "Light movement helps — even a short walk speeds recovery.": (
        "轻度活动有帮助 — 即使短暂散步也能加速恢复。",
        "輕度活動有幫助 — 即使短暫散步也能加速恢復。",
    ),
    "A warm bath can ease the achy, restless feeling.": (
        "温水浴可以缓解酸痛和不安感。",
        "溫水浴可以緩解痠痛和不安感。",
    ),
    "Sleep if you can. Your body does its best recovery work unconscious.": (
        "能睡就睡。身体在无意识时做最好的恢复工作。",
        "能睡就睡。身體在無意識時做最好的恢復工作。",
    ),
    "If withdrawal symptoms concern you, seek medical advice. Help exists.": (
        "如果担心戒断症状,请寻求医疗建议。帮助是存在的。",
        "如果擔心戒斷症狀,請尋求醫療建議。幫助是存在的。",
    ),
    "Don't redose to chase the feeling — tolerance builds fast and that path is dangerous.": (
        "不要为了追求感觉而再次服用 — 耐受性会快速建立,这条路很危险。",
        "不要為了追求感覺而再次服用 — 耐受性會快速建立,這條路很危險。",
    ),
    "Never mix with alcohol, benzos, or other depressants.": (
        "绝不要与酒精、苯二氮䓬或其他抑制剂混用。",
        "絕不要與酒精、苯二氮䓬或其他抑制劑混用。",
    ),
    "Don't isolate yourself. Let someone know where you are.": (
        "不要独自一人。让某人知道您在哪里。",
        "不要獨自一人。讓某人知道您在哪裡。",
    ),
    "Avoid driving — reaction time and judgment may still be affected.": (
        "避免驾驶 — 反应时间和判断力可能仍受影响。",
        "避免駕駛 — 反應時間和判斷力可能仍受影響。",
    ),
    # Comedown guide — Benzodiazepine
    "Your GABA receptors are readjusting — anxiety or restlessness may temporarily increase.": (
        "您的 GABA 受体正在重新调整 — 焦虑或不安可能暂时加剧。",
        "您的 GABA 受體正在重新調整 — 焦慮或不安可能暫時加劇。",
    ),
    "This is a rebound effect, not a return to baseline anxiety. It passes.": (
        "这是反弹效应,而非回到基线焦虑。它会过去。",
        "這是反彈效應,而非回到基線焦慮。它會過去。",
    ),
    "If you've been using regularly, talk to a doctor about tapering — never stop abruptly.": (
        "如果您一直规律使用,请咨询医生关于逐渐减量 — 切勿突然停药。",
        "如果您一直規律使用,請諮詢醫生關於逐漸減量 — 切勿突然停藥。",
    ),
    "Stay somewhere calm and safe. The rebound anxiety is temporary.": (
        "留在平静、安全的地方。反弹性焦虑是暂时的。",
        "留在平靜、安全的地方。反彈性焦慮是暫時的。",
    ),
    "Drink water and eat something — stable blood sugar helps mood.": (
        "喝水并吃点东西 — 稳定的血糖有助于情绪。",
        "喝水並吃點東西 — 穩定的血糖有助於情緒。",
    ),
    "Breathing exercises: 4 seconds in, 7 seconds hold, 8 seconds out.": (
        "呼吸练习:吸气 4 秒、屏住 7 秒、呼气 8 秒。",
        "呼吸練習:吸氣 4 秒、屏住 7 秒、呼氣 8 秒。",
    ),
    "Avoid caffeine — it amplifies the rebound anxiety.": (
        "避免咖啡因 — 它会放大反弹性焦虑。",
        "避免咖啡因 — 它會放大反彈性焦慮。",
    ),
    "Sleep may be disrupted tonight — melatonin or chamomile tea can help.": (
        "今晚睡眠可能受打扰 — 褪黑素或甘菊茶有帮助。",
        "今晚睡眠可能受打擾 — 褪黑素或甘菊茶有幫助。",
    ),
    "Light activity like walking helps burn off anxious energy.": (
        "散步等轻度活动有助于消耗焦虑的能量。",
        "散步等輕度活動有助於消耗焦慮的能量。",
    ),
    "The discomfort peaks and then fades. Give it time.": (
        "不适会达到顶峰然后消退。给它时间。",
        "不適會達到頂峰然後消退。給它時間。",
    ),
    "If this is frequent for you, consider talking to a professional about alternatives.": (
        "如果这对您很频繁,请考虑与专业人士讨论替代方案。",
        "如果這對您很頻繁,請考慮與專業人士討論替代方案。",
    ),
    "Don't redose reactively — it reinforces the cycle.": (
        "不要反射性地再次服用 — 这会强化循环。",
        "不要反射性地再次服用 — 這會強化循環。",
    ),
    "Avoid alcohol completely — it acts on the same receptors.": (
        "完全避免酒精 — 它作用于相同的受体。",
        "完全避免酒精 — 它作用於相同的受體。",
    ),
    "Don't make this worse by doom-scrolling health anxiety forums.": (
        "不要通过滑动健康焦虑论坛让情况恶化。",
        "不要透過滑動健康焦慮論壇讓情況惡化。",
    ),
    "Never abruptly stop after regular use — benzo withdrawal can be medically serious.": (
        "规律使用后切勿突然停药 — 苯二氮䓬戒断可能在医学上非常严重。",
        "規律使用後切勿突然停藥 — 苯二氮䓬戒斷可能在醫學上非常嚴重。",
    ),
    # Comedown guide — Depressant
    "Your central nervous system was being suppressed and is now rebounding.": (
        "您的中枢神经系统之前被抑制,现在正反弹。",
        "您的中樞神經系統之前被抑制,現在正反彈。",
    ),
    "You may feel shaky, anxious, or nauseous as your body recalibrates.": (
        "身体重新校准时,您可能感到颤抖、焦虑或恶心。",
        "身體重新校準時,您可能感到顫抖、焦慮或噁心。",
    ),
    "Headaches and fatigue are common — this is your body processing the substance.": (
        "头痛和疲劳很常见 — 这是您的身体在处理物质。",
        "頭痛和疲勞很常見 — 這是您的身體在處理物質。",
    ),
    "Drink water — depressants are dehydrating, especially alcohol.": (
        "喝水 — 抑制剂会导致脱水,特别是酒精。",
        "喝水 — 抑制劑會導致脫水,特別是酒精。",
    ),
    "Eat something with salt, protein, and carbs. Your body needs fuel to recover.": (
        "吃些含盐、蛋白质和碳水的食物。您的身体需要燃料恢复。",
        "吃些含鹽、蛋白質和碳水的食物。您的身體需要燃料恢復。",
    ),
    "If nauseous, small sips of water and lying on your side help.": (
        "感到恶心时,小口喝水并侧卧有帮助。",
        "感到噁心時,小口喝水並側臥有幫助。",
    ),
    "An electrolyte drink is better than plain water if available.": (
        "如果有,电解质饮料比清水更好。",
        "如果有,電解質飲料比清水更好。",
    ),
    "Sleep it off if you can — your body needs rest to metabolize and recover.": (
        "能睡就睡过去 — 您的身体需要休息来代谢和恢复。",
        "能睡就睡過去 — 您的身體需要休息來代謝和恢復。",
    ),
    "A cool, dark room helps with headaches and overstimulation.": (
        "凉爽、昏暗的房间有助于缓解头痛和过度刺激。",
        "涼爽、昏暗的房間有助於緩解頭痛和過度刺激。",
    ),
    "Light food every few hours, even if you don't feel hungry.": (
        "每隔几小时吃些清淡的食物,即使不饿。",
        "每隔幾小時吃些清淡的食物,即使不餓。",
    ),
    "Fresh air and gentle movement when you're ready.": (
        "准备好时呼吸新鲜空气并轻度活动。",
        "準備好時呼吸新鮮空氣並輕度活動。",
    ),
    "Don't 'hair of the dog' — more depressant just delays recovery.": (
        "不要「以毒攻毒」 — 更多抑制剂只会延迟恢复。",
        "不要「以毒攻毒」 — 更多抑制劑只會延遲恢復。",
    ),
    "Avoid painkillers that stress the liver (acetaminophen) after heavy alcohol use.": (
        "大量饮酒后避免使用对肝脏有压力的止痛药(对乙酰氨基酚)。",
        "大量飲酒後避免使用對肝臟有壓力的止痛藥(對乙醯氨基酚)。",
    ),
    "Don't drive or make important decisions until fully sober.": (
        "完全清醒前不要驾驶或做重要决定。",
        "完全清醒前不要駕駛或做重要決定。",
    ),
    "Avoid greasy, heavy food — it sounds good but often makes nausea worse.": (
        "避免油腻的重食 — 听起来不错,但常使恶心加剧。",
        "避免油膩的重食 — 聽起來不錯,但常使噁心加劇。",
    ),
    # Comedown guide — Cannabinoid
    "Your endocannabinoid system is returning to baseline.": (
        "您的内源性大麻素系统正回到基线。",
        "您的內源性大麻素系統正回到基線。",
    ),
    "You may feel foggy, lethargic, or mildly irritable.": (
        "您可能感到迷糊、嗜睡或轻微易怒。",
        "您可能感到迷糊、嗜睡或輕微易怒。",
    ),
    "Appetite changes and sleep disruption are common after heavy sessions.": (
        "大量使用后,食欲变化和睡眠紊乱很常见。",
        "大量使用後,食慾變化和睡眠紊亂很常見。",
    ),
    "Drink water — cotton mouth means you've been dehydrating.": (
        "喝水 — 口干意味着您在脱水。",
        "喝水 — 口乾意味著您在脫水。",
    ),
    "Eat something balanced. The munchies may have had you eating junk.": (
        "吃些均衡的食物。嘴馋可能让您吃了垃圾食品。",
        "吃些均衡的食物。嘴饞可能讓您吃了垃圾食品。",
    ),
    "If you feel anxious, focus on slow breathing. It passes.": (
        "如果感到焦虑,专注于慢呼吸。它会过去。",
        "如果感到焦慮,專注於慢呼吸。它會過去。",
    ),
    "A change of scenery — even moving to a different room — can shift your headspace.": (
        "换个环境 — 即使只是换到另一个房间 — 可以改变心境。",
        "換個環境 — 即使只是換到另一個房間 — 可以改變心境。",
    ),
    "Physical activity helps clear the fog faster than anything.": (
        "身体活动是清除迷糊感最快的方法。",
        "身體活動是清除迷糊感最快的方法。",
    ),
    "Caffeine in moderation can help with grogginess.": (
        "适量咖啡因有助于缓解昏沉。",
        "適量咖啡因有助於緩解昏沉。",
    ),
    "Sleep quality may be off tonight — melatonin can help.": (
        "今晚睡眠质量可能欠佳 — 褪黑素有帮助。",
        "今晚睡眠品質可能欠佳 — 褪黑素有幫助。",
    ),
    "If you feel spacey, grounding exercises: name 5 things you can see, 4 you can touch.": (
        "如果感觉飘忽,做接地练习:说出 5 件您能看见的、4 件能触摸的。",
        "如果感覺飄忽,做接地練習:說出 5 件您能看見的、4 件能觸摸的。",
    ),
    "Don't drive until the fog fully clears — it takes longer than you think.": (
        "迷糊感完全消失前不要驾驶 — 比您想的要久。",
        "迷糊感完全消失前不要駕駛 — 比您想的要久。",
    ),
    "Avoid more cannabis to 'take the edge off' the comedown.": (
        "不要用更多大麻来「缓解」缓和期。",
        "不要用更多大麻來「緩解」緩和期。",
    ),
    "Don't panic about short-term memory gaps — they resolve with sobriety.": (
        "不要因短期记忆空白而恐慌 — 它们会随清醒恢复。",
        "不要因短期記憶空白而恐慌 — 它們會隨清醒恢復。",
    ),
    "Skip intense social obligations if you're not feeling up to it.": (
        "如果状态不佳,跳过繁重的社交义务。",
        "如果狀態不佳,跳過繁重的社交義務。",
    ),
    # Comedown guide — Default (other)
    "Your body is processing and eliminating the substance.": (
        "您的身体正在处理并排出该物质。",
        "您的身體正在處理並排出該物質。",
    ),
    "How you feel depends on what you took, how much, and your body's chemistry.": (
        "感觉如何取决于您服用了什么、多少,以及您的身体化学。",
        "感覺如何取決於您服用了什麼、多少,以及您的身體化學。",
    ),
    "Drink water and eat something nutritious.": ("喝水并吃些营养食物。", "喝水並吃些營養食物。"),
    "Rest in a comfortable, safe environment.": (
        "在舒适、安全的环境中休息。",
        "在舒適、安全的環境中休息。",
    ),
    "If you feel unwell, don't hesitate to call for help.": (
        "如感到不适,请毫不犹豫地寻求帮助。",
        "如感到不適,請毫不猶豫地尋求幫助。",
    ),
    "Sleep is your best recovery tool.": ("睡眠是您最好的恢复工具。", "睡眠是您最好的恢復工具。"),
    "Light food and fluids every few hours.": (
        "每隔几小时摄入清淡食物和水分。",
        "每隔幾小時攝入清淡食物和水分。",
    ),
    "Give yourself time. Most effects are temporary.": (
        "给自己时间。大部分影响都是暂时的。",
        "給自己時間。大部分影響都是暫時的。",
    ),
    "Don't redose without careful consideration.": (
        "未经仔细考虑前不要再次服用。",
        "未經仔細考慮前不要再次服用。",
    ),
    "Avoid mixing substances.": ("避免混用物质。", "避免混用物質。"),
    "Don't drive or make important decisions until you feel baseline.": (
        "感觉回到基线前不要驾驶或做重要决定。",
        "感覺回到基線前不要駕駛或做重要決定。",
    ),
    "Full recovery guide": ("完整恢复指南", "完整恢復指南"),
    "View Full Recovery Guide": ("查看完整恢复指南", "查看完整恢復指南"),
    "Get care reminders as effects fade — hydration, rest, and recovery tips.": (
        "效果消退时获得护理提醒 — 补水、休息和恢复提示。",
        "效果消退時獲得護理提醒 — 補水、休息和恢復提示。",
    ),
    "You'll get care reminders as the effects begin to fade — hydration, nutrition, and recovery tips.": (
        "效果开始消退时,您会收到护理提醒 — 补水、营养和恢复提示。",
        "效果開始消退時,您會收到護理提醒 — 補水、營養和恢復提示。",
    ),
    "Piru will notify you as the comedown approaches with practical care reminders — hydration, nutrition, and rest tips tailored to what you took.": (
        "缓和期来临时,Piru 会以实用的护理提醒通知您 — 根据您所服用的物质,提供补水、营养和休息建议。",
        "緩和期來臨時,Piru 會以實用的護理提醒通知您 — 根據您所服用的物質,提供補水、營養和休息建議。",
    ),
    "Currently In Your System": ("目前体内活跃", "目前體內活躍"),
    "In Your System": ("体内活跃", "體內活躍"),
    "Showing guidance for substances in your system. Tap above for the full guide.": (
        "正在显示您体内物质的指导。点击上方查看完整指南。",
        "正在顯示您體內物質的指導。點擊上方查看完整指南。",
    ),
    "Practical tips for taking care of yourself as substances wear off. Every category is different — tap one below for specific guidance.": (
        "物质消退时照顾自己的实用建议。每个类别都不同 — 点击下方任意一项查看具体指导。",
        "物質消退時照顧自己的實用建議。每個類別都不同 — 點擊下方任意一項查看具體指導。",
    ),
    # Reports
    "Generate Medical Report": ("生成医疗报告", "產生醫療報告"),
    "Generate PDF Report": ("生成 PDF 报告", "產生 PDF 報告"),
    "Medical Report": ("医疗报告", "醫療報告"),
    "Patient Name (Optional)": ("患者姓名(可选)", "患者姓名(可選)"),
    "Name (for the report header)": ("姓名(用于报告标题)", "姓名(用於報告標題)"),
    "Add notes for your doctor...": ("为您的医生添加备注…", "為您的醫生新增備註…"),
    "These notes will appear at the end of the PDF report.": (
        "这些备注将出现在 PDF 报告末尾。",
        "這些備註將出現在 PDF 報告末尾。",
    ),
    "Report Includes": ("报告包含", "報告包含"),
    "Data sourced from peer-reviewed literature, FDA labels, and established pharmacological databases. Always consult a healthcare professional.": (
        "数据来源于同行评审文献、FDA 标签和成熟的药理学数据库。请始终咨询医疗专业人员。",
        "資料來源於同行評審文獻、FDA 標籤和成熟的藥理學資料庫。請始終諮詢醫療專業人員。",
    ),
    # About / Sources
    "Pharmacological data in this app is compiled from the sources listed above. Dosage ranges, half-lives, duration profiles, mechanisms of action, and interaction data are sourced from peer-reviewed literature, FDA-approved labeling, and established pharmacological databases. Mechanism of action descriptions are based on human pharmacological research only. This information is provided for harm reduction and educational purposes only. Always consult a qualified healthcare professional before making any decisions about substance use.": (
        "此应用中的药理数据汇编自上述来源。剂量范围、半衰期、持续时间、作用机制及相互作用数据来源于同行评审文献、FDA 批准的标签和成熟的药理学数据库。作用机制描述仅基于人类药理学研究。此信息仅用于减害和教育目的。在做出任何关于物质使用的决定前,请始终咨询合格的医疗专业人员。",
        "此應用中的藥理資料彙編自上述來源。劑量範圍、半衰期、持續時間、作用機制及相互作用資料來源於同行評審文獻、FDA 批准的標籤和成熟的藥理學資料庫。作用機制描述僅基於人類藥理學研究。此資訊僅用於減害和教育目的。在做出任何關於物質使用的決定前,請始終諮詢合格的醫療專業人員。",
    ),
    # Onboarding-style sub-text in Settings
    "Show a Live Activity on the Lock Screen and Dynamic Island when tracking active substances.": (
        "追踪活跃物质时在锁定屏幕和灵动岛上显示实时活动。",
        "追蹤活躍物質時在鎖定畫面和動態島上顯示即時動態。",
    ),
    "Wellness reminders send hydration and sleep nudges automatically. Phase notifications alert you at onset, come-up, and peak — requires a substance with duration data.": (
        "健康提醒会自动发送补水和睡眠提示。阶段通知会在起效、上升期和巅峰时提醒您 — 需要物质具备时长数据。",
        "健康提醒會自動發送補水和睡眠提示。階段通知會在起效、上升期和巔峰時提醒您 — 需要物質具備時長資料。",
    ),
    "Combine repeat doses of the same substance into a single curve, where each redose adds to the combined intensity. When off, each dose is drawn as its own line.": (
        "将同一物质的重复剂量合并为单条曲线,每次重复剂量都会加到综合强度中。关闭时,每个剂量都会作为独立线条绘制。",
        "將同一物質的重複劑量合併為單條曲線,每次重複劑量都會加到綜合強度中。關閉時,每個劑量都會作為獨立線條繪製。",
    ),
    "Doses logged before this hour are grouped with the previous day's session — so a 02:00 dose joins the night before instead of starting a new day at midnight. Set to 12 AM for classic calendar-day grouping.": (
        "在此小时之前记录的剂量会与前一天的会话分到一组 — 例如 02:00 的剂量会归入前一晚,而不是从午夜开始新的一天。设为凌晨 12 点即为传统日历日分组。",
        "在此小時之前記錄的劑量會與前一天的工作階段分到一組 — 例如 02:00 的劑量會歸入前一晚,而不是從午夜開始新的一天。設為凌晨 12 點即為傳統日曆日分組。",
    ),
    "Organize prescriptions by time of day or purpose. Drag items onto a category to assign them.": (
        "按时段或用途整理处方。将项目拖到某个类别上即可分配。",
        "按時段或用途整理處方。將項目拖到某個類別上即可分配。",
    ),
    # Form fields / Pickers
    "Select at least one day.": ("请至少选择一天。", "請至少選擇一天。"),
    "Checked every day.": ("每天检查。", "每天檢查。"),
    "Checked every 2 days starting from the start date.": (
        "从开始日期起每 2 天检查一次。",
        "從開始日期起每 2 天檢查一次。",
    ),
    "Checked once per week on the same day as the start date.": (
        "每周与开始日期同一日检查一次。",
        "每週與開始日期同一日檢查一次。",
    ),
    "Checked every 2 weeks on the same day as the start date.": (
        "每两周与开始日期同一日检查。",
        "每兩週與開始日期同一日檢查。",
    ),
    "Checked once per month on the same day-of-month as the start date.": (
        "每月与开始日期同一日(每月几日)检查一次。",
        "每月與開始日期同一日(每月幾日)檢查一次。",
    ),
    "Checked every %@.": ("每 %@ 检查一次。", "每 %@ 檢查一次。"),
    # Cumulative
    "Cumulative Doses": ("累积剂量", "累積劑量"),
    "Heads up — %@%@ %@ today": ("提醒 — 今日 %@%@ %@", "提醒 — 今日 %@%@ %@"),
    "That's a high cumulative dose. %@": ("这是较高的累积剂量。%@", "這是較高的累積劑量。%@"),
    # Tags
    "Add tag...": ("添加标签…", "新增標籤…"),
    "#%@": ("#%@", "#%@"),
    # Insights stats
    "Activity": ("活动", "活動"),
    "Usage Entries": ("使用记录", "使用記錄"),
    "Dose Trends": ("剂量趋势", "劑量趨勢"),
    "Daily average per week": ("每周日均", "每週日均"),
    "Most common: %@ %@": ("最常见:%@ %@", "最常見:%@ %@"),
    "Milestones": ("里程碑", "里程碑"),
    "day streak": ("天连续", "天連續"),
    "days streak": ("天连续", "天連續"),
    "this month": ("本月", "本月"),
    # Frequency-related
    "%lld daily reminder%@ scheduled.": (
        "已安排 %1$lld 个每日提醒。",
        "已排程 %1$lld 個每日提醒。",
    ),
    "%lld prescription%@": ("%1$lld 个处方", "%1$lld 個處方"),
    "Uncategorized — %lld prescription%@": ("未分类 — %1$lld 个处方", "未分類 — %1$lld 個處方"),
    # Distance / time formatted
    "%@ in · %@ left": ("%@ 后 · 剩 %@", "%@ 後 · 剩 %@"),
    "%@ %@ left": ("剩 %@ %@", "剩 %@ %@"),
    "%@ %@ remaining after %@": ("%@ 后剩 %@ %@", "%@ 後剩 %@ %@"),
    "%@ %@ total · est. ~%lld%% remaining": (
        "总计 %@ %@ · 预计剩约 %lld%%",
        "總計 %@ %@ · 預計剩約 %lld%%",
    ),
    "Consider waiting ~%@ more": ("建议再等待约 %@", "建議再等待約 %@"),
    "~%lld%% of your last dose (%@%@, %@) is still active": (
        "上次剂量(%2$@%3$@,%4$@)仍有约 %1$lld%% 活跃",
        "上次劑量(%2$@%3$@,%4$@)仍有約 %1$lld%% 活躍",
    ),
    # Adherence
    "Taken %@": ("已服用 %@", "已服用 %@"),
    "Missed %@ of %@": ("漏服 %@ 的 %@", "漏服 %@ 的 %@"),
    "%lld/%lld taken": ("%lld/%lld 已服用", "%lld/%lld 已服用"),
    # Day detail
    "Dose taken": ("已服用剂量", "已服用劑量"),
    "Other dose": ("其他剂量", "其他劑量"),
    # Format strings
    "Add (%lld)": ("添加(%lld)", "新增(%lld)"),
    "Log %lld Item%@": ("记录 %1$lld 个项目", "記錄 %1$lld 個項目"),
    "Log %@": ("记录 %@", "記錄 %@"),
    "Dosage — %@": ("剂量 — %@", "劑量 — %@"),
    "Duration — %@": ("持续时间 — %@", "持續時間 — %@"),
    "No entries for %@": ("无 %@ 的记录", "無 %@ 的記錄"),
    "No data for %@": ("无 %@ 的数据", "無 %@ 的資料"),
    "Add to %@": ("添加到 %@", "新增到 %@"),
    'Create "%@"': ('创建 "%@"', '建立 "%@"'),
    'Use "%@"': ('使用 "%@"', '使用 "%@"'),
    'A custom substance named "%@" already exists.': (
        '已存在名为 "%@" 的自定义物质。',
        '已存在名為 "%@" 的自訂物質。',
    ),
    'No substances match "%@"': ('没有匹配 "%@" 的物质', '沒有符合 "%@" 的物質'),
    "%@ — %lld prescription%@": ("%1$@ — %2$lld 个处方", "%1$@ — %2$lld 個處方"),
    # Substance entries summary
    "%lld entr%@": ("%1$lld 条记录", "%1$lld 條記錄"),
    "%lld entries across %lld substances": (
        "%lld 条记录,涉及 %lld 种物质",
        "%lld 條記錄,涉及 %lld 種物質",
    ),
    "%lld substance%@": ("%1$lld 种物质", "%1$lld 種物質"),
    "%lld results": ("%lld 个结果", "%lld 個結果"),
    "%lld loaded so far": ("已加载 %lld 个", "已載入 %lld 個"),
    "%lld%%": ("%lld%%", "%lld%%"),
    "%lld · %lld%%": ("%lld · %lld%%", "%lld · %lld%%"),
    "%lld-%@ avg": ("%lld-%@ 平均", "%lld-%@ 平均"),
    "(%lld%%)": ("(%lld%%)", "(%lld%%)"),
    "(%lldx)": ("(%lldx)", "(%lldx)"),
    "(%@)": ("(%@)", "(%@)"),
    "%lldh": ("%lld 小时", "%lld 小時"),
    "%lld": ("%lld", "%lld"),
    "+%lld": ("+%lld", "+%lld"),
    # Single chars / passthrough
    "·": ("·", "·"),
    "•": ("•", "•"),
    "–": ("–", "–"),
    "×": ("×", "×"),
    "S": ("S", "S"),
    "#": ("#", "#"),
    "(past)": ("(已过)", "(已過)"),
    "0": ("0", "0"),
    "--": ("--", "--"),
    "FFAACC": ("FFAACC", "FFAACC"),
    " ": (" ", " "),
    "Tap": ("点击", "點擊"),
    # Misc UI labels not yet covered
    "From journal": ("来自日志", "來自日誌"),
    "From Library": ("来自物质库", "來自物質庫"),
    "Your History": ("您的历史", "您的歷史"),
    "Showing %@ entries only — other units excluded": (
        "仅显示 %@ 条目 — 其他单位已排除",
        "僅顯示 %@ 條目 — 其他單位已排除",
    ),
    "Format strings: %@ %@": ("%@ %@", "%@ %@"),
    "%@ %@": ("%@ %@", "%@ %@"),
    "%@ - %@ %@": ("%@ - %@ %@", "%@ - %@ %@"),
    "%@ – %@": ("%@ – %@", "%@ – %@"),
    "%@ – %@ %@": ("%@ – %@ %@", "%@ – %@ %@"),
    "%@ %@ — %@": ("%@ %@ — %@", "%@ %@ — %@"),
    "%@ %@ %@ on %@": ("%@ %@ %@ 于 %@", "%@ %@ %@ 於 %@"),
    "%@ — %@": ("%@ — %@", "%@ — %@"),
    "%@: %@ + %@": ("%@:%@ + %@", "%@:%@ + %@"),
    "%@, %@": ("%@,%@", "%@,%@"),
    "· %@": ("· %@", "· %@"),
    "· %lld total": ("· 共 %lld", "· 共 %lld"),
    "%@+ %@": ("%@+ %@", "%@+ %@"),
    "%@ (%lld)": ("%@ (%lld)", "%@ (%lld)"),
    "%@ %@ total": ("共 %1$@ %2$@", "共 %1$@ %2$@"),
    "%@ +%lld more": ("%1$@ +%2$lld 更多", "%1$@ +%2$lld 更多"),
    "Duration": ("持续时间", "持續時間"),
    "30D": ("30天", "30天"),
    "7D": ("7天", "7天"),
    "90D": ("90天", "90天"),
    "Adherence": ("依从性", "依從性"),
    "All Time": ("所有时间", "所有時間"),
    "Concentration": ("浓度", "濃度"),
    "Dose Volume": ("剂量体积", "劑量體積"),
    "Interactions": ("相互作用", "相互作用"),
    "Last 30 Days": ("最近 30 天", "最近 30 天"),
    "Last 7 Days": ("最近 7 天", "最近 7 天"),
    "Last 90 Days": ("最近 90 天", "最近 90 天"),
    "Recovery": ("恢复", "恢復"),
    "Solvent Needed": ("所需溶剂", "所需溶劑"),
    "Usage": ("使用", "使用"),
    "Volumetric": ("容积", "容積"),
    "Filter by dates": ("按日期筛选", "按日期篩選"),
    "Timing": ("时机", "時機"),
    "This calculator uses a one-compartment oral pharmacokinetic model with absorption and elimination phases. Absorption rates are estimated from known duration profiles (onset + comeup timing) when available, or use a default 4× elimination rate ratio. Population-average elimination half-lives are sourced from FDA-approved prescribing information, published pharmacokinetic studies (PubMed), and DrugBank. Half-lives for some research chemicals and novel substances are estimated from structurally similar compounds and may be less reliable.\n\nReal pharmacokinetics vary significantly based on individual metabolism, genetics, liver and kidney function, body composition, age, drug interactions, tolerance, and route of administration. Multi-compartment distribution, protein binding, active metabolites, and enterohepatic recirculation are not accounted for. Polydrug use may alter elimination rates unpredictably.\n\nThese figures are approximate population averages — not a substitute for clinical monitoring or professional medical advice. Always consult a qualified healthcare professional.": (
        "此计算器使用一房室口服药代动力学模型,包含吸收和消除两个阶段。如有已知的持续时间数据(起效 + 上升期),则吸收速率会由此估算;否则使用默认的 4× 消除速率比。群体平均消除半衰期来源于 FDA 批准的处方信息、已发表的药代动力学研究(PubMed)以及 DrugBank。部分研究化学品和新型物质的半衰期是根据结构类似的化合物估算的,可能不够可靠。\n\n实际药代动力学因个人代谢、遗传、肝肾功能、体成分、年龄、药物相互作用、耐受性和给药途径而显著不同。多房室分布、蛋白结合、活性代谢物和肠肝循环未被纳入考虑。多药联用可能不可预测地改变消除速率。\n\n这些数字是群体的近似平均值 — 不能替代临床监测或专业医疗建议。请始终咨询合格的医疗专业人员。",
        "此計算器使用一房室口服藥動學模型,包含吸收和消除兩個階段。如有已知的持續時間資料(起效 + 上升期),則吸收速率會由此估算;否則使用預設的 4× 消除速率比。族群平均消除半衰期來源於 FDA 批准的處方資訊、已發表的藥動學研究(PubMed)以及 DrugBank。部分研究化學品和新型物質的半衰期是根據結構類似的化合物估算的,可能不夠可靠。\n\n實際藥動學因個人代謝、遺傳、肝腎功能、體成分、年齡、藥物相互作用、耐受性和給藥途徑而顯著不同。多房室分布、蛋白質結合、活性代謝物和腸肝循環未被納入考慮。多藥聯用可能不可預測地改變消除速率。\n\n這些數字是族群的近似平均值 — 不能替代臨床監測或專業醫療建議。請始終諮詢合格的醫療專業人員。",
    ),
    # 2026-06 review fixes — crisis help links (previously plain String, never localized)
    "Emergency: 911": ("紧急情况：911", "緊急情況：911"),
    "Poison Control: 1-800-222-1222": (
        "中毒控制中心：1-800-222-1222",
        "中毒控制中心：1-800-222-1222",
    ),
    "Crisis Lifeline: 988": ("危机生命线：988", "危機生命線：988"),
    "Crisis Text: HOME to 741741": (
        "危机短信：发送 HOME 至 741741",
        "危機簡訊：傳送 HOME 至 741741",
    ),
    "Call 911 (US) or your local emergency number": (
        "拨打 911（美国）或当地紧急电话",
        "撥打 911（美國）或當地緊急電話",
    ),
    "1-800-222-1222 (US)": ("1-800-222-1222（美国）", "1-800-222-1222（美國）"),
    "988 Suicide & Crisis Lifeline": ("988 自杀与危机生命线", "988 自殺與危機生命線"),
    "Call or text 988": ("拨打或发送短信至 988", "撥打或傳送簡訊至 988"),
    "Text HOME to 741741": ("发送 HOME 至 741741", "傳送 HOME 至 741741"),
    "1-800-662-4357 — Free, confidential, 24/7": (
        "1-800-662-4357 — 免费、保密、全天候",
        "1-800-662-4357 — 免費、保密、全天候",
    ),
    # 2026-06 review fixes — inflected plurals (replace hand-rolled "s"/"ies" suffixes)
    "^[%lld substance](inflect: true)": ("%lld 种物质", "%lld 種物質"),
    "^[%lld entry](inflect: true)": ("%lld 条记录", "%lld 條記錄"),
    "^[%lld item](inflect: true)": ("%lld 项", "%lld 項"),
    # 2026-06 Library browse redesign — family blurbs, favorites card, not-found
    "κ-opioid agonists — salvia, salvinorin A.": (
        "κ-阿片受体激动剂 — 鼠尾草、沙维诺林A。",
        "κ-鴉片受體激動劑 — 鼠尾草、沙維諾林A。",
    ),
    "GABAergics & gabapentinoids — GHB, pregabalin, phenibut.": (
        "GABA能药物与加巴喷丁类 — GHB、普瑞巴林、苯尼布特。",
        "GABA能藥物與加巴噴丁類 — GHB、普瑞巴林、苯尼布特。",
    ),
    "^[%lld saved substance](inflect: true).": ("%lld 种收藏的物质。", "%lld 種收藏的物質。"),
    "Substance Not Found": ("未找到物质", "未找到物質"),
    "“%@” isn’t in the library anymore. It may have been renamed or merged.": (
        "“%@”已不在资料库中，可能已被重命名或合并。",
        "「%@」已不在資料庫中，可能已被重新命名或合併。",
    ),
    # 2026-06 review fixes — accessibility labels & chart descriptions
    "Back": ("返回", "返回"),
    "Expand Chart": ("展开图表", "展開圖表"),
    "Collapse Chart": ("收起图表", "收起圖表"),
    "Previous Month": ("上个月", "上個月"),
    "Next Month": ("下个月", "下個月"),
    "Add Routine": ("添加日常", "新增日常"),
    "Add Custom Substance": ("添加自定义物质", "新增自訂物質"),
    "Log %@ %@": ("记录 %1$@ %2$@", "記錄 %1$@ %2$@"),
    "Concentration curve": ("浓度曲线", "濃度曲線"),
    "Elimination curve for %@": ("%@ 的消除曲线", "%@ 的消除曲線"),
    "%@ %@ remaining, %lld%% eliminated, half-life %@": (
        "剩余 %1$@ %2$@，已消除 %3$lld%%，半衰期 %4$@",
        "剩餘 %1$@ %2$@，已消除 %3$lld%%，半衰期 %4$@",
    ),
    "Peak after %@, %@ of %@ %@ remaining now": (
        "%1$@ 后达到峰值，%3$@ %4$@ 中目前剩余 %2$@",
        "%1$@ 後達到峰值，%3$@ %4$@ 中目前剩餘 %2$@",
    ),
    # 2026-06 review fixes — color picker validation errors
    "Enter a valid 6-digit hex code": (
        "请输入有效的 6 位十六进制颜色代码",
        "請輸入有效的 6 位十六進位顏色代碼",
    ),
    "This shade already exists in the preset palette": (
        "预设调色板中已有此颜色",
        "預設調色盤中已有此顏色",
    ),
    "You've already created this shade": ("你已创建过此颜色", "你已建立過此顏色"),
    # 2026-06 — stacked-lane (small multiples) timeline preference
    "Stack Busy Sessions": ("拆分繁忙记录图表", "拆分繁忙記錄圖表"),
    "Stack From": ("拆分阈值", "拆分閾值"),
    "When a session reaches this many different substances, the timeline splits overlapping curves into separate stacked lanes — one per substance — so a busy session stays readable. When off, every curve is always overlaid on one graph.": (
        "当某次记录达到这么多种不同物质时，时间线会将重叠的曲线拆分为独立的堆叠泳道——每种物质一条——让繁忙的记录依然清晰可读。关闭后，所有曲线始终叠加在同一张图上。",
        "當某次記錄達到這麼多種不同物質時，時間線會將重疊的曲線拆分為獨立的堆疊泳道——每種物質一條——讓繁忙的記錄依然清晰可讀。關閉後，所有曲線始終疊加在同一張圖上。",
    ),
    # Pharmacology axis Stage 6 — Ceiling Effect tool (2026-06-22)
    "Ceiling Effect": ("封顶效应", "封頂效應"),
    "When dose and exposure aren't proportional": (
        "当剂量与暴露不成正比时",
        "當劑量與暴露不成正比時",
    ),
    "When dose and effect aren't proportional": (
        "当剂量与效应不成正比时",
        "當劑量與效應不成正比時",
    ),
    "For most substances, twice the dose means roughly twice the exposure. For these few, an enzyme runs out of capacity — so exposure can climb much faster than the dose (a warning), or an effect can stop climbing entirely (a ceiling). Shapes are model predictions, relative — not absolute concentrations.": (
        "对大多数物质而言，剂量加倍，暴露量大致也加倍。但对这少数几种，某种酶的处理能力会达到上限——于是暴露量可能远比剂量增长得快（一种警示），或者效应会彻底停止增长（封顶）。这些曲线是模型预测的相对形状，并非绝对浓度。",
        "對大多數物質而言，劑量加倍，暴露量大致也加倍。但對這少數幾種，某種酶的處理能力會達到上限——於是暴露量可能遠比劑量增長得快（一種警示），或者效應會徹底停止增長（封頂）。這些曲線是模型預測的相對形狀，並非絕對濃度。",
    ),
    "Each line is one dose; its height is the level in your blood and the area under it is your total exposure. Time is in days.": (
        "每条曲线代表一个剂量；高度是血液中的水平，曲线下面积是你的总暴露量。时间以天为单位。",
        "每條曲線代表一個劑量；高度是血液中的水平，曲線下面積是你的總暴露量。時間以天為單位。",
    ),
    "Each line is one dose; its height is the level in your blood and the area under it is your total exposure. Time is in hours.": (
        "每条曲线代表一个剂量；高度是血液中的水平，曲线下面积是你的总暴露量。时间以小时为单位。",
        "每條曲線代表一個劑量；高度是血液中的水平，曲線下面積是你的總暴露量。時間以小時為單位。",
    ),
    "%@× the dose isn't %@× the exposure — the largest curve here holds about %@× the total exposure of one reference dose.": (
        "%@ 倍剂量并不等于 %@ 倍暴露——图中最大的曲线所含的总暴露量约为单个参考剂量的 %@ 倍。",
        "%@ 倍劑量並不等於 %@ 倍暴露——圖中最大的曲線所含的總暴露量約為單個參考劑量的 %@ 倍。",
    ),
    "Ceiling on effect — described, not drawn (no precise dose knee).": (
        "效应封顶——以文字说明，未绘制曲线（没有精确的剂量拐点）。",
        "效應封頂——以文字說明，未繪製曲線（沒有精確的劑量拐點）。",
    ),
    "Steep, supralinear — described, not drawn (no reliable human kinetics).": (
        "陡峭、超线性——以文字说明，未绘制曲线（缺乏可靠的人体动力学数据）。",
        "陡峭、超線性——以文字說明，未繪製曲線（缺乏可靠的人體動力學數據）。",
    ),
    "Saturable elimination — exposure climbs faster than dose": (
        "可饱和消除——暴露量比剂量增长得更快",
        "可飽和消除——暴露量比劑量增長得更快",
    ),
    "Saturable activation — effect hits a ceiling": (
        "可饱和激活——效应触及上限",
        "可飽和激活——效應觸及上限",
    ),
    "1 drink": ("1 杯", "1 杯"),
    "%lld drinks": ("%lld 杯", "%lld 杯"),
    "%lld mg": ("%lld 毫克", "%lld 毫克"),
    "Alcohol (ethanol)": ("酒精（乙醇）", "酒精（乙醇）"),
    "Phenytoin": ("苯妥英", "苯妥英"),
    "GHB / GBL": ("GHB / GBL", "GHB / GBL"),
    "Codeine → morphine": ("可待因 → 吗啡", "可待因 → 嗎啡"),
    "Clearance is capped at ~1 drink/hour, so each extra drink stacks on top of the last and lingers — total exposure climbs far faster than the number of drinks.": (
        "清除速度被限制在约每小时 1 杯，因此每多喝一杯都会叠加在上一杯之上并滞留更久——总暴露量的增长远快于杯数。",
        "清除速度被限制在約每小時 1 杯，因此每多喝一杯都會疊加在上一杯之上並滯留更久——總暴露量的增長遠快於杯數。",
    ),
    "Elimination is already maxed out after about one drink, so there is no “safe extra” that clears as fast as the first.": (
        "大约一杯之后消除速度就已达到上限，因此并不存在能像第一杯那样快速清除的“安全的额外一杯”。",
        "大約一杯之後消除速度就已達到上限，因此並不存在能像第一杯那樣快速清除的“安全的額外一杯”。",
    ),
    "Alcohol is the classic zero-order drug: above a very low blood level the enzyme that clears it (alcohol dehydrogenase) is fully saturated and works at a fixed rate. Doubling the drinks more than doubles how long alcohol stays in your system and the area under the curve. Chronic heavy drinking speeds clearance somewhat (CYP2E1 induction); the ALDH2 “flush” variant does the opposite for acetaldehyde.": (
        "酒精是典型的零级动力学药物：当血液浓度高于一个很低的水平后，清除它的酶（乙醇脱氢酶）便完全饱和，以固定速率工作。杯数翻倍，酒精在体内停留的时间和曲线下面积会增加一倍以上。长期大量饮酒会在一定程度上加快清除（诱导 CYP2E1）；而 ALDH2“脸红”变异对乙醛的作用恰好相反。",
        "酒精是典型的零級動力學藥物：當血液濃度高於一個很低的水平後，清除它的酶（乙醇脫氫酶）便完全飽和，以固定速率工作。杯數翻倍，酒精在體內停留的時間和曲線下面積會增加一倍以上。長期大量飲酒會在一定程度上加快清除（誘導 CYP2E1）；而 ALDH2“臉紅”變異對乙醛的作用恰好相反。",
    ),
    "The clearing enzyme is already half-saturated inside the normal dose range, so a small dose increase near the top can roughly double the level into toxicity.": (
        "在正常剂量范围内，清除它的酶就已经半饱和，因此在范围上限附近，剂量稍有增加就可能使血药水平大致翻倍，进入中毒区间。",
        "在正常劑量範圍內，清除它的酶就已經半飽和，因此在範圍上限附近，劑量稍有增加就可能使血藥水平大致翻倍，進入中毒區間。",
    ),
    "Saturation begins within the therapeutic window itself — the curve bends up where most other drugs would still be a straight line.": (
        "饱和就发生在治疗窗之内——在大多数其他药物仍是直线的地方，这条曲线已经向上弯折。",
        "飽和就發生在治療窗之內——在大多數其他藥物仍是直線的地方，這條曲線已經向上彎折。",
    ),
    "Phenytoin is hydroxylated by a saturable liver enzyme system (CYP2C9/CYP2C19). Because its Km lies below the therapeutic range, dose and level are not proportional: titrate in small steps and confirm with blood levels. CYP2C9/2C19 poor metabolizers, age, and interacting drugs shift the knee lower. Shown as relative shape — phenytoin is individualized by therapeutic drug monitoring.": (
        "苯妥英由一套可饱和的肝酶系统（CYP2C9/CYP2C19）羟基化代谢。由于其 Km 低于治疗范围，剂量与血药水平并不成正比：应小幅调整剂量并通过血药浓度确认。CYP2C9/2C19 慢代谢者、年龄以及相互作用的药物都会使拐点提前。此处仅显示相对形状——苯妥英需通过治疗药物监测进行个体化调整。",
        "苯妥英由一套可飽和的肝酶系統（CYP2C9/CYP2C19）羥基化代謝。由於其 Km 低於治療範圍，劑量與血藥水平並不成正比：應小幅調整劑量並透過血藥濃度確認。CYP2C9/2C19 慢代謝者、年齡以及相互作用的藥物都會使拐點提前。此處僅顯示相對形狀——苯妥英需透過治療藥物監測進行個體化調整。",
    ),
    "Codeine only works by being converted to morphine, and most people's CYP2D6 enzyme caps how much morphine they can make — so past a point, more codeine adds side-effects and duration, not more pain relief.": (
        "可待因只有转化为吗啡才能起效，而大多数人的 CYP2D6 酶限制了能生成的吗啡量——因此超过某一点后，增加可待因只会带来更多副作用和更长的持续时间，而非更强的镇痛。",
        "可待因只有轉化為嗎啡才能起效，而大多數人的 CYP2D6 酶限制了能生成的嗎啡量——因此超過某一點後，增加可待因只會帶來更多副作用和更長的持續時間，而非更強的鎮痛。",
    ),
    "The limit is set by how much CYP2D6 enzyme you have, not by a specific milligram dose. The analgesic plateau around ~60 mg is a clinical observation, not a kinetic ceiling.": (
        "这个上限取决于你拥有多少 CYP2D6 酶，而非某个具体的毫克剂量。约 60 毫克左右的镇痛平台是临床观察结果，并非动力学封顶。",
        "這個上限取決於你擁有多少 CYP2D6 酶，而非某個具體的毫克劑量。約 60 毫克左右的鎮痛平台是臨床觀察結果，並非動力學封頂。",
    ),
    "This ceiling is on the opioid effect only — not on codeine's other risks. Two big caveats: “ultra-rapid metabolizers” convert far more codeine to morphine and can reach dangerous levels at ordinary doses (the FDA contraindicates codeine in them), while “poor metabolizers” get little relief. So this is not a green light to take more.": (
        "这个封顶只针对阿片效应——并不涵盖可待因的其他风险。两点重要提醒：“超快代谢者”会把多得多的可待因转化为吗啡，在普通剂量下就可能达到危险水平（FDA 对这类人群禁用可待因），而“慢代谢者”几乎得不到缓解。所以这并不是可以多服的许可。",
        "這個封頂只針對阿片效應——並不涵蓋可待因的其他風險。兩點重要提醒：“超快代謝者”會把多得多的可待因轉化為嗎啡，在普通劑量下就可能達到危險水平（FDA 對這類人群禁用可待因），而“慢代謝者”幾乎得不到緩解。所以這並不是可以多服的許可。",
    ),
    "Exposure rises steeply and faster than dose — a small step up can disproportionately increase how much your body sees. The gap between a recreational and a dangerous dose is small.": (
        "暴露量陡峭上升，且比剂量增长得更快——小幅增加剂量就可能使身体承受的量不成比例地增加。娱乐剂量与危险剂量之间的差距很小。",
        "暴露量陡峭上升，且比劑量增長得更快——小幅增加劑量就可能使身體承受的量不成比例地增加。娛樂劑量與危險劑量之間的差距很小。",
    ),
    "Nonlinearity appears already at moderate recreational doses: a controlled study saw ~40% more exposure going from 25 to 35 mg/kg, and the regulated product's exposure rises ~3.8× when the dose doubles.": (
        "非线性在中等娱乐剂量时就已出现：一项对照研究发现，从 25 增至 35 毫克/千克时暴露量增加约 40%，而获批产品在剂量翻倍时暴露量上升约 3.8 倍。",
        "非線性在中等娛樂劑量時就已出現：一項對照研究發現，從 25 增至 35 毫克/千克時暴露量增加約 40%，而獲批產品在劑量翻倍時暴露量上升約 3.8 倍。",
    ),
    "GHB's clearing pathway saturates, so dose and effect are not proportional and the margin for error is thin. Measure precisely, wait fully between doses (never re-dose because “it hasn't hit yet”), and treat any other depressant — especially alcohol — as compounding the danger. Liver impairment lowers the threshold further. No reliable human Km/Vmax exists, so the direction is shown without a drawn curve.": (
        "GHB 的清除通路会饱和，因此剂量与效应并不成正比，容错空间很小。请精确量取，两次服用之间充分等待（绝不要因为“还没起效”就追加），并把任何其他抑制剂——尤其是酒精——视为会叠加危险。肝功能受损会进一步降低阈值。目前没有可靠的人体 Km/Vmax 数据，因此只显示趋势方向而不绘制曲线。",
        "GHB 的清除通路會飽和，因此劑量與效應並不成正比，容錯空間很小。請精確量取，兩次服用之間充分等待（絕不要因為“還沒起效”就追加），並把任何其他抑制劑——尤其是酒精——視為會疊加危險。肝功能受損會進一步降低閾值。目前沒有可靠的人體 Km/Vmax 數據，因此只顯示趨勢方向而不繪製曲線。",
    ),
    # Pharmacology axis Stage 6 — Benzo equivalence converter (2026-06-23)
    "Benzo Equivalence": ("苯二氮䓬等效换算", "苯二氮䓬等效換算"),
    "Compare benzodiazepine doses to diazepam": (
        "将苯二氮䓬剂量与地西泮比较",
        "將苯二氮䓬劑量與地西泮比較",
    ),
    "Compare benzodiazepine doses against diazepam, or convert between two — the way clinicians do when switching for a taper.": (
        "将苯二氮䓬的剂量与地西泮比较，或在两种之间换算——就像临床医生在为减量而换药时所做的那样。",
        "將苯二氮䓬的劑量與地西泮比較，或在兩種之間換算——就像臨床醫師在為減量而換藥時所做的那樣。",
    ),
    "mg": ("mg", "mg"),
    "Equivalent Dose": ("等效剂量", "等效劑量"),
    "≈ %@ mg": ("≈ %@ mg", "≈ %@ mg"),
    "%@ mg %@ ≈ %@ mg %@": ("%@ mg %@ ≈ %@ mg %@", "%@ mg %@ ≈ %@ mg %@"),
    "(≈ %@ mg diazepam)": ("（≈ %@ mg 地西泮）", "（≈ %@ mg 地西泮）"),
    "Approximate — equivalence tables disagree. Treat this as a ballpark, not a precise dose.": (
        "仅为近似——各等效换算表并不一致。请将其视为大致参考，而非精确剂量。",
        "僅為近似——各等效換算表並不一致。請將其視為大致參考，而非精確劑量。",
    ),
    "Enter a dose to convert.": ("输入剂量以进行换算。", "輸入劑量以進行換算。"),
    "No numeric equivalence is available for this substance.": (
        "该物质没有可用的数值等效数据。",
        "該物質沒有可用的數值等效資料。",
    ),
    "No numeric equivalence is available for the target substance.": (
        "目标物质没有可用的数值等效数据。",
        "目標物質沒有可用的數值等效資料。",
    ),
    "Pick both substances and a dose.": (
        "请选择两种物质并输入剂量。",
        "請選擇兩種物質並輸入劑量。",
    ),
    "Cited equivalence": ("引用的等效数据", "引用的等效資料"),
    "Source: TripSit benzodiazepine dataset. Equivalences vary by reference (Ashton, manufacturer, clinical); these are a guide, not a single clinical truth.": (
        "来源：TripSit 苯二氮䓬数据集。不同参考来源（Ashton、厂商、临床）的等效值各异；这些仅供参考，并非唯一的临床标准。",
        "來源：TripSit 苯二氮䓬資料集。不同參考來源（Ashton、廠商、臨床）的等效值各異；這些僅供參考，並非唯一的臨床標準。",
    ),
    "A cross-taper usually switches from a short- to a long-half-life benzo: the longer drug self-tapers more smoothly. Diazepam's long-acting active metabolites stretch its effective half-life well beyond the parent.": (
        "交叉减量通常是从短半衰期的苯二氮䓬换成长半衰期的：作用更长的药物会更平稳地自我递减。地西泮的长效活性代谢物使其有效半衰期远超母体药物。",
        "交叉減量通常是從短半衰期的苯二氮䓬換成長半衰期的：作用更長的藥物會更平穩地自我遞減。地西泮的長效活性代謝物使其有效半衰期遠超母體藥物。",
    ),
    "This converts and compares — it is not a taper schedule. Plan any dose reduction with a clinician.": (
        "本工具用于换算与比较，并非减量方案。任何减量都应与临床医生一起制定。",
        "本工具用於換算與比較，並非減量方案。任何減量都應與臨床醫師一起制定。",
    ),
    "Never stop a benzodiazepine abruptly. Withdrawal can be dangerous (seizures); a slow taper is the safe path.": (
        "切勿骤然停用苯二氮䓬。戒断可能有危险（癫痫发作）；缓慢递减才是安全之道。",
        "切勿驟然停用苯二氮䓬。戒斷可能有危險（癲癇發作）；緩慢遞減才是安全之道。",
    ),
    "Single-dose equivalence isn't steady-state equivalence — long-acting metabolites accumulate over days.": (
        "单次剂量的等效并不等于稳态下的等效——长效代谢物会在数日内累积。",
        "單次劑量的等效並不等於穩態下的等效——長效代謝物會在數日內累積。",
    ),
    "Equivalences are approximate and contested. Use the cited value as a starting estimate, not a precise dose.": (
        "等效值只是近似且存在争议。请将引用值作为起始估计，而非精确剂量。",
        "等效值只是近似且存在爭議。請將引用值作為起始估計，而非精確劑量。",
    ),
    "~%lld min": ("~%lld 分钟", "~%lld 分鐘"),
    "~%@ h": ("~%@ 小时", "~%@ 小時"),
    "~%lld h": ("~%lld 小时", "~%lld 小時"),
    "Search benzodiazepines": ("搜索苯二氮䓬", "搜尋苯二氮䓬"),
    "Select Benzodiazepine": ("选择苯二氮䓬", "選擇苯二氮䓬"),
    # Pharmacology axis Stage 5 — Cannabis vertical / 11-OH-THC (2026-06-23)
    "11-OH-THC": ("11-OH-THC", "11-OH-THC"),
    "11-OH-THC (edibles)": ("11-OH-THC（食用大麻）", "11-OH-THC（食用大麻）"),
    "Swallowed THC passes through your liver first, which turns much of it into 11-hydroxy-THC — an active by-product that reaches the brain more easily and binds the CB1 receptor far more strongly than THC itself. That's why an edible tends to feel stronger, milligram for milligram, than the same amount smoked.": (
        "口服的 THC 会先经过肝脏，其中大部分被转化为 11-羟基-THC——一种活性代谢物，它更容易进入大脑，并且与 CB1 受体的结合远比 THC 本身更强。这就是为什么按毫克计算，食用大麻通常比吸食同等剂量感觉更强。",
        "口服的 THC 會先經過肝臟，其中大部分被轉化為 11-羥基-THC——一種活性代謝物，它更容易進入大腦，並且與 CB1 受體的結合遠比 THC 本身更強。這就是為什麼按毫克計算，食用大麻通常比吸食同等劑量感覺更強。",
    ),
    "Edibles also come on slowly — usually 30 minutes to 2 hours — and last much longer, often 6–10 hours. That slow start is the redose trap: wait at least 2 hours before taking more, or you can stack a far stronger, longer dose than you meant to.": (
        "食用大麻起效也很慢——通常为 30 分钟到 2 小时——而且持续时间长得多，常达 6–10 小时。这种缓慢起效正是重复用药的陷阱：再次服用前至少等待 2 小时，否则你可能叠加出远比预期更强、更长的剂量。",
        "食用大麻起效也很慢——通常為 30 分鐘到 2 小時——而且持續時間長得多，常達 6–10 小時。這種緩慢起效正是重複用藥的陷阱：再次服用前至少等待 2 小時，否則你可能疊加出遠比預期更強、更長的劑量。",
    ),
    "Based on first-pass metabolism of oral THC · educational, not a measured level. Onset and duration vary with dose, product, and tolerance.": (
        "基于口服 THC 的首过代谢 · 仅供教育参考，并非实测值。起效与持续时间因剂量、产品和耐受性而异。",
        "基於口服 THC 的首過代謝 · 僅供教育參考，並非實測值。起效與持續時間因劑量、產品和耐受性而異。",
    ),
    # Alcohol by-volume input (2026-06-22)
    "By Drink": ("按饮品", "按飲品"),
    "By Weight": ("按重量", "按重量"),
    "Volume": ("容量", "容量"),
    "Strength": ("浓度", "濃度"),
    "% ABV": ("% 酒精度", "% 酒精度"),
    "Optional": ("可选", "可選"),
    "Beer": ("啤酒", "啤酒"),
    "Wine": ("葡萄酒", "葡萄酒"),
    "Shot": ("烈酒", "烈酒"),
    "Pint": ("品脱", "品脫"),
    "Enter a volume and strength": ("输入容量和浓度", "輸入容量和濃度"),
    "ethanol · ≈ %@ standard drinks": ("乙醇 · ≈ %@ 标准杯", "乙醇 · ≈ %@ 標準杯"),
    "%lld g": ("%lld g", "%lld g"),
    "Input": ("输入", "輸入"),
    "Volume unit": ("容量单位", "容量單位"),
    # Alcohol ALDH2 / acetaldehyde (2026-06-22, Stage 5)
    "I get the alcohol flush": ("我喝酒会脸红", "我喝酒會臉紅"),
    "Tobacco smoke speeds up CYP1A2, so it lowers the levels of some drugs (like caffeine and olanzapine). Grapefruit slows down CYP3A4, raising the levels of others — turn on grapefruit logging to mark it on individual doses of affected substances. The alcohol flush (facial redness, fast heartbeat, nausea after a little alcohol) signals the ALDH2 variant — turn it on to see acetaldehyde, the toxic by-product it lets build up, on alcohol entries. All three are shown only where they actually change a drug's levels or risk.": (
        "烟草烟雾会加快 CYP1A2，从而降低某些药物（如咖啡因和奥氮平）的水平。西柚会减慢 CYP3A4，升高另一些药物的水平——开启西柚记录后，可在受影响物质的单次剂量上标记。喝一点酒就脸红（面部发红、心跳加快、恶心）提示携带 ALDH2 变异——开启后即可在酒精记录中看到它放任堆积的毒性副产物乙醛。这三项仅在确实改变某药物水平或风险时才显示。",
        "菸草煙霧會加快 CYP1A2，從而降低某些藥物（如咖啡因和奧氮平）的水平。葡萄柚會減慢 CYP3A4，升高另一些藥物的水平——開啟葡萄柚記錄後，可在受影響物質的單次劑量上標記。喝一點酒就臉紅（面部發紅、心跳加快、噁心）提示攜帶 ALDH2 變異——開啟後即可在酒精記錄中看到它放任堆積的毒性副產物乙醛。這三項僅在確實改變某藥物水平或風險時才顯示。",
    ),
    "Acetaldehyde": ("乙醛", "乙醛"),
    "Acetaldehyde (ALDH2)": ("乙醛（ALDH2）", "乙醛（ALDH2）"),
    "Elevated": ("偏高", "偏高"),
    "Very high": ("极高", "極高"),
    "Your ALDH2 variant clears acetaldehyde — the first, toxic by-product of alcohol — slowly, so it builds up and lingers. That build-up *is* the flush, racing heart, and nausea, and it's a Group 1 carcinogen (IARC): for flush-reactive drinkers each drink carries more long-term throat and oesophageal cancer risk. Less alcohol means less acetaldehyde — there's no amount that clears as cleanly as it does for others.": (
        "你的 ALDH2 变异清除乙醛——酒精的第一个毒性副产物——的速度很慢，因此它会堆积并滞留。这种堆积正是脸红、心跳加快和恶心的原因，而乙醛是一级致癌物（IARC）：对喝酒会脸红的人来说，每一杯都带来更高的长期咽喉与食道癌风险。少喝就意味着更少的乙醛——没有任何分量能像对别人那样被干净地清除掉。",
        "你的 ALDH2 變異清除乙醛——酒精的第一個毒性副產物——的速度很慢，因此它會堆積並滯留。這種堆積正是臉紅、心跳加快和噁心的原因，而乙醛是一級致癌物（IARC）：對喝酒會臉紅的人來說，每一杯都帶來更高的長期咽喉與食道癌風險。少喝就意味著更少的乙醛——沒有任何分量能像對別人那樣被乾淨地清除掉。",
    ),
    "Avoid mixing alcohol with metronidazole or certain other antibiotics — they block this same step and can make even a small drink severe.": (
        "避免将酒精与甲硝唑或某些其他抗生素同用——它们会阻断同一步骤，可能使哪怕一小杯也变得严重。",
        "避免將酒精與甲硝唑或某些其他抗生素同用——它們會阻斷同一步驟，可能使哪怕一小杯也變得嚴重。",
    ),
    "Based on your self-reported alcohol flush · educational, not a measured level.": (
        "依据你自报的喝酒脸红 · 仅供参考，并非实测水平。",
        "依據你自報的喝酒臉紅 · 僅供參考，並非實測水平。",
    ),
    # Opioid safety axis — reset-after-break overdose (2026-06-22, Stage 5)
    "Your tolerance has dropped": ("你的耐受已下降", "你的耐受已下降"),
    "If a dose is too much, you don't feel it coming — breathing just stops and you black out with no warning. There's no moment where you notice and react.": (
        "如果剂量过量，你不会有任何预兆——呼吸会直接停止，你会在毫无征兆的情况下失去意识。没有让你察觉并作出反应的时机。",
        "如果劑量過量，你不會有任何預兆——呼吸會直接停止，你會在毫無徵兆的情況下失去意識。沒有讓你察覺並作出反應的時機。",
    ),
    "And you can't use naloxone (Narcan) on yourself once that happens. Have someone with you who can, keep naloxone where they can reach it, and start much lower than your old dose.": (
        "而一旦发生，你无法给自己使用纳洛酮（Narcan）。请让能帮你的人陪在身边，把纳洛酮放在他们够得到的地方，并且从远低于你以前的剂量开始。",
        "而一旦發生，你無法給自己使用納洛酮（Narcan）。請讓能幫你的人陪在身邊，把納洛酮放在他們夠得到的地方，並且從遠低於你以前的劑量開始。",
    ),
    "After about a %lld-day break your opioid tolerance has fallen to roughly %lld%% of full — close to none. A dose that felt fine before the break can stop your breathing now. This is the most common way people overdose.": (
        "在大约 %lld 天的间断后，你的阿片耐受已降至约满值的 %lld%%——几乎为零。间断前让你感觉没问题的剂量，现在可能让你停止呼吸。这是最常见的过量方式。",
        "在大約 %lld 天的間斷後，你的阿片耐受已降至約滿值的 %lld%%——幾乎為零。間斷前讓你感覺沒問題的劑量，現在可能讓你停止呼吸。這是最常見的過量方式。",
    ),
    "Predicted from your logged use (model, %@).": (
        "依据你的记录使用情况预测（模型，%@）。",
        "依據你的記錄使用情況預測（模型，%@）。",
    ),
    # Tolerance-mechanism explainer (2026-06-22, Stage 5)
    "How tolerance works": ("耐受是如何形成的", "耐受是如何形成的"),
    "Three kinds of tolerance": ("三种耐受", "三種耐受"),
    "Availability — the real tolerance": ("可用度——真正的耐受", "可用度——真正的耐受"),
    "With repeated use a receptor gets less responsive, so the same dose does less. We show it as your predicted response versus rested (≈X%). It recovers when you stop — over days to weeks depending on the receptor. This is the honest “tolerance” for opioids, psychedelics, benzodiazepines, dissociatives, and cannabis.": (
        "反复使用后，受体的反应性下降，因此同样的剂量效果变弱。我们用相对于休息状态的预测反应（≈X%）来表示。停用后它会恢复——视受体不同，需数天到数周。这才是阿片类、致幻剂、苯二氮䓬、解离剂和大麻真正意义上的“耐受”。",
        "反覆使用後，受體的反應性下降，因此同樣的劑量效果變弱。我們用相對於休息狀態的預測反應（≈X%）來表示。停用後它會恢復——視受體不同，需數天到數週。這才是阿片類、致幻劑、苯二氮䓬、解離劑和大麻真正意義上的「耐受」。",
    ),
    "Within-session redose": ("同次内追加", "同次內追加"),
    "Separately, a second dose the same session often lands weaker — fast desensitization (tachyphylaxis). It recovers overnight, so it's shown apart from the slow tolerance above. Chasing it with more rarely works and stacks risk.": (
        "另外，同一次使用中追加的第二剂往往更弱——这是快速脱敏（速发耐受）。它会在一夜之间恢复，因此与上面的慢性耐受分开显示。靠加量去追效果通常无效，反而叠加风险。",
        "另外，同一次使用中追加的第二劑往往更弱——這是快速脫敏（速發耐受）。它會在一夜之間恢復，因此與上面的慢性耐受分開顯示。靠加量去追效果通常無效，反而疊加風險。",
    ),
    "Recovery-state load — not a multiplier": ("恢复状态负荷——不是倍率", "恢復狀態負荷——不是倍率"),
    "For stimulants and serotonin releasers there is no honest “tolerance %” to multiply a dose by. The slow change is a months-long recovery state of the whole system, not a take-more signal. We show that as a bounded load bar instead of a fake number — refusing to imply a dose you should escalate to.": (
        "对于兴奋剂和血清素释放剂，并不存在可以拿来乘剂量的诚实“耐受百分比”。其缓慢变化是整个系统长达数月的恢复状态，而非“可以加量”的信号。我们用一个有上限的负荷条来表示，而不是给出一个假数字——拒绝暗示你应该加到的剂量。",
        "對於興奮劑和血清素釋放劑，並不存在可以拿來乘劑量的誠實「耐受百分比」。其緩慢變化是整個系統長達數月的恢復狀態，而非「可以加量」的信號。我們用一個有上限的負荷條來表示，而不是給出一個假數字——拒絕暗示你應該加到的劑量。",
    ),
    "These are model predictions of how repeated use changes each receptor — never a measurement. Each figure carries a confidence tier.": (
        "这些是模型对反复使用如何改变各受体的预测——绝非实测。每个数字都附有置信等级。",
        "這些是模型對反覆使用如何改變各受體的預測——絕非實測。每個數字都附有置信等級。",
    ),
    "Cross-tolerance": ("交叉耐受", "交叉耐受"),
    "Tolerance is shared by receptor, not by name": (
        "耐受按受体共享，而非按名称",
        "耐受按受體共享，而非按名稱",
    ),
    "Two different drugs that hit the same receptor share tolerance. Recent LSD lowers a mushroom trip because both work at 5-HT2A; one benzodiazepine carries to another; one opioid to the next. That's why tolerance here is tracked per receptor target, and why a “new” drug in the same family can still be blunted.": (
        "作用于同一受体的两种不同药物会共享耐受。近期用过 LSD 会削弱蘑菇的体验，因为两者都作用于 5-HT2A；一种苯二氮䓬的耐受会带到另一种；一种阿片也会带到下一种。这正是本工具按受体靶点追踪耐受的原因，也是为什么同一类的“新”药仍可能被削弱。",
        "作用於同一受體的兩種不同藥物會共享耐受。近期用過 LSD 會削弱蘑菇的體驗，因為兩者都作用於 5-HT2A；一種苯二氮䓬的耐受會帶到另一種；一種阿片也會帶到下一種。這正是本工具按受體靶點追蹤耐受的原因，也是為什麼同一類的「新」藥仍可能被削弱。",
    ),
    "By mechanism": ("按机制", "按機制"),
    "Recovery timescales and tolerance behaviour are calibrated to the published literature for each receptor class. The note under each is the calibration basis; the badge is how well-established those kinetics are.": (
        "各受体类别的恢复时间尺度与耐受行为均依据已发表文献校准。每项下方的注释是校准依据；徽章表示这些动力学的可靠程度。",
        "各受體類別的恢復時間尺度與耐受行為均依據已發表文獻校準。每項下方的註釋是校準依據；徽章表示這些動力學的可靠程度。",
    ),
    "Dose-response tolerance": ("剂量反应耐受", "劑量反應耐受"),
    "Recovery-state load": ("恢复状态负荷", "恢復狀態負荷"),
    "Recovers in days": ("数天内恢复", "數天內恢復"),
    "Recovers over ~a week": ("约一周内恢复", "約一週內恢復"),
    "Recovers over weeks": ("数周内恢复", "數週內恢復"),
    "Recovers over a month+": ("一个多月内恢复", "一個多月內恢復"),
    "Recovers over months": ("数月内恢复", "數月內恢復"),
    "Strong and fast: a second trip soon after is much weaker. Resets within a few days.": (
        "强而快：短期内再次体验会弱很多。数天内重置。",
        "強而快：短期內再次體驗會弱很多。數天內重置。",
    ),
    "Real tolerance that resets after a break — which is exactly what makes returning to an old dose dangerous.": (
        "真实的耐受会在间断后重置——这正是回到旧剂量之所以危险的原因。",
        "真實的耐受會在間斷後重置——這正是回到舊劑量之所以危險的原因。",
    ),
    "Tolerance plus physical dependence; stopping abruptly after heavy regular use can be dangerous — taper.": (
        "既有耐受也有躯体依赖；长期大量使用后骤停可能危险——应逐步减量。",
        "既有耐受也有軀體依賴；長期大量使用後驟停可能危險——應逐步減量。",
    ),
    "Builds its own tolerance, and can also blunt opioid tolerance when taken together.": (
        "会形成自身耐受，同时使用还可能削弱阿片类的耐受。",
        "會形成自身耐受，同時使用還可能削弱阿片類的耐受。",
    ),
    "Fast and real, but recovers fairly quickly once you stop.": (
        "又快又真实，但停用后恢复得相当快。",
        "又快又真實，但停用後恢復得相當快。",
    ),
    "Clean, predictable tolerance — the caffeine case, the textbook example.": (
        "干净、可预测的耐受——咖啡因的情形，教科书式的例子。",
        "乾淨、可預測的耐受——咖啡因的情形，教科書式的例子。",
    ),
    "No single “tolerance %” fits: a fast within-session fade plus a slow, months-long recovery state — not a signal to take more.": (
        "没有单一的“耐受百分比”能概括：既有同次内的快速衰减，又有长达数月的缓慢恢复状态——并非加量的信号。",
        "沒有單一的「耐受百分比」能概括：既有同次內的快速衰減，又有長達數月的緩慢恢復狀態——並非加量的信號。",
    ),
    "A reversible-leaning change at the serotonin transporter — a recovery-state indicator, not a dose multiplier.": (
        "血清素转运体上偏向可逆的变化——是恢复状态指标，而非剂量倍率。",
        "血清素轉運體上偏向可逆的變化——是恢復狀態指標，而非劑量倍率。",
    ),
    "Mostly fast receptor desensitization that recovers between uses rather than a lasting dose multiplier.": (
        "主要是快速的受体脱敏，在两次使用之间恢复，而非持久的剂量倍率。",
        "主要是快速的受體脫敏，在兩次使用之間恢復，而非持久的劑量倍率。",
    ),
    "Where the numbers come from": ("数字从何而来", "數字從何而來"),
    "Binding affinities come from the NIMH PDSP Kᵢ database and primary literature; the tolerance kinetics are calibrated to published human recovery studies. Every parameter is graded, and anything resting on a class default is flagged. Nothing here is measured from you — it's predicted from your dose log and these curated values.": (
        "结合亲和力来自 NIMH PDSP Kᵢ 数据库及原始文献；耐受动力学依据已发表的人体恢复研究校准。每个参数都经过分级，任何依赖类别默认值的内容都会被标注。这里没有任何数据是从你身上测得的——而是依据你的剂量记录和这些经过整理的数值预测得出。",
        "結合親和力來自 NIMH PDSP Kᵢ 資料庫及原始文獻；耐受動力學依據已發表的人體恢復研究校準。每個參數都經過分級，任何依賴類別預設值的內容都會被標註。這裡沒有任何數據是從你身上測得的——而是依據你的劑量記錄和這些經過整理的數值預測得出。",
    ),
}

# Widget translations
WT = {
    "Today": ("今日", "今日"),
    "Today's Doses": ("今日剂量", "今日劑量"),
    "Last Dose": ("最近剂量", "最近劑量"),
    "No doses today": ("今日无剂量", "今日無劑量"),
    "No doses yet": ("尚无剂量", "尚無劑量"),
    "No recent doses": ("无最近剂量", "無最近劑量"),
    "See what you've taken today at a glance.": (
        "一眼查看今天服用了什么。",
        "一眼查看今天服用了什麼。",
    ),
    "See your most recent dose and how long ago it was.": (
        "查看最近的剂量及多久前服用。",
        "查看最近的劑量及多久前服用。",
    ),
    "%lld dose%@": ("%1$lld 个剂量", "%1$lld 個劑量"),
    "+%lld more": ("+%lld 更多", "+%lld 更多"),
    "%lldm": ("%lld 分钟", "%lld 分鐘"),
    "%lldh %lldm": ("%1$lld 小时 %2$lld 分钟", "%1$lld 小時 %2$lld 分鐘"),
    "%@ %@ · %@": ("%@ %@ · %@", "%@ %@ · %@"),
    "%@ %@": ("%@ %@", "%@ %@"),
    "%lld": ("%lld", "%lld"),
}


def serialize_catalog(data: dict) -> str:
    """Serialize a String Catalog byte-for-byte the way Xcode does, so a no-op
    run produces an empty `git diff`.

    Three details matter and none are json.dumps defaults:
    - `separators=(",", " : ")` — Xcode puts spaces around the key colon.
    - empty entries (extracted-but-untranslated, English-only keys) are written
      `"key" : {\\n\\n    }`, not the collapsed `{}` json emits.
    - NO trailing newline — Xcode ends the file on the closing brace.
    Get any of these wrong and the whole 20k-line file reformats.
    """
    text = json.dumps(
        data,
        indent=2,
        ensure_ascii=False,
        sort_keys=False,
        separators=(",", " : "),
    )
    return text.replace('" : {}', '" : {\n\n    }')


def apply_translations(catalog_path: Path, translations: dict, insert_keys: set | None = None):
    """Fill zh-Hans/zh-Hant for every catalog key present in `translations`.

    By default this only UPDATES keys Xcode has already extracted — never adds
    new ones — so a catalog stays scoped to the strings its target actually
    references (the widget must not inherit all 1000+ app strings).

    `insert_keys` is an explicit allow-list of brand-new keys to insert when
    absent — for strings added from the CLI that Xcode hasn't extracted yet.
    Keep it to the handful you actually added; Xcode folds them into its
    collation order on the next open.
    """
    insert_keys = insert_keys or set()
    data = json.loads(catalog_path.read_text(encoding="utf-8"))
    strings = data.setdefault("strings", {})

    translated_count = 0
    added = []
    for key, (zh_hans, zh_hant) in translations.items():
        entry = strings.get(key)
        if entry is None:
            if key not in insert_keys:
                continue
            entry = {}
            strings[key] = entry
            added.append(key)
        locs = entry.setdefault("localizations", {})
        locs["zh-Hans"] = {"stringUnit": {"state": "translated", "value": zh_hans}}
        locs["zh-Hant"] = {"stringUnit": {"state": "translated", "value": zh_hant}}
        translated_count += 1

    # English-only keys still lacking a translation in T (informational).
    missing = [
        key
        for key, entry in strings.items()
        if key.strip() and "localizations" not in entry and key not in translations
    ]

    catalog_path.write_text(serialize_catalog(data), encoding="utf-8")
    return translated_count, added, missing


CANONICAL_LANGUAGES = ("zh-Hans", "zh-Hant")


def canonicalize_catalogs(project_path: Path, languages=CANONICAL_LANGUAGES) -> bool:
    """Let Xcode re-collate every catalog key into its canonical order.

    Why this exists: `apply_translations` appends brand-new `insert_keys` to the
    end of the catalog (Python dict insertion order). Xcode's String Catalog
    editor stores keys in an ICU-collated order that we can't reproduce in
    Python and that `xcstringstool sync` mangles (it stales/drops live strings
    when invoked outside the build graph — see CLAUDE.md). So instead of sorting
    ourselves, we hand the catalog back to Xcode: an `xcodebuild
    -exportLocalizations` → `-importLocalizations` round-trip rewrites every
    project `.xcstrings` in Xcode's canonical order, byte-for-byte identical to
    what opening the catalog in the IDE produces. The round-trip is idempotent
    (a second pass is a no-op) and non-destructive (no keys dropped, stale marks
    and untranslated entries preserved), so committing its output stops the IDE
    from re-ordering the file on the next build.

    Returns True on success, False if xcodebuild isn't available or fails (in
    which case the script's own serialization is left in place untouched).
    """
    if not project_path.exists():
        print(f"  (skipped canonicalize: {project_path} not found)")
        return False

    with tempfile.TemporaryDirectory(prefix="piru-loc-") as tmp:
        tmp_path = Path(tmp)
        export = [
            "xcodebuild",
            "-exportLocalizations",
            "-project",
            str(project_path),
            "-localizationPath",
            str(tmp_path),
        ]
        for lang in languages:
            export += ["-exportLanguage", lang]

        result = subprocess.run(export, capture_output=True, text=True)
        if result.returncode != 0:
            print("  (canonicalize failed at export — leaving Python output in place)")
            print(result.stderr.strip()[-500:])
            return False

        for lang in languages:
            xcloc = tmp_path / f"{lang}.xcloc"
            if not xcloc.exists():
                print(f"  (canonicalize: no {xcloc.name} produced — skipping)")
                continue
            imp = subprocess.run(
                [
                    "xcodebuild",
                    "-importLocalizations",
                    "-project",
                    str(project_path),
                    "-localizationPath",
                    str(xcloc),
                ],
                capture_output=True,
                text=True,
            )
            if imp.returncode != 0:
                print(f"  (canonicalize failed at import of {lang})")
                print(imp.stderr.strip()[-500:])
                return False

    return True


sys.path.insert(0, "/tmp")
try:
    from moa_translations import MOA_DESCRIPTIONS, MOA_SUMMARIES

    T.update(MOA_SUMMARIES)
    T.update(MOA_DESCRIPTIONS)
except ImportError:
    pass

if __name__ == "__main__":
    project_root = Path(__file__).resolve().parent

    # Brand-new strings added from the CLI that Xcode hasn't extracted into the
    # catalog yet. List them here so they get inserted; clear once Xcode has
    # picked them up on a real build (after which they're update-only).
    NEW_KEYS = {
        # Pharmacology card hybrid redesign (2026-06-29)
        "Detail level",
        "Pharmacology",
        "Minor / off-targets",
        "Full μ-opioid agonist",
        "Partial μ-opioid agonist",
        "μ-opioid antagonist",
        "GABA-A positive modulator",
        "Amplifies GABA — it doesn't open the channel on its own.",
        "NMDA channel blocker",
        "Lower IC₅₀ / Kᵢ = more potent block.",
        "Sedation",
        "Anxiolysis",
        "Muscle",
        "Memory",
        "Release",
        "Reuptake",
        "More",
        "Personalize Substance…",
        # Pharmacology card round-3 phase-2 (2026-06-28)
        "Renal excretion",
        "Biliary excretion",
        "Activates 5-HT2B, which is linked to heart-valve damage (valvulopathy) with chronic or heavy use.",
        # Pharmacology card harmony pass — round 3 (2026-06-28)
        "Measures how tightly the drug grips the target (Ki). A smaller number means a tighter grip — under 100 nM is strong, over 1000 nM is weak.",
        "Measures the dose needed to actually switch the target on or block it, rather than just stick to it. These run about 10× higher than binding, so the dots use a matching scale (under 1 µM strong, over 10 µM weak).",
        # Pharmacology card harmony pass — round 2 (2026-06-28)
        "Repeated doses build up faster than the dose suggests",
        "%@ may raise levels",
        "%@ may lower levels",
        "How the drug acts in the body — which receptors and transporters it targets, and what it does at each (switches them on, blocks them, and so on). The dots show how strongly it acts at each target.",
        "A summary of how the drug affects the brain's three main signalling chemicals — serotonin, dopamine, and noradrenaline — and whether it releases them or blocks their reuptake. The slider shows which one it leans toward.",
        "How your body breaks the drug down — which liver enzymes do the work, what byproducts (metabolites) form, and whether those are still active. The percentage is each enzyme's rough share of clearance.",
        "Everyday things — foods like grapefruit, smoking, or the drug's own buildup over repeated doses — can speed up or slow down how fast it's cleared, which raises or lowers its levels in the body.",
        "Estimates from primary literature, not measured for you.",
        "Educated predictions from typical pharmacology, not measured for you.",
        # Pharmacology card harmony pass (2026-06-28)
        "binding",
        "functional",
        "Binding",
        "Functional",
        "What do these mean?",
        "Receptor data",
        "Additional Info",
        "Strength dots",
        "nM (nanomolar)",
        "Human vs animal",
        "These are population averages from research — your own values vary with genetics, body size, and how the drug is taken.",
        "Stronger doesn't mean more dangerous — it's just how tightly the drug grips that one target in the lab.",
        "How much of a dose actually reaches your bloodstream. Swallowing a drug usually delivers less than injecting it.",
        "How long after taking it the level in your blood is highest — roughly when effects peak.",
        "The time for your body to clear half of what's left. It takes about five half-lives to clear almost all of it.",
        "The share that rides along stuck to blood proteins. Only the unbound rest is free to act.",
        "How widely the drug spreads from blood into the rest of the body. A bigger number means it soaks into tissues rather than staying in the blood.",
        "How fast your body removes the drug, mostly via the liver and kidneys.",
        "The highest concentration reached in the blood after a dose.",
        "A quick read of how potent the drug is at that target — three dots is strong, one is weak. The same scale is used on the Mechanism card.",
        "Measures how tightly the drug grips the target (Ki). A smaller number means a tighter grip.",
        "Measures the dose needed to actually switch the target on or block it, rather than just stick to it. Also smaller = more potent.",
        "The concentration unit these values use. Lower numbers always mean the drug works at smaller amounts.",
        "Many values come from animal or lab-dish studies. Human data is the most reliable — the source tag tells you which it is.",
        # Pharmacology axis — RC-expansion UI (2026-06-24)
        "Monoamine Profile",
        "Substrate releaser",
        "Reuptake blocker",
        "Mixed (releaser / blocker)",
        "Reverses the transporters to pump monoamines out (substrate efflux) — the MDMA/amphetamine-type mechanism.",
        "Blocks reuptake without triggering release (cocaine/methylphenidate-type) — a different tolerance and redose profile from a releaser.",
        "Releases at one transporter while blocking another — an intermediate profile; a single α-alkyl or N-ethyl group flips DAT from substrate to blocker.",
        "Balance not characterized (DAT or SERT data missing)",
        "Serotonin-leaning (entactogenic)",
        "Balanced — empathogen-like",
        "Dopamine-leaning — more stimulant in character",
        "Strongly dopaminergic (SERT-sparing)",
        "Serotonin",
        "Dopamine",
        "Engages 5-HT2B — the valvular-heart-disease antitarget. Chronic 5-HT2B agonism is what made fenfluramine cardiotoxic, so it is a mechanistic flag for repeated or heavy dosing.",
        "Often mis-sold as MDMA / “molly,” but it is pharmacologically a reuptake blocker — longer, more stimulant and anxiogenic, and more dangerous on an empathogen-style redose.",
        "%@ may raise %@ levels.",
        "%@ may lower %@ levels.",
        "Predicted",
        "Time to peak",
        "Protein binding",
        "Distribution",
        "Clearance",
        "Peak level",
        "Fraction-of-clearance estimates and major metabolites from primary literature. Which enzymes clear a drug is what grapefruit, smoking, and interacting medications act on — see Metabolism Interactions below.",
        "Derived from this substance's graded DAT/NET/SERT bindings. Transporter potencies are mostly within-assay ratios, not absolute cross-platform numbers.",
        "Human",
        "Rat",
        "Mouse",
        "Animal",
        "In-vitro",
        "Aggregated",
        "human assay",
        "rat assay",
        "mouse assay",
        "animal assay",
        "in-vitro assay",
        "aggregator source",
        "Evidence source: %@, %@",
        "May reduce hormonal birth-control efficacy",
        "Induces %@, which clears the hormones in the combined pill, patch, ring, implant and hormonal IUD — lowering their levels. Anyone relying on hormonal contraception should consider a backup method. Often noted on the label, but easy to miss.",
        "Modafinil",
        "Armodafinil",
        "Modafinil induces CYP3A4, lowering the levels of drugs cleared by it — including the hormones in systemic contraception.",
        "Armodafinil induces CYP3A4, lowering the levels of drugs cleared by it — including the hormones in systemic contraception.",
        "Same class, opposite behavior",
        "Gabapentin vs pregabalin — one absorbing target, two opposite dose curves",
        "Gabapentin — falls with dose",
        "Pregabalin — flat ~90%",
        "Fraction reaching your blood (up the side) against dose (along the bottom, as a multiple of the usual starting dose).",
        "Bioavailability versus dose: gabapentin falls as the dose rises, pregabalin stays flat.",
        "Saturable absorption — exposure climbs slower than dose",
        "%@× the dose is only about %@× the exposure — past the knee, extra drug mostly isn't absorbed.",
        "Tramadol → O-DSMT (M1)",
        "The carrier is already saturating across the normal dose range: bioavailability falls from ~60% at 900 mg/day to ~27% at 4800 mg/day, so each step up buys progressively less.",
        "There is no fixed milligram knee — the limit (or its absence) is set by your CYP2D6 activity. Poor metabolizers get little opioid effect but keep tramadol's serotonin/seizure risk; ultra-rapid metabolizers blow past the usual ceiling.",
        "Two drugs that hit the same target behave oppositely as you scale the dose: gabapentin's absorbed fraction falls, pregabalin's stays put.",
        "Both bind the α2δ-1 calcium-channel subunit — but gabapentin rides a saturable intestinal carrier (system-L / LAT1), so the fraction absorbed drops as the dose climbs (~60% → ~27%) and exposure flattens out. That's why gabapentin is dosed several times a day and why very large single doses buy little extra. Pregabalin uses the carrier without saturating it, so it stays ~90% absorbed at any dose — predictable, dose-proportional, simpler to titrate. (Pregabalin is also effective at far fewer milligrams, so its line sits at the low end of the dose axis.)",
        "Gabapentin is absorbed by a carrier that runs out of capacity, so the fraction that reaches your blood DROPS as the dose climbs — taking twice as much delivers much less than twice the exposure.",
        "This is the opposite of the alcohol/phenytoin ceiling: there the clearing enzyme saturates and exposure runs away upward; here the absorbing transporter (system-L / LAT1) saturates and exposure flattens out — a built-in brake, not a danger, though it also caps the benefit of very large single doses and is why gabapentin is dosed several times a day. Pregabalin, the same drug class, uses the transporter differently and stays ~90% absorbed at any dose (dose-linear) — a clean contrast in the same family. Shown as relative shape, not absolute level.",
        "Tramadol only becomes a strong opioid after CYP2D6 converts it to M1 — and how much you make depends on your genes, not just the dose. Most people plateau; “ultra-rapid metabolizers” have no such cap and can reach dangerous levels at ordinary doses.",
        "This is the mirror image of codeine: same CYP2D6 activation step, opposite danger. Two cautions. (1) Repeated dosing raises tramadol's own absorption (first-pass saturates, F climbs ~75%→90–100%), so steady-state levels run higher than a single dose predicts. (2) The opioid limb is carried almost entirely by the metabolite M1/O-DSMT (a potent 3.4 nM µ-agonist), so strong CYP2D6 inhibitors (paroxetine, fluoxetine, bupropion, quinidine) mute the painkilling effect while leaving — or raising — the serotonergic and seizure risk of the parent. “Cleaner” is not “safer.” Described, not drawn.",
        # Pharmacology axis Stage 3b — Combined depression index (2026-06-21)
        "Combined depression",
        "Combined respiratory depression peaks around %@.",
        "Severe",
        "High",
        "Moderate",
        "Predicted from receptor occupancy · %@.",
        "Estimated from effect curves · %@.",
        "%lld of %lld substances from receptor occupancy, the rest estimated from effect curves · %@.",
        "Predicted combined depression · %@.",
        "%@ combined depression · predicted (model, %@).",
        # Pharmacology axis Stage 3c — effect attenuation (2026-06-21)
        "serotonin transporter",
        "Reduced effect",
        "%@ may feel weaker — %@ blocks the %@ it needs to work.",
        "Predicted ~%@ reduced effect · predicted (model, %@). Reduced effect, not a danger warning.",
        "%@ blocks the %@ that %@ needs to work, so %@ is predicted to feel ~%@ weaker.",
        "This is a reduced effect, not a danger warning · predicted (model, %@).",
        # Pharmacology axis Stage 4a — cross-tolerance readout (2026-06-21)
        "Reduced response predicted — ~%lld%% of rested.",
        "Shared %@ tolerance · predicted (model, %@).",
        "Shared %@ tolerance from %@ · predicted (model, %@).",
        # Pharmacology axis Stage 4c — metabolic modulation (2026-06-21)
        "%@ may raise %@ levels (%@).",
        "%@ may lower %@ levels (%@).",
        "Repeated %@ doses build up faster than the dose suggests.",
        "%@ · predicted (model, %@).",
        "I smoke tobacco regularly",
        "Grapefruit dose logging",
        "Metabolic Effects",
        "Metabolism Interactions",
        "Had grapefruit with this dose",
        "Tobacco smoke speeds up CYP1A2, so it lowers the levels of some drugs (like caffeine and olanzapine). Grapefruit slows down CYP3A4, raising the levels of others — turn on grapefruit logging to mark it on individual doses of affected substances. Both are shown only where they actually change a drug's levels.",
        "How grapefruit, smoking, and this drug's own metabolism can change its levels. Educational — predicted from typical pharmacokinetics, not measured for you.",
        "Grapefruit",
        "Tobacco smoking",
        "Ritonavir",
        "Fluvoxamine",
        "Carbamazepine",
        "Rifampicin",
        "St John's Wort",
        "MDMA",
        "Grapefruit (and related citrus) inhibits intestinal CYP3A4 for roughly 1–3 days, raising the levels of drugs cleared by it.",
        "Tobacco smoke induces CYP1A2, lowering the levels of drugs cleared by it. Quitting reverses this over about a week and can raise levels.",
        "Ritonavir strongly inhibits CYP3A4, sharply raising the levels of drugs cleared by it.",
        "Fluvoxamine strongly inhibits CYP1A2, raising the levels of drugs cleared by it.",
        "Carbamazepine induces CYP3A4, lowering the levels of drugs cleared by it.",
        "Rifampicin strongly induces CYP3A4, markedly lowering the levels of drugs cleared by it.",
        "St John's Wort induces CYP3A4, lowering the levels of drugs cleared by it (magnitude varies by product).",
        "MDMA inactivates the CYP2D6 that clears it, so repeated or closely-spaced doses build up disproportionately rather than in proportion to the dose. The enzyme recovers over about 10 days.",
        # Antidepressant + empathogen reframed as myth-buster (2026-06-21)
        "SSRIs blunt MDMA — it may feel much weaker or not work. On their own they don't cause serotonin syndrome.",
        "SNRIs blunt MDMA — it may feel weaker. On their own they don't cause serotonin syndrome.",
        "TCAs blunt MDMA — it may feel weaker. On their own they don't cause serotonin syndrome.",
        # Serotonergic special cases — evidence-grounded (Foundation-C run, 2026-06-22)
        "SSRIs usually blunt MDMA — it may feel much weaker, so people often redose into trouble (overheating, heart strain). On their own they don't cause serotonin syndrome.",
        "SNRIs usually blunt MDMA — it may feel weaker, so people often redose into trouble (overheating, heart strain). On their own they don't cause serotonin syndrome.",
        "TCAs usually blunt MDMA rather than boosting it, so people may redose; the bigger concern is added strain on heart rate and blood pressure.",
        "Serotonin syndrome risk — these drugs add serotonin on top of an empathogen's surge. Some (tramadol, meperidine) can also trigger seizures.",
        "Serotonin syndrome — potentially fatal. Do not combine.",
        "Serotonin syndrome risk — two serotonin-raising drugs stacked together.",
        "Serotonin syndrome risk — a serotonin-raising drug stacked with an SSRI.",
        "Serotonin syndrome risk — a serotonin-raising drug stacked with an SNRI.",
        "Serotonin syndrome risk — a serotonin-raising drug stacked with a tricyclic antidepressant.",
        "Increased serotonin syndrome risk — lithium adds to the serotonergic load.",
        # Alpha-2 agonists + beta-blockers (Foundation-C run, 2026-06-22)
        "Heavy sedation with a dangerously slow heart rate and breathing. Naloxone reverses the opioid but NOT the alpha-2 part — give rescue breaths and call for help even after naloxone.",
        "Adds up sedation and lowers blood pressure further — expect stronger drowsiness and dizziness. Use less and don't drive.",
        "Compounded sedation and low blood pressure — stronger drowsiness and dizziness.",
        "Additive sedation and low blood pressure — increased drowsiness and dizziness.",
        "Tricyclics can cancel out clonidine-type blood-pressure lowering, so blood pressure may rise — a medical issue more than an overdose risk.",
        "Don't stop the clonidine-type drug suddenly while on a beta-blocker — it can spike blood pressure to dangerous levels. Taper it slowly.",
        "The old “never mix” warning is largely a medical myth — large reviews found no real harm. Both still strain the heart, so it isn't a green light to combine them.",
        "Both can lower blood pressure and add to dizziness — you may feel faint, especially standing up.",
        # Pharmacology axis Stage 4d — combination metabolite / cocaethylene (2026-06-22)
        "Combination Products",
        "Cocaethylene",
        "Cocaine and alcohol together form cocaethylene — an active stimulant your body makes only while both are present. It lasts noticeably longer than cocaine, so the stimulant effect (and its strain) is drawn out.",
        'Cocaethylene adds extra strain on the heart and liver beyond cocaine alone, so this combination is harder on your body. (The widely-repeated "18–25× sudden death" figure is not supported by the evidence — but the added cardiac and liver strain is real, so it\'s worth avoiding the mix.)',
        # Pharmacology axis Stage 2 — Tolerance tool (2026-06-21)
        "Tolerance",
        "Predicted receptor tolerance and recovery",
        "Psychedelics (5-HT2A)",
        "Opioids (μ)",
        "Stimulants (DAT/NET)",
        "Serotonin releasers (SERT)",
        "GABA (benzos / alcohol)",
        "Dissociatives (NMDA)",
        "Cannabinoids (CB1)",
        "Adenosine (caffeine)",
        "Nicotinic (nAChR)",
        "Predicted, not measured",
        "These are model predictions of how repeated use changes each receptor's responsiveness — never a measurement. Tolerance is shown per mechanism, because one universal “tolerance %” is wrong for some classes (stimulants especially).",
        "Nothing to show yet",
        "Log doses of substances with receptor data and your predicted tolerance will appear here. Targets you haven't engaged recently read as fully rested.",
        "Shared by %@ — tolerance to one carries to the others.",
        "· from %@",
        "Predicted response vs. rested: ~%lld%%",
        "Recovery-state load: low",
        "Recovery-state load: moderate",
        "Recovery-state load: high",
        "Stimulant tolerance isn't one number you can multiply a dose by. The fast part is within a session (a redose lands weaker); the slow part is a months-long recovery state, not a “take more” signal.",
        "The slow change here is a SERT-binding association, reversible-leaning — not proven neurotoxicity, and not a dose multiplier. It's a recovery-state indicator.",
        "Nicotine tolerance is mostly fast receptor desensitization that recovers between uses — a single “tolerance %” wouldn't capture it.",
        "The slow axis here is a recovery-state indicator, not an effect multiplier.",
        "A redose right now would land ~%lld%% as strong — within-session tachyphylaxis, recovers overnight.",
        "After a break your opioid tolerance drops — the dose that felt fine before can stop your breathing. Hypoxia is sudden, with no warning. Restart low, and keep naloxone accessible to someone who's with you.",
        "Repeated GABA depressant use builds dependence; abrupt stops after heavy use can be dangerous. Taper rather than quitting cold.",
        "%@ to ~90%% if you stop now.",
        "%@ to clear if you stop now.",
        "Nearly recovered.",
        "~%lld months",
        "~%lld weeks",
        "~%lld days",
        "~%lld hours",
        "under an hour",
        # Pharmacology axis Stage 0 — confidence tiers + body-weight UI (2026-06-21)
        "High confidence",
        "Medium confidence",
        "Low confidence",
        "Unverified",
        "Body Weight",
        "Your weight",
        "Not set",
        "Source",
        "Estimated — set your weight for more accurate estimates.",
        "Apple Health",
        "Entered manually",
        "Estimated (default 60 kg)",
        "Why we ask",
        "Your weight is the denominator that turns a dose into an exposure: the same dose hits harder the less you weigh. With it, Piru can estimate things like how strong a drink is for *your* body, and how repeated use builds tolerance. Without it, those numbers fall back to an average adult and are marked estimated.",
        "Set manually",
        "Enter a number.",
        "Enter a weight between 20 and 300 kg.",
        "Use Apple Health",
        "Updated from Apple Health.",
        "Couldn't read a weight from Health. If you've used Health before, Piru may not have access.",
        "Open Settings",
        "Apple Health isn't available on this device.",
        "Piru reads your latest body weight from Health, read-only. You can turn this off anytime in Settings ▸ Health ▸ Data Access.",
        "Use the estimated default",
        "Reverts to the average-adult default (60 kg). Estimates will be marked estimated.",
        "Estimated",
        "Use Body Weight",
        "Read your weight from Apple Health so estimates fit your body — a drink hits harder the less you weigh. Read-only; change anytime in Settings.",
        "Weight",
        "kg",
        "Couldn't read a weight from Health. You may not have granted access, or haven't recorded a weight there yet.",
        # Bottom-accessory "Log a dose" CTA 2026-06
        "Log a dose",
        # Search redesign 2026-06
        "Recently Searched",
        "Browse by class",
        "Search Library instead",
        "Help & Safety",
        "Crisis resources, harm-reduction basics, and how Piru works.",
        "Class Not Found",
        "This class isn’t in the library anymore.",
        "Clear",
        # Cake joke entry 2026-06
        "Made-up drug",
        "A fictional drug from a 1997 TV satire on media drug panics — “Cake” isn’t real, and nothing below is either. It supposedly overstimulates “Shatner’s Bassoon,” the part of the brain that governs time. Made in Prague.",
        # Detail-view Design D 2026-06
        "Dose & Duration",
        # FreeOD Wiki overview section 2026-06
        "Overview",
        "Machine-translated from FreeOD Wiki",
        # Substance detail polish 2026-06 (Overview read-more + caution overflow)
        "Read more",
        "Read less",
        "+%lld more",
        "Show All",
        "Default route",
        "Experience reports",
        "PubChem CID",
        "First-hand reports from Erowid's Experience Vaults. Opens a search in your browser.",
        "Each link opens this substance's page on that source. Always verify against the original.",
        # Detail-view restructure 2026-06
        "Search experiences on Erowid",
        "All effects",
        "All effects (%lld)",
        "Press and hold a value to copy it.",
        "Physical",
        "Cognitive",
        "Visual",
        "Auditory",
        "Tactile",
        "Multisensory",
        "Sensory",
        "Smell and taste",
        "Transpersonal",
        "Disconnective",
        # DB cleanup 2026-06
        "Other / Miscellaneous",
        "Everything that doesn't fit a class above.",
        "Limited data",
        "Sources & references",
        "Databases",
        "Primary literature",
        "The databases and primary literature behind this compound's data. Tap to open; always verify against the original source.",
        # Library redesign — family titles, blurbs, sub-class blurbs, renames
        "Stimulants",
        "Empathogens",
        "Hallucinogens",
        "Cannabinoids",
        "Opioids",
        "Sedatives & Depressants",
        "Peptides",
        "Mind & Cognition",
        "Pharmaceuticals",
        "Supplements",
        "Research Chemicals",
        "Sedative-Hypnotic",
        "Everyday substances, by the names most people know.",
        "Energy, focus, and wakefulness.",
        "Warmth, empathy, and emotional openness.",
        "Alter perception, thought, and sense of reality.",
        "Relaxation, euphoria, and altered senses.",
        "Pain relief, euphoria, and sedation.",
        "Calm and slow the central nervous system.",
        "GLP-1, healing, and research peptides.",
        "Mood, psychiatric, and cognitive medications.",
        "Clinical medications, by therapeutic class.",
        "Vitamins, minerals, and nutrients.",
        "Novel and lesser-characterized compounds.",
        "Serotonergic — LSD, psilocybin, mescaline.",
        "NMDA antagonists — ketamine, DXM, PCP.",
        "Anticholinergic — DPH, datura, Benadryl.",
        "Atypical tryptamines — DiPT, 5-MeO-MiPT.",
        "GABA-A modulators — diazepam, alprazolam.",
        "GABA-active — GHB, phenibut, gabapentin.",
        "Barbiturates, sedative-hypnotics, and Z-drugs.",
        "SSRIs, SNRIs, and MAOIs.",
        "Dopamine antagonists — quetiapine, risperidone.",
        "Racetams, choline, and cognitive aids.",
        "AMPA-receptor positive modulators.",
        "Wakefulness — modafinil, armodafinil.",
        "Non-opioid pain relief — NSAIDs, paracetamol.",
        "Allergy and sleep antihistamines.",
        "Blood pressure, heart, and cholesterol.",
        "Antibiotics, antivirals, and antifungals.",
        "Acid, nausea, and gut motility.",
        "Inhalers, decongestants, and cough.",
        "Hormones, thyroid, and metabolic drugs.",
        "Immune modulators and steroids.",
        "Seizure and mood-stabilizing drugs.",
        "Highest overdose risk",
        "This calculator uses a one-compartment oral pharmacokinetic model with absorption and elimination phases. Absorption rates are estimated from known duration profiles (onset + comeup timing) when available, or use a default 4× elimination rate ratio. Population-average elimination half-lives are sourced from FDA-approved prescribing information, published pharmacokinetic studies (PubMed), and DrugBank. Half-lives for some research chemicals and novel substances are estimated from structurally similar compounds and may be less reliable.\n\nReal pharmacokinetics vary significantly based on individual metabolism, genetics, liver and kidney function, body composition, age, drug interactions, tolerance, and route of administration. Multi-compartment distribution, protein binding, active metabolites, and enterohepatic recirculation are not accounted for. Polydrug use may alter elimination rates unpredictably.\n\nThese figures are approximate population averages — not a substitute for clinical monitoring or professional medical advice. Always consult a qualified healthcare professional.",
        "My Substances",
        "Notifications",
        "Preferences",
        "Data",
        "Day Grouping",
        "None yet",
        "No Substance Colors",
        "No Substances Yet",
        "Create or personalize substances — adjust dose ranges, duration, and units to match your own data and tolerance.",
        "Doses logged before this hour count toward the previous day — so a 2 AM dose stays with the night before instead of starting a new day at midnight. Set to 12 AM for standard calendar days.",
        "Pharmacological data is compiled from the sources above — community harm-reduction databases, FDA labeling, and peer-reviewed literature. Provided for harm-reduction and educational purposes only. Always consult a qualified healthcare professional before making decisions about substance use.",
        "Colors appear here after you log your first entry. Tap one to change it.",
        "Substances you create or personalize appear here. You can also create them from the Quick Log search.",
        "Move to Session…",
        "Move %@",
        "New Session",
        "Pull this dose into its own session.",
        "Move To",
        "Filter",
        "Nowhere to Move",
        "This is the only session.",
        "Move",
        "Set Time",
        "New time on %@",
        "%@ is logged on a different day. Pick a time within this session's day so the session stays a single day.",
        "Location",
        "Current Location",
        "Results",
        "Add Location",
        "Change Location",
        "Remove location",
        "Search for a place or address",
        "Location access is off. Turn it on in Settings to use your current location.",
        "Piru Backup",
        "A complete backup you can restore into Piru",
        "PsychonautWiki Format",
        "For importing into the PsychonautWiki app",
        "Data & Backup",
        "iCloud Backup",
        "Export",
        "Encrypted Backup…",
        "Passphrase-protected — save or send it anywhere",
        "Import & Restore",
        "Import from a File…",
        "A Piru or PsychonautWiki JSON file",
        "Restore Encrypted Backup…",
        "A passphrase-protected .piruenc file",
        "From your automatic iCloud backups",
        "Import Failed",
        "Import Complete",
        "Your data was imported.",
        "Export and import your journal under Data & Backup above.",
        "Export, import, and encrypted backups to iCloud or a passphrase-protected file. Backups are optional and off by default.",
        "Piru and PsychonautWiki files are plain, unencrypted JSON. An encrypted backup is protected by a passphrase you choose — **if you forget it, the file cannot be opened, not even by us.**",
        "Imported entries are added to your journal (duplicates are skipped). Encrypted restores can merge or replace; iCloud and your own passphrase backups unlock automatically or prompt for the passphrase.",
        "Report",
        "A PDF summary to share with a clinician",
        "Delete Failed",
        "Permanently removes every dose, session, and setting. A recoverable snapshot is taken first.",
        "Share session log",
        # Quick-log dose tray
        "%lld min ago",
        "Pick date & time…",
        "Remove",
        "When",
        "Log Dose",
        "Log %lld Doses",
        "Add note…",
        "Collapse",
        "Collapses the editor",
        "Shared time",
        "Custom…",
        "Discard staged doses?",
        "Discard Doses",
        "Keep Logging",
        "Show %lld more doses",
        "Custom dose",
        "Active dose details",
        # Quick-log v2 — morphing dock, Daily routine card
        "Add another…",
        "Remove from Tray",
        "Routine",
        "Log all",
        "%lld left",
        "Back to staged doses",
        "≈%@ %@ active · %@ left",
        "≈%@ %@ active",
        "≈%@ %@ active · %@ ago · %@ left",
        "≈%@ %@ active · %@ ago",
        "≈%@ %@ of your %@ %@ dose (%@) is still active — ~%lld%%",
        "Fixed Order",
        "Create custom substance",
        "Find a Place…",
        "Recents",
        "Edit Favorites",
        "Time for your %@ routine.",
        "No Routines",
        "New Routine",
        "Unassigned",
        "e.g. Morning, Pre-workout, Night",
        "Routine Name",
        "Time of day",
        "Remind Me",
        "A notification repeats daily at this time.",
        "Items",
        "Edit Item",
        "Delete Routine",
        "Group the meds and supplements you take together — Pre-workout, Night — and stage a whole set with one tap.",
        "Edit Routine…",
        "Manage Routines…",
        "Clear search",
        "Common %@–%@ %@",
        "Routines",
        "No Routine Items",
        "Add the meds and supplements you take regularly.",
        "Group items into routines by time of day or purpose — a routine stages everything in it with one tap on the Log screen. Drag items onto a category to assign them.",
        "%@ — %lld item%@",
        "%lld item%@",
        "Uncategorized — %lld item%@",
        # 2026-06 review fixes
        "Emergency: 911",
        "Poison Control: 1-800-222-1222",
        "Crisis Lifeline: 988",
        "Crisis Text: HOME to 741741",
        "Call 911 (US) or your local emergency number",
        "1-800-222-1222 (US)",
        "988 Suicide & Crisis Lifeline",
        "Call or text 988",
        "Text HOME to 741741",
        "1-800-662-4357 — Free, confidential, 24/7",
        "^[%lld substance](inflect: true)",
        "^[%lld entry](inflect: true)",
        "^[%lld item](inflect: true)",
        "κ-opioid agonists — salvia, salvinorin A.",
        "GABAergics & gabapentinoids — GHB, pregabalin, phenibut.",
        "^[%lld saved substance](inflect: true).",
        "Substance Not Found",
        "“%@” isn’t in the library anymore. It may have been renamed or merged.",
        "Back",
        "Expand Chart",
        "Collapse Chart",
        "Previous Month",
        "Next Month",
        "Add Routine",
        "Add Custom Substance",
        "Log %@ %@",
        "Concentration curve",
        "Elimination curve for %@",
        "%@ %@ remaining, %lld%% eliminated, half-life %@",
        "Peak after %@, %@ of %@ %@ remaining now",
        "Enter a valid 6-digit hex code",
        "This shade already exists in the preset palette",
        "You've already created this shade",
        # Salt-form picker title (options are chemical proper nouns, not localized)
        "Form",
        # Elemental-content breakdown for salts (Magnesium, Lithium…)
        "≈ %@ %@ elemental",
        "%lld%% elemental",
        # Stage 4 — chemistry card + pharmacokinetics disclosure 2026-06
        "Pharmacokinetics",
        "Metabolism",
        "Population-average pharmacokinetics from primary literature with per-row source attribution. Real values vary with genetics, organ function, and route.",
        "Physicochemical values are predicted/computed (PubChem, NPS-DataHub), not measured for this preparation.",
        "LD50 is rodent toxicity (order of magnitude) — not a human safe dose.",
        "IUPAC name",
        "H-bond acceptors",
        "H-bond donors",
        "Melting point",
        "Boiling point",
        "LD50 (oral, rodent)",
        "LD50 (dermal, rodent)",
        "active",
        "inactive",
        # Scientific symbols — identical in zh (no translation), but still
        # catalog keys because gridCell takes a LocalizedStringResource.
        "SMILES",
        "LogP",
        "LogD",
        "TPSA",
        "pKa",
        # Stacked-lane timeline preference 2026-06
        "Stack Busy Sessions",
        "Stack From",
        "When a session reaches this many different substances, the timeline splits overlapping curves into separate stacked lanes — one per substance — so a busy session stays readable. When off, every curve is always overlaid on one graph.",
        # Pharmacology axis Stage 6 — Ceiling Effect tool (2026-06-22)
        "Ceiling Effect",
        "When dose and exposure aren't proportional",
        "When dose and effect aren't proportional",
        "For most substances, twice the dose means roughly twice the exposure. For these few, an enzyme runs out of capacity — so exposure can climb much faster than the dose (a warning), or an effect can stop climbing entirely (a ceiling). Shapes are model predictions, relative — not absolute concentrations.",
        "Each line is one dose; its height is the level in your blood and the area under it is your total exposure. Time is in days.",
        "Each line is one dose; its height is the level in your blood and the area under it is your total exposure. Time is in hours.",
        "Ceiling on effect — described, not drawn (no precise dose knee).",
        "Steep, supralinear — described, not drawn (no reliable human kinetics).",
        "Saturable elimination — exposure climbs faster than dose",
        "Saturable activation — effect hits a ceiling",
        "1 drink",
        "%lld drinks",
        "%lld mg",
        "Alcohol (ethanol)",
        "Phenytoin",
        "GHB / GBL",
        "Codeine → morphine",
        "Clearance is capped at ~1 drink/hour, so each extra drink stacks on top of the last and lingers — total exposure climbs far faster than the number of drinks.",
        "Elimination is already maxed out after about one drink, so there is no “safe extra” that clears as fast as the first.",
        "Alcohol is the classic zero-order drug: above a very low blood level the enzyme that clears it (alcohol dehydrogenase) is fully saturated and works at a fixed rate. Doubling the drinks more than doubles how long alcohol stays in your system and the area under the curve. Chronic heavy drinking speeds clearance somewhat (CYP2E1 induction); the ALDH2 “flush” variant does the opposite for acetaldehyde.",
        "The clearing enzyme is already half-saturated inside the normal dose range, so a small dose increase near the top can roughly double the level into toxicity.",
        "Saturation begins within the therapeutic window itself — the curve bends up where most other drugs would still be a straight line.",
        "Phenytoin is hydroxylated by a saturable liver enzyme system (CYP2C9/CYP2C19). Because its Km lies below the therapeutic range, dose and level are not proportional: titrate in small steps and confirm with blood levels. CYP2C9/2C19 poor metabolizers, age, and interacting drugs shift the knee lower. Shown as relative shape — phenytoin is individualized by therapeutic drug monitoring.",
        "Codeine only works by being converted to morphine, and most people's CYP2D6 enzyme caps how much morphine they can make — so past a point, more codeine adds side-effects and duration, not more pain relief.",
        "The limit is set by how much CYP2D6 enzyme you have, not by a specific milligram dose. The analgesic plateau around ~60 mg is a clinical observation, not a kinetic ceiling.",
        "This ceiling is on the opioid effect only — not on codeine's other risks. Two big caveats: “ultra-rapid metabolizers” convert far more codeine to morphine and can reach dangerous levels at ordinary doses (the FDA contraindicates codeine in them), while “poor metabolizers” get little relief. So this is not a green light to take more.",
        "Exposure rises steeply and faster than dose — a small step up can disproportionately increase how much your body sees. The gap between a recreational and a dangerous dose is small.",
        "Nonlinearity appears already at moderate recreational doses: a controlled study saw ~40% more exposure going from 25 to 35 mg/kg, and the regulated product's exposure rises ~3.8× when the dose doubles.",
        "GHB's clearing pathway saturates, so dose and effect are not proportional and the margin for error is thin. Measure precisely, wait fully between doses (never re-dose because “it hasn't hit yet”), and treat any other depressant — especially alcohol — as compounding the danger. Liver impairment lowers the threshold further. No reliable human Km/Vmax exists, so the direction is shown without a drawn curve.",
        # Pharmacology axis Stage 6 — Benzo equivalence converter (2026-06-23)
        "Benzo Equivalence",
        "Compare benzodiazepine doses to diazepam",
        "Compare benzodiazepine doses against diazepam, or convert between two — the way clinicians do when switching for a taper.",
        "mg",
        "Equivalent Dose",
        "≈ %@ mg",
        "%@ mg %@ ≈ %@ mg %@",
        "(≈ %@ mg diazepam)",
        "Approximate — equivalence tables disagree. Treat this as a ballpark, not a precise dose.",
        "Enter a dose to convert.",
        "No numeric equivalence is available for this substance.",
        "No numeric equivalence is available for the target substance.",
        "Pick both substances and a dose.",
        "Cited equivalence",
        "Source: TripSit benzodiazepine dataset. Equivalences vary by reference (Ashton, manufacturer, clinical); these are a guide, not a single clinical truth.",
        "A cross-taper usually switches from a short- to a long-half-life benzo: the longer drug self-tapers more smoothly. Diazepam's long-acting active metabolites stretch its effective half-life well beyond the parent.",
        "This converts and compares — it is not a taper schedule. Plan any dose reduction with a clinician.",
        "Never stop a benzodiazepine abruptly. Withdrawal can be dangerous (seizures); a slow taper is the safe path.",
        "Single-dose equivalence isn't steady-state equivalence — long-acting metabolites accumulate over days.",
        "Equivalences are approximate and contested. Use the cited value as a starting estimate, not a precise dose.",
        "~%lld min",
        "~%@ h",
        "~%lld h",
        "Search benzodiazepines",
        "Select Benzodiazepine",
        # Pharmacology axis Stage 5 — Cannabis vertical / 11-OH-THC (2026-06-23)
        "11-OH-THC",
        "11-OH-THC (edibles)",
        "Swallowed THC passes through your liver first, which turns much of it into 11-hydroxy-THC — an active by-product that reaches the brain more easily and binds the CB1 receptor far more strongly than THC itself. That's why an edible tends to feel stronger, milligram for milligram, than the same amount smoked.",
        "Edibles also come on slowly — usually 30 minutes to 2 hours — and last much longer, often 6–10 hours. That slow start is the redose trap: wait at least 2 hours before taking more, or you can stack a far stronger, longer dose than you meant to.",
        "Based on first-pass metabolism of oral THC · educational, not a measured level. Onset and duration vary with dose, product, and tolerance.",
        # Alcohol by-volume input (2026-06-22)
        "By Drink",
        "By Weight",
        "Volume",
        "Strength",
        "% ABV",
        "Optional",
        "Beer",
        "Wine",
        "Shot",
        "Pint",
        "Enter a volume and strength",
        "ethanol · ≈ %@ standard drinks",
        "%lld g",
        "Input",
        "Volume unit",
        # Alcohol ALDH2 / acetaldehyde (2026-06-22, Stage 5)
        "I get the alcohol flush",
        "Tobacco smoke speeds up CYP1A2, so it lowers the levels of some drugs (like caffeine and olanzapine). Grapefruit slows down CYP3A4, raising the levels of others — turn on grapefruit logging to mark it on individual doses of affected substances. The alcohol flush (facial redness, fast heartbeat, nausea after a little alcohol) signals the ALDH2 variant — turn it on to see acetaldehyde, the toxic by-product it lets build up, on alcohol entries. All three are shown only where they actually change a drug's levels or risk.",
        "Acetaldehyde",
        "Acetaldehyde (ALDH2)",
        "Elevated",
        "Very high",
        "Your ALDH2 variant clears acetaldehyde — the first, toxic by-product of alcohol — slowly, so it builds up and lingers. That build-up *is* the flush, racing heart, and nausea, and it's a Group 1 carcinogen (IARC): for flush-reactive drinkers each drink carries more long-term throat and oesophageal cancer risk. Less alcohol means less acetaldehyde — there's no amount that clears as cleanly as it does for others.",
        "Avoid mixing alcohol with metronidazole or certain other antibiotics — they block this same step and can make even a small drink severe.",
        "Based on your self-reported alcohol flush · educational, not a measured level.",
        # Opioid safety axis (2026-06-22, Stage 5)
        "Your tolerance has dropped",
        "If a dose is too much, you don't feel it coming — breathing just stops and you black out with no warning. There's no moment where you notice and react.",
        "And you can't use naloxone (Narcan) on yourself once that happens. Have someone with you who can, keep naloxone where they can reach it, and start much lower than your old dose.",
        "After about a %lld-day break your opioid tolerance has fallen to roughly %lld%% of full — close to none. A dose that felt fine before the break can stop your breathing now. This is the most common way people overdose.",
        "Predicted from your logged use (model, %@).",
        # Tolerance-mechanism explainer (2026-06-22, Stage 5)
        "How tolerance works",
        "Three kinds of tolerance",
        "Availability — the real tolerance",
        "With repeated use a receptor gets less responsive, so the same dose does less. We show it as your predicted response versus rested (≈X%). It recovers when you stop — over days to weeks depending on the receptor. This is the honest “tolerance” for opioids, psychedelics, benzodiazepines, dissociatives, and cannabis.",
        "Within-session redose",
        "Separately, a second dose the same session often lands weaker — fast desensitization (tachyphylaxis). It recovers overnight, so it's shown apart from the slow tolerance above. Chasing it with more rarely works and stacks risk.",
        "Recovery-state load — not a multiplier",
        "For stimulants and serotonin releasers there is no honest “tolerance %” to multiply a dose by. The slow change is a months-long recovery state of the whole system, not a take-more signal. We show that as a bounded load bar instead of a fake number — refusing to imply a dose you should escalate to.",
        "These are model predictions of how repeated use changes each receptor — never a measurement. Each figure carries a confidence tier.",
        "Cross-tolerance",
        "Tolerance is shared by receptor, not by name",
        "Two different drugs that hit the same receptor share tolerance. Recent LSD lowers a mushroom trip because both work at 5-HT2A; one benzodiazepine carries to another; one opioid to the next. That's why tolerance here is tracked per receptor target, and why a “new” drug in the same family can still be blunted.",
        "By mechanism",
        "Recovery timescales and tolerance behaviour are calibrated to the published literature for each receptor class. The note under each is the calibration basis; the badge is how well-established those kinetics are.",
        "Dose-response tolerance",
        "Recovery-state load",
        "Recovers in days",
        "Recovers over ~a week",
        "Recovers over weeks",
        "Recovers over a month+",
        "Recovers over months",
        "Strong and fast: a second trip soon after is much weaker. Resets within a few days.",
        "Real tolerance that resets after a break — which is exactly what makes returning to an old dose dangerous.",
        "Tolerance plus physical dependence; stopping abruptly after heavy regular use can be dangerous — taper.",
        "Builds its own tolerance, and can also blunt opioid tolerance when taken together.",
        "Fast and real, but recovers fairly quickly once you stop.",
        "Clean, predictable tolerance — the caffeine case, the textbook example.",
        "No single “tolerance %” fits: a fast within-session fade plus a slow, months-long recovery state — not a signal to take more.",
        "A reversible-leaning change at the serotonin transporter — a recovery-state indicator, not a dose multiplier.",
        "Mostly fast receptor desensitization that recovers between uses rather than a lasting dose multiplier.",
        "Where the numbers come from",
        "Binding affinities come from the NIMH PDSP Kᵢ database and primary literature; the tolerance kinetics are calibrated to published human recovery studies. Every parameter is graded, and anything resting on a class default is flagged. Nothing here is measured from you — it's predicted from your dose log and these curated values.",
    }

    print("--- Piru main app catalog ---")
    n, added, missing = apply_translations(
        project_root / "Piru/Localizable.xcstrings", T, insert_keys=NEW_KEYS
    )
    print(f"Translated: {n}  (inserted {len(added)} new key(s))")
    for a in added:
        print(f"  + {a!r}")
    print(f"Missing: {len(missing)}")
    for m in missing[:30]:
        print(f"  - {m!r}")

    print()
    print("--- Widget catalog ---")
    # Widget reuses many Shared model strings (RouteOfAdministration, DoseFrequency, etc.)
    # Keep the widget's insert set to just the handful of strings the widget target
    # actually shows, so it stays a small subset.
    WIDGET_NEW_KEYS = {
        "Session",
        "No active session",
        "Current Session",
        "See your current session's doses at a glance.",
    }
    widget_dict = {**T, **WT}
    n, added, missing = apply_translations(
        project_root / "PiruWidget/Localizable.xcstrings", widget_dict, insert_keys=WIDGET_NEW_KEYS
    )
    print(f"Translated: {n}  (inserted {len(added)} new key(s))")
    for a in added:
        print(f"  + {a!r}")
    print(f"Missing: {len(missing)}")
    for m in missing:
        print(f"  - {m!r}")

    # Hand both catalogs back to Xcode so it re-collates every key into its
    # canonical order — this is what stops the IDE from churning the file on the
    # next build. Done last, after all translations are filled, so the export
    # captures the freshly-inserted keys. Skipped gracefully if xcodebuild is
    # unavailable (the Python serialization above is still valid, just unsorted).
    print()
    print("--- Canonicalizing key order via Xcode (export/import round-trip) ---")
    if canonicalize_catalogs(project_root / "Piru.xcodeproj"):
        print("Done — catalogs rewritten in Xcode's canonical order.")
