#!/usr/bin/env python3
"""Apply zh-Hans and zh-Hant translations to a Localizable.xcstrings catalog."""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

# Translations: English -> (Simplified, Traditional)
T = {
    # b46 feedback batches (2026-09-01)
    "Backups, export & import are under Tools › Data & Backup; preferences are under Settings.": (
        "备份、导出与导入在「工具 › 数据与备份」；偏好设置在「设置」。",
        "備份、匯出與匯入在「工具 › 資料與備份」；偏好設定在「設定」。",
    ),
    "That's everything today — %lld days and counting": (
        "今天的都完成了 — 已连续 %lld 天",
        "今天的都完成了 — 已連續 %lld 天",
    ),
    "That's everything today": ("今天的都完成了", "今天的都完成了"),
    "Scale by Dose Strength": ("按剂量强度缩放", "依劑量強度縮放"),
    "· %lld of %lld": ("· 已服 %1$lld / %2$lld", "· 已服 %1$lld / %2$lld"),
    "%lld of %lld logged today": ("今天已记录 %1$lld / %2$lld", "今天已記錄 %1$lld / %2$lld"),
    "Dose Times": ("用药时间", "用藥時間"),
    "Edit Dose Times…": ("编辑用药时间…", "編輯用藥時間…"),
    "The quick offsets in the “Now” menu when logging a dose.": (
        "记录剂量时“现在”菜单中的快捷时间偏移。",
        "記錄劑量時「現在」選單中的快捷時間偏移。",
    ),
    "Colors": ("颜色", "顏色"),
    "A color for every substance you log": (
        "为你记录的每种物质配一个颜色",
        "為你記錄的每種物質配一個顏色",
    ),
    "^[%lld substances](inflect: true) with a color": ("%lld 种物质已配色", "%lld 種物質已配色"),
    "Export, import, and encrypted backups": ("导出、导入与加密备份", "匯出、匯入與加密備份"),
    "Which source wins when they disagree, and opt-in updates to the bundled substance data.": (
        "来源冲突时以哪个为准，以及内置物质数据的自选更新。",
        "來源衝突時以哪個為準，以及內建物質資料的自選更新。",
    ),
    "Tap a dot to name it": ("点一下圆点显示名称", "點一下圓點顯示名稱"),
    "Name on plot": ("在图上显示名称", "在圖上顯示名稱"),
    "%@, this substance": ("%@，当前物质", "%@，目前物質"),
    "%@, measured in the same study": ("%@，同一研究中测得", "%@，同一研究中測得"),
    # Unified timeline (Journal → Active Now / Timeline grouping)
    "No Entries Yet": (
        "还没有记录",
        "還沒有記錄",
    ),
    "Your dose timeline will appear here once you log something.": (
        "记录第一笔用药后，剂量时间线会显示在这里。",
        "記錄第一筆用藥後，劑量時間線會顯示在這裡。",
    ),
    "Projected · %@": (
        "预测 · %@",
        "預測 · %@",
    ),
    "Compress empty time": (
        "压缩空闲时间",
        "壓縮空閒時間",
    ),
    "Effect curves": (
        "效果曲线",
        "效果曲線",
    ),
    "How strongly effects are felt over time": (
        "随时间感受到的效果强度",
        "隨時間感受到的效果強度",
    ),
    "Body load (PK)": (
        "体内残留（药代）",
        "體內殘留（藥代）",
    ),
    "How much is estimated to remain in your body": (
        "估计体内剩余的量",
        "估計體內剩餘的量",
    ),
    "Display Options": (
        "显示选项",
        "顯示選項",
    ),
    "Previous Year": (
        "上一年",
        "上一年",
    ),
    "Next Year": (
        "下一年",
        "下一年",
    ),
    "^[%lld substances](inflect: true) you added or customized": (
        "你添加或自定义的 %lld 种物质",
        "你新增或自訂的 %lld 種物質",
    ),
    # The three category floors rewritten so they stop asserting an efficacy or a
    # generation for every member they describe (7-OH read "Full Agonist" above its own
    # partial-agonist rows).
    "μ-Opioid Receptor Ligand": (
        "μ-阿片受体配体",
        "μ-鴉片受體配體",
    ),
    "Acts at μ-opioid receptors (MOR), G-protein coupled receptors distributed throughout the central and peripheral nervous system. MOR activation inhibits adenylyl cyclase, opens inwardly rectifying potassium channels, and closes voltage-gated calcium channels, reducing neuronal excitability and neurotransmitter release — producing analgesia, euphoria, respiratory depression, and slowed gastrointestinal transit. How far this particular compound activates the receptor, and whether it also engages κ or δ, is not characterized here; the receptor panel below carries whatever has been measured for it.": (
        "作用于 μ-阿片受体（MOR）——一类分布于中枢与外周神经系统的 G 蛋白偶联受体。MOR 激活会抑制腺苷酸环化酶、开放内向整流钾通道并关闭电压门控钙通道，降低神经元兴奋性与神经递质释放，产生镇痛、欣快、呼吸抑制以及胃肠蠕动减慢。此处未说明该化合物对受体的激活程度，也未说明它是否同时作用于 κ 或 δ；下方的受体面板列出的是已实测到的数据。",
        "作用於 μ-鴉片受體（MOR）——一類分布於中樞與周邊神經系統的 G 蛋白偶聯受體。MOR 活化會抑制腺苷酸環化酶、開放內向整流鉀通道並關閉電壓閘控鈣通道，降低神經元興奮性與神經傳導物質釋放，產生鎮痛、欣快、呼吸抑制以及胃腸蠕動減慢。此處未說明該化合物對受體的活化程度，也未說明它是否同時作用於 κ 或 δ；下方的受體面板列出的是已實測到的資料。",
    ),
    "Antipsychotic (Dopamine Receptor Antagonist)": (
        "抗精神病药（多巴胺受体拮抗剂）",
        "抗精神病藥（多巴胺受體拮抗劑）",
    ),
    "Blocks dopamine D2 receptors in the mesolimbic pathway, reducing positive psychotic symptoms. Whether this compound also carries the 5-HT2A antagonism that distinguishes the second-generation agents, and the histamine, muscarinic and adrenergic activity that drives sedation and orthostasis, varies across the class and is not characterized here.": (
        "阻断中脑边缘通路的多巴胺 D2 受体，减轻精神病性阳性症状。该化合物是否同时具有区分第二代药物的 5-HT2A 拮抗作用，以及导致镇静与体位性低血压的组胺、毒蕈碱与肾上腺素能活性，在同类药物中各不相同，此处未作说明。",
        "阻斷中腦邊緣通路的多巴胺 D2 受體，減輕精神病性陽性症狀。該化合物是否同時具有區分第二代藥物的 5-HT2A 拮抗作用，以及導致鎮靜與姿勢性低血壓的組織胺、蕈毒鹼與腎上腺素能活性，在同類藥物中各不相同，此處未作說明。",
    ),
    "Histamine H1 Receptor Antagonist": (
        "组胺 H1 受体拮抗剂",
        "組織胺 H1 受體拮抗劑",
    ),
    "Blocks histamine H1 receptors, reducing the itching, flare, wheal and vasodilation of the histamine response. Whether this compound crosses into the central nervous system — the difference between a sedating first-generation antihistamine with a muscarinic load and a peripherally selective second-generation one — is not characterized here.": (
        "阻断组胺 H1 受体，减轻组胺反应中的瘙痒、红晕、风团与血管扩张。该化合物是否进入中枢神经系统——这正是具有毒蕈碱负荷、会引起嗜睡的第一代抗组胺药与外周选择性的第二代抗组胺药之间的区别——此处未作说明。",
        "阻斷組織胺 H1 受體，減輕組織胺反應中的搔癢、紅暈、風疹塊與血管擴張。該化合物是否進入中樞神經系統——這正是具有蕈毒鹼負荷、會引起嗜睡的第一代抗組織胺藥與周邊選擇性的第二代抗組織胺藥之間的區別——此處未作說明。",
    ),
    # The methamphetamine class-mechanism description — the one MOA template literal that was
    # never translated, found when the class prose moved into the bundled DB.
    "Enters dopamine (DAT), norepinephrine (NET), and serotonin (SERT) nerve terminals and reverses their transporters, releasing all three monoamines. Also agonizes TAAR1 and acts at VMAT2 to redistribute vesicular monoamines into the cytosol.": (
        "进入多巴胺（DAT）、去甲肾上腺素（NET）与血清素（SERT）能神经末梢，使其转运体反向运作，释放这三种单胺。同时激动 TAAR1，并作用于 VMAT2，将囊泡内的单胺重新分布到胞质中。",
        "進入多巴胺（DAT）、正腎上腺素（NET）與血清素（SERT）能神經末梢，使其轉運體反向運作，釋放這三種單胺。同時激動 TAAR1，並作用於 VMAT2，將囊泡內的單胺重新分布到胞質中。",
    ),
    # The opioid converter's picker label for transdermal fentanyl: fentanyl shares
    # one substance row across every route, so the route is what disambiguates it.
    "%@ (transdermal)": ("%@（透皮贴）", "%@（穿皮貼片）"),
    # Why the converter will not convert methadone. CDC 2022 does publish a single
    # factor (4.7) for population-level accounting; Piru declines to use it, so the
    # copy states Piru's choice rather than a claim about CDC.
    "Methadone's half-life is long and variable, and its peak effect on breathing arrives later and lasts longer than its peak pain relief — so a converted dose can look adequate while the risk is still building. CDC publishes a single factor for population-level accounting; Piru will not use it to convert a dose. This one belongs to a clinician.": (
        "美沙酮的半衰期长且个体差异大，对呼吸的最强抑制出现得比镇痛高峰更晚、持续更久——因此换算出的剂量看起来足够时，风险可能仍在累积。CDC 确实公布了一个用于人群统计的换算系数，但 Piru 不会用它来换算剂量。这一项应交由临床医生处理。",
        "美沙酮的半衰期長且個體差異大，對呼吸的最強抑制出現得比鎮痛高峰更晚、持續更久——因此換算出的劑量看起來足夠時，風險可能仍在累積。CDC 確實公布了一個用於人群統計的換算係數，但 Piru 不會用它來換算劑量。這一項應交由臨床醫師處理。",
    ),
    # Why transdermal fentanyl cannot share the mg-based table.
    "Transdermal fentanyl is dosed in micrograms per hour — a rate, not a mass, so it shares no unit space with the mg-based table (CDC gives 2.4 MME per mcg/hr). Absorption also changes with heat and other factors.": (
        "透皮芬太尼以每小时微克数给药——那是速率而非质量，与以毫克为单位的换算表不在同一单位体系（CDC 给出每 mcg/hr 折合 2.4 MME）。其吸收还会随体温和其他因素变化。",
        "穿皮吩坦尼以每小時微克數給藥——那是速率而非質量，與以毫克為單位的換算表不在同一單位體系（CDC 給出每 mcg/hr 折合 2.4 MME）。其吸收還會隨體溫和其他因素變化。",
    ),
    # Why buprenorphine is excluded from MME entirely.
    "Buprenorphine is a partial agonist with a ceiling on its effect on breathing, so risk doesn't scale the way a full agonist's does. CDC excludes it from MME entirely and says it should not be counted toward a daily total.": (
        "丁丙诺啡是部分激动剂，对呼吸的抑制存在封顶效应，因此风险不会像完全激动剂那样随剂量线性上升。CDC 将其完全排除在 MME 之外，并指出不应计入每日总量。",
        "丁丙諾啡是部分激動劑，對呼吸的抑制存在封頂效應，因此風險不會像完全激動劑那樣隨劑量線性上升。CDC 將其完全排除在 MME 之外，並指出不應計入每日總量。",
    ),
    # The signalling cascade's own label in the pharmacology card, so it does
    # not read as a second mechanism description.
    "Downstream": ("下游", "下游"),
    # Shown in place of "Fully eliminated" when no half-life is known, so an
    # unmodelable dose is not reported as gone.
    "No half-life data": ("无半衰期数据", "無半衰期數據"),
    # Contraindication flag labels — Piru's own wording for a normalized
    # label contraindication (see Piru/Domain/ContraindicationFlag.swift).
    "Known allergy to it": ("已知对它过敏", "已知對它過敏"),
    "With an MAOI, or within 14 days of one": (
        "与单胺氧化酶抑制剂同用，或停药 14 天内",
        "與單胺氧化酶抑制劑同用，或停藥 14 天內",
    ),
    "With other CNS depressants": ("与其他中枢神经抑制剂同用", "與其他中樞神經抑制劑同用"),
    "With a strong CYP3A4 inhibitor": ("与强效 CYP3A4 抑制剂同用", "與強效 CYP3A4 抑制劑同用"),
    "With a QT-prolonging drug": ("与延长 QT 间期的药物同用", "與延長 QT 間期的藥物同用"),
    "With a live vaccine": ("与活疫苗同用", "與活疫苗同用"),
    "With a nitrate or a guanylate cyclase stimulator": (
        "与硝酸酯类或鸟苷酸环化酶激动剂同用",
        "與硝酸酯類或鳥苷酸環化酶激動劑同用",
    ),
    "With alcohol": ("与酒精同用", "與酒精同用"),
    "With an anticoagulant": ("与抗凝药同用", "與抗凝藥同用"),
    "Existing respiratory depression": ("已有呼吸抑制", "已有呼吸抑制"),
    "During an acute asthma attack": ("哮喘急性发作期间", "氣喘急性發作期間"),
    "Bowel obstruction": ("肠梗阻", "腸阻塞"),
    "Active bleeding": ("活动性出血", "活動性出血"),
    "Liver disease": ("肝病", "肝病"),
    "Kidney disease": ("肾病", "腎病"),
    "Anuria": ("无尿", "無尿"),
    "Recent heart attack or heart surgery": ("近期心肌梗死或心脏手术", "近期心肌梗塞或心臟手術"),
    "Uncontrolled high blood pressure": ("血压控制不佳", "血壓控制不佳"),
    "Heart rhythm disorder": ("心律失常", "心律不整"),
    "Heart failure": ("心力衰竭", "心臟衰竭"),
    "Seizure disorder": ("癫痫", "癲癇"),
    "Narrow-angle glaucoma": ("闭角型青光眼", "閉角型青光眼"),
    "Urinary retention": ("尿潴留", "尿滯留"),
    "Adrenal insufficiency": ("肾上腺功能不全", "腎上腺功能不全"),
    "Systemic fungal infection": ("全身性真菌感染", "全身性真菌感染"),
    "Porphyria": ("卟啉症", "紫質症"),
    "Pheochromocytoma": ("嗜铬细胞瘤", "嗜鉻細胞瘤"),
    "Untreated thyroid disease": ("未经治疗的甲状腺疾病", "未經治療的甲狀腺疾病"),
    "Pregnancy": ("妊娠", "懷孕"),
    "Breastfeeding": ("哺乳", "哺乳"),
    "Children": ("儿童", "兒童"),
    "Eating disorder": ("进食障碍", "飲食障礙"),
    "Myasthenia gravis": ("重症肌无力", "重症肌無力"),
    "Sleep apnea": ("睡眠呼吸暂停", "睡眠呼吸中止"),
    "Smoking over the age of 35": ("35 岁以上且吸烟", "35 歲以上且吸菸"),
    "During low blood sugar": ("低血糖期间", "低血糖期間"),
    "Low potassium": ("低血钾", "低血鉀"),
    "High potassium": ("高血钾", "高血鉀"),
    "Personal or family history of thyroid cancer": (
        "本人或家族有甲状腺癌病史",
        "本人或家族有甲狀腺癌病史",
    ),
    "Marked anxiety or agitation": ("明显焦虑或激越", "明顯焦慮或激動"),
    "Around surgery": ("手术前后", "手術前後"),
    "Patterns": ("规律", "規律"),
    "Log doses to see your patterns": ("记录剂量以查看你的规律", "記錄劑量以查看你的規律"),
    "Days used, cumulative exposure, dose trend, and overlap — for you or your doctor": (
        "用药天数、累积暴露、剂量趋势与重叠——供你或你的医生参考",
        "用藥天數、累積暴露、劑量趨勢與重疊——供你或你的醫生參考",
    ),
    "Days used, exposure, dose trend, and overlap": (
        "用药天数、暴露、剂量趋势与重叠",
        "用藥天數、暴露、劑量趨勢與重疊",
    ),
    "Log some doses to see your patterns.": (
        "记录一些剂量以查看你的规律。",
        "記錄一些劑量以查看你的規律。",
    ),
    # Reports & Export hub (Insights → Reports)
    "Reports": ("报告", "報告"),
    "Export sessions, generate clinical reports": (
        "导出记录、生成临床报告",
        "匯出記錄、產生臨床報告",
    ),
    "Latest": ("最近", "最近"),
    "By Date": ("按日期", "按日期"),
    "Select sessions": ("选择记录", "選擇記錄"),
    "Select Sessions": ("选择记录", "選擇記錄"),
    "%lld of %lld sessions": ("%lld / %lld 条记录", "%lld / %lld 條記錄"),
    "No entries in this range": ("此范围内没有条目", "此範圍內沒有條目"),
    "Clinical Report": ("临床报告", "臨床報告"),
    "Key findings, medication summary, dose trends — for your doctor": (
        "关键发现、用药概要、剂量趋势——供你的医生参考",
        "關鍵發現、用藥概要、劑量趨勢——供你的醫生參考",
    ),
    "Session Images": ("记录图片", "記錄圖片"),
    "Stitched Image": ("拼接图片", "拼接圖片"),
    "All selected sessions in one tall image": (
        "所有选中记录合成为一张长图",
        "所有選中記錄合成為一張長圖",
    ),
    "Plain-text session data — for notes, AI, or records": (
        "纯文本记录数据——用于笔记、AI 或存档",
        "純文字記錄資料——用於筆記、AI 或存檔",
    ),
    "· %lld entries": ("· %lld 条记录", "· %lld 條記錄"),
    "%lld sessions as individual images": (
        "%lld 条记录导出为单独图片",
        "%lld 條記錄匯出為單獨圖片",
    ),
    "Sessions in this range as individual images": (
        "此范围内的记录导出为单独图片",
        "此範圍內的記錄匯出為單獨圖片",
    ),
    "No sessions yet": ("暂无记录", "暫無記錄"),
    "Nothing to Summarize": ("暂无可汇总内容", "暫無可彙總內容"),
    "Nothing logged in this range.": ("此范围内没有记录。", "此範圍內沒有記錄。"),
    "A record and a model, not medical advice. Exposure uses clinical equivalents where they're established, and the substance's typical dose otherwise.": (
        "这是记录与模型，并非医疗建议。暴露在有公认临床当量时采用当量，否则采用该物质的常见剂量。",
        "這是記錄與模型，並非醫療建議。暴露在有公認臨床當量時採用當量，否則採用該物質的常見劑量。",
    ),
    "Days used": ("用药天数", "用藥天數"),
    "How often, across this range": ("此范围内的用药频率", "此範圍內的用藥頻率"),
    "of %lld days": ("共 %lld 天", "共 %lld 天"),
    "of days": ("天数占比", "天數占比"),
    "longest break": ("最长间断", "最長間斷"),
    "since last": ("距上次", "距上次"),
    "Cumulative exposure": ("累积暴露", "累積暴露"),
    "Total taken this range, in each substance's clinical or common-dose unit": (
        "此范围内的总量，以各物质的临床当量或常见剂量为单位",
        "此範圍內的總量，以各物質的臨床當量或常見劑量為單位",
    ),
    "Benzodiazepines ≈ %@ mg diazepam-eq/day": (
        "苯二氮䓬类 ≈ %@ mg 地西泮当量/天",
        "苯二氮平類 ≈ %@ mg 地西泮當量/天",
    ),
    "Opioids: peak day ≈ %@ MME": ("阿片类：单日峰值 ≈ %@ MME", "鴉片類：單日峰值 ≈ %@ MME"),
    "below the CDC 50 MME/day reference": (
        "低于 CDC 50 MME/天 参考线",
        "低於 CDC 50 MME/天 參考線",
    ),
    "at or above the CDC 50 MME/day reference": (
        "达到或超过 CDC 50 MME/天 参考线",
        "達到或超過 CDC 50 MME/天 參考線",
    ),
    "at or above the CDC 90 MME/day reference": (
        "达到或超过 CDC 90 MME/天 参考线",
        "達到或超過 CDC 90 MME/天 參考線",
    ),
    "Average %@ MME/day over the range": ("此范围内平均 %@ MME/天", "此範圍內平均 %@ MME/天"),
    "%@: %@ %@ total": ("%@：共 %@ %@", "%@：共 %@ %@"),
    "Dose trend": ("剂量趋势", "劑量趨勢"),
    "Whether your typical dose has moved over this range": (
        "你的常用剂量在此范围内是否有变化",
        "你的常用劑量在此範圍內是否有變化",
    ),
    "steady": ("平稳", "平穩"),
    "rising": ("上升", "上升"),
    "falling": ("下降", "下降"),
    "%@: dose %@, %@": ("%@：剂量%@，%@", "%@：劑量%@，%@"),
    "Active together": ("同时活跃", "同時活躍"),
    "Hours two substances were both in your body at once": (
        "两种物质同时在体内的小时数",
        "兩種物質同時在體內的小時數",
    ),
    "%@ and %@: %@ active together": ("%@ 与 %@：同时活跃 %@", "%@ 與 %@：同時活躍 %@"),
    "MME": ("MME", "MME"),
    "mg diazepam-eq": ("mg 地西泮当量", "mg 地西泮當量"),
    "common doses": ("常见剂量", "常見劑量"),
    "In your body over time": ("体内留存变化", "體內留存變化"),
    "Estimated amount still circulating, each line a share of its own peak": (
        "估算仍在循环的量，每条线为各自峰值的占比",
        "估算仍在循環的量，每條線為各自峰值的占比",
    ),
    "How much of each substance has been circulating, day by day": (
        "逐日显示每种物质在体内循环的量",
        "逐日顯示每種物質在體內循環的量",
    ),
    "Log some doses to see what's been in your body over time.": (
        "记录一些剂量，查看体内留存随时间的变化。",
        "記錄一些劑量，查看體內留存隨時間的變化。",
    ),
    "Nothing to Model": ("暂无可建模数据", "暫無可建模資料"),
    "None of your logged substances in this range have a modeled elimination curve.": (
        "此范围内记录的物质都没有可建模的消除曲线。",
        "此範圍內記錄的物質都沒有可建模的消除曲線。",
    ),
    "An estimate from a one-compartment model, not a measurement. How much is in your body doesn't always match how strong the effects feel, or how long a substance stays detectable.": (
        "这是单室模型的估算，并非实测。体内留存量与主观感受强度或可检出时长不一定一致。",
        "這是單室模型的估算，並非實測。體內留存量與主觀感受強度或可檢出時長不一定一致。",
    ),
    "Nothing in your body at this time": ("此刻体内没有留存", "此刻體內沒有留存"),
    "Tolerance & Receptors": ("耐受与受体", "耐受與受體"),
    "Your streak and this month's rate": ("你的连续天数与本月比例", "你的連續天數與本月比例"),
    "When and how much you log": ("你在何时、记录了多少", "你在何時、記錄了多少"),
    "Predicted per-mechanism tolerance": ("按机制预测的耐受", "按機制預測的耐受"),
    "What's still active in your body right now": (
        "此刻体内仍在起作用的物质",
        "此刻體內仍在起作用的物質",
    ),
    "How body-load has moved over time": ("体内留存随时间的变化", "體內留存隨時間的變化"),
    "Receptor load over time": ("受体负荷变化", "受體負荷變化"),
    "Receptor Load": ("受体负荷", "受體負荷"),
    "How hard each mechanism has been driven, relative to your recent baseline": (
        "相对于近期基线，各机制被驱动的程度",
        "相對於近期基線，各機制被驅動的程度",
    ),
    "How hard each mechanism has been driven over time": (
        "各机制随时间被驱动的程度",
        "各機制隨時間被驅動的程度",
    ),
    "Log some doses to see how your receptors have been driven.": (
        "记录一些剂量，查看受体被驱动的情况。",
        "記錄一些劑量，查看受體被驅動的情況。",
    ),
    "None of your logged substances in this range drive a modeled mechanism.": (
        "此范围内记录的物质都不驱动任何可建模的机制。",
        "此範圍內記錄的物質都不驅動任何可建模的機制。",
    ),
    "A predicted relative load from your logged doses, not a measurement. It's a model of receptor drive, not of how you feel.": (
        "这是根据记录剂量预测的相对负荷，并非实测。它建模的是受体驱动，而非你的主观感受。",
        "這是根據記錄劑量預測的相對負荷，並非實測。它建模的是受體驅動，而非你的主觀感受。",
    ),
    "Nothing driven at this time": ("此刻没有被驱动的机制", "此刻沒有被驅動的機制"),
    "Toggles this mechanism's line": ("切换该机制的曲线", "切換該機制的曲線"),
    "Steady state": ("稳态", "穩態"),
    "Where a regular dose settles, from your own cadence": (
        "按你自己的节奏，规律剂量最终稳定在何处",
        "按你自己的節奏，規律劑量最終穩定在何處",
    ),
    "No Steady Cadence Yet": ("尚无规律的用药节奏", "尚無規律的用藥節奏"),
    "Steady state needs a regular schedule. Log a substance on a consistent cadence and its plateau appears here.": (
        "稳态需要规律的用药安排。按固定节奏记录某种物质，其平台值就会显示在这里。",
        "穩態需要規律的用藥安排。按固定節奏記錄某種物質，其平台值就會顯示在這裡。",
    ),
    "A projection from your median dose and spacing, assuming you keep that cadence and linear kinetics. Body content in the dose's units, not a plasma level.": (
        "这是根据你的中位剂量与间隔做出的推算，假设你保持该节奏且动力学为线性。数值为以该剂量单位计的体内含量，而非血药浓度。",
        "這是根據你的中位劑量與間隔做出的推算，假設你保持該節奏且動力學為線性。數值為以該劑量單位計的體內含量，而非血藥濃度。",
    ),
    "Plateau": ("平台", "平台"),
    "Buildup": ("累积", "累積"),
    "Reaches": ("达到", "達到"),
    "Between doses": ("两次用药之间", "兩次用藥之間"),
    "about daily": ("约每天", "約每天"),
    "about every 2 days": ("约每2天", "約每2天"),
    "<1 day": ("不到1天", "不到1天"),
    "clears, no buildup": ("清除，无累积", "清除，無累積"),
    "every ~%lld h": ("约每 %lld 小时", "約每 %lld 小時"),
    "every ~%@ days": ("约每 %@ 天", "約每 %@ 天"),
    "Accumulation curve for %@": ("%@ 的累积曲线", "%@ 的累積曲線"),
    "Plateaus around %@, %@× one dose, reached in %@": (
        "稳定在约 %@，为单次剂量的 %@ 倍，在 %@ 内达到",
        "穩定在約 %@，為單次劑量的 %@ 倍，在 %@ 內達到",
    ),
    "Clears between doses; each peaks around %@": (
        "两次用药之间清除；每次峰值约 %@",
        "兩次用藥之間清除；每次峰值約 %@",
    ),
    "%@ now at %@ %@": ("%@ 现为 %@ %@", "%@ 現為 %@ %@"),
    "%@ now at %@": ("%@ 现为 %@", "%@ 現為 %@"),
    # ---- Steady State tool (Aug 2026) ----
    "On a fixed schedule, each dose lands on the tail of the last and the level climbs until intake and clearance balance — steady state.": (
        "按固定间隔用药时，每一剂都叠加在上一剂的尾部，体内水平不断上升，直到摄入与清除达到平衡——即稳态。",
        "按固定間隔用藥時，每一劑都疊加在上一劑的尾部，體內水平不斷上升，直到攝入與清除達到平衡——即穩態。",
    ),
    "Values are body content in the dose's units, not a plasma concentration. Real accumulation varies with metabolism, dosing gaps, and metabolites.": (
        "数值为以剂量单位表示的体内含量，而非血浆浓度。实际蓄积会因代谢、用药间隔和代谢物而异。",
        "數值為以劑量單位表示的體內含量，而非血漿濃度。實際蓄積會因代謝、用藥間隔和代謝物而異。",
    ),
    "Uses the same one-compartment oral model, assuming a regular schedule and linear kinetics. Values are body content in the dose's units, not a plasma concentration. Real accumulation varies with metabolism, dosing gaps, and active metabolites.": (
        "使用相同的单室口服模型，假设规律用药且动力学为线性。数值为以剂量单位表示的体内含量，而非血浆浓度。实际蓄积会因代谢、用药间隔和活性代谢物而异。",
        "使用相同的單室口服模型，假設規律用藥且動力學為線性。數值為以劑量單位表示的體內含量，而非血漿濃度。實際蓄積會因代謝、用藥間隔和活性代謝物而異。",
    ),
    "Steady State": ("稳态", "穩態"),
    "steady state": ("稳态", "穩態"),
    "Where a repeated dose settles, and when": (
        "重复用药最终稳定在何处，以及需要多久",
        "重複用藥最終穩定在何處，以及需要多久",
    ),
    "Where a med taken every day settles": (
        "每天服用的药物会稳定在何处",
        "每天服用的藥物會穩定在何處",
    ),
    "The Half-Life Calculator models one dose fading out. A dose repeated on a schedule instead lands on the tail of the last, and the level climbs until intake and clearance balance — steady state.": (
        "半衰期计算器模拟单次剂量的消退。而按固定间隔重复用药时，每一剂都叠加在上一剂的尾部，体内水平不断上升，直到摄入与清除达到平衡——这就是稳态。",
        "半衰期計算器模擬單次劑量的消退。而按固定間隔重複用藥時，每一劑都疊加在上一劑的尾部，體內水平不斷上升，直到攝入與清除達到平衡——這就是穩態。",
    ),
    "Dose each time": ("每次剂量", "每次劑量"),
    "Taken every": ("用药间隔", "用藥間隔"),
    "Every 4 hours": ("每 4 小时", "每 4 小時"),
    "Every 6 hours": ("每 6 小时", "每 6 小時"),
    "Every 8 hours": ("每 8 小时", "每 8 小時"),
    "Every 12 hours": ("每 12 小时", "每 12 小時"),
    "Once daily": ("每天一次", "每天一次"),
    "Twice daily": ("每天两次", "每天兩次"),
    "Barely accumulates": ("几乎不蓄积", "幾乎不蓄積"),
    "Accumulates modestly": ("适度蓄积", "適度蓄積"),
    "Accumulates substantially": ("明显蓄积", "明顯蓄積"),
    "Each dose has mostly cleared before the next, so the level tracks a single dose.": (
        "在下一剂之前，每一剂大多已被清除，因此体内水平与单次剂量相当。",
        "在下一劑之前，每一劑大多已被清除，因此體內水平與單次劑量相當。",
    ),
    "The level settles around %@ a single dose, reaching steady state in about %@.": (
        "体内水平稳定在单次剂量的约 %@，约 %@ 达到稳态。",
        "體內水平穩定在單次劑量的約 %@，約 %@ 達到穩態。",
    ),
    "Doses stack faster than they clear — the level climbs to roughly %@ a single dose and takes about %@ to get there.": (
        "用药速度快于清除速度——体内水平升至单次剂量的约 %@，约需 %@ 才能达到。",
        "用藥速度快於清除速度——體內水平升至單次劑量的約 %@，約需 %@ 才能達到。",
    ),
    "Level over time — climbing to plateau": (
        "随时间变化的水平——逐渐升至平台",
        "隨時間變化的水平——逐漸升至平台",
    ),
    "Estimated amount in your body, in %@. The shaded band is the steady-state range once the level stops climbing; the dashed line is a single dose.": (
        "体内估计量，单位为 %@。阴影带是水平不再上升后的稳态范围；虚线表示单次剂量。",
        "體內估計量，單位為 %@。陰影帶是水平不再上升後的穩態範圍；虛線表示單次劑量。",
    ),
    "At steady state": ("稳态时", "穩態時"),
    "Steady state by": ("达到稳态", "達到穩態"),
    "fully settled in %@": ("%@ 完全稳定", "%@ 完全穩定"),
    "Accumulation": ("蓄积", "蓄積"),
    "at the peak, vs. one dose": ("峰值时，相对于单次剂量", "峰值時，相對於單次劑量"),
    "Plateau range": ("平台范围", "平台範圍"),
    "%@ · trough to peak": ("%@ · 谷值到峰值", "%@ · 谷值到峰值"),
    "Fluctuation": ("波动", "波動"),
    "smooth": ("平稳", "平穩"),
    "moderate swing": ("中等波动", "中等波動"),
    "spiky": ("起伏大", "起伏大"),
    "Time to steady state depends only on the half-life — not the dose or how often you take it. A bigger dose or shorter gap raises the plateau; it doesn't arrive sooner.": (
        "达到稳态的时间只取决于半衰期——与剂量或用药频率无关。更大的剂量或更短的间隔会抬高平台，但不会更快达到。",
        "達到穩態的時間只取決於半衰期——與劑量或用藥頻率無關。更大的劑量或更短的間隔會抬高平台，但不會更快達到。",
    ),
    "This projects a perfectly regular schedule onto the same one-compartment oral model the Half-Life Calculator uses, assuming dose-proportional (linear) kinetics. Amounts are body content in the dose's units — not a plasma concentration, which would need an individual volume of distribution. Real accumulation varies with metabolism, missed or extra doses, active metabolites, and saturable elimination. A model of the pharmacology, not a dosing plan — it says what a level does, never what a dose should be. Not medical advice.": (
        "本工具在半衰期计算器所用的同一单室口服模型上，假设一个完全规律的用药方案，并假定动力学与剂量成正比（线性）。所示数值为以剂量单位表示的体内含量，而非血浆浓度——后者需要个体的分布容积。实际蓄积会因代谢、漏服或加服、活性代谢物以及可饱和消除而异。这是对药理学的建模，而非用药方案——它说明水平如何变化，绝不建议剂量。非医疗建议。",
        "本工具在半衰期計算器所用的同一單室口服模型上，假設一個完全規律的用藥方案，並假定動力學與劑量成正比（線性）。所示數值為以劑量單位表示的體內含量，而非血漿濃度——後者需要個體的分布容積。實際蓄積會因代謝、漏服或加服、活性代謝物以及可飽和消除而異。這是對藥理學的建模，而非用藥方案——它說明水平如何變化，絕不建議劑量。非醫療建議。",
    ),
    "%@ peak": ("%@ 峰值", "%@ 峰值"),
    "%@ trough": ("%@ 谷值", "%@ 谷值"),
    "days": ("天", "天"),
    "Climbs from one dose to a steady-state range of %@ to %@ %@, reached in about %lld days": (
        "从单次剂量上升到 %@ 到 %@ %@ 的稳态范围，约 %lld 天达到",
        "從單次劑量上升到 %@ 到 %@ %@ 的穩態範圍，約 %lld 天達到",
    ),
    "Taking this daily? See where the level settles": (
        "每天服用？看看会稳定在何处",
        "每天服用？看看會穩定在何處",
    ),
    "Where a med taken on a schedule settles": (
        "按固定间隔服用的药物会稳定在何处",
        "按固定間隔服用的藥物會穩定在何處",
    ),
    # ---- Benzo effect ladder + occupancy / withdrawal (Aug 2026) ----
    "Faded": ("已减弱", "已減弱"),
    "Unchanged": ("未变化", "未變化"),
    "strong evidence": ("证据充分", "證據充分"),
    "moderate evidence": ("证据中等", "證據中等"),
    "low evidence": ("证据较弱", "證據較弱"),
    "not measured": ("未测量", "未測量"),
    "%lld%% left": ("剩余 %lld%%", "剩餘 %lld%%"),
    "%lld percent left": ("剩余百分之 %lld", "剩餘百分之 %lld"),
    "%lld days": ("%lld 天", "%lld 天"),
    "Muscle relaxation": ("肌肉松弛", "肌肉鬆弛"),
    "Coordination": ("协调", "協調"),
    "Fades near-completely in ~2 weeks": ("约 2 周内几乎完全减弱", "約 2 週內幾乎完全減弱"),
    "The sleep effect tolerizes": ("助眠效果会产生耐受", "助眠效果會產生耐受"),
    "No decline detected": ("未检测到下降", "未偵測到下降"),
    "Fades slowly and partially, over months": ("数月内缓慢、部分减弱", "數月內緩慢、部分減弱"),
    "Develops; rate not quantified": ("会产生耐受；速率未量化", "會產生耐受；速率未量化"),
    "No tolerance detected": ("未检测到耐受", "未偵測到耐受"),
    "Receptor load": ("受体负荷", "受體負荷"),
    "About %lld%% of your recent peak GABA-A load right now, summed across everything active.": (
        "当前 GABA-A 负荷约为近期峰值的 %lld%%，已合并计入所有仍在起效的物质。",
        "目前 GABA-A 負荷約為近期峰值的 %lld%%，已合併計入所有仍在起效的物質。",
    ),
    "Combined load across your active GABAergics, relative to your recent peak.": (
        "你所有仍在起效的 GABA 类物质的合并负荷，相对于近期峰值。",
        "你所有仍在起效的 GABA 類物質的合併負荷，相對於近期峰值。",
    ),
    "Combined load across your active GABAergics, relative to your recent peak. Alcohol is included; it loads the receptor at a different site.": (
        "你所有仍在起效的 GABA 类物质的合并负荷，相对于近期峰值。已计入酒精；它作用于受体的另一位点。",
        "你所有仍在起效的 GABA 類物質的合併負荷，相對於近期峰值。已計入酒精；它作用於受體的另一位點。",
    ),
    "GABA-A receptor load over time": (
        "随时间变化的 GABA-A 受体负荷",
        "隨時間變化的 GABA-A 受體負荷",
    ),
    "Combined load relative to your recent peak, currently about %lld percent, clearing over the following days.": (
        "相对于近期峰值的合并负荷，目前约为百分之 %lld，将在随后几天内清除。",
        "相對於近期峰值的合併負荷，目前約為百分之 %lld，將在隨後幾天內清除。",
    ),
    'Three things people call "withdrawal" that behave differently, and roughly when each starts for drugs like the ones you\'ve logged.': (
        "人们所说的三种“戒断”，它们表现各不相同，以及对于你记录的这类药物，各自大致何时开始。",
        "人們所說的三種「戒斷」，它們表現各不相同，以及對於你記錄的這類藥物，各自大致何時開始。",
    ),
    "A model of your dose log, not medical advice. Stopping a benzodiazepine abruptly after regular use can cause seizures.": (
        "这是基于你用药记录的模型，并非医疗建议。规律使用后突然停用苯二氮䓬可能引发癫痫发作。",
        "這是基於你用藥記錄的模型，並非醫療建議。規律使用後突然停用苯二氮平可能引發癲癇發作。",
    ),
    "Estimating how much is still in your system…": (
        "正在估算你体内还剩多少……",
        "正在估算你體內還剩多少……",
    ),
    "Your modeled GABA-A load has essentially cleared — past the point where the drug itself is still leaving your system. The bands below say when symptoms tend to follow.": (
        "你的 GABA-A 负荷模型显示已基本清除——药物本身已过了仍在离开体内的阶段。下方的区间表示症状通常何时随之出现。",
        "你的 GABA-A 負荷模型顯示已基本清除——藥物本身已過了仍在離開體內的階段。下方的區間表示症狀通常何時隨之出現。",
    ),
    "under a day": ("不到一天", "不到一天"),
    "Your modeled GABA-A load is still about %lld%% of your recent peak — the drug is still clearing, so withdrawal hasn't started yet.": (
        "你的 GABA-A 负荷模型仍约为近期峰值的 %lld%%——药物仍在清除，因此戒断尚未开始。",
        "你的 GABA-A 負荷模型仍約為近期峰值的 %lld%%——藥物仍在清除，因此戒斷尚未開始。",
    ),
    "Your modeled GABA-A load is still about %lld%% of your recent peak — the drug is still clearing, so withdrawal hasn't started. On your current clearance it drops into the onset range in about %@.": (
        "你的 GABA-A 负荷模型仍约为近期峰值的 %1$lld%%——药物仍在清除，因此戒断尚未开始。按你目前的清除速度，大约再过 %2$@ 会进入起始区间。",
        "你的 GABA-A 負荷模型仍約為近期峰值的 %1$lld%%——藥物仍在清除，因此戒斷尚未開始。按你目前的清除速度，大約再過 %2$@ 會進入起始區間。",
    ),
    "Research findings, not medical advice. Benzodiazepine discontinuation can be medically dangerous.": (
        "这些是研究结果，并非医疗建议。停用苯二氮䓬在医学上可能有危险。",
        "這些是研究結果，並非醫療建議。停用苯二氮平在醫學上可能有危險。",
    ),
    "Effect-selective tolerance": ("效应选择性耐受", "效應選擇性耐受"),
    "Some effects fade, others don't": ("有些效应会减弱，有些不会", "有些效應會減弱，有些不會"),
    "For most drugs every effect tolerizes together. Benzodiazepines are the exception: sedation fades almost completely in about two weeks, while the anxiety relief, memory impairment and loss of coordination barely change. That's why the benzodiazepine card shows an effect ladder instead of one bar.": (
        "对大多数药物来说，所有效应会一起产生耐受。苯二氮䓬是个例外：镇静作用大约在两周内几乎完全减弱，而抗焦虑、记忆损害和协调能力下降却几乎不变。这就是为什么苯二氮䓬卡片显示的是效应阶梯，而不是单一条形。",
        "對大多數藥物來說，所有效應會一起產生耐受。苯二氮平是個例外：鎮靜作用大約在兩週內幾乎完全減弱，而抗焦慮、記憶損害和協調能力下降卻幾乎不變。這就是為什麼苯二氮平卡片顯示的是效應階梯，而不是單一條形。",
    ),
    "Why — the receptor comes in subtypes": ("原因——受体分为多种亚型", "原因——受體分為多種亞型"),
    "GABA-A is built from several α-subtypes that adapt at different rates. α1 carries sedation and desensitizes (it uncouples, then the receptors are pulled from the synapse); α5 is required for that sedative tolerance to develop at all; α2 and α3, which carry the anxiety relief, don't adapt. So the dose that no longer makes you sleepy impairs your memory and coordination exactly as much as it did on day one — which is how tolerance quietly drives the dose up.": (
        "GABA-A 由多种 α 亚型构成，它们以不同的速度适应。α1 负责镇静并会脱敏（先解偶联，随后受体被从突触中移除）；α5 是镇静耐受得以形成的必要条件；而负责抗焦虑的 α2 和 α3 并不适应。因此，那个不再让你困倦的剂量，对记忆和协调能力的损害与第一天完全一样——耐受就是这样悄悄把剂量推高的。",
        "GABA-A 由多種 α 亞型構成，它們以不同的速度適應。α1 負責鎮靜並會脫敏（先解偶聯，隨後受體被從突觸中移除）；α5 是鎮靜耐受得以形成的必要條件；而負責抗焦慮的 α2 和 α3 並不適應。因此，那個不再讓你睏倦的劑量，對記憶和協調能力的損害與第一天完全一樣——耐受就是這樣悄悄把劑量推高的。",
    ),
    "Benzodiazepine effect kinetics: Vinkers & Olivier 2012; Piot & Jovanovic 2026. These are directions from the literature, graded low — not fitted numbers.": (
        "苯二氮䓬效应动力学：Vinkers & Olivier 2012；Piot & Jovanovic 2026。这些是来自文献的方向性判断，评级为低——并非拟合数值。",
        "苯二氮平效應動力學：Vinkers & Olivier 2012；Piot & Jovanovic 2026。這些是來自文獻的方向性判斷，評級為低——並非擬合數值。",
    ),
    "Why these effects differ": ("这些效应为何不同", "這些效應為何不同"),
    "Prediction": ("预测", "預測"),
    "Prediction from a model": ("来自模型的预测", "來自模型的預測"),
    # ---- Custom units (Settings) ----
    "Custom Units": ("自定义单位", "自訂單位"),
    "No Custom Units": ("暂无自定义单位", "尚無自訂單位"),
    "Add Custom Unit": ("添加自定义单位", "新增自訂單位"),
    "Edit Custom Unit": ("编辑自定义单位", "編輯自訂單位"),
    "unit": ("单位", "單位"),
    "1 %@ =": ("1 %@ =", "1 %@ ="),
    "Unit label (e.g. capsule)": ("单位名称（如 胶囊）", "單位名稱（如 膠囊）"),
    'This substance already has a "%@" unit.': (
        "该物质已有“%@”单位。",
        "此物質已有「%@」單位。",
    ),
    "Logs in this unit convert to the mass automatically.": (
        "以该单位记录时会自动换算为质量。",
        "以此單位記錄時會自動換算為質量。",
    ),
    'Define a unit like "1 capsule = 30 mg" and it appears in the dose picker for that substance — log half a capsule, get 15 mg.': (
        "定义一个单位，例如“1 胶囊 = 30 mg”，它就会出现在该物质的剂量选择器中——记录半个胶囊，即得 15 mg。",
        "定義一個單位，例如「1 膠囊 = 30 mg」，它就會出現在該物質的劑量選擇器中——記錄半個膠囊，即得 15 mg。",
    ),
    # ---- Approximate dose flag ----
    "Approximate amount": ("近似用量", "近似用量"),
    "Shows the dose with a ~; the estimate still drives the curves.": (
        "剂量会显示为 ~；这个估计值仍会用于绘制曲线。",
        "劑量會顯示為 ~；這個估計值仍會用於繪製曲線。",
    ),
    "approximately %@ %@": ("大约 %@ %@", "大約 %@ %@"),
    # ---- Label scanner (camera → QuickLog) ----
    "Regular": ("常规", "常規"),
    "Racemic": ("外消旋", "外消旋"),
    # QuickLog "Form" pill accessibility label — the isomer × release form selector.
    "Formulation": ("剂型", "劑型"),
    # QuickLog brand picker — release group + niche-brand submenu.
    "Extended-release": ("缓释", "緩釋"),
    "More…": ("更多…", "更多…"),
    "Scan a label": ("扫描标签", "掃描標籤"),
    "Close scanner": ("关闭扫描", "關閉掃描"),
    "Point at the medication name or its barcode": ("对准药品名称或条形码", "對準藥品名稱或條碼"),
    "Point at a barcode or label, then tap a highlighted area": (
        "对准条形码或标签，然后轻点高亮区域",
        "對準條碼或標籤，然後輕點高亮區域",
    ),
    "Resolving…": ("识别中…", "辨識中…"),
    "Add to Log": ("添加到记录", "新增至記錄"),
    "Scan Again": ("重新扫描", "重新掃描"),
    "No match": ("无匹配", "無匹配"),
    "Point the camera at the printed drug name.": (
        "将相机对准印刷的药品名称。",
        "將相機對準印刷的藥品名稱。",
    ),
    "Camera Access Needed": ("需要相机权限", "需要相機權限"),
    "Scanning Unavailable": ("无法扫描", "無法掃描"),
    "Enable camera access in Settings to scan medication labels.": (
        "在“设置”中允许相机访问以扫描药品标签。",
        "在「設定」中允許相機存取以掃描藥品標籤。",
    ),
    "Label scanning isn't available on this device.": (
        "此设备不支持标签扫描。",
        "此裝置不支援標籤掃描。",
    ),
    # ---------------------------------------------------------------
    # I.ref — GABA withdrawal reference card (WithdrawalReferenceView).
    # Population-level relapse/rebound/withdrawal taxonomy + onset bands.
    # ---------------------------------------------------------------
    "If You Stop": ("如果你停用", "如果你停用"),
    "If you stop: withdrawal timing": ("如果你停用：戒断时间", "如果你停用：戒斷時間"),
    'What stopping looks like, at the population level — three things people call "withdrawal" that behave differently, and roughly when each starts for drugs like the ones you\'ve logged. Timing is from research populations, not a prediction for you.': (
        "从群体层面看停药会怎样——人们所说的“戒断”其实包含三种表现不同的情况，以及对于你记录过的这类药物，每种大约何时开始。这些时间来自研究人群，并非对你个人的预测。",
        "從群體層面看停藥會怎樣——人們所說的「戒斷」其實包含三種表現不同的情況，以及對於你記錄過的這類藥物，每種大約何時開始。這些時間來自研究人群，並非對你個人的預測。",
    ),
    'Three kinds of "withdrawal"': ("三种“戒断”", "三種「戒斷」"),
    "When symptoms start": ("症状何时开始", "症狀何時開始"),
    "Longer-acting drugs delay onset because the drug is still leaving your system. Active metabolites (diazepam, chlordiazepoxide, clonazepam) can push the window later still.": (
        "长效药物会推迟起始，因为药物仍在从体内清除。活性代谢物（地西泮、氯氮䓬、氯硝西泮）会让这一时间窗更晚出现。",
        "長效藥物會延後起始，因為藥物仍在從體內清除。活性代謝物（地西泮、氯氮䓬、氯硝西泮）會讓這一時間窗更晚出現。",
    ),
    "Not medical advice. Stopping a benzodiazepine abruptly after regular use can cause seizures. These are population timings, not a taper plan.": (
        "非医疗建议。规律使用后突然停用苯二氮䓬类药物可能引发癫痫发作。这些是群体层面的时间，而非减量方案。",
        "非醫療建議。規律使用後突然停用苯二氮䓬類藥物可能引發癲癇發作。這些是群體層面的時間，而非減量方案。",
    ),
    "Since your last dose": ("距上次用药", "距上次用藥"),
    "Estimated from your logged doses — the window is a population range, not a prediction for you.": (
        "根据你记录的用药估算——这一时间窗是群体范围，并非对你个人的预测。",
        "根據你記錄的用藥估算——這一時間窗是群體範圍，並非對你個人的預測。",
    ),
    "Estimated withdrawal onset window, with a marker for time since your last dose.": (
        "估算的戒断起始时间窗，并标出距上次用药的时间。",
        "估算的戒斷起始時間窗，並標出距上次用藥的時間。",
    ),
    "Less than a day": ("不到一天", "不到一天"),
    "1 day": ("1 天", "1 天"),
    "No half-life on file for your logged drugs, so the onset window can't be placed.": (
        "你记录的药物没有半衰期数据，因此无法定位起始时间窗。",
        "你記錄的藥物沒有半衰期資料，因此無法定位起始時間窗。",
    ),
    "Before the usual onset window for your slowest-clearing drug — symptoms, if any, would typically start later.": (
        "早于你清除最慢的药物通常的起始时间窗——即使会出现症状，通常也会更晚开始。",
        "早於你清除最慢的藥物通常的起始時間窗——即使會出現症狀，通常也會更晚開始。",
    ),
    "Within the window when symptoms for drugs like yours typically begin and peak.": (
        "正处于此类药物症状通常开始并达到高峰的时间窗内。",
        "正處於此類藥物症狀通常開始並達到高峰的時間窗內。",
    ),
    "Past the typical peak window for your drugs — a protracted tail can still persist for weeks.": (
        "已过你的药物通常的高峰时间窗——但迁延的尾期仍可能持续数周。",
        "已過你的藥物通常的高峰時間窗——但遷延的尾期仍可能持續數週。",
    ),
    "Onset %@, peak %@": ("起始 %@，高峰 %@", "起始 %@，高峰 %@"),
    "your drugs": ("你的药物", "你的藥物"),
    "long-acting": ("长效", "長效"),
    "intermediate": ("中效", "中效"),
    "short-acting": ("短效", "短效"),
    "diazepam, chlordiazepoxide, clonazepam": (
        "地西泮、氯氮䓬、氯硝西泮",
        "地西泮、氯氮䓬、氯硝西泮",
    ),
    "temazepam, bromazepam": ("替马西泮、溴西泮", "替馬西泮、溴西泮"),
    "triazolam, alprazolam, lorazepam, oxazepam": (
        "三唑仑、阿普唑仑、劳拉西泮、奥沙西泮",
        "三唑侖、阿普唑侖、勞拉西泮、奧沙西泮",
    ),
    "2–7 days": ("2–7 天", "2–7 天"),
    "5–14 days": ("5–14 天", "5–14 天"),
    "1–2 days": ("1–2 天", "1–2 天"),
    "3–7 days": ("3–7 天", "3–7 天"),
    "6–24 hours": ("6–24 小时", "6–24 小時"),
    "1–4 days": ("1–4 天", "1–4 天"),
    "Relapse": ("复发", "復發"),
    "Rebound": ("反跳", "反跳"),
    "Withdrawal": ("戒断", "戒斷"),
    "The original symptoms return — the thing the drug was treating comes back.": (
        "原有症状重新出现——药物本来在治疗的问题又回来了。",
        "原有症狀重新出現——藥物本來在治療的問題又回來了。",
    ),
    "The original symptoms return, briefly stronger than before.": (
        "原有症状重新出现，并在短期内比之前更强。",
        "原有症狀重新出現，並在短期內比之前更強。",
    ),
    "New symptoms the drug wasn't treating — insomnia, tremor, and, after regular use, seizure risk.": (
        "药物原本并未治疗的新症状——失眠、震颤，规律使用后还有癫痫发作风险。",
        "藥物原本並未治療的新症狀——失眠、震顫，規律使用後還有癲癇發作風險。",
    ),
    "Gradual onset, persists until treated.": (
        "逐渐出现，直到得到治疗才缓解。",
        "逐漸出現，直到得到治療才緩解。",
    ),
    "Onset 1–2 days, time-limited (days).": (
        "1–2 天出现，持续时间有限（数天）。",
        "1–2 天出現，持續時間有限（數天）。",
    ),
    "2–4 weeks, with a protracted tail in some people.": (
        "持续 2–4 周，部分人有迁延的尾期。",
        "持續 2–4 週，部分人有遷延的尾期。",
    ),
    # ---------------------------------------------------------------
    # Live Activity timer labels — orphaned in PiruLiveActivityExtension's own
    # catalog, so they shipped English to zh users on the Lock Screen.
    "Elapsed": ("已用时间", "已用時間"),
    "Remaining": ("剩余时间", "剩餘時間"),
    # Four parallel lanes merged 2026-08-03: class signatures (Lane A),
    # Insights > Usage v2 (Lane B), med-time consequence + heavy-tier band
    # + combination metabolites (Lane D), Sources ledger (Lane E).
    # ---------------------------------------------------------------
    # ---- Lane A — class signatures on the substance detail screen ----
    "Efficacy axis": ("效能轴", "效能軸"),
    "Measurement basis": ("测量基准", "測量基準"),
    "Release EC₅₀": ("释放 EC₅₀", "釋放 EC₅₀"),
    "Functional EC₅₀": ("功能 EC₅₀", "功能 EC₅₀"),
    "Reuptake IC₅₀": ("再摄取 IC₅₀", "再攝取 IC₅₀"),
    "Binding Kᵢ": ("结合 Kᵢ", "結合 Kᵢ"),
    "release EC₅₀": ("释放 EC₅₀", "釋放 EC₅₀"),
    "functional EC₅₀": ("功能 EC₅₀", "功能 EC₅₀"),
    "reuptake-inhibition IC₅₀": ("再摄取抑制 IC₅₀", "再攝取抑制 IC₅₀"),
    "binding Kᵢ": ("结合 Kᵢ", "結合 Kᵢ"),
    "inhibition IC₅₀": ("抑制 IC₅₀", "抑制 IC₅₀"),
    "efficacy τ": ("效能 τ", "效能 τ"),
    "intrinsic activity": ("内在活性", "內在活性"),
    "Emax": ("Emax", "Emax"),
    "Full agonist": ("完全激动剂", "完全促效劑"),
    "Partial agonist": ("部分激动剂", "部分促效劑"),
    "no activation": ("无激活", "無活化"),
    "full activation": ("完全激活", "完全活化"),
    "full activation · %@": ("完全激活 · %@", "完全活化 · %@"),
    "mixed species": ("混合物种", "混合物種"),
    "one panel": ("同一组实验", "同一組實驗"),
    "one study": ("同一研究", "同一研究"),
    "across studies": ("跨研究", "跨研究"),
    "different study": ("不同研究", "不同研究"),
    "nothing comparable to rank it against": ("没有可比对象供排序", "沒有可比對象供排序"),
    "perception": ("感知", "感知"),
    "body": ("身体", "身體"),
    "balanced": ("均衡", "均衡"),
    "%@ to %@ balance": ("%1$@ 与 %2$@ 的平衡", "%1$@ 與 %2$@ 的平衡"),
    "%@ vs %@": ("%1$@ 对 %2$@", "%1$@ 對 %2$@"),
    "%@ at %@": ("%1$@ 于 %2$@", "%1$@ 於 %2$@"),
    "Transporter potency share": ("转运体效价占比", "轉運體效價占比"),
    "Transporter triangle withheld": ("已隐去转运体三角图", "已隱去轉運體三角圖"),
    "No comparison axis for dissociatives": ("解离剂没有可比坐标轴", "解離劑沒有可比座標軸"),
    "These values were not measured together — each is its own study. Ranked here for scale, not as a league table.": (
        "这些数值并非在同一实验中测得——每个都来自各自的研究。此处排列只为呈现量级，不是排行榜。",
        "這些數值並非在同一實驗中測得——每個都來自各自的研究。此處排列只為呈現量級，不是排行榜。",
    ),
    "Faint dots are other compounds measured on the same basis — each in its own study, drawn for scale.": (
        "浅色圆点是以相同基准测得的其他化合物——各自出自不同研究，仅用于呈现量级。",
        "淺色圓點是以相同基準測得的其他化合物——各自出自不同研究，僅用於呈現量級。",
    ),
    "No single study in our data measured 5-HT2A and 5-HT1A for this compound on one assay, so the balance is withheld — a ratio built from two studies is not a ratio. The 5-HT2A value alone is shown.": (
        "我们的数据中没有任何一项研究在同一实验里同时测定该化合物的 5-HT2A 与 5-HT1A，因此不显示平衡图——由两项研究拼出的比值算不上比值。此处仅显示 5-HT2A 数值。",
        "我們的資料中沒有任何一項研究在同一實驗裡同時測定該化合物的 5-HT2A 與 5-HT1A，因此不顯示平衡圖——由兩項研究拼出的比值算不上比值。此處僅顯示 5-HT2A 數值。",
    ),
    "No single study in our data measured SERT, DAT and NET for this compound on one basis. Mixing them is how MDMA once rendered as a 95 % noradrenaline drug — a binding Kᵢ plotted against a release EC₅₀ — so the triangle is withheld rather than drawn from rows that can't be ranked together.": (
        "我们的数据中没有任何一项研究以同一基准同时测定该化合物的 SERT、DAT 与 NET。混用不同基准正是 MDMA 一度被呈现为「95% 去甲肾上腺素能药物」的原因——把结合 Kᵢ 与释放 EC₅₀ 画在了一起——因此宁可隐去三角图，也不用无法相互排序的数据作图。",
        "我們的資料中沒有任何一項研究以同一基準同時測定該化合物的 SERT、DAT 與 NET。混用不同基準正是 MDMA 一度被呈現為「95% 去甲腎上腺素能藥物」的原因——把結合 Kᵢ 與釋放 EC₅₀ 畫在了一起——因此寧可隱去三角圖，也不用無法相互排序的資料作圖。",
    ),
    "NMDA-block potency is the obvious signature for this class, and it is the one number the literature disagrees about most — the same site is reported decades apart, in different preparations, mostly in rat. Most dissociatives here carry no measured value at all, and potency is not what separates them subjectively. So this card says so instead of drawing an axis out of numbers that can't be ranked against each other.": (
        "NMDA 阻断效价是这一类物质最直观的特征，却也是文献分歧最大的一个数字——同一位点的报告相隔数十年，制备方法各异，且多为大鼠数据。此处多数解离剂根本没有实测值，而主观差异也并非由效价决定。因此这张卡片如实说明，而不是用无法相互排序的数字硬画一条坐标轴。",
        "NMDA 阻斷效價是這一類物質最直觀的特徵，卻也是文獻分歧最大的一個數字——同一位點的報告相隔數十年，製備方法各異，且多為大鼠數據。此處多數解離劑根本沒有實測值，而主觀差異也並非由效價決定。因此這張卡片如實說明，而不是用無法相互排序的數字硬畫一條座標軸。",
    ),
    # ---- Lane B — Insights › Usage, eight analytical sections ----
    "This period": ("本期", "本期"),
    "1Y": ("1年", "1年"),
    "Activity heatmap": ("活动热力图", "活動熱力圖"),
    "Day of week": ("星期分布", "星期分佈"),
    "Hour of day": ("时段分布", "時段分佈"),
    "Hour": ("小时", "小時"),
    "Bucket": ("区间", "區間"),
    "Selected": ("已选中", "已選取"),
    "Trend": ("趋势", "趨勢"),
    "Per week": ("每周", "每週"),
    "%@/wk": ("%@/周", "%@/週"),
    "Dose levels": ("剂量档位", "劑量檔位"),
    "Dose levels over time": ("剂量档位随时间变化", "劑量檔位隨時間變化"),
    "Substance trends": ("物质趋势", "物質趨勢"),
    "Regularity": ("规律性", "規律性"),
    "Routes": ("给药途径", "給藥途徑"),
    "Used together": ("同时使用", "同時使用"),
    "Very regular": ("非常规律", "非常規律"),
    "Somewhat regular": ("较为规律", "較為規律"),
    "Irregular": ("不规律", "不規律"),
    "Sporadic": ("零星", "零星"),
    "Hidden": ("已隐藏", "已隱藏"),
    "Which days and hours you log on": ("你在哪些日子和时段记录", "你在哪些日子和時段記錄"),
    "Entries by weekday, split by class": (
        "按星期统计的条目，并按类别拆分",
        "按星期統計的條目，並按類別拆分",
    ),
    "Entries per week, 7-day rolling average": (
        "每周条目数，7 天滚动平均",
        "每週條目數，7 天滾動平均",
    ),
    "Entries per week, 4-week rolling average": (
        "每周条目数，4 周滚动平均",
        "每週條目數，4 週滾動平均",
    ),
    "Common doses per week, 7-day rolling average": (
        "每周常规剂量数，7 天滚动平均",
        "每週常規劑量數，7 天滾動平均",
    ),
    "Common doses per week, 4-week rolling average": (
        "每周常规剂量数，4 周滚动平均",
        "每週常規劑量數，4 週滾動平均",
    ),
    "Ranked by how often, or by total common-dose units": (
        "按记录次数，或按常规剂量单位总量排序",
        "按記錄次數，或按常規劑量單位總量排序",
    ),
    "Common doses": ("常规剂量", "常規劑量"),
    "Entries/wk": ("条目/周", "條目/週"),
    "Common doses/wk": ("常规剂量/周", "常規劑量/週"),
    "Entries/day": ("条目/天", "條目/天"),
    "Common doses/day": ("常规剂量/天", "常規劑量/天"),
    "Common doses per day": ("每天常规剂量数", "每天常規劑量數"),
    "Which weekdays you log on most": ("你最常在星期几记录", "你最常在星期幾記錄"),
    "Common-dose units by weekday": ("按星期统计的常规剂量单位", "按星期統計的常規劑量單位"),
    "Common-dose units by weekday, most on %@": (
        "按星期统计的常规剂量单位，%@ 最多",
        "按星期統計的常規劑量單位，%@ 最多",
    ),
    "No common dose defined for these substances": (
        "这些物质未定义常规剂量",
        "這些物質未定義常規劑量",
    ),
    "No common dose defined": ("未定义常规剂量", "未定義常規劑量"),
    "Common-dose units count each dose as a multiple of its common dose. %lld of %lld substances have one.": (
        "常规剂量单位将每次剂量按其常规剂量的倍数计。已定义：%lld / %lld 种物质。",
        "常規劑量單位將每次劑量按其常規劑量的倍數計。已定義：%lld / %lld 種物質。",
    ),
    "%@ common-dose units across %lld entries": (
        "%@ 个常规剂量单位，共 %lld 条目",
        "%@ 個常規劑量單位，共 %lld 條目",
    ),
    "Where your doses sit on each substance's ladder": (
        "你的剂量在各物质剂量阶梯上的位置",
        "你的劑量在各物質劑量階梯上的位置",
    ),
    "Only a minority of entries could be placed on a ladder": (
        "只有少数条目能对应到剂量阶梯",
        "只有少數條目能對應到劑量階梯",
    ),
    "Substances logged on the same day": ("同一天记录的物质", "同一天記錄的物質"),
    "How evenly spaced your doses are": ("你的剂量间隔有多均匀", "你的劑量間隔有多均勻"),
    "How each substance was taken": ("每种物质的使用方式", "每種物質的使用方式"),
    "Most active: %@": ("最活跃：%@", "最活躍：%@"),
    "%lld new this period": ("本期新增 %lld 种", "本期新增 %lld 種"),
    "at common or above": ("达到常规或以上", "達到常規或以上"),
    "at common or above · %lld heavy": (
        "达到常规或以上 · %lld 次大剂量",
        "達到常規或以上 · %lld 次大劑量",
    ),
    "Based on %lld of %lld entries with dose data": (
        "基于 %2$lld 条条目中有剂量数据的 %1$lld 条",
        "基於 %2$lld 筆條目中有劑量資料的 %1$lld 筆",
    ),
    "No dose ladders matched": ("没有匹配的剂量阶梯", "沒有匹配的劑量階梯"),
    "No dose levels resolved": ("未能解析出剂量档位", "未能解析出劑量檔位"),
    "No entries in the previous period": ("上一期没有条目", "上一期沒有條目"),
    "No entries in this window": ("此时间范围内没有条目", "此時間範圍內沒有條目"),
    "Nothing logged in this window": ("此时间范围内没有记录", "此時間範圍內沒有記錄"),
    "No pairs in this class": ("此类别下没有组合", "此類別下沒有組合"),
    "Nothing in This Range": ("此范围内没有数据", "此範圍內沒有資料"),
    "Pick a longer time range to see your history.": (
        "选择更长的时间范围以查看历史记录。",
        "選擇更長的時間範圍以查看歷史記錄。",
    ),
    "Not enough history yet": ("历史记录还不够", "歷史記錄還不夠"),
    "Show all %lld": ("显示全部 %lld 项", "顯示全部 %lld 項"),
    "Show fewer": ("收起", "收起"),
    "Clear selected day": ("清除所选日期", "清除所選日期"),
    "every %@ days": ("每 %@ 天一次", "每 %@ 天一次"),
    "up %lld percent": ("上升百分之 %lld", "上升百分之 %lld"),
    "down %lld percent": ("下降百分之 %lld", "下降百分之 %lld"),
    "↑ %lld%% vs previous %@": ("↑ %1$lld%% 相比上一个%2$@", "↑ %1$lld%% 相比上一個%2$@"),
    "↓ %lld%% vs previous %@": ("↓ %1$lld%% 相比上一个%2$@", "↓ %1$lld%% 相比上一個%2$@"),
    "%@ entries across seven equal slices of the period.": (
        "按本期七等分统计的 %@ 条条目。",
        "按本期七等分統計的 %@ 筆條目。",
    ),
    "%@ entries per day": ("每日 %@ 条条目", "每日 %@ 筆條目"),
    "%@ entries per day on average": ("平均每日 %@ 条条目", "平均每日 %@ 筆條目"),
    "%@ entries per day, most active on %@": (
        "每日 %1$@ 条条目，%2$@最活跃",
        "每日 %1$@ 筆條目，%2$@最活躍",
    ),
    "%lld entries": ("%lld 条条目", "%lld 筆條目"),
    "%lld distinct substances": ("%lld 种不同物质", "%lld 種不同物質"),
    "%lld distinct substances, %lld new this period": (
        "%1$lld 种不同物质，本期新增 %2$lld 种",
        "%1$lld 種不同物質，本期新增 %2$lld 種",
    ),
    "%lld entries, %@ versus the previous period": (
        "%1$lld 条条目，较上一期%2$@",
        "%1$lld 筆條目，較上一期%2$@",
    ),
    "%lld entries, busiest around %@": (
        "%1$lld 条条目，%2$@前后最密集",
        "%1$lld 筆條目，%2$@前後最密集",
    ),
    "%@ common-dose units, busiest around %@": (
        "%1$@ 个常规剂量单位，%2$@前后最密集",
        "%1$@ 個常規劑量單位，%2$@前後最密集",
    ),
    "%@ common-dose units": ("%@ 个常规剂量单位", "%@ 個常規劑量單位"),
    "Which days and hours, by common-dose units": (
        "按常规剂量单位统计的日期和时段",
        "按常規劑量單位統計的日期和時段",
    ),
    "%lld entries, busiest on %@ with %lld": (
        "%1$lld 条条目，%2$@最多，共 %3$lld 条",
        "%1$lld 筆條目，%2$@最多，共 %3$lld 筆",
    ),
    "%lld entries: %@": ("%1$lld 条条目：%2$@", "%1$lld 筆條目：%2$@"),
    "%lld percent of %lld placed doses were common or above, %lld heavy": (
        "在 %2$lld 次可定位的剂量中，百分之 %1$lld 达到常规或以上，其中 %3$lld 次为大剂量",
        "在 %2$lld 次可定位的劑量中，百分之 %1$lld 達到常規或以上，其中 %3$lld 次為大劑量",
    ),
    "No entries could be placed on a dose ladder": (
        "没有条目能对应到剂量阶梯",
        "沒有條目能對應到劑量階梯",
    ),
    "%lld days together, %lld percent of the days either was logged": (
        "共同出现 %1$lld 天，占任一方被记录天数的百分之 %2$lld",
        "共同出現 %1$lld 天，佔任一方被記錄天數的百分之 %2$lld",
    ),
    "%@, about every %@ days across %lld entries": (
        "%1$@，%3$lld 条条目中大约每 %2$@ 天一次",
        "%1$@，%3$lld 筆條目中大約每 %2$@ 天一次",
    ),
    "%@ rising to %@ per week": ("%1$@ 上升至每周 %2$@", "%1$@ 上升至每週 %2$@"),
    "%@ falling to %@ per week": ("%1$@ 下降至每周 %2$@", "%1$@ 下降至每週 %2$@"),
    "%@ steady at %@ per week": ("%1$@ 稳定在每周 %2$@", "%1$@ 穩定在每週 %2$@"),
    "%@ rising to %@ per day": ("%1$@ 上升至每天 %2$@", "%1$@ 上升至每天 %2$@"),
    "%@ falling to %@ per day": ("%1$@ 下降至每天 %2$@", "%1$@ 下降至每天 %2$@"),
    "%@ steady at %@ per day": ("%1$@ 稳定在每天 %2$@", "%1$@ 穩定在每天 %2$@"),
    "%@ with %@": ("%1$@ 与 %2$@", "%1$@ 與 %2$@"),
    "%@ %lld percent": ("%1$@ 百分之 %2$lld", "%1$@ 百分之 %2$lld"),
    "%lld %@": ("%1$lld %2$@", "%1$lld %2$@"),
    "%lld. %@": ("%1$lld. %2$@", "%1$lld. %2$@"),
    "%lld/%lld": ("%1$lld/%2$lld", "%1$lld/%2$lld"),
    "%@ %@ · %@": ("%1$@ %2$@ · %3$@", "%1$@ %2$@ · %3$@"),
    "Entries by hour of day": ("按时段统计的条目", "按時段統計的條目"),
    "Entries by weekday": ("按星期统计的条目", "按星期統計的條目"),
    "Days with entries are listed one by one. Select a day to filter the hour chart below.": (
        "有条目的日期会逐一列出。选择某一天可筛选下方的时段图表。",
        "有條目的日期會逐一列出。選擇某一天可篩選下方的時段圖表。",
    ),
    "Toggles this substance's line": ("切换该物质的曲线显示", "切換該物質的曲線顯示"),
    # ---- Lane D — med times, heavy-tier band, combination metabolites ----
    "Kicks in ~%@": ("约 %@ 起效", "約 %@ 起效"),
    "Kicks in ~%@ · easing off ~%@": (
        "约 %1$@ 起效 · 约 %2$@ 开始消退",
        "約 %1$@ 起效 · 約 %2$@ 開始消退",
    ),
    "Clear for sleep ~%@": ("约 %@ 消退，不影响睡眠", "約 %@ 消退，不影響睡眠"),
    "Clear for sleep ~%@ — after most bedtimes.": (
        "约 %@ 消退，不影响睡眠——晚于多数人的就寝时间。",
        "約 %@ 消退，不影響睡眠——晚於多數人的就寢時間。",
    ),
    "Kick-in and wear-off come from this med's own duration data — the same model the timeline draws. An estimate, not a schedule.": (
        "起效与消退时间来自这款药物自身的持续时间数据——与时间线所用的模型相同。这是估算，不是时刻表。",
        "起效與消退時間來自這款藥物自身的持續時間資料——與時間線所用的模型相同。這是估算，不是時刻表。",
    ),
    "heavy": ("大剂量", "大劑量"),
    "This curve reaches the heavy dose range": ("此曲线达到大剂量区间", "此曲線達到大劑量區間"),
    "Formed With": ("联合生成", "聯合生成"),
    "A third compound your body makes from this dose and something else in the session — not from either alone.": (
        "你的身体用这次剂量和本次记录中的另一种物质生成的第三种化合物——单独任何一种都不会产生。",
        "你的身體用這次劑量和本次記錄中的另一種物質生成的第三種化合物——單獨任何一種都不會產生。",
    ),
    "Next: %@ at %@ · %@": ("下一次：%1$@ 于 %2$@ · %3$@", "下一次：%1$@ 於 %2$@ · %3$@"),
    # ---- Lane E — Sources screen ledger ----
    "dose": ("剂量", "劑量"),
    "duration": ("持续时间", "持續時間"),
    "effects": ("效应", "效應"),
    "overview": ("概述", "概述"),
    "pharmacology": ("药理学", "藥理學"),
    "pharmacokinetics": ("药代动力学", "藥物動力學"),
    "tolerance": ("耐受性", "耐受性"),
    "prescribing": ("处方信息", "處方資訊"),
    "interactions": ("相互作用", "相互作用"),
    "chemistry": ("化学", "化學"),
    "names & tags": ("名称与标签", "名稱與標籤"),
    "supplies %@": ("提供 %@", "提供 %@"),
    "licensed %@": ("授权协议 %@", "授權條款 %@"),
    "Each row lists what that source supplied here. Links open the source's own page — always verify against the original.": (
        "每一行列出该来源在此提供的内容。链接会打开来源自身的页面——请始终对照原始资料核实。",
        "每一行列出該來源在此提供的內容。連結會開啟來源自身的頁面——請始終對照原始資料核實。",
    ),
    # Substance-detail round 5 (2026-08-01) — dose/effects split, the dose-source
    # comparison sheet, the folded Prescribing card, and the Log CTA under the
    # dose card.
    "Log this": ("记录这次", "記錄這次"),
    "Prescribing": ("处方信息", "處方資訊"),
    "Approved uses": ("已批准用途", "已批准用途"),
    "Boxed warning": ("黑框警告", "黑框警告"),
    "Fewer": ("收起", "收起"),
    "Dose sources": ("剂量来源", "劑量來源"),
    "In use": ("使用中", "使用中"),
    "About metabolites": ("关于代谢物", "關於代謝物"),
    "Compare all %lld sources": ("对比全部 %lld 个来源", "對比全部 %lld 個來源"),
    "%@ · %lld sources": ("%1$@ · %2$lld 个来源", "%1$@ · %2$lld 個來源"),
    "Piru shows the source you rank highest — change that in Settings › Source Priority.": (
        "Piru 显示你排序最高的来源——可在“设置 › 来源优先级”中更改。",
        "Piru 顯示你排序最高的來源——可在「設定 › 來源優先順序」中更改。",
    ),
    # TestFlight feedback round, build 33 (2026-07-27) — card overflow menu.
    "More actions": ("更多操作", "更多操作"),
    # Substance-detail redesign v2 (proto8/proto10) — header chips, dose card,
    # bar-first pharmacology, tappable metabolites (2026-07-24).
    "+ %lld chemical names": ("+ %lld 个化学名称", "+ %lld 個化學名稱"),
    "Also known as %@.": ("又称 %@。", "又稱 %@。"),
    "Also known as %@, and %lld other names.": (
        "又称 %@，以及另外 %lld 个名称。",
        "又稱 %@，以及另外 %lld 個名稱。",
    ),
    "Effect over time · %@": ("效果随时间变化 · %@", "效果隨時間變化 · %@"),
    "Effect over time: rises over the come-up, plateaus at peak, then falls.": (
        "效果随时间变化：在上升期逐渐增强，在峰值期保持平稳，随后减弱。",
        "效果隨時間變化：在上升期逐漸增強，在峰值期保持平穩，隨後減弱。",
    ),
    "Duration of action": ("作用持续时间", "作用持續時間"),
    "Acts on": ("作用靶点", "作用標靶"),
    "reuptake": ("再摄取", "再攝取"),
    "via %@": ("经 %@", "經 %@"),
    "Opens %@": ("打开 %@", "打開 %@"),
    # Inventory manager: collapsible class sections + class arrangement (2026-07-21).
    "Arrange Classes": ("排列类别", "排列類別"),
    "Arrange Classes…": ("排列类别…", "排列類別…"),
    "Collapse All": ("全部折叠", "全部折疊"),
    "Expand All": ("全部展开", "全部展開"),
    "Double tap to collapse": ("轻点两下以折叠", "點兩下以折疊"),
    "Double tap to expand": ("轻点两下以展开", "點兩下以展開"),
    "Drag to set the order class sections appear in. Reset to let the current sort decide.": (
        "拖动以设置类别分区的显示顺序。重置后将由当前排序方式决定。",
        "拖動以設定類別分區的顯示順序。重置後將由目前排序方式決定。",
    ),
    # Inventory manager: search, sort, filter, group-by-class (2026-07-21).
    "Search Inventory": ("搜索库存", "搜尋庫存"),
    "Sort By": ("排序方式", "排序方式"),
    "Supply Level": ("存量水平", "存量水準"),
    "Recently Updated": ("最近更新", "最近更新"),
    "Manual": ("手动", "手動"),
    "Group by Class": ("按类别分组", "按類別分組"),
    "Status": ("状态", "狀態"),
    "Class": ("类别", "類別"),
    "In Stock": ("有库存", "有庫存"),
    "Remove filter": ("移除筛选", "移除篩選"),
    "No Matching Items": ("无匹配项目", "無符合項目"),
    "No tracked substance matches the current search and filters.": (
        "没有符合当前搜索和筛选条件的追踪物质。",
        "沒有符合目前搜尋與篩選條件的追蹤物質。",
    ),
    # Source-priority screen rework (2026-07-19).
    "Reset": ("重置", "重置"),
    "When several sources report the same fact — a dose, a duration — Piru shows the one nearest the top. Drag to set which you trust most.": (
        "当多个来源报告同一事实（如剂量、时长）时，Piru 会显示最靠上的那个。拖动以设置你最信任的来源。",
        "當多個來源報告同一事實（如劑量、時長）時，Piru 會顯示最靠上的那個。拖動以設定你最信任的來源。",
    ),
    "%@, priority %lld": ("%1$@，优先级 %2$lld", "%1$@，優先級 %2$lld"),
    # Source-attribution explainer + priority surfacing (2026-07-19).
    "Shown from": ("显示来源", "顯示來源"),
    "Why this source": ("为何选此来源", "為何選此來源"),
    "Shown": ("采用", "採用"),
    "Also has this": ("也有此项", "也有此項"),
    "Manage source priority": ("管理来源优先级", "管理來源優先級"),
    "Where this comes from": ("数据来自哪里", "數據來自哪裡"),
    "Source Priority": ("来源优先级", "來源優先級"),
    "Piru shows the highest-priority source you've enabled that has this data — and you choose the order.": (
        "Piru 会显示你已启用的、拥有该数据的最高优先级来源——顺序由你决定。",
        "Piru 會顯示你已啟用的、擁有該數據的最高優先級來源——順序由你決定。",
    ),
    "Higher-priority sources that don't list this field are skipped.": (
        "优先级更高但未提供此项的来源会被跳过。",
        "優先級更高但未提供此項的來源會被跳過。",
    ),
    "Open %@ page": ("打开 %@ 页面", "開啟 %@ 頁面"),
    "Explains why this source was used and lets you reorder sources": (
        "说明为何采用此来源，并可重新排序来源",
        "說明為何採用此來源，並可重新排序來源",
    ),
    # Share-card redesign — effects-mode toggle + effects section (2026-07-19).
    "Minimal": ("简约", "簡約"),
    "Standard": ("标准", "標準"),
    "Rich": ("详尽", "詳盡"),
    "EFFECT OVER TIME": ("效应时程", "效應時程"),
    "Ramp": ("梯度", "梯度"),
    "Columns": ("分栏", "分欄"),
    "Effects style": ("效应样式", "效應樣式"),
    "Most common effects · by dose": ("最常见效应 · 按剂量", "最常見效應 · 按劑量"),
    "release": ("释放", "釋放"),
    "uptake": ("再摄取", "再攝取"),
    "Reported effects": ("报告的效应", "報告的效應"),
    "Most reported": ("最多报告", "最多報告"),
    # Notifications management screen — unified per-type toggles (2026-07-17).
    "Pause All Notifications": ("暂停所有通知", "暫停所有通知"),
    "Silences everything without losing your choices below.": (
        "静音全部通知，但保留你在下方的选择。",
        "靜音全部通知，但保留你在下方的選擇。",
    ),
    "Dose Reminders": ("剂量提醒", "劑量提醒"),
    "During a Session": ("使用期间", "使用期間"),
    "Safety Limits": ("安全限度", "安全限度"),
    "Supplies": ("库存", "庫存"),
    "Safety & Supplies": ("安全与库存", "安全與庫存"),
    "Session Alerts": ("使用期间提醒", "使用期間提醒"),
    "All on": ("全部开启", "全部開啟"),
    "All off": ("全部关闭", "全部關閉"),
    "Comedown": ("缓和期", "緩和期"),
    "Hydration": ("补水", "補水"),
    "Sleep": ("睡眠", "睡眠"),
    "Phase": ("阶段", "階段"),
    "Next-Dose": ("下一剂", "下一劑"),
    "Re-ask %lld": ("第 %lld 次再问", "第 %lld 次再問"),
    "Add Re-ask": ("添加再问", "新增再問"),
    "Remove Last": ("移除最后一个", "移除最後一個"),
    "5 min": ("5 分钟", "5 分鐘"),
    "10 min": ("10 分钟", "10 分鐘"),
    "15 min": ("15 分钟", "15 分鐘"),
    "20 min": ("20 分钟", "20 分鐘"),
    "30 min": ("30 分钟", "30 分鐘"),
    "45 min": ("45 分钟", "45 分鐘"),
    "60 min": ("60 分钟", "60 分鐘"),
    "Reminders fire at each med's times. Quiet meds share one reminder per time of day. Logging a dose clears its follow-ups.": (
        "提醒按每种药物的设定时间触发。静音药物共享每个时段一次提醒。记录剂量后后续提醒自动取消。",
        "提醒按每種藥物的設定時間觸發。靜音藥物共享每個時段一次提醒。記錄劑量後後續提醒自動取消。",
    ),
    "Timed from the typical onset and duration of each dose you log, for its substance and route. These are estimates from published data — Piru doesn't sense anything.": (
        "根据你记录的每剂量的物质和给药途径，按典型起效时间和持续时间计时。这些是基于已发表数据的估算——Piru 不感知任何东西。",
        "根據你記錄的每劑量的物質和給藥途徑，按典型起效時間和持續時間計時。這些是基於已發表資料的估算——Piru 不感知任何東西。",
    ),
    "Totals include scheduled meds, as-needed doses, and everything else — the safety net doesn't care why you took it.": (
        "总量包括计划用药、按需用药和其他所有——安全网不在乎你为什么服用。",
        "總量包括計畫用藥、按需用藥和其他所有——安全網不在乎你為什麼服用。",
    ),
    "Comedown alerts are armed per dose in Ramp-Down.": (
        "缓和期提醒在「渐减」中按剂量启用。",
        "緩和期提醒在「漸減」中按劑量啟用。",
    ),
    "Turning off the cumulative dose warning removes a safety net.": (
        "关闭累积剂量警告将移除一层安全保障。",
        "關閉累積劑量警告將移除一層安全保障。",
    ),
    "If a dose isn't logged, ask again after these intervals. Applies to every med. A med can override or opt out in its own settings. Re-asks never scold — they just ask.": (
        "如果剂量未记录，按这些间隔再次提醒。适用于所有药物。每种药物可单独覆盖或退出。再次提醒绝不训斥——只是问一声。",
        "如果劑量未記錄，按這些間隔再次提醒。適用於所有藥物。每種藥物可單獨覆蓋或退出。再次提醒絕不訓斥——只是問一聲。",
    ),
    "Notifications Enabled": ("通知已开启", "通知已開啟"),
    "Notifications Are Off": ("通知已关闭", "通知已關閉"),
    "Allow Notifications": ("允许通知", "允許通知"),
    "Asking…": ("正在请求…", "正在請求…"),
    "Checking Permission…": ("正在检查权限…", "正在檢查權限…"),
    "Notifications for Piru are turned off in Settings. None of the alerts below can be delivered until they're allowed again.": (
        "「设置」中已关闭 Piru 的通知。在重新允许之前，下方所有提醒都无法送达。",
        "「設定」中已關閉 Piru 的通知。在重新允許之前，下方所有提醒都無法送達。",
    ),
    "Piru asks the system once. You choose exactly what it's allowed to send below.": (
        "Piru 只会向系统请求一次。它能发送什么，完全由你在下方决定。",
        "Piru 只會向系統請求一次。它能傳送什麼，完全由你在下方決定。",
    ),
    "Piru only sends the notifications listed on this screen.": (
        "Piru 只会发送此页面列出的通知。",
        "Piru 只會傳送此頁面列出的通知。",
    ),
    "Next: %@": ("下一次：%@", "下一次：%@"),
    "Comedown Alerts": ("缓和期提醒", "緩和期提醒"),
    "Hydration Reminders": ("补水提醒", "補水提醒"),
    "Sleep Reminders": ("睡眠提醒", "睡眠提醒"),
    "Phase Alerts": ("阶段提醒", "階段提醒"),
    "Cumulative Dose Warnings": ("累积剂量警告", "累積劑量警告"),
    "Routine Reminders": ("日常提醒", "日常提醒"),
    "Low Stock Alerts": ("低库存提醒", "低庫存提醒"),
    "Warns you before a dose wears off, so the drop doesn't catch you off guard. Turned on per dose from its comedown alert screen.": (
        "在药效消退前提醒你，让落差不至于让你措手不及。需在每剂的缓和期提醒页面单独开启。",
        "在藥效消退前提醒你，讓落差不至於讓你措手不及。需在每劑的緩和期提醒頁面單獨開啟。",
    ),
    "Water nudges timed to your dose — stimulants and empathogens mask thirst.": (
        "按剂量时间安排的补水提醒——兴奋剂和共情剂会掩盖口渴感。",
        "按劑量時間安排的補水提醒——興奮劑和共情劑會掩蓋口渴感。",
    ),
    "A wind-down reminder late into long stimulant sessions, when sleep is the best recovery.": (
        "在长时间兴奋剂使用的后段提醒你放松入睡——此时睡眠是最好的恢复。",
        "在長時間興奮劑使用的後段提醒你放鬆入睡——此時睡眠是最好的恢復。",
    ),
    "Timing cues at onset, come-up, and peak so you can anchor what you feel to the timeline.": (
        "在起效、上升期和巅峰时给出时间提示，让你把感受对应到时间线上。",
        "在起效、上升期和巔峰時給出時間提示，讓你把感受對應到時間線上。",
    ),
    "A heads-up when your 12-hour total of one substance reaches a heavy range. Turning this off removes a safety net.": (
        "当某一物质 12 小时内的累积量达到大剂量范围时提醒你。关闭它等于拆掉一道安全网。",
        "當某一物質 12 小時內的累積量達到大劑量範圍時提醒你。關閉它等於拆掉一道安全網。",
    ),
    "A daily nudge at each routine's set time so a dose never slips your mind. Tapping it opens Quick Log with the routine staged.": (
        "每天在各个日常设定的时间提醒你，不再漏掉任何一剂。点按通知即打开快捷记录，日常内容已预先排好。",
        "每天在各個日常設定的時間提醒你，不再漏掉任何一劑。點按通知即打開快捷記錄，日常內容已預先排好。",
    ),
    "A heads-up when something you track runs low or out — before the empty bottle surprises you.": (
        "当你追踪的物品所剩不多或已用完时提前提醒——别等到瓶子空了才发现。",
        "當你追蹤的物品所剩不多或已用完時提前提醒——別等到瓶子空了才發現。",
    ),
    "Notification Settings": ("通知设置", "通知設定"),
    "Choose which notifications Piru sends — routine reminders, session alerts, safety warnings, and low-stock alerts.": (
        "选择 Piru 发送哪些通知——日常提醒、使用期间提醒、安全警告和低库存提醒。",
        "選擇 Piru 傳送哪些通知——日常提醒、使用期間提醒、安全警告和低庫存提醒。",
    ),
    "Routine reminders are turned off in Notification Settings, so this reminder won't be delivered.": (
        "通知设置中已关闭日常提醒，因此这条提醒不会送达。",
        "通知設定中已關閉日常提醒，因此這條提醒不會送達。",
    ),
    "Notifications for Piru are off in the system Settings, so this reminder won't be delivered.": (
        "系统设置中已关闭 Piru 的通知，因此这条提醒不会送达。",
        "系統設定中已關閉 Piru 的通知，因此這條提醒不會送達。",
    ),
    # Notifications Stage 3+4 — occurrences, next-dose, quiet hours, actions,
    # progressive onboarding (2026-07-18).
    "Next-Dose Window": ("下一剂窗口", "下一劑窗口"),
    "Next-dose window reminder": ("下一剂窗口提醒", "下一劑窗口提醒"),
    "Next-dose window — %@": ("下一剂窗口——%@", "下一劑窗口——%@"),
    "After you log a med you've opted in, a nudge when its next dose window opens. An estimate, not medical advice — opt in per med.": (
        "记录你已选择开启的药物后，会在下一剂窗口开启时提醒你。这只是估算，并非医疗建议——请按药物逐一开启。",
        "記錄你已選擇開啟的藥物後，會在下一劑窗口開啟時提醒你。這只是估算，並非醫療建議——請按藥物逐一開啟。",
    ),
    "After you log this med, a nudge when the model says its next dose window opens. An estimate, not medical advice — follow your prescriber's schedule.": (
        "记录这种药物后，当模型判断下一剂窗口开启时提醒你。这只是估算，并非医疗建议——请遵循处方医生的安排。",
        "記錄這種藥物後，當模型判斷下一劑窗口開啟時提醒你。這只是估算，並非醫療建議——請遵循處方醫生的安排。",
    ),
    "Enough time has passed since your last dose. This is a model estimate — follow your prescriber's schedule.": (
        "距离你的上一剂已经过了足够的时间。这是模型估算——请遵循处方医生的安排。",
        "距離你的上一劑已經過了足夠的時間。這是模型估算——請遵循處方醫生的安排。",
    ),
    "Quiet Hours": ("勿扰时段", "勿擾時段"),
    "Session nudges, re-asks, and next-dose reminders inside this window stay silent. Routine reminders at times you set, and cumulative dose warnings, still come through.": (
        "此时间段内的使用期间提醒、再次提醒和下一剂窗口提醒将保持静默。你设定了时间的日常提醒和累积剂量警告仍会送达。",
        "此時間段內的使用期間提醒、再次提醒和下一劑窗口提醒將保持靜默。你設定了時間的日常提醒和累積劑量警告仍會送達。",
    ),
    "Start time": ("开始时间", "開始時間"),
    "End time": ("结束时间", "結束時間"),
    "Delete this routine?": ("删除这个日常？", "刪除這個日常？"),
    "Its items aren't deleted — they move to Unassigned in the Routines list.": (
        "其中的项目不会被删除——它们会移到日常列表的「未分组」中。",
        "其中的項目不會被刪除——它們會移到日常列表的「未分組」中。",
    ),
    "Start": ("开始", "開始"),
    "End": ("结束", "結束"),
    "Skip Today": ("今天跳过", "今天跳過"),
    "View Timeline": ("查看时间线", "查看時間線"),
    "Notifications, your pick": ("通知，由你决定", "通知，由你決定"),
    "Choose what Piru may send. Everything stays adjustable in Settings, switch by switch.": (
        "选择 Piru 可以发送的内容。所有开关之后都能在设置中逐一调整。",
        "選擇 Piru 可以傳送的內容。所有開關之後都能在設定中逐一調整。",
    ),
    "Never miss a dose": ("不漏掉任何一剂", "不漏掉任何一劑"),
    "Reminders at each routine's time — and, if you want, a gentle re-ask a little later, like snooze.": (
        "在每个日常设定的时间提醒你——如果需要，稍后还会像闹钟稍后提醒一样轻轻再问一次。",
        "在每個日常設定的時間提醒你——如果需要，稍後還會像鬧鐘稍後提醒一樣輕輕再問一次。",
    ),
    "During a session": ("使用期间", "使用期間"),
    "Hydration and wind-down nudges, wearing-off alerts, and onset/peak timing cues while something is active.": (
        "在有物质起效期间，提供补水与放松提醒、药效消退警示，以及起效/巅峰时间提示。",
        "在有物質起效期間，提供補水與放鬆提醒、藥效消退警示，以及起效/巔峰時間提示。",
    ),
    "A safety net": ("一道安全网", "一道安全網"),
    "A heads-up if one substance's daily total climbs into a heavy range, or tracked stock runs low.": (
        "当某一物质的当日总量攀升至大剂量范围，或追踪的库存不足时提醒你。",
        "當某一物質的當日總量攀升至大劑量範圍，或追蹤的庫存不足時提醒你。",
    ),
    "Enable Selected": ("开启所选", "開啟所選"),
    # Snooze-style routine follow-up reminders (2026-07-17).
    "Follow-Up Reminders": ("后续提醒", "後續提醒"),
    "Asks again a little later if a routine still isn't logged — like snooze for an alarm. Set it up on each routine.": (
        "如果日常迟迟未记录，稍后会再问一次——就像闹钟的稍后提醒。可在每个日常中开启。",
        "如果日常遲遲未記錄，稍後會再問一次——就像鬧鐘的稍後提醒。可在每個日常中開啟。",
    ),
    "Time Sensitive": ("时效性通知", "時效性通知"),
    "Time Sensitive notifications can break through Focus modes and the notification summary. Turn off any you'd rather have wait.": (
        "时效性通知可以突破专注模式和通知摘要。不希望立即送达的可以在这里关闭。",
        "時效性通知可以突破專注模式和通知摘要。不希望立即送達的可以在這裡關閉。",
    ),
    "Ask Again": ("再次提醒", "再次提醒"),
    "10 minutes later": ("10 分钟后", "10 分鐘後"),
    "10 and 30 minutes later": ("10 和 30 分钟后", "10 和 30 分鐘後"),
    "Time to log your %@ routine.": ("该记录「%@」日常了。", "該記錄「%@」日常了。"),
    "Still need to log your %@ routine?": (
        "还没记录「%@」日常吗？",
        "還沒記錄「%@」日常嗎？",
    ),
    "Comedown alerts are turned off": ("缓和期提醒已关闭", "緩和期提醒已關閉"),
    "Turn comedown alerts back on in Notification Settings to turn one on for this dose.": (
        "在通知设置中重新开启缓和期提醒，才能为这一剂设置提醒。",
        "在通知設定中重新開啟緩和期提醒，才能為這一劑設定提醒。",
    ),
    # Effect Estimator — the what-if / compare-two-meds sandbox tool (2026-07-17).
    "Effect Estimator": ("效果估算器", "效果估算器"),
    "Compare substances and preview how they may feel": (
        "比较不同物质，预览它们可能带来的感受",
        "比較不同物質，預覽它們可能帶來的感受",
    ),
    "Try a combination": ("试试组合", "試試組合"),
    "See how doses might feel over time — compare two meds, preview a stack, or change the timing — without logging anything. This is a scratch surface; nothing here touches your journal.": (
        "看看不同剂量随时间可能带来的感受——比较两种药物、预览叠加、或调整时间——无需记录任何内容。这是一个草稿区，不会影响你的记录。",
        "看看不同劑量隨時間可能帶來的感受——比較兩種藥物、預覽疊加、或調整時間——無需記錄任何內容。這是一個草稿區，不會影響你的記錄。",
    ),
    "Compare two meds": ("比较两种药物", "比較兩種藥物"),
    "Add a dose": ("添加剂量", "新增劑量"),
    "Add a calibrated substance": ("添加一种已校准的物质", "新增一種已校準的物質"),
    "Add a dose to model it": ("添加剂量以进行建模", "新增劑量以進行建模"),
    "The model anchors on five stimulants — amphetamine, methylphenidate, mephedrone, 3-MMC, 2-MMC. Add one of those (or a brand of it) and the others will shape the curves around it.": (
        "该模型以五种兴奋剂为基准——安非他明、哌甲酯、4-甲基甲卡西酮、3-MMC、2-MMC。添加其中之一（或它的品牌药），其他物质便会围绕它塑造曲线。",
        "該模型以五種興奮劑為基準——安非他命、哌甲酯、4-甲基甲卡西酮、3-MMC、2-MMC。加入其中之一（或它的品牌藥），其他物質便會圍繞它塑造曲線。",
    ),
    "Pick a substance and an amount to see how it may feel over time.": (
        "选择一种物质和剂量，即可查看它随时间可能带来的感受。",
        "選擇一種物質和劑量，即可查看它隨時間可能帶來的感受。",
    ),
    "Plan A": ("方案 A", "方案 A"),
    "Plan B": ("方案 B", "方案 B"),
    "Move to": ("移动到", "移動到"),
    "Compare with another plan": ("与另一个方案比较", "與另一個方案比較"),
    "Dose options": ("剂量选项", "劑量選項"),
    "Opens full size": ("打开完整视图", "開啟完整檢視"),
    "Calibrated": ("已校准", "已校準"),
    "Modeled alongside": ("可与其一同模拟", "可與其一同模擬"),
    "The model was calibrated on these. Each one can be modeled on its own.": (
        "模型以这些物质为基准校准，每一种都可单独模拟。",
        "模型以這些物質為基準校準，每一種都可單獨模擬。",
    ),
    "The engine can simulate these as part of a plan, but they need a calibrated substance in the same plan to anchor the curve.": (
        "引擎可以在方案中模拟这些物质，但同一方案中需要有一种已校准的物质来锚定曲线。",
        "引擎可以在方案中模擬這些物質，但同一方案中需要有一種已校準的物質來錨定曲線。",
    ),
    "Add a Dose": ("添加剂量", "新增劑量"),
    "Clear All": ("全部清除", "全部清除"),
    "At start": ("开始时", "開始時"),
    "%lld min later": ("%lld 分钟后", "%lld 分鐘後"),
    "%lld h later": ("%lld 小时后", "%lld 小時後"),
    "%lld h %lld m later": ("%1$lld 小时 %2$lld 分后", "%1$lld 小時 %2$lld 分後"),
    "All four lenses": ("全部四个视角", "全部四個視角"),
    "Choose a different substance": ("选择其他物质", "選擇其他物質"),
    "A second plan is drawn as its own curve, so you can hold two ideas side by side — two meds, or a split dose against a single one.": (
        "第二个方案会绘制为独立曲线，让你并排比较两种设想——两种药物，或分次服用与一次服用。",
        "第二個方案會繪製為獨立曲線，讓你並排比較兩種設想——兩種藥物，或分次服用與一次服用。",
    ),
    "Nothing here can anchor a curve. Add a calibrated substance — amphetamine, methylphenidate, mephedrone, 3-MMC, or 2-MMC.": (
        "此处没有可锚定曲线的物质。请添加一种已校准的物质——安非他命、哌甲酯、4-甲基甲卡西酮、3-MMC 或 2-MMC。",
        "此處沒有可錨定曲線的物質。請新增一種已校準的物質——安非他命、哌甲酯、4-甲基甲卡西酮、3-MMC 或 2-MMC。",
    ),
    "How this is estimated": ("估算方式", "估算方式"),
    "Measured pharmacokinetics": ("实测药代动力学", "實測藥物動力學"),
    "What the engine uses": ("引擎实际使用的数值", "引擎實際使用的數值"),
    "Binding used": ("所用结合数据", "所用結合數據"),
    "Weakest input": ("最弱输入", "最弱輸入"),
    "Model anchor dose": ("模型基准剂量", "模型基準劑量"),
    "Elimination rate (ke)": ("消除速率 (ke)", "消除速率 (ke)"),
    "Absorption rate (ka)": ("吸收速率 (ka)", "吸收速率 (ka)"),
    "Transporter weights": ("转运体权重", "轉運體權重"),
    "Releaser": ("释放剂", "釋放劑"),
    "Half-life (t½)": ("半衰期 (t½)", "半衰期 (t½)"),
    "Time to peak (Tmax)": ("达峰时间 (Tmax)", "達峰時間 (Tmax)"),
    "Bioavailability (F)": ("生物利用度 (F)", "生物利用度 (F)"),
    "Distribution (Vd)": ("分布容积 (Vd)", "分布容積 (Vd)"),
    "Reference dose": ("参考剂量", "參考劑量"),
    "Species": ("物种", "物種"),
    "µ-opioid drive": ("µ-阿片受体驱动", "µ-鴉片受體驅動"),
    "GABA-A drive": ("GABA-A 驱动", "GABA-A 驅動"),
    "No resolved pharmacology for this substance.": (
        "未能解析该物质的药理数据。",
        "未能解析該物質的藥理數據。",
    ),
    "What the simulation is actually computing, and why rate matters more than amount.": (
        "模拟实际在计算什么，以及为何速率比剂量更重要。",
        "模擬實際在計算什麼，以及為何速率比劑量更重要。",
    ),
    "Every curve starts as a number you typed and ends as a line on a chart. These are the steps in between.": (
        "每条曲线都始于你输入的一个数字，终于图上的一条线。以下是中间的每一步。",
        "每條曲線都始於你輸入的一個數字，終於圖上的一條線。以下是中間的每一步。",
    ),
    "From dose to concentration": ("从剂量到浓度", "從劑量到濃度"),
    "Your dose is first expressed as a multiple of that substance's reference dose — the amount the model was tuned around. It then moves through a three-stage absorption chain into a central compartment that clears by first-order elimination, using an absorption rate (ka) and an elimination rate (ke) derived from the measured half-life and time to peak.": (
        "你的剂量首先会换算为该物质参考剂量的倍数——即模型调校时所围绕的用量。随后它经过三级吸收链进入中央室，并以一级消除方式清除；其中吸收速率 (ka) 与消除速率 (ke) 由实测半衰期和达峰时间推导而来。",
        "你的劑量首先會換算為該物質參考劑量的倍數——即模型調校時所圍繞的用量。隨後它經過三級吸收鏈進入中央室，並以一級消除方式清除；其中吸收速率 (ka) 與消除速率 (ke) 由實測半衰期和達峰時間推導而來。",
    ),
    "Route changes how steeply the curve rises, and whether the drug redistributes into a peripheral compartment — not how high it peaks. An insufflated and an oral dose of the same size reach the same peak here. What differs is the slope, and the later stages are sensitive to slope.": (
        "给药途径改变的是曲线上升的陡峭程度，以及药物是否再分布到外周室——而非峰值高度。在此模型中，相同剂量的鼻吸与口服会达到相同的峰值。差别在于斜率，而后续各阶段对斜率非常敏感。",
        "給藥途徑改變的是曲線上升的陡峭程度，以及藥物是否再分布到周邊室——而非峰值高度。在此模型中，相同劑量的鼻吸與口服會達到相同的峰值。差別在於斜率，而後續各階段對斜率非常敏感。",
    ),
    "From concentration to target engagement": ("从浓度到靶点结合", "從濃度到標靶結合"),
    "Concentration becomes fractional occupancy of the dopamine, noradrenaline and serotonin transporters. The dopamine transporter gets a time-resolved binding equation — separate association and dissociation rates rather than instant equilibrium — so a drug that lets go slowly holds its occupancy plateau after concentration has begun to fall.": (
        "浓度会转换为多巴胺、去甲肾上腺素和血清素转运体的占据率。其中多巴胺转运体使用时间分辨的结合方程——分别设定结合与解离速率，而非瞬时平衡——因此解离缓慢的药物会在浓度开始下降后仍维持占据平台期。",
        "濃度會轉換為多巴胺、正腎上腺素和血清素轉運體的佔據率。其中多巴胺轉運體使用時間解析的結合方程——分別設定結合與解離速率，而非瞬時平衡——因此解離緩慢的藥物會在濃度開始下降後仍維持佔據平台期。",
    ),
    "The DAT:NET:SERT potency ratios are taken from one published assay, chosen by coverage and confidence, never mixed across labs. Only ratios measured in the same experiment are physically comparable.": (
        "DAT:NET:SERT 的效价比取自同一篇已发表的实验，依覆盖度与可信度择优，绝不跨实验室混用。只有在同一实验中测得的比值才具有物理可比性。",
        "DAT:NET:SERT 的效價比取自同一篇已發表的實驗，依覆蓋度與可信度擇優，絕不跨實驗室混用。只有在同一實驗中測得的比值才具有物理可比性。",
    ),
    "Everything present draws on one shared pool of free transporters, so a second substance finds fewer sites open. This is the point where combinations stop being additive.": (
        "在场的所有物质共用同一个空闲转运体池，因此第二种物质可用的位点更少。组合效应正是从这里开始不再是简单相加。",
        "在場的所有物質共用同一個空閒轉運體池，因此第二種物質可用的位點更少。組合效應正是從這裡開始不再是簡單相加。",
    ),
    "Releasers and reuptake blockers diverge": (
        "释放剂与再摄取抑制剂就此分道",
        "釋放劑與再攝取抑制劑就此分道",
    ),
    "A releaser's output is limited by the vesicular dopamine still in store, and is suppressed further if a reuptake blocker is also on board. A blocker is not store-limited — it raises dopamine by slowing clearance rather than by pushing transmitter out. The two are handled by different code paths, not by one shared knob.": (
        "释放剂的输出受限于囊泡中剩余的多巴胺存量；若同时存在再摄取抑制剂，还会被进一步压制。抑制剂则不受存量限制——它通过减慢清除而非推出递质来提升多巴胺。两者由不同的代码路径处理，而非共用一个参数。",
        "釋放劑的輸出受限於囊泡中剩餘的多巴胺存量；若同時存在再攝取抑制劑，還會被進一步壓制。抑制劑則不受存量限制——它透過減慢清除而非推出遞質來提升多巴胺。兩者由不同的程式路徑處理，而非共用一個參數。",
    ),
    "What you feel is a gap, not a level": (
        "你感受到的是差距，而非水平",
        "你感受到的是差距，而非水平",
    ),
    "Two internal compensation signals chase the drug-driven dopamine elevation: a fast one that settles within minutes (autoreceptor feedback, transporter trafficking) and a slow one over hours (synthesis regulation). The felt effect is modeled as the distance between dopamine and those expectations — never the dopamine level itself.": (
        "两条内部代偿信号追赶着药物引起的多巴胺升高：一条在数分钟内稳定（自受体反馈、转运体转运），另一条历时数小时（合成调节）。主观效应被建模为多巴胺与这些预期之间的距离——而绝非多巴胺水平本身。",
        "兩條內部代償訊號追趕著藥物引起的多巴胺升高：一條在數分鐘內穩定（自受體回饋、轉運體運輸），另一條歷時數小時（合成調節）。主觀效應被建模為多巴胺與這些預期之間的距離——而絕非多巴胺水平本身。",
    ),
    "The fast gap is the rush. Because the fast signal catches up within minutes, that gap is effectively proportional to how quickly dopamine rose. The slow gap is the high while it stays positive; once the slow expectation overshoots the falling dopamine, the same term turns into part of the comedown.": (
        "快速差距就是冲劲。由于快速信号在数分钟内即可追平，该差距实际上与多巴胺上升的速度成正比。缓慢差距在为正时即是高峰体验；一旦缓慢预期超过了正在下落的多巴胺，同一项便转为退药反应的一部分。",
        "快速差距就是衝勁。由於快速訊號在數分鐘內即可追平，該差距實際上與多巴胺上升的速度成正比。緩慢差距在為正時即是高峰體驗；一旦緩慢預期超過了正在下落的多巴胺，同一項便轉為退藥反應的一部分。",
    ),
    "Reward is gated by rate": ("奖赏受上升速率闸控", "獎賞受上升速率閘控"),
    "Reward is multiplied by a gate that integrates how fast dopamine is rising. A substance can occupy the transporter fully and still register almost no reward if it arrived slowly — the same pharmacology reading as therapeutic or as euphoric depending on speed alone.": (
        "奖赏会乘上一个闸门，该闸门对多巴胺上升的速率进行积分。若到达缓慢，某物质即便完全占据转运体也几乎产生不了奖赏——同样的药理学，仅因速度不同，就可读作治疗性或欣快性。",
        "獎賞會乘上一個閘門，該閘門對多巴胺上升的速率進行積分。若到達緩慢，某物質即便完全佔據轉運體也幾乎產生不了獎賞——同樣的藥理學，僅因速度不同，就可讀作治療性或欣快性。",
    ),
    "Depletion, and where the comedown comes from": (
        "耗竭，以及退药反应的来源",
        "耗竭，以及退藥反應的來源",
    ),
    "Releasers spend vesicular stores in proportion to concentration, and dopamine elevation itself throttles resynthesis — so the debt deepens while the drug is still on board rather than being repaid in real time.": (
        "释放剂消耗囊泡存量的速度与浓度成正比，而多巴胺升高本身又抑制再合成——因此在药物仍在体内时亏空会不断加深，而非实时偿还。",
        "釋放劑消耗囊泡存量的速度與濃度成正比，而多巴胺升高本身又抑制再合成——因此在藥物仍在體內時虧空會不斷加深，而非即時償還。",
    ),
    "Past a threshold that debt switches on a comedown term, which then recovers with accelerating synthesis over hours. Serotonin activity cushions it. That is why an amphetamine crash and a cathinone's calmer return separate so sharply in these curves.": (
        "越过某一阈值后，这份亏空会启动退药项，随后在数小时内以逐渐加速的合成恢复。血清素活性会起到缓冲作用。这正是安非他命的崩落与卡西酮类平缓回落在这些曲线上分野如此鲜明的原因。",
        "越過某一閾值後，這份虧空會啟動退藥項，隨後在數小時內以逐漸加速的合成恢復。血清素活性會起到緩衝作用。這正是安非他命的崩落與卡西酮類平緩回落在這些曲線上分野如此鮮明的原因。",
    ),
    "The comedown here is over-compensation plus a depletion debt — not dopamine falling below baseline.": (
        "此处的退药反应是代偿过度加上耗竭亏空——并非多巴胺跌破基线。",
        "此處的退藥反應是代償過度加上耗竭虧空——並非多巴胺跌破基線。",
    ),
    "The four readouts": ("四项读数", "四項讀數"),
    "Feeling sums reward, serotonin and opioid warmth, and liking, minus the comedown.": (
        "「感受」将奖赏、血清素与阿片带来的暖意以及喜爱相加，再减去退药反应。",
        "「感受」將獎賞、血清素與鴉片帶來的暖意以及喜愛相加，再減去退藥反應。",
    ),
    "Energy is a noradrenaline-led inverted U set against its own adaptation, minus sedative load. Past a point, more noradrenergic drive lowers functional energy instead of adding to it.": (
        "「精力」是一条以去甲肾上腺素为主导、并与自身适应相抗衡的倒 U 形曲线，再减去镇静负荷。超过某一点后，更强的去甲肾上腺素驱动反而会降低而非提升功能性精力。",
        "「精力」是一條以正腎上腺素為主導、並與自身適應相抗衡的倒 U 形曲線，再減去鎮靜負荷。超過某一點後，更強的正腎上腺素驅動反而會降低而非提升功能性精力。",
    ),
    "Compulsion sums a slowly-decaying incentive envelope that charges from the rate of rise, and the gap between the rush you remember and the rush you are getting now.": (
        "「冲动」由两部分相加：一条由上升速率充能、衰减缓慢的激励包络，以及你记忆中的冲劲与当下实际冲劲之间的落差。",
        "「衝動」由兩部分相加：一條由上升速率充能、衰減緩慢的激勵包絡，以及你記憶中的衝勁與當下實際衝勁之間的落差。",
    ),
    "Strain sums a noradrenergic cardiovascular term drawing on a depletable vasoconstriction pool, plus an opioid respiratory term. It deliberately follows concentration rather than the felt gap, so it stays elevated after the effect itself has faded.": (
        "「负荷」由两项相加：一项取用可耗竭血管收缩池的去甲肾上腺素心血管项，以及一项阿片类呼吸抑制项。它刻意跟随浓度而非主观差距，因此在效应本身消退后仍会维持在高位。",
        "「負荷」由兩項相加：一項取用可耗竭血管收縮池的正腎上腺素心血管項，以及一項鴉片類呼吸抑制項。它刻意跟隨濃度而非主觀差距，因此在效應本身消退後仍會維持在高位。",
    ),
    "How it is solved": ("如何求解", "如何求解"),
    "All of it is a set of coupled differential equations advanced by forward Euler in half-minute steps across twelve hours or more.": (
        "这一切构成一组耦合微分方程，以前向欧拉法按半分钟步长推进，跨越十二小时以上。",
        "這一切構成一組耦合微分方程，以前向尤拉法按半分鐘步長推進，跨越十二小時以上。",
    ),
    "Every substance shares one set of neural constants. Only the store-depletion susceptibility is fitted per substance, anchored to the observed contrast between an amphetamine crash and a crashless cathinone.": (
        "所有物质共用同一组神经常数。只有存量耗竭易感性是逐物质拟合的，其锚点是安非他命崩落与不产生崩落的卡西酮之间的实测反差。",
        "所有物質共用同一組神經常數。只有存量耗竭易感性是逐物質擬合的，其錨點是安非他命崩落與不產生崩落的卡西酮之間的實測反差。",
    ),
    "Step by step": ("逐步拆解", "逐步拆解"),
    "No tolerance between sessions. Every simulation starts from a naive baseline; acclimation within the session is modeled, carry-over from yesterday is not.": (
        "不含跨次耐受。每次模拟都从未接触药物的基线开始；单次会话内的适应有被建模，但昨天的残留影响没有。",
        "不含跨次耐受。每次模擬都從未接觸藥物的基線開始；單次會話內的適應有被建模，但昨天的殘留影響沒有。",
    ),
    "No body weight, bioavailability or volume of distribution. Concentration here is dimensionless and relative to a reference dose, not a measured blood level.": (
        "不含体重、生物利用度或分布容积。此处的浓度是无量纲的、相对于参考剂量而言，并非实测血药浓度。",
        "不含體重、生物利用度或分布容積。此處的濃度是無量綱的、相對於參考劑量而言，並非實測血藥濃度。",
    ),
    "No genetics, no metabolizer phenotype, and no drug–drug metabolic interaction. Interactions are pharmacodynamic only: shared transporters, shared stores, shared receptors.": (
        "不含遗传因素、代谢表型，也不含药物间代谢相互作用。相互作用仅限药效学层面：共用转运体、共用存量、共用受体。",
        "不含遺傳因素、代謝表型，也不含藥物間代謝交互作用。交互作用僅限藥效學層面：共用轉運體、共用存量、共用受體。",
    ),
    "No individual variability. The same inputs always give the same curve, and no confidence band is drawn around it.": (
        "不含个体差异。相同输入永远给出相同曲线，且不会绘制置信区间。",
        "不含個體差異。相同輸入永遠給出相同曲線，且不會繪製信賴區間。",
    ),
    "Psychedelics, dissociatives and cannabinoids are out of scope — pharmacokinetics is not what drives their effects.": (
        "迷幻剂、解离剂与大麻素类不在适用范围内——药代动力学并非其效应的主导因素。",
        "迷幻劑、解離劑與大麻素類不在適用範圍內——藥物動力學並非其效應的主導因素。",
    ),
    "What this does not model": ("本模型不涵盖的内容", "本模型不涵蓋的內容"),
    "The idea first, then every stage from your dose to the line on the chart.": (
        "先讲思路，再逐一拆解从你的剂量到图上那条线的每个阶段。",
        "先講思路，再逐一拆解從你的劑量到圖上那條線的每個階段。",
    ),
    "The calculation, step by step": ("逐步拆解计算过程", "逐步拆解計算過程"),
    "Pick a substance and an amount above to see how it may feel over time.": (
        "在上方选择一种物质和剂量，即可查看它随时间可能带来的感受。",
        "在上方選擇一種物質和劑量，即可查看它隨時間可能帶來的感受。",
    ),
    "This shows what the model predicts about the shape and sign of an effect — not what you should take. It is an estimate from typical pharmacology, never a recommendation or a safe-dose guide.": (
        "这里展示的是模型对某种效果形态与正负的预测——而非你应该服用什么。它是基于典型药理学的估算，绝非建议或安全剂量指南。",
        "這裡展示的是模型對某種效果形態與正負的預測——而非你應該服用什麼。它是基於典型藥理學的估算，絕非建議或安全劑量指南。",
    ),
    "Calibrated on five stimulants; other substances shape the curves through how they interact with those. Compare the shape of a curve more than its exact height.": (
        "基于五种兴奋剂校准；其他物质通过与它们的相互作用来影响曲线。比较曲线的形态，胜过比较其确切高度。",
        "基於五種興奮劑校準；其他物質透過與它們的相互作用來影響曲線。比較曲線的形態，勝過比較其確切高度。",
    ),
    "Your own response shifts with tolerance, body chemistry, and the day. Talk to a prescriber about your medication.": (
        "你自身的反应会随耐受度、身体状况和当天情况而变化。有关你的用药，请咨询开药医生。",
        "你自身的反應會隨耐受度、身體狀況和當天情況而變化。有關你的用藥，請諮詢開藥醫生。",
    ),
    "Reading these estimates": ("解读这些估算", "解讀這些估算"),
    "Choose substance": ("选择物质", "選擇物質"),
    "start": ("起始", "起始"),
    "+%@h": ("+%@ 小时", "+%@ 小時"),
    "Earlier": ("提前", "提前"),
    "Later": ("延后", "延後"),
    "Time offset": ("时间偏移", "時間偏移"),
    "Pick a substance": ("选择物质", "選擇物質"),
    "at start": ("在起始时", "在起始時"),
    "plus %@ hours": ("加 %@ 小时", "加 %@ 小時"),
    # Pill picker — branded fixed-strength meds logged as tablets/capsules (2026-07-17).
    "extended-release": ("缓释", "緩釋"),
    "immediate-release": ("速释", "速釋"),
    "depot": ("长效", "長效"),
    "%@ tablet": ("%@ 片", "%@ 片"),
    "%@ tablets": ("%@ 片", "%@ 片"),
    "%@ capsule": ("%@ 粒", "%@ 粒"),
    "%@ capsules": ("%@ 粒", "%@ 粒"),
    "Custom milligrams": ("自定义毫克", "自訂毫克"),
    "Fewer pills": ("减少药片", "減少藥片"),
    "More pills": ("增加药片", "增加藥片"),
    "Quantity": ("数量", "數量"),
    # Apple Health vitals overlay — heart rate / blood pressure on sessions (2026-07-06).
    "Heart rate": ("心率", "心率"),
    "Heart Rate": ("心率", "心率"),
    "Blood pressure": ("血压", "血壓"),
    "Show on sessions": ("在记录中显示", "在記錄中顯示"),
    "The same Health connection also switches on your heart rate and blood pressure on each session — you can turn that off anytime in Settings.": (
        "同一“健康”连接还会在每次记录中开启你的心率和血压显示——可随时在“设置”中关闭。",
        "同一「健康」連線還會在每次記錄中開啟你的心率和血壓顯示——可隨時在「設定」中關閉。",
    ),
    "Piru reads your latest body weight from Health, read-only, and switches on the heart-rate & blood-pressure overlay for your sessions (off-able under Heart Rate). Revoke access anytime in Settings ▸ Health ▸ Data Access.": (
        "Piru 以只读方式读取你在“健康”中的最新体重，并为你的记录开启心率和血压叠加显示（可在“心率”中关闭）。可随时在“设置 ▸ 健康 ▸ 数据访问”中撤销权限。",
        "Piru 以唯讀方式讀取你在「健康」中的最新體重，並為你的記錄開啟心率和血壓疊加顯示（可在「心率」中關閉）。可隨時在「設定 ▸ 健康 ▸ 資料取用」中撤銷權限。",
    ),
    "Connect Apple Health": ("连接“健康”App", "連接「健康」App"),
    "Open Health Settings": ("打开“健康”设置", "打開「健康」設定"),
    "Not seeing your heart rate on a session? Apple doesn't tell apps whether read access was granted, so tap Connect to (re)request it, or open Settings ▸ Health ▸ Data Access ▸ Piru and switch Heart Rate and Blood Pressure on.": (
        "在某次记录中看不到心率？Apple 不会告知 App 是否已获得读取权限，因此可点按“连接”来（重新）请求，或前往“设置 ▸ 健康 ▸ 数据访问 ▸ Piru”并打开“心率”和“血压”。",
        "在某次記錄中看不到心率？Apple 不會告知 App 是否已取得讀取權限，因此可點按「連接」來（重新）請求，或前往「設定 ▸ 健康 ▸ 資料取用 ▸ Piru」並開啟「心率」和「血壓」。",
    ),
    # Apple Health onboarding step redesign (2026-07-07).
    "Your body weight sizes every estimate to you — and your heart rate shows how your body actually answered each dose, right on the session timeline.": (
        "你的体重会让每项估算贴合你自己——而你的心率会直接在记录时间线上，显示身体对每次用量的真实反应。",
        "你的體重會讓每項估算貼合你自己——而你的心率會直接在記錄時間軸上，顯示身體對每次用量的真實反應。",
    ),
    "Synced from Apple Health — check the number looks right.": (
        "已从“健康”同步——请确认数值无误。",
        "已從「健康」同步——請確認數值無誤。",
    ),
    "Couldn't read a weight from Health. Set it above instead.": (
        "无法从“健康”读取体重，请在上方手动设置。",
        "無法從「健康」讀取體重，請在上方手動設定。",
    ),
    "Health access is read-only. Turn it off anytime in Settings.": (
        "“健康”访问为只读，可随时在“设置”中关闭。",
        "「健康」存取為唯讀，可隨時在「設定」中關閉。",
    ),
    "Connecting…": ("连接中…", "連線中…"),
    "Alcohol": ("酒精", "酒精"),
    "A couple of drinks, with the heart rate a watch recorded alongside.": (
        "两杯酒，以及手表同时记录的心率。",
        "兩杯酒，以及手錶同時記錄的心率。",
    ),
    "Example chart: an alcohol effect curve with heart rate rising and falling alongside it.": (
        "示例图表：酒精效应曲线，心率随之起伏。",
        "範例圖表：酒精效應曲線，心率隨之起伏。",
    ),
    # Unified Apple Health settings + session vitals discovery banner (2026-07-07).
    "Dismiss": ("关闭", "關閉"),
    "Show heart rate on sessions": ("在记录中显示心率", "在記錄中顯示心率"),
    "See your heart rate here": ("在这里查看你的心率", "在這裡查看你的心率"),
    "Turn On Apple Health": ("开启“健康”", "開啟「健康」"),
    "Connect Apple Health to overlay how your body responded to each dose — read-only.": (
        "连接“健康”，将身体对每次用量的反应叠加显示——仅供读取。",
        "連接「健康」，將身體對每次用量的反應疊加顯示——僅供讀取。",
    ),
    "Piru reads your latest body weight and overlays your heart rate & blood pressure on each session — all read-only, on your device. Revoke access anytime in Settings ▸ Health ▸ Data Access.": (
        "Piru 会读取你的最新体重，并在每次记录中叠加显示你的心率和血压——全部仅供读取，存于你的设备。可随时在“设置 ▸ 健康 ▸ 数据访问”中撤销权限。",
        "Piru 會讀取你的最新體重，並在每次記錄中疊加顯示你的心率和血壓——全部僅供讀取，存於你的裝置。可隨時在「設定 ▸ 健康 ▸ 資料取用」中撤銷權限。",
    ),
    "Your weight is the denominator that turns a dose into an exposure: the same dose hits harder the less you weigh. With it, Piru can estimate things like how strong a drink is for *your* body, and how repeated use builds tolerance. Your heart rate and blood pressure, laid over each session, then show how your body actually responded to a dose — turning a predicted curve into a record.": (
        "体重是把剂量换算成暴露量的分母：越轻，同样的剂量作用越强。有了它，Piru 才能估算诸如一杯酒对*你的*身体有多强、反复使用如何累积耐受等。而叠加在每次记录上的心率和血压，则显示身体对某次用量的真实反应——把预测曲线变成一份记录。",
        "體重是把劑量換算成暴露量的分母：越輕，同樣的劑量作用越強。有了它，Piru 才能估算諸如一杯酒對*你的*身體有多強、反覆使用如何累積耐受等。而疊加在每次記錄上的心率和血壓，則顯示身體對某次用量的真實反應——把預測曲線變成一份記錄。",
    ),
    # Redesigned unified Apple Health settings — weight footnotes by source (2026-07-07).
    "Synced from Apple Health. Your weight sizes every dose estimate — the same dose hits harder the less you weigh.": (
        "已从“健康”同步。体重决定每项剂量估算——越轻，同样的剂量作用越强。",
        "已從「健康」同步。體重決定每項劑量估算——越輕，同樣的劑量作用越強。",
    ),
    "Entered manually. Your weight sizes every dose estimate — the same dose hits harder the less you weigh.": (
        "已手动输入。体重决定每项剂量估算——越轻，同样的剂量作用越强。",
        "已手動輸入。體重決定每項劑量估算——越輕，同樣的劑量作用越強。",
    ),
    "Using the average 60 kg. Set yours above so estimates fit your body — the same dose hits harder the less you weigh.": (
        "正使用平均值 60 kg。在上方设置你的体重，让估算贴合你自己——越轻，同样的剂量作用越强。",
        "正使用平均值 60 kg。在上方設定你的體重，讓估算貼合你自己——越輕，同樣的劑量作用越強。",
    ),
    "Use the average (60 kg)": ("使用平均值（60 kg）", "使用平均值（60 kg）"),
    "Show heart data on sessions": ("在记录中显示心脏数据", "在記錄中顯示心臟數據"),
    "Heart data": ("心脏数据", "心臟數據"),
    "Connect once to pull your body weight, heart rate, and blood pressure from Health — all read-only, on your device. Workouts come too, only so a run isn't read as a dose's effect.": (
        "连接一次即可从“健康”读取你的体重、心率和血压——全部仅供读取，存于你的设备。锻炼记录也会一并读取，只为避免把一次跑步当成某次用药的效果。",
        "連接一次即可從「健康」讀取你的體重、心率和血壓——全部僅供讀取，存於你的裝置。運動記錄也會一併讀取，只為避免把一次跑步當成某次用藥的效果。",
    ),
    "Overlays your heart rate and blood pressure on each session's timeline — read-only. If something didn't connect — blood pressure especially, which iOS doesn't always prompt for — open **Settings ▸ Privacy & Security ▸ Health ▸ Piru** and turn it on there.": (
        "在每次记录的时间线上叠加显示你的心率和血压——仅供读取。若有项目未能连接（尤其是血压，iOS 不一定会弹出请求），请前往 **设置 ▸ 隐私与安全性 ▸ 健康 ▸ Piru** 手动开启。",
        "在每次記錄的時間軸上疊加顯示你的心率和血壓——僅供讀取。若有項目未能連接（尤其是血壓，iOS 不一定會彈出請求），請前往 **設定 ▸ 隱私權與安全性 ▸ 健康 ▸ Piru** 手動開啟。",
    ),
    "Piru reads your body weight and overlays your heart rate & blood pressure on each session — all read-only, on your device. If something didn't connect — blood pressure especially, which iOS doesn't always prompt for — open **Settings ▸ Privacy & Security ▸ Health ▸ Piru** and turn it on there.": (
        "Piru 会读取你的体重，并在每次记录中叠加显示你的心率和血压——全部仅供读取，存于你的设备。若有项目未能连接（尤其是血压，iOS 不一定会弹出请求），请前往 **设置 ▸ 隐私与安全性 ▸ 健康 ▸ Piru** 手动开启。",
        "Piru 會讀取你的體重，並在每次記錄中疊加顯示你的心率和血壓——全部僅供讀取，存於你的裝置。若有項目未能連接（尤其是血壓，iOS 不一定會彈出請求），請前往 **設定 ▸ 隱私權與安全性 ▸ 健康 ▸ Piru** 手動開啟。",
    ),
    "On": ("开", "開"),
    "Off": ("关", "關"),
    "avg %lld · peak %lld bpm": ("平均 %lld · 峰值 %lld bpm", "平均 %lld · 峰值 %lld bpm"),
    "%lld bpm": ("%lld bpm", "%lld bpm"),
    "Elevated vs your resting %lld bpm": ("高于静息心率 %lld bpm", "高於靜息心率 %lld bpm"),
    "Includes %lld min of workout — the dose rows leave it out": (
        "其中含 %lld 分钟锻炼——单次用药行已排除",
        "其中含 %lld 分鐘運動——單次用藥列已排除",
    ),
    "In line with your resting %lld bpm": ("与静息心率 %lld bpm 相当", "與靜息心率 %lld bpm 相當"),
    "Heart rate %lld rising to %lld beats per minute": (
        "心率 %lld，升至每分钟 %lld 次",
        "心率 %lld，升至每分鐘 %lld 次",
    ),
    "Heart rate %lld falling to %lld beats per minute": (
        "心率 %lld，降至每分钟 %lld 次",
        "心率 %lld，降至每分鐘 %lld 次",
    ),
    "Heart rate %lld beats per minute, no clear change": (
        "心率每分钟 %lld 次，无明显变化",
        "心率每分鐘 %lld 次，無明顯變化",
    ),
    "overlaps %@": ("与 %@ 重叠", "與 %@ 重疊"),
    "Overlays your Apple Watch heart rate — and any blood-pressure readings — on each session's timeline, and shows how your heart responded to each dose. Read-only; you can turn Piru's access off anytime in Settings ▸ Health ▸ Data Access. With no data for a session, nothing is shown.": (
        "将你的 Apple Watch 心率（以及任何血压读数）叠加到每次记录的时间线上，并显示你的心脏对每次用药的反应。仅供读取；你可以随时在“设置 ▸ 健康 ▸ 数据访问”中关闭 Piru 的访问权限。某次记录没有数据时，不会显示任何相关内容。",
        "將你的 Apple Watch 心率（以及任何血壓讀數）疊加到每次記錄的時間軸上，並顯示你的心臟對每次用藥的反應。僅供讀取；你可以隨時在「設定 ▸ 健康 ▸ 資料取用」中關閉 Piru 的存取權限。某次記錄沒有資料時，不會顯示任何相關內容。",
    ),
    "A modelled curve predicts what a dose *should* do; your heart rate shows what your body *actually* did — stimulants and alcohol both raise it, so seeing the two together turns a prediction into a record. A blood-pressure reading is worth attaching too: you often take one *because* you felt off.": (
        "模型曲线预测一次用药*应该*产生的效果；而你的心率显示身体*实际*的反应——兴奋剂和酒精都会使其升高，因此将两者放在一起看，就把预测变成了记录。血压读数也值得附上：你往往*正是因为*感觉不适才会去测量。",
        "模型曲線預測一次用藥*應該*產生的效果；而你的心率顯示身體*實際*的反應——興奮劑和酒精都會使其升高，因此將兩者放在一起看，就把預測變成了記錄。血壓讀數也值得附上：你往往*正是因為*感覺不適才會去測量。",
    ),
    # Share sheet previews + session image (2026-07-06).
    "Cumulative": ("累计", "累計"),
    "Image": ("图片", "圖片"),
    # Export any session (historical) — 2026-07-06.
    "Session Report": ("记录报告", "記錄報告"),
    "Session Data": ("记录数据", "記錄資料"),
    "View session image": ("查看记录图片", "查看記錄圖片"),
    "Tap to edit": ("轻点编辑", "輕點編輯"),
    # Consolidated "Share Session" sheet + entry points (2026-07-05).
    "Share Session": ("分享本次记录", "分享本次記錄"),
    "Share session": ("分享本次记录", "分享本次記錄"),
    "Session Image": ("记录图片", "記錄圖片"),
    "State Report": ("状态报告", "狀態報告"),
    "State Data": ("状态数据", "狀態資料"),
    "PDF": ("PDF", "PDF"),
    "Markdown": ("Markdown", "Markdown"),
    "Share": ("分享", "分享"),
    "Share Current State…": ("分享当前状态…", "分享目前狀態…"),
    "Share Current State": ("分享当前状态", "分享目前狀態"),
    "A snapshot of what's active right now — image, PDF, or data": (
        "此刻仍在活跃的物质快照 — 图片、PDF 或数据。",
        "此刻仍在活躍的物質快照 — 圖片、PDF 或資料。",
    ),
    # Session state export — PDF report + Markdown (2026-07-05).
    "Session Snapshot": ("本次记录快照", "本次記錄快照"),
    "Generated": ("生成时间", "產生時間"),
    "Session started": ("记录开始于", "記錄開始於"),
    "in progress": ("进行中", "進行中"),
    "Session started %@ · %@ in progress": (
        "记录开始于 %1$@ · %2$@ 进行中",
        "記錄開始於 %1$@ · %2$@ 進行中",
    ),
    "Right now — subjective state": ("此刻 — 主观感受", "此刻 — 主觀感受"),
    "Elimination": ("消除", "消除"),
    "Taken": ("摄入", "攝入"),
    "Skipped": ("已跳过", "已跳過"),
    "Skipped for today": ("今天已跳过", "今天已跳過"),
    "Intensity": ("强度", "強度"),
    "Next": ("下一阶段", "下一階段"),
    "baseline": ("基线", "基線"),
    "in body": ("在体内", "在體內"),
    "gone": ("已消除", "已消除"),
    "left in body": ("体内剩余", "體內剩餘"),
    "No half-life data — elimination not modelled": (
        "无半衰期数据 — 未建模消除",
        "無半衰期資料 — 未建模消除",
    ),
    "50% eliminated": ("消除 50%", "消除 50%"),
    "90% eliminated": ("消除 90%", "消除 90%"),
    "Effectively clear": ("基本清除", "基本清除"),
    "Sober": ("清醒", "清醒"),
    "zero-order": ("零级动力学", "零級動力學"),
    "Export Current State…": ("导出当前状态…", "匯出目前狀態…"),
    "Export Current State": ("导出当前状态", "匯出目前狀態"),
    "PDF Report": ("PDF 报告", "PDF 報告"),
    "Markdown (for an AI)": ("Markdown（供 AI 使用）", "Markdown（供 AI 使用）"),
    "A snapshot of what's active right now — effects and elimination.": (
        "此刻仍在活跃的物质快照 — 效果与消除。",
        "此刻仍在活躍的物質快照 — 效果與消除。",
    ),
    "Model estimates (one-compartment oral PK; alcohol zero-order) from population half-lives and your logged doses — individual clearance varies. Subjective intensity is relative to each dose's own peak, not a measure of impairment. Not medical advice.": (
        "模型估算（单室口服 PK；酒精按零级动力学）基于群体半衰期与你记录的剂量 — 个体清除速度存在差异。主观强度相对于每次剂量自身的峰值，并非损伤程度的衡量。不构成医疗建议。",
        "模型估算（單室口服 PK；酒精按零級動力學）基於群體半衰期與你記錄的劑量 — 個體清除速度存在差異。主觀強度相對於每次劑量自身的峰值，並非損傷程度的衡量。不構成醫療建議。",
    ),
    # Opioid Equivalence + Pharma Table + Insights/Education (2026-07-04) — CLI-added, not yet extracted.
    "Loading pharmacology…": ("正在加载药理学数据…", "正在載入藥理學資料…"),
    "Targets": ("靶点", "靶點"),
    "Potency": ("效价", "效價"),
    "Show": ("显示", "顯示"),
    "All substances": ("所有物质", "所有物質"),
    "PK columns": ("药代动力学列", "藥代動力學列"),
    "Filters and columns": ("筛选与列", "篩選與列"),
    "mechanism of action": ("作用机制", "作用機制"),
    "primary receptor targets": ("主要受体靶点", "主要受體靶點"),
    "primary target potency": ("主要靶点效价", "主要靶點效價"),
    "Substances you log will appear here while they're still estimated to be in your body.": (
        "你记录的物质在预计仍留存于体内期间会显示在这里。",
        "你記錄的物質在預計仍留存於體內期間會顯示在這裡。",
    ),
    "Related": ("相关", "相關"),
    "Model a single dose's decay over time": (
        "模拟单次剂量随时间的衰减",
        "模擬單次劑量隨時間的衰減",
    ),
    "See what's active in your body right now": (
        "查看当前体内仍活跃的物质",
        "查看當前體內仍活躍的物質",
    ),
    "entries": ("条记录", "筆記錄"),
    "%@/day": ("%@/天", "%@/天"),
    "Past 2 weeks": ("过去两周", "過去兩週"),
    "Doses logged per day over the past two weeks": (
        "过去两周每天记录的剂量数",
        "過去兩週每天記錄的劑量數",
    ),
    "%lld in the last 14 days": ("过去 14 天共 %lld 次", "過去 14 天共 %lld 次"),
    "Track prescriptions in Settings to see adherence": (
        "在设置中追踪处方以查看依从性",
        "在設定中追蹤處方以查看依從性",
    ),
    "%@ this month": ("本月 %@", "本月 %@"),
    "This month's adherence calendar": ("本月依从性日历", "本月依從性日曆"),
    "%lld showing tolerance": ("%lld 项出现耐受", "%lld 項出現耐受"),
    "Receptors rested": ("受体已恢复", "受體已恢復"),
    "No notable predicted tolerance right now": ("当前无明显的预测耐受", "當前無明顯的預測耐受"),
    "Morphine": ("吗啡", "嗎啡"),
    "Codeine": ("可待因", "可待因"),
    "Hydrocodone": ("氢可酮", "氫可酮"),
    "Oxycodone": ("羟考酮", "羥考酮"),
    "Oxymorphone": ("羟吗啡酮", "羥嗎啡酮"),
    "Hydromorphone": ("氢吗啡酮", "氫嗎啡酮"),
    "Tramadol": ("曲马多", "曲馬多"),
    "Tapentadol": ("他喷他多", "他噴他多"),
    "Methadone": ("美沙酮", "美沙酮"),
    "Fentanyl (transdermal)": ("芬太尼（透皮）", "芬太尼（透皮）"),
    "Buprenorphine": ("丁丙诺啡", "丁丙諾啡"),
    "Methadone's potency rises with dose (nonlinear) and its long, variable half-life makes any single factor unsafe. CDC removed its conversion factor. Never back-calculate a methadone dose from MME — this must be done by a clinician.": (
        "美沙酮的效价随剂量升高（非线性），且半衰期长而多变，任何单一换算系数都不安全。CDC 已取消其换算系数。切勿根据 MME 反推美沙酮剂量——这必须由临床医生完成。",
        "美沙酮的效價隨劑量升高（非線性），且半衰期長而多變，任何單一換算係數都不安全。CDC 已取消其換算係數。切勿根據 MME 反推美沙酮劑量——這必須由臨床醫生完成。",
    ),
    "Transdermal fentanyl is dosed in micrograms per hour, not milligrams — it has no oral-mg equivalent (CDC uses ≈ 2.4 MME per mcg/hr). It can't share the mg-based table.": (
        "透皮芬太尼以微克/小时计量，而非毫克——没有口服毫克当量（CDC 使用约 2.4 MME 每 mcg/hr）。它无法套用基于毫克的换算表。",
        "透皮芬太尼以微克/小時計量，而非毫克——沒有口服毫克當量（CDC 使用約 2.4 MME 每 mcg/hr）。它無法套用基於毫克的換算表。",
    ),
    "Buprenorphine is a partial agonist with a ceiling on respiratory depression, so overdose risk doesn't scale linearly. CDC deliberately excludes it — MME does not apply.": (
        "丁丙诺啡是部分激动剂，对呼吸抑制存在封顶效应，因此过量风险不呈线性增长。CDC 有意将其排除——MME 不适用。",
        "丁丙諾啡是部分激動劑，對呼吸抑制存在封頂效應，因此過量風險不呈線性增長。CDC 有意將其排除——MME 不適用。",
    ),
    "Opioid Equivalence": ("阿片等效换算", "阿片等效換算"),
    "Convert a dose of one opioid to another through oral morphine milligram equivalents (MME), using the CDC 2022 conversion factors.": (
        "通过口服吗啡毫克当量（MME），使用 CDC 2022 换算系数，将一种阿片的剂量换算为另一种。",
        "透過口服嗎啡毫克當量（MME），使用 CDC 2022 換算係數，將一種阿片的劑量換算為另一種。",
    ),
    "≈ %@ mg oral morphine equivalent": ("≈ %@ mg 口服吗啡当量", "≈ %@ mg 口服嗎啡當量"),
    "CDC daily-risk bands: ≥ %lld MME caution, ≥ %lld MME high-risk (per day).": (
        "CDC 每日风险分级：≥ %lld MME 需谨慎，≥ %lld MME 高风险（每日）。",
        "CDC 每日風險分級：≥ %lld MME 需謹慎，≥ %lld MME 高風險（每日）。",
    ),
    "If taken over a day, this is a high-risk daily MME.": (
        "若一天内服用，这属于高风险的每日 MME。",
        "若一天內服用，這屬於高風險的每日 MME。",
    ),
    "If taken over a day, this reaches the CDC caution band.": (
        "若一天内服用，这已达到 CDC 谨慎分级。",
        "若一天內服用，這已達到 CDC 謹慎分級。",
    ),
    "Below the CDC daily caution band.": ("低于 CDC 每日谨慎分级。", "低於 CDC 每日謹慎分級。"),
    "This opioid can't be linearly converted — see the note below.": (
        "该阿片无法进行线性换算——请参见下方说明。",
        "該阿片無法進行線性換算——請參見下方說明。",
    ),
    "The target opioid can't be linearly converted — see the note below.": (
        "目标阿片无法进行线性换算——请参见下方说明。",
        "目標阿片無法進行線性換算——請參見下方說明。",
    ),
    "Pick two opioids and a dose.": ("请选择两种阿片和一个剂量。", "請選擇兩種阿片和一個劑量。"),
    "Not a simple conversion": ("并非简单换算", "並非簡單換算"),
    "Incomplete cross-tolerance": ("不完全交叉耐受", "不完全交叉耐受"),
    "When switching opioids, the equianalgesic dose is an over-estimate: tolerance to one opioid doesn't fully transfer to another. Clinicians start the new opioid **25–50% lower** than the calculated dose (more for high doses or frail/elderly people) and re-titrate. Never take the full converted dose.": (
        "更换阿片时，等效镇痛剂量会被高估：对一种阿片的耐受不会完全转移到另一种。临床医生会将新阿片的起始剂量定为比计算值 **低 25–50%**（剂量高或体弱/年长者更低），再重新滴定。切勿直接服用完整的换算剂量。",
        "更換阿片時，等效鎮痛劑量會被高估：對一種阿片的耐受不會完全轉移到另一種。臨床醫生會將新阿片的起始劑量定為比計算值 **低 25–50%**（劑量高或體弱/年長者更低），再重新滴定。切勿直接服用完整的換算劑量。",
    ),
    "MME is a population risk metric, not a precision dosing tool. CDC states the calculated MME should not be used to determine the dose when switching opioids.": (
        "MME 是群体风险指标，而非精确给药工具。CDC 指出，更换阿片时不应使用计算得出的 MME 来确定剂量。",
        "MME 是群體風險指標，而非精確給藥工具。CDC 指出，更換阿片時不應使用計算得出的 MME 來確定劑量。",
    ),
    "Individual variation is large — genetics (e.g. CYP2D6 for codeine, tramadol, oxycodone), liver and kidney function all shift real potency.": (
        "个体差异很大——遗传因素（如可待因、曲马多、羟考酮涉及的 CYP2D6）、肝肾功能都会改变实际效价。",
        "個體差異很大——遺傳因素（如可待因、曲馬多、羥考酮涉及的 CYP2D6）、肝腎功能都會改變實際效價。",
    ),
    "These oral factors don't cover every route or product. Transdermal, buccal, and IV forms differ.": (
        "这些口服换算系数并不涵盖所有给药途径或剂型。透皮、口颊和静脉剂型各不相同。",
        "這些口服換算係數並不涵蓋所有給藥途徑或劑型。透皮、口頰和靜脈劑型各不相同。",
    ),
    "Opioids plus benzodiazepines, alcohol, or other depressants sharply raise overdose risk. Carry naloxone.": (
        "阿片与苯二氮䓬、酒精或其他抑制剂合用会大幅提高过量风险。请随身携带纳洛酮。",
        "阿片與苯二氮䓬、酒精或其他抑制劑合用會大幅提高過量風險。請隨身攜帶納洛酮。",
    ),
    "Opioids plus benzodiazepines, alcohol, or other depressants sharply raise overdose risk. Tolerance also drops fast after a break — a dose you once handled can be fatal.": (
        "阿片与苯二氮䓬、酒精或其他抑制剂合用会大幅提高过量风险。而且中断一段时间后耐受会迅速下降——你以前能承受的剂量也可能致命。",
        "阿片與苯二氮䓬、酒精或其他抑制劑合用會大幅提高過量風險。而且中斷一段時間後耐受會迅速下降——你以前能承受的劑量也可能致命。",
    ),
    "Don't use alone and don't mix with other downers. An overdose is a sudden blackout with no warning — you can't naloxone yourself, so someone with you needs it and should call emergency services.": (
        "不要独自使用，也不要与其他抑制剂混用。过量会毫无预兆地突然失去意识——你无法给自己使用纳洛酮，因此身边的人需要备有纳洛酮，并应拨打急救电话。",
        "不要獨自使用，也不要與其他抑制劑混用。過量會毫無預兆地突然失去意識——你無法給自己使用納洛酮，因此身邊的人需要備有納洛酮，並應撥打急救電話。",
    ),
    "An opioid overdose is a sudden loss of consciousness with no warning — you can't give yourself naloxone. Don't use alone: someone with you needs naloxone and should call emergency services. Nodding off can also lead to choking on vomit or burns, so never use where you might pass out unattended.": (
        "阿片过量会毫无预兆地突然失去意识——你无法给自己使用纳洛酮。不要独自使用：身边的人需要备有纳洛酮，并应拨打急救电话。昏睡还可能导致呕吐物窒息或烧伤，因此绝不要在无人陪伴、可能昏睡过去的地方使用。",
        "阿片過量會毫無預兆地突然失去意識——你無法給自己使用納洛酮。不要獨自使用：身邊的人需要備有納洛酮，並應撥打急救電話。昏睡還可能導致嘔吐物窒息或燒傷，因此絕不要在無人陪伴、可能昏睡過去的地方使用。",
    ),
    "%lld%% tolerance": ("耐受 %lld%%", "耐受 %lld%%"),
    "Education": ("学习", "學習"),
    "How dosing, tolerance, and recovery work": (
        "了解给药、耐受与恢复的原理",
        "了解給藥、耐受與恢復的原理",
    ),
    "Expand": ("展开", "展開"),
    "%@ + %@": ("%@ + %@", "%@ + %@"),
    "%@ and %@: %@": ("%@ 与 %@：%@", "%@ 與 %@：%@"),
    "Pharma Table": ("药理表格", "藥理表格"),
    "Search substances": ("搜索物质", "搜尋物質"),
    "Has half-life": ("有半衰期数据", "有半衰期資料"),
    "Filter by category": ("按类别筛选", "按類別篩選"),
    "Sort by substance name": ("按物质名称排序", "按物質名稱排序"),
    "Sort by %@": ("按 %@ 排序", "按 %@ 排序"),
    "Not sorted": ("未排序", "未排序"),
    "Sorted ascending": ("升序排列", "升序排列"),
    "Sorted descending": ("降序排列", "降序排列"),
    "Loading pharmacokinetics…": ("正在加载药代动力学数据…", "正在載入藥物動力學資料…"),
    "No substances match these filters.": (
        "没有物质符合这些筛选条件。",
        "沒有物質符合這些篩選條件。",
    ),
    "Tmax": ("Tmax", "Tmax"),
    "Cmax": ("Cmax", "Cmax"),
    "Vd": ("Vd", "Vd"),
    "half-life": ("半衰期", "半衰期"),
    "time to peak": ("达峰时间", "達峰時間"),
    "bioavailability": ("生物利用度", "生物利用度"),
    "maximum concentration": ("最高血药浓度", "最高血藥濃度"),
    "protein binding": ("血浆蛋白结合", "血漿蛋白結合"),
    "volume of distribution": ("分布容积", "分佈容積"),
    "clearance": ("清除率", "清除率"),
    "%@ h": ("%@ 小时", "%@ 小時"),
    "How Tolerance Works": ("耐受性原理", "耐受性原理"),
    "Convert opioid doses to morphine (MME)": (
        "将阿片剂量换算为吗啡（MME）",
        "將阿片劑量換算為嗎啡（MME）",
    ),
    "Why effects fade and how receptors recover": (
        "为何效果减弱以及受体如何恢复",
        "為何效果減弱以及受體如何恢復",
    ),
    "Browse pharmacokinetics for every substance": (
        "浏览每种物质的药代动力学",
        "瀏覽每種物質的藥物動力學",
    ),
    # Tolerance improvements (2026-07-02): stimulant CV two-mechanism copy (§6) + Insights card (§7).
    "Within a session the high fades faster than the strain on your heart — chasing it with more stacks onto a blood-pressure spike that hasn't eased. Space your doses.": (
        "一次嗨里，快感消退得比心脏的负担快——再加量去追，只会叠在一个还没缓下来的血压高峰上。把每次剂量间隔开。",
        "一次嗨裡，快感消退得比心臟的負擔快——再加量去追，只會疊在一個還沒緩下來的血壓高峰上。把每次劑量間隔開。",
    ),
    "With regular use, your resting heart rate and blood pressure tend to settle over weeks.": (
        "长期规律使用，你静息时的心率和血压通常会在几周内慢慢回落。",
        "長期規律使用，你靜息時的心率和血壓通常會在幾週內慢慢回落。",
    ),
    "%lld mechanisms showing tolerance": ("%lld 个机制出现耐受", "%lld 個機制出現耐受"),
    # Alcohol by-drink logging (2026-07-02) — preset list, steppers, a11y labels.
    "Drink": ("饮品", "飲品"),
    "Choose drink": ("选择饮品", "選擇飲品"),
    "Opens your drink presets": ("打开你的饮品预设", "開啟你的飲品預設"),
    "Your drinks": ("你的饮品", "你的飲品"),
    "Add preset": ("添加预设", "新增預設"),
    "New preset": ("新预设", "新預設"),
    "Edit preset": ("编辑预设", "編輯預設"),
    "Save preset": ("保存预设", "儲存預設"),
    "Fixed serving size": ("固定分量", "固定份量"),
    "Name (e.g. IPA)": ("名称（如 IPA）", "名稱（如 IPA）"),
    "Drink emoji": ("饮品表情", "飲品表情"),
    "Lower strength": ("降低浓度", "降低濃度"),
    "Raise strength": ("提高浓度", "提高濃度"),
    "Lower volume": ("减少容量", "減少容量"),
    "Raise volume": ("增加容量", "增加容量"),
    "· %@ std drinks": ("· %@ 标准杯", "· %@ 標準杯"),
    "Drink: %@": ("饮品：%@", "飲品：%@"),
    "Edit %@": ("编辑 %@", "編輯 %@"),
    "Delete %@": ("删除 %@", "刪除 %@"),
    "Log %@, %@": ("记录 %@，%@", "記錄 %@，%@"),
    # Tolerance tool toolbar cleanup (2026-07-01) — Mail-style options menu + per-substance mode.
    # ("By mechanism" already lives in the tolerance-explainer block below — reused here.)
    "By substance": ("按物质", "按物質"),
    "Display options": ("显示选项", "顯示選項"),
    "Log a few doses and each substance's tolerance shows up here.": (
        "记录几次剂量后，每种物质的耐受性都会显示在这里。",
        "記錄幾次劑量後，每種物質的耐受性都會顯示在這裡。",
    ),
    "Show all %lld doses": ("显示全部 %lld 次剂量", "顯示全部 %lld 次劑量"),
    "Show %lld latest doses": ("显示最近 %lld 次剂量", "顯示最近 %lld 次劑量"),
    "Show less": ("收起", "收起"),
    "Calculating each substance's contribution…": (
        "正在计算每种物质的贡献……",
        "正在計算每種物質的貢獻……",
    ),
    "Each card is that substance's own contribution. Mechanisms are shared, so your overall level (the chart above, or By mechanism) can be higher.": (
        "每张卡片是该物质自身的贡献。机制是共享的，所以你的整体水平（上方图表或“按机制”）可能更高。",
        "每張卡片是該物質自身的貢獻。機制是共享的，所以你的整體水平（上方圖表或「按機制」）可能更高。",
    ),
    # Onboarding redesign (2026-07-01): 8-step first-run flow — welcome, privacy, tour, depth, weight, reminders, import, done, tips.
    "Track what you take — and understand how it affects your body.": (
        "记录你摄入的一切——并了解它如何影响你的身体。",
        "記錄你攝入的一切——並了解它如何影響你的身體。",
    ),
    "Private by design": ("隐私为先", "隱私為先"),
    "Piru is built for sensitive data. Yours never leaves your device unless you choose.": (
        "Piru 专为敏感数据而打造。除非你选择，你的数据绝不会离开设备。",
        "Piru 專為敏感資料而打造。除非你選擇，你的資料絕不會離開裝置。",
    ),
    "Stays on your device": ("只留在你的设备上", "只留在你的裝置上"),
    "Your journal lives locally. No sign-up, no account required.": (
        "你的日志保存在本地。无需注册，无需账号。",
        "你的日誌保存在本機。無需註冊，無需帳號。",
    ),
    "No cloud unless you ask": ("云端由你决定", "雲端由你決定"),
    "Backups are opt-in and end-to-end encrypted with your key.": (
        "备份需你主动开启，并用你的密钥进行端到端加密。",
        "備份需你主動開啟，並用你的密鑰進行端到端加密。",
    ),
    "Never sold or shared": ("绝不出售或分享", "絕不出售或分享"),
    "There are no ads and no trackers. Your data is yours alone.": (
        "没有广告，也没有追踪器。你的数据只属于你。",
        "沒有廣告，也沒有追蹤器。你的資料只屬於你。",
    ),
    "How much detail?": ("想看多少细节？", "想看多少細節？"),
    "Piru can keep it simple or go deep into the pharmacology. Change this anytime in Settings.": (
        "Piru 可以保持简洁，也可以深入药理。随时可在设置中更改。",
        "Piru 可以保持簡潔，也可以深入藥理。隨時可在設定中更改。",
    ),
    "Gentle reminders": ("贴心的提醒", "貼心的提醒"),
    "Optional nudges that look out for you while a substance is active.": (
        "在物质起效期间为你留意的可选提醒。",
        "在物質起效期間為你留意的可選提醒。",
    ),
    "A reminder to drink water during stimulants and long sessions.": (
        "使用兴奋剂或长时间用药时，提醒你补充水分。",
        "使用興奮劑或長時間用藥時，提醒你補充水分。",
    ),
    "Wind down for sleep": ("睡前放松", "睡前放鬆"),
    "A heads-up when it's late enough that another dose could cost you sleep.": (
        "当时间已晚、再来一剂可能影响睡眠时，提前提醒你。",
        "當時間已晚、再來一劑可能影響睡眠時，提前提醒你。",
    ),
    "Know the phases": ("掌握各个阶段", "掌握各個階段"),
    "Optional alerts for onset, come-up, and peak so nothing catches you off guard.": (
        "可选的起效、上升期和巅峰提醒，让一切尽在掌握。",
        "可選的起效、上升期與巔峰提醒，讓一切盡在掌握。",
    ),
    "Turn On Reminders": ("开启提醒", "開啟提醒"),
    "Turning On…": ("正在开启…", "正在開啟…"),
    "Re-read from Health": ("重新从「健康」读取", "重新從「健康」讀取"),
    "Your data lives here": ("你的数据都在这里", "你的資料都在這裡"),
    "Backups, export & import, and preferences are all under Settings.": (
        "备份、导入导出和偏好设置都在「设置」中。",
        "備份、匯入匯出與偏好設定都在「設定」中。",
    ),
    "Not Now": ("暂不", "暫不"),
    "You're all set": ("一切就绪", "一切就緒"),
    "Tap the + button any time to log your first dose. Tips will point out the rest as you go.": (
        "随时点按 + 按钮记录你的第一笔剂量。其余功能会在使用中通过提示为你指引。",
        "隨時點按 + 按鈕記錄你的第一筆劑量。其餘功能會在使用中透過提示為你指引。",
    ),
    "Live Activity, when you want it": ("需要时，随手开启实时活动", "需要時，隨手開啟即時動態"),
    "Start one from any active session to watch it on your Lock Screen.": (
        "从任何进行中的记录开启，即可在锁定屏幕上查看。",
        "從任何進行中的記錄開啟，即可在鎖定畫面上查看。",
    ),
    "Track your stock": ("追踪你的库存", "追蹤你的庫存"),
    "Keep tabs on what you have on hand and get a heads-up when it runs low.": (
        "随时掌握你的现有量，库存不足时提醒你。",
        "隨時掌握你的現有量，庫存不足時提醒你。",
    ),
    "Back up anytime": ("随时备份", "隨時備份"),
    "Turn on end-to-end encrypted backups whenever you're ready.": (
        "准备好后，随时开启端到端加密备份。",
        "準備好後，隨時開啟端到端加密備份。",
    ),
    "Start Using Piru": ("开始使用 Piru", "開始使用 Piru"),
    "Log it in seconds": ("几秒即可记录", "幾秒即可記錄"),
    "Every dose lands on a timeline so you can see what's active — and when it fades.": (
        "每一笔剂量都会落在时间轴上，让你看清什么正在起效——以及何时消退。",
        "每一筆劑量都會落在時間軸上，讓你看清什麼正在起效——以及何時消退。",
    ),
    "1,500+ substances": ("1,500+ 种物质", "1,500+ 種物質"),
    "Browse by family — dosing, duration, effects, and interactions, sourced and cited.": (
        "按类别浏览——剂量、持续时间、效果与相互作用，皆有来源和引用。",
        "按類別瀏覽——劑量、持續時間、效果與相互作用，皆有來源與引用。",
    ),
    "Tools that have your back": ("为你保驾护航的工具", "為你保駕護航的工具"),
    "Check interactions, model tolerance, track your stock, and dose liquids safely.": (
        "检查相互作用、模拟耐受、追踪库存，并安全地量取液体剂量。",
        "檢查相互作用、模擬耐受、追蹤庫存，並安全地量取液體劑量。",
    ),
    "See your patterns": ("看清你的规律", "看清你的規律"),
    "Usage over time, times of day, and what's in your system right now — at a glance.": (
        "一目了然地查看长期用量、各时段分布，以及此刻体内的活性物质。",
        "一目了然地查看長期用量、各時段分佈，以及此刻體內的活性物質。",
    ),
    "Morning": ("上午", "上午"),
    "Afternoon": ("下午", "下午"),
    "Evening": ("晚上", "晚上"),
    "Night": ("夜间", "夜間"),
    "Half-Life": ("半衰期", "半衰期"),
    "Your body weight": ("你的体重", "你的體重"),
    "The same dose hits harder the less you weigh. Set yours so estimates fit your body — otherwise Piru assumes an average adult, about 60 kg.": (
        "体重越轻，同样的剂量作用越强。设置你的体重，让估算贴合你的身体——否则 Piru 会按普通成年人（约 60 公斤）计算。",
        "體重越輕，同樣的劑量作用越強。設定你的體重，讓估算貼合你的身體——否則 Piru 會按普通成年人（約 60 公斤）計算。",
    ),
    "I'll Set This Later": ("稍后再设置", "稍後再設定"),
    "Synced from Apple Health, and kept up to date. Check the number looks right.": (
        "已从 Apple 健康同步，并会保持更新。请确认上面的数字无误。",
        "已從 Apple 健康同步，並會保持更新。請確認上面的數字無誤。",
    ),
    "Couldn't read a weight from Health — you may not have granted access, or haven't logged one there. Set it above instead.": (
        "无法从「健康」读取体重——你可能尚未授权，或还没有在那里记录过。请改在上方设置。",
        "無法從「健康」讀取體重——你可能尚未授權，或還沒有在那裡記錄過。請改在上方設定。",
    ),
    "Continue": ("继续", "繼續"),
    "Bring your history": ("带上你的历史记录", "帶上你的歷史記錄"),
    "Already keep a journal? Import a Piru backup or a PsyLog-format export — or start with a clean slate.": (
        "已经在记录了？导入 Piru 备份或 PsyLog 格式的导出文件——或者从头开始。",
        "已經在記錄了？匯入 Piru 備份或 PsyLog 格式的匯出檔案——或者從頭開始。",
    ),
    "Import complete. Your data is ready.": (
        "导入完成，你的数据已就绪。",
        "匯入完成，你的資料已就緒。",
    ),
    "Piru backup": ("Piru 备份", "Piru 備份"),
    "Restore a full journal you exported from Piru.": (
        "恢复你从 Piru 导出的完整日志。",
        "還原你從 Piru 匯出的完整日誌。",
    ),
    "PsyLog format": ("PsyLog 格式", "PsyLog 格式"),
    "Import from PsyLog or any app that shares its format — both old and new versions.": (
        "从 PsyLog 或任何使用该格式的应用导入——新旧版本均支持。",
        "從 PsyLog 或任何使用該格式的應用程式匯入——新舊版本皆支援。",
    ),
    "Start Fresh": ("从头开始", "從頭開始"),
    "Log your first dose": ("记录你的第一笔剂量", "記錄你的第一筆劑量"),
    "Tap here any time to record what you've taken — it only takes a few seconds.": (
        "随时点这里记录你所摄入的——只需几秒钟。",
        "隨時點這裡記錄你所攝入的——只需幾秒鐘。",
    ),
    "Track it on your Lock Screen": ("在锁定屏幕上追踪", "在鎖定畫面上追蹤"),
    "Start a Live Activity to follow this session on your Lock Screen and Dynamic Island.": (
        "开启实时活动，在锁定屏幕和灵动岛上追踪本次记录。",
        "開啟即時動態，在鎖定畫面和靈動島上追蹤本次記錄。",
    ),
    # Substance inventory tracking (2026-06-30): manager, detail, restock/edit forms, stock cards, widget.
    "Inventory": ("库存", "庫存"),
    "No Inventory Yet": ("还没有库存", "尚無庫存"),
    "Track a substance to see how much you have left as you log doses.": (
        "追踪某种物质，随着记录剂量查看剩余用量。",
        "追蹤某種物質，隨著記錄劑量查看剩餘用量。",
    ),
    "Track a Substance": ("追踪物质", "追蹤物質"),
    "Track Substance": ("追踪物质", "追蹤物質"),
    "Restock · %@": ("补充 · %@", "補充 · %@"),
    "Track · %@": ("追踪 · %@", "追蹤 · %@"),
    "Add Inventory Item": ("添加库存项目", "新增庫存項目"),
    "Track how much you have on hand": ("追踪你的现有用量", "追蹤你的現有用量"),
    "Starting amount": ("初始数量", "初始數量"),
    "Amount added": ("补充数量", "補充數量"),
    "Use as baseline": ("用作基准量", "用作基準量"),
    "Set as new baseline": ("设为新基准量", "設為新基準量"),
    "Marks the amount after this as a full supply, so the bar can show how full you are. Leave off if this isn't a full restock.": (
        "将此操作后的数量标记为满量，进度条便能显示你的充足程度。如果这不是一次补满，请关闭。",
        "將此操作後的數量標記為滿量，進度條便能顯示你的充足程度。如果這不是一次補滿，請關閉。",
    ),
    "Custom substance — its doses count by exact name match.": (
        "自定义物质——其剂量按名称精确匹配计入。",
        "自訂物質——其劑量按名稱精確匹配計入。",
    ),
    "Restock": ("补充", "補充"),
    "Track": ("追踪", "追蹤"),
    "Not tracked": ("未追踪", "未追蹤"),
    "On hand": ("现有量", "現有量"),
    "Baseline (100%)": ("基准量 (100%)", "基準量 (100%)"),
    "Single dose": ("单次剂量", "單次劑量"),
    "Warn when below": ("低于此值时提醒", "低於此值時提醒"),
    "Counting": ("剂量计数", "劑量計數"),
    "The exact amount you have now. Changing it is logged as a correction.": (
        "你当前的确切数量。修改后会记录为一次校正。",
        "你目前的確切數量。修改後會記錄為一次校正。",
    ),
    "The amount that counts as a full supply for the bar. Set to 0 to hide the bar.": (
        "作为进度条满量基准的数量。设为 0 可隐藏进度条。",
        "作為進度條滿量基準的數量。設為 0 可隱藏進度條。",
    ),
    "Used to show how many doses you have left. Set to 0 to disable.": (
        "用于显示你还剩多少次剂量。设为 0 可停用。",
        "用於顯示你還剩多少次劑量。設為 0 可停用。",
    ),
    "Your remaining amount stands out once it drops below this. Set to 0 to disable.": (
        "当剩余量低于此值时会突出显示。设为 0 可停用。",
        "當剩餘量低於此值時會突出顯示。設為 0 可停用。",
    ),
    "History": ("历史记录", "歷史記錄"),
    "No restocks or doses yet.": ("还没有补充或剂量记录。", "尚無補充或劑量記錄。"),
    "Initial": ("初始量", "初始量"),
    "Adjustment": ("校正", "校正"),
    "Out": ("用尽", "用盡"),
    "Out of stock": ("库存用尽", "庫存用盡"),
    "Run-out estimate": ("用尽预估", "用盡預估"),
    "Estimated from your average daily use over the last 7 days. Shown only when you've dosed on most days, so a one-off doesn't skew it.": (
        "根据你过去 7 天的日均用量估算。仅在大多数日子都用药时显示，以免偶尔一次造成偏差。",
        "根據你過去 7 天的日均用量估算。僅在大多數日子都用藥時顯示，以免偶爾一次造成偏差。",
    ),
    "How this is calculated": ("如何计算", "如何計算"),
    "Daily avg %@": ("日均 %@", "日均 %@"),
    "Single dose %@ %@ · daily avg %@": ("单次剂量 %@ %@ · 日均 %@", "單次劑量 %@ %@ · 日均 %@"),
    "Doses in other units aren't counted.": ("其他单位的剂量不计入。", "其他單位的劑量不計入。"),
    "last dose %@": ("上次剂量 %@", "上次劑量 %@"),
    "~%lld doses left": ("剩约 %lld 次", "剩約 %lld 次"),
    "~%lld doses · %@ left": ("剩约 %lld 次 · %@", "剩約 %lld 次 · %@"),
    "%@ left": ("还剩 %@", "還剩 %@"),
    "%@, %@ %@ in stock": ("%@，库存 %@ %@", "%@，庫存 %@ %@"),
    "%@, %@ %@ in stock, low": ("%@，库存 %@ %@，偏低", "%@，庫存 %@ %@，偏低"),
    "%@, out of stock": ("%@，库存用尽", "%@，庫存用盡"),
    "Increase": ("增加", "增加"),
    "Decrease": ("减少", "減少"),
    "You're out of %@. Restock when you can.": (
        "你的 %@ 已用尽。请尽快补充。",
        "你的 %@ 已用盡。請盡快補充。",
    ),
    "Nothing tracked": ("未追踪任何物质", "未追蹤任何物質"),
    # Positional specifiers: EN order is (remaining, unit, substance) but zh
    # leads with the substance — the old "共 %@" rendered the drug NAME as a
    # "total" quantity.
    "%@ %@ of %@ left.": ("%3$@还剩 %1$@ %2$@。", "%3$@還剩 %1$@ %2$@。"),
    "Out of %@": ("%@已用尽", "%@已用盡"),
    "Running low on %@": ("%@所剩不多", "%@所剩不多"),
    "%@ of %@ %@ remaining": ("剩 %1$@，共 %2$@ %3$@", "剩 %1$@，共 %2$@ %3$@"),
    "Piru and PsychonautWiki files are plain, unencrypted JSON. Imported entries are added to your journal (duplicates are skipped). Encrypted restores can merge or replace. Inventory is included in Piru and encrypted backups, but not PsychonautWiki files.": (
        "Piru 和 PsychonautWiki 文件是未加密的纯 JSON。导入的条目会添加到你的日志中（重复项会跳过）。加密备份的恢复可以合并或替换。库存包含在 Piru 和加密备份中，但不包含在 PsychonautWiki 文件中。",
        "Piru 和 PsychonautWiki 檔案是未加密的純 JSON。匯入的條目會新增到你的日誌中（重複項會略過）。加密備份的還原可以合併或取代。庫存包含在 Piru 和加密備份中，但不包含在 PsychonautWiki 檔案中。",
    ),
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
    "Curated": ("人工整理", "人工整理"),
    "human assay": ("人体实验", "人體實驗"),
    "rat assay": ("大鼠实验", "大鼠實驗"),
    "mouse assay": ("小鼠实验", "小鼠實驗"),
    "animal assay": ("动物实验", "動物實驗"),
    "in-vitro assay": ("体外实验", "體外實驗"),
    "aggregator source": ("综合来源", "綜合來源"),
    "curated entry": ("人工整理条目", "人工整理條目"),
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
    # Off-Target Effects card. The concern chips describe the *consequence*, not
    # the binding strength — a bare 高/低 beside a receptor name would read as
    # affinity, which is the one thing this column never means.
    # ---------------------------------------------------------------
    # 2026-08-04 negative-clause sweep. "Say what it is, never what it isn't":
    # every ", not X" clause below was cut from the English, so the Chinese loses
    # its matching 而非／並非／不是 clause. Kept only where the negation is mandated
    # elsewhere — "not medical advice", "not clinical potency", and the
    # tolerance-by-receptor title, which name a belief the reader actively holds.
    "A releaser's output is limited by the vesicular dopamine still in store, and is suppressed further if a reuptake blocker is also on board. A blocker is not store-limited — it raises dopamine by slowing clearance rather than by pushing transmitter out. The two are handled by different code paths.": (
        "释放剂的输出受限于囊泡中剩余的多巴胺存量；若同时存在再摄取抑制剂，还会被进一步压制。抑制剂则不受存量限制——它通过减慢清除而非推出递质来提升多巴胺。两者由不同的代码路径处理。",
        "釋放劑的輸出受限於囊泡中剩餘的多巴胺存量；若同時存在再攝取抑制劑，還會被進一步壓制。抑制劑則不受存量限制——它透過減慢清除而非推出遞質來提升多巴胺。兩者由不同的程式路徑處理。",
    ),
    "Approximate — equivalence tables disagree. Treat this as a ballpark.": (
        "仅为近似——各等效换算表并不一致。请将其视为大致参考。",
        "僅為近似——各等效換算表並不一致。請將其視為大致參考。",
    ),
    "Based on first-pass metabolism of oral THC · educational. Onset and duration vary with dose, product, and tolerance.": (
        "基于口服 THC 的首过代谢 · 仅供教育参考。起效与持续时间因剂量、产品和耐受性而异。",
        "基於口服 THC 的首過代謝 · 僅供教育參考。起效與持續時間因劑量、產品和耐受性而異。",
    ),
    "Based on your self-reported alcohol flush · educational.": (
        "依据你自报的喝酒脸红 · 仅供参考。",
        "依據你自報的喝酒臉紅 · 僅供參考。",
    ),
    "Ceiling on effect — described in words (no precise dose knee).": (
        "效应封顶——以文字说明（没有精确的剂量拐点）。",
        "效應封頂——以文字說明（沒有精確的劑量拐點）。",
    ),
    "Steep, supralinear — described in words (no reliable human kinetics).": (
        "陡峭、超线性——以文字说明（缺乏可靠的人体动力学数据）。",
        "陡峭、超線性——以文字說明（缺乏可靠的人體動力學數據）。",
    ),
    "Codeine only works by being converted to morphine, and most people's CYP2D6 enzyme caps how much morphine they can make — so past a point, more codeine adds side-effects and duration while the pain relief plateaus.": (
        "可待因只有转化为吗啡才能起效，而大多数人的 CYP2D6 酶限制了能生成的吗啡量——因此超过某一点后，增加可待因只会带来更多副作用和更长的持续时间，镇痛则趋于平台。",
        "可待因只有轉化為嗎啡才能起效，而大多數人的 CYP2D6 酶限制了能生成的嗎啡量——因此超過某一點後，增加可待因只會帶來更多副作用和更長的持續時間，鎮痛則趨於平台。",
    ),
    "The limit is set by how much CYP2D6 enzyme you have. The analgesic plateau around ~60 mg is a clinical observation.": (
        "这个上限取决于你拥有多少 CYP2D6 酶。约 60 毫克左右的镇痛平台是临床观察结果。",
        "這個上限取決於你擁有多少 CYP2D6 酶。約 60 毫克左右的鎮痛平台是臨床觀察結果。",
    ),
    "Derived from this substance's graded DAT/NET/SERT bindings. Transporter potencies are mostly within-assay ratios.": (
        "依据该物质经分级的 DAT/NET/SERT 结合数据得出。转运体效价多为同一实验内的相对比值。",
        "依據該物質經分級的 DAT/NET/SERT 結合資料得出。轉運體效價多為同一實驗內的相對比值。",
    ),
    "Don't try to 'figure it all out' right now. Integration takes days.": (
        "现在不要试图「想通一切」。整合需要数天。",
        "現在不要試圖「想通一切」。整合需要數天。",
    ),
    "The foggy feeling will clear. Give it hours.": (
        "迷糊感会消散。需要数小时。",
        "迷糊感會消散。需要數小時。",
    ),
    "The low mood is chemical. It lifts.": (
        "情绪低落源于化学变化。它会过去。",
        "情緒低落源於化學變化。它會過去。",
    ),
    "This is a rebound effect. It passes.": (
        "这是反弹效应。它会过去。",
        "這是反彈效應。它會過去。",
    ),
    "Doses are milligrams of THC. Flower needed ≈ desired THC ÷ the strain's %THC (e.g. 3 mg ÷ 18% ≈ 0.02 g). Smoking loses 50–80% to combustion, so real flower amounts run higher.": (
        "剂量是 THC 的毫克数。所需花量 ≈ 目标 THC ÷ 品系的 THC 含量百分比（例如 3 mg ÷ 18% ≈ 0.02 g）。吸食会因燃烧损失 50–80%，因此实际所需花量更高。",
        "劑量是 THC 的毫克數。所需花量 ≈ 目標 THC ÷ 品系的 THC 含量百分比（例如 3 mg ÷ 18% ≈ 0.02 g）。吸食會因燃燒損失 50–80%，因此實際所需花量更高。",
    ),
    "Equivalences are approximate and contested. Use the cited value as a starting estimate.": (
        "等效值只是近似且存在争议。请将引用值作为起始估计。",
        "等效值只是近似且存在爭議。請將引用值作為起始估計。",
    ),
    "Estimates from primary literature.": (
        "数据为原始文献中的估计值。",
        "數據為原始文獻中的估計值。",
    ),
    "Kick-in and wear-off come from this med's own duration data — the same model the timeline draws. An estimate.": (
        "起效与消退时间来自这款药物自身的持续时间数据——与时间线所用的模型相同。这是估算。",
        "起效與消退時間來自這款藥物自身的持續時間資料——與時間線所用的模型相同。這是估算。",
    ),
    "MME is a population risk metric. CDC states the calculated MME should not be used to determine the dose when switching opioids.": (
        "MME 是群体风险指标。CDC 指出，更换阿片时不应使用计算得出的 MME 来确定剂量。",
        "MME 是群體風險指標。CDC 指出，更換阿片時不應使用計算得出的 MME 來確定劑量。",
    ),
    "No body weight, bioavailability or volume of distribution. Concentration here is dimensionless and relative to a reference dose.": (
        "不含体重、生物利用度或分布容积。此处的浓度是无量纲的、相对于参考剂量而言。",
        "不含體重、生物利用度或分布容積。此處的濃度是無量綱的、相對於參考劑量而言。",
    ),
    "Runs down with use and returns over weeks. MDMA-type use is slower because it dents serotonin supply as well as the receptors.": (
        "用着用着会减弱，要好几周才回得来。MDMA 这类更慢，因为它连血清素的供应一起伤到了。",
        "用著用著會減弱，要好幾週才回得來。MDMA 這類更慢，因為它連血清素的供應一起傷到了。",
    ),
    "Suppresses the enzyme that makes serotonin, so recovery takes weeks.": (
        "它会抑制生成血清素的那种酶，所以恢复要几周。",
        "它會抑制生成血清素的那種酶，所以恢復要幾週。",
    ),
    "Source: TripSit benzodiazepine dataset. Equivalences vary by reference (Ashton, manufacturer, clinical); these are a guide.": (
        "来源：TripSit 苯二氮䓬数据集。不同参考来源（Ashton、厂商、临床）的等效值各异；这些仅供参考。",
        "來源：TripSit 苯二氮䓬資料集。不同參考來源（Ashton、廠商、臨床）的等效值各異；這些僅供參考。",
    ),
    "These values were not measured together — each is its own study. Ranked here for scale.": (
        "这些数值并非在同一实验中测得——每个都来自各自的研究。此处排列只为呈现量级。",
        "這些數值並非在同一實驗中測得——每個都來自各自的研究。此處排列只為呈現量級。",
    ),
    "Transdermal fentanyl is dosed in micrograms per hour — it has no oral-mg equivalent (CDC uses ≈ 2.4 MME per mcg/hr). It can't share the mg-based table.": (
        "透皮芬太尼以微克/小时计量——没有口服毫克当量（CDC 使用约 2.4 MME 每 mcg/hr）。它无法套用基于毫克的换算表。",
        "透皮芬太尼以微克/小時計量——沒有口服毫克當量（CDC 使用約 2.4 MME 每 mcg/hr）。它無法套用基於毫克的換算表。",
    ),
    "What you feel is a gap": ("你感受到的是差距", "你感受到的是差距"),
    "This is a reduced effect · predicted (model, %@).": (
        "这是效果减弱 · 预测（模型，%@）。",
        "這是效果減弱 · 預測（模型，%@）。",
    ),
    "Binding affinities come from the NIMH PDSP Kᵢ database and primary literature; the recovery kinetics are calibrated to published human studies. Every parameter is graded, and anything resting on a class default is flagged. The cards are predicted from your dose log and these curated values — estimates.": (
        "结合亲和力来自 NIMH PDSP Kᵢ 数据库和原始文献；恢复动力学则照着已发表的人体研究校准。每个参数都标了可信度，凡是用了类别默认值的都会标出来。卡片是根据你的剂量记录和这些经过整理的数值预测出来的——都是估计值。",
        "結合親和力來自 NIMH PDSP Kᵢ 資料庫和原始文獻；恢復動力學則照著已發表的人體研究校準。每個參數都標了可信度，凡是用了類別預設值的都會標出來。卡片是根據你的劑量記錄和這些經過整理的數值預測出來的——都是估計值。",
    ),
    "MDA is an active drug of its own — more amphetamine-like and more hallucinogenic than MDMA, and longer-lived — so the later hours can feel qualitatively different from the peak.": (
        "MDA 本身就是一种活性药物——比 MDMA 更像安非他明、致幻性更强，也更持久——因此后段时间的体验在性质上会与峰值不同。",
        "MDA 本身就是一種活性藥物——比 MDMA 更像安非他命、致幻性更強，也更持久——因此後段時間的體驗在性質上會與峰值不同。",
    ),
    "Model estimates (one-compartment oral PK; alcohol zero-order) from population half-lives and your logged doses — individual clearance varies. Subjective intensity is relative to each dose's own peak. Not medical advice.": (
        "模型估算（单室口服 PK；酒精按零级动力学）基于群体半衰期与你记录的剂量 — 个体清除速度存在差异。主观强度相对于每次剂量自身的峰值。不构成医疗建议。",
        "模型估算（單室口服 PK；酒精按零級動力學）基於群體半衰期與你記錄的劑量 — 個體清除速度存在差異。主觀強度相對於每次劑量自身的峰值。不構成醫療建議。",
    ),
    "This is the mirror image of codeine: same CYP2D6 activation step, opposite danger. Two cautions. (1) Repeated dosing raises tramadol's own absorption (first-pass saturates, F climbs ~75%→90–100%), so steady-state levels run higher than a single dose predicts. (2) The opioid limb is carried almost entirely by the metabolite M1/O-DSMT (a potent 3.4 nM µ-agonist), so strong CYP2D6 inhibitors (paroxetine, fluoxetine, bupropion, quinidine) mute the painkilling effect while leaving — or raising — the serotonergic and seizure risk of the parent. “Cleaner” is not “safer.” Described in words.": (
        "这是可待因的镜像：同样的 CYP2D6 活化步骤，危险却相反。两点提醒。(1) 反复给药会提高曲马多自身的吸收（首过代谢饱和，生物利用度由约 75% 升至 90–100%），因此稳态血药浓度高于单次剂量的预测值。(2) 阿片效应几乎完全由代谢物 M1／O-DSMT（一种强效的 3.4 nM µ 受体激动剂）承载，因此强效 CYP2D6 抑制剂（帕罗西汀、氟西汀、安非他酮、奎尼丁）会削弱镇痛作用，同时保留——甚至升高——原药的 5-羟色胺能及致癫痫风险。“更干净”并不等于“更安全”。此处为文字描述。",
        "這是可待因的鏡像：同樣的 CYP2D6 活化步驟，危險卻相反。兩點提醒。(1) 反覆給藥會提高曲馬多自身的吸收（首過代謝飽和，生物利用度由約 75% 升至 90–100%），因此穩態血藥濃度高於單次劑量的預測值。(2) 鴉片效應幾乎完全由代謝物 M1／O-DSMT（一種強效的 3.4 nM µ 受體激動劑）承載，因此強效 CYP2D6 抑制劑（帕羅西汀、氟西汀、安非他酮、奎尼丁）會削弱鎮痛作用，同時保留——甚至升高——原藥的 5-羥色胺能及致癲癇風險。「更乾淨」並不等於「更安全」。此處為文字描述。",
    ),
    "This is the opposite of the alcohol/phenytoin ceiling: there the clearing enzyme saturates and exposure runs away upward; here the absorbing transporter (system-L / LAT1) saturates and exposure flattens out — a built-in brake, though it also caps the benefit of very large single doses and is why gabapentin is dosed several times a day. Pregabalin, the same drug class, uses the transporter differently and stays ~90% absorbed at any dose (dose-linear) — a clean contrast in the same family. Shown as relative shape.": (
        "这与酒精／苯妥英的“封顶”恰好相反：那里是清除酶饱和、暴露量失控上升；而这里是吸收转运体（system-L／LAT1）饱和、暴露量趋于平缓——这是一种内在的制动，不过它也限制了单次大剂量的获益，并且正是加巴喷丁每日分多次服用的原因。普瑞巴林虽属同一药物类别，却以不同方式利用该转运体，在任何剂量下都保持约 90% 的吸收（与剂量呈线性）——是同类药物中一个清晰的对照。此处显示的是相对形态。",
        "這與酒精／苯妥英的「封頂」恰好相反：那裡是清除酶飽和、暴露量失控上升；而這裡是吸收轉運體（system-L／LAT1）飽和、暴露量趨於平緩——這是一種內在的制動，不過它也限制了單次大劑量的獲益，並且正是加巴噴丁每日分多次服用的原因。普瑞巴林雖屬同一藥物類別，卻以不同方式利用該轉運體，在任何劑量下都保持約 90% 的吸收（與劑量呈線性）——是同類藥物中一個清晰的對照。此處顯示的是相對形態。",
    ),
    "Tramadol only becomes a strong opioid after CYP2D6 converts it to M1 — and how much you make depends on your genes. Most people plateau; “ultra-rapid metabolizers” have no such cap and can reach dangerous levels at ordinary doses.": (
        "曲马多只有在 CYP2D6 将其转化为 M1 后才成为强效阿片类药物——而生成多少取决于你的基因。多数人会达到平台；“超快代谢者”则没有这种上限，在普通剂量下也可能达到危险水平。",
        "曲馬多只有在 CYP2D6 將其轉化為 M1 後才成為強效鴉片類藥物——而生成多少取決於你的基因。多數人會達到平台；「超快代謝者」則沒有這種上限，在普通劑量下也可能達到危險水平。",
    ),
    "%@ acts through %@ — the pharmacology below is %@'s.": (
        "%@ 通过 %@ 起效——下方的药理数据来自 %@。",
        "%@ 透過 %@ 起效——下方的藥理資料來自 %@。",
    ),
    "Off-Target Effects": ("脱靶作用", "脫靶作用"),
    "Significant": ("影响明确", "影響明確"),
    "Limited": ("影响有限", "影響有限"),
    "Minor": ("影响轻微", "影響輕微"),
    "Clinically significant": ("具有临床意义", "具有臨床意義"),
    "Real but bounded": ("确有影响但有限", "確有影響但有限"),
    "Not clinically dominant": ("在临床上并不占主导", "在臨床上並不佔主導"),
    # Benzodiazepine duration ladder. The caption's negation is deliberate: every
    # reader arrives believing half-life is how long the drug is felt.
    "How Long It Stays": ("在体内停留多久", "在體內停留多久"),
    "Elimination half-life — not how long you feel it.": (
        "消除半衰期——不是你能感觉到的时长。",
        "消除半衰期——不是你能感覺到的時長。",
    ),
    "Metabolite of the above": ("上一项的代谢产物", "上一項的代謝產物"),
    # Antidepressant class card.
    "Drug Class": ("药物类别", "藥物類別"),
    "The rest of the family": ("同类其他药物", "同類其他藥物"),
    "When it peaks": (
        "最严重的时候",
        "最嚴重的時候",
    ),
    "Worst around %@": (
        "大约在%@最严重",
        "大約在%@最嚴重",
    ),
    "%lld hours": (
        "%lld小时",
        "%lld小時",
    ),
    "From a trial that stopped 57 people abruptly after a year or more of daily use and assessed them every day. Longer-acting drugs peak later because the drug is still leaving your system; active metabolites (diazepam, chlordiazepoxide, clonazepam) push it later still. When symptoms *start* is not shown because no source survives checking — the figures in circulation land at or after the measured peak, which cannot be right.": (
        "数据来自一项试验：57人在连续每日使用一年以上后骤然停药，并接受每日评估。长效药物达到最严重的时间更晚，因为药物仍在排出体内；活性代谢物（地西泮、氯氮䓬、氯硝西泮）会把这个时间推得更晚。这里不显示症状“开始”的时间，因为没有经得起核查的来源——流传的那些数字落在实测峰值当天或之后，这不可能成立。",
        "數據來自一項試驗：57人在連續每日使用一年以上後驟然停藥，並接受每日評估。長效藥物達到最嚴重的時間更晚，因為藥物仍在排出體內；活性代謝物（地西泮、氯二氮平、氯硝西泮）會把這個時間推得更晚。這裡不顯示症狀「開始」的時間，因為沒有經得起核查的來源——流傳的那些數字落在實測峰值當天或之後，這不可能成立。",
    ),
    "Peak timing: Rickels K, et al. Long-term therapeutic use of benzodiazepines. I. Effects of abrupt discontinuation. Arch Gen Psychiatry. 1990;47(10):899-907.": (
        "峰值时间来源：Rickels K 等，《苯二氮䓬类药物的长期治疗性使用（一）：骤然停药的影响》，《普通精神病学文献》1990;47(10):899-907。",
        "峰值時間來源：Rickels K 等，《苯二氮平類藥物的長期治療性使用（一）：驟然停藥的影響》，《普通精神病學文獻》1990;47(10):899-907。",
    ),
    "Symptom groups and drug classes: Navarrete F, et al. Benzodiazepine Dependence: Clinical and Molecular Aspects, Preventive Strategies and Therapeutic Approaches. Int J Mol Sci. 2026;27(3):1430.": (
        "症状分组与药物分类来源：Navarrete F 等，《苯二氮䓬类依赖：临床与分子层面、预防策略与治疗方法》，《国际分子科学杂志》2026;27(3):1430。",
        "症狀分組與藥物分類來源：Navarrete F 等，《苯二氮平類依賴：臨床與分子層面、預防策略與治療方法》，《國際分子科學雜誌》2026;27(3):1430。",
    ),
    "Both raise serotonin, so serotonin syndrome is possible — agitation, tremor, sweating, a racing heart — and most likely in the first weeks. This pairing is prescribed and monitored on purpose; SSRIs do not raise lithium levels.": (
        "两者都会升高5-羟色胺，因此可能出现5-羟色胺综合征——躁动、震颤、出汗、心跳加快，最常见于开始用药的头几周。这个组合本就是医生有意开出并加以监测的；SSRI 不会升高锂的血药浓度。",
        "兩者都會升高血清素，因此可能出現血清素症候群——躁動、顫抖、出汗、心跳加快，最常見於開始用藥的頭幾週。這個組合本就是醫師有意開出並加以監測的；SSRI 不會升高鋰的血藥濃度。",
    ),
    "Both raise serotonin, so serotonin syndrome is possible — agitation, tremor, sweating, a racing heart — and most likely in the first weeks. This pairing is prescribed and monitored on purpose; SNRIs do not raise lithium levels.": (
        "两者都会升高5-羟色胺，因此可能出现5-羟色胺综合征——躁动、震颤、出汗、心跳加快，最常见于开始用药的头几周。这个组合本就是医生有意开出并加以监测的；SNRI 不会升高锂的血药浓度。",
        "兩者都會升高血清素，因此可能出現血清素症候群——躁動、顫抖、出汗、心跳加快，最常見於開始用藥的頭幾週。這個組合本就是醫師有意開出並加以監測的；SNRI 不會升高鋰的血藥濃度。",
    ),
    "A large serotonin load on top of lithium's own. The lithium label names tramadol and fentanyl in this group; serotonin syndrome can start within hours.": (
        "在锂本身的5-羟色胺负荷之上再叠加一份很大的负荷。锂的说明书把曲马多和芬太尼列在这一组里；5-羟色胺综合征可在数小时内发作。",
        "在鋰本身的血清素負荷之上再疊加一份很大的負荷。鋰的說明書把曲馬多和吩坦尼列在這一組裡；血清素症候群可在數小時內發作。",
    ),
    "MAOIs block the enzyme that clears serotonin, so the load builds instead of levelling off. Serotonin syndrome is the risk; MAOIs do not raise lithium levels.": (
        "MAOI 阻断清除5-羟色胺的酶，因此负荷会不断累积而不是趋于平稳。风险是5-羟色胺综合征；MAOI 不会升高锂的血药浓度。",
        "MAOI 阻斷清除血清素的酶，因此負荷會不斷累積而不是趨於平穩。風險是血清素症候群；MAOI 不會升高鋰的血藥濃度。",
    ),
    "Of 62 reports of this combination, 47% described a seizure and 39% involved medical attention — against none of 34 reports for lamotrigine. Self-reported, so the rate is not a measured one, but no other pairing shows a signal like it.": (
        "在这一组合的62份报告中，47% 描述了癫痫发作，39% 涉及就医——而拉莫三嗪的34份报告中一例也没有。这些都是自我报告，所以这个比例并非实测值，但没有别的组合出现过这样的信号。",
        "在這一組合的62份報告中，47% 描述了癲癇發作，39% 涉及就醫——而拉莫三嗪的34份報告中一例也沒有。這些都是自我報告，所以這個比例並非實測值，但沒有別的組合出現過這樣的訊號。",
    ),
    "MDMA releases serotonin in bulk and lithium adds to it, so serotonin syndrome is the main risk. Seizures are reported for lithium with classic psychedelics; MDMA has not been looked at the same way.": (
        "MDMA 会大量释放5-羟色胺，锂在此之上再加一份，因此主要风险是5-羟色胺综合征。锂与经典致幻剂合用有癫痫发作的报告；MDMA 没有被同样地研究过。",
        "MDMA 會大量釋放血清素，鋰在此之上再加一份，因此主要風險是血清素症候群。鋰與經典致幻劑合用有癲癇發作的報告；MDMA 沒有被同樣地研究過。",
    ),
    "Source: the Ashton Manual's equivalence table, which calls these doses approximate and notes that not every clinician agrees with them.": (
        "来源：Ashton 手册的等效剂量表。该表自称这些剂量只是近似值，并指出并非所有临床医生都认同这些换算。",
        "來源：Ashton 手冊的等效劑量表。該表自稱這些劑量只是近似值，並指出並非所有臨床醫師都認同這些換算。",
    ),
    "Not in the Ashton Manual's equivalence table, and not sourced elsewhere — treat the number as a rough guide and dose by this drug's own threshold.": (
        "不在 Ashton 手册的等效剂量表中，也没有其他来源——这个数字只能当作粗略参考，请按这个药自身的阈值来把握剂量。",
        "不在 Ashton 手冊的等效劑量表中，也沒有其他來源——這個數字只能當作粗略參考，請按這個藥自身的閾值來拿捏劑量。",
    ),
    "One of these is from the Ashton Manual's equivalence table; the other is not in it and is not sourced elsewhere. Equivalences are approximate either way.": (
        "其中一个来自 Ashton 手册的等效剂量表，另一个不在表中、也没有其他来源。无论哪种，等效换算都只是近似。",
        "其中一個來自 Ashton 手冊的等效劑量表，另一個不在表中、也沒有其他來源。無論哪種，等效換算都只是近似。",
    ),
    "Which class this belongs in is argued over — the label is the conventional one, not a settled one.": (
        "它该归到哪一类是有争议的——这个标签是约定俗成的说法，而不是定论。",
        "它該歸到哪一類是有爭議的——這個標籤是約定俗成的說法，而不是定論。",
    ),
    "Selective serotonin reuptake inhibitor": (
        "选择性5-羟色胺再摄取抑制剂",
        "選擇性血清素回收抑制劑",
    ),
    "Serotonin–noradrenaline reuptake inhibitor": (
        "5-羟色胺-去甲肾上腺素再摄取抑制剂",
        "血清素-正腎上腺素回收抑制劑",
    ),
    "Noradrenaline reuptake inhibitor": (
        "去甲肾上腺素再摄取抑制剂",
        "正腎上腺素回收抑制劑",
    ),
    "Noradrenaline–dopamine reuptake inhibitor": (
        "去甲肾上腺素-多巴胺再摄取抑制剂",
        "正腎上腺素-多巴胺回收抑制劑",
    ),
    "Serotonin modulator and stimulator": (
        "5-羟色胺调节剂与激动剂",
        "血清素調節劑與激動劑",
    ),
    "Tricyclic antidepressant": ("三环类抗抑郁药", "三環類抗憂鬱藥"),
    "Monoamine oxidase inhibitor": ("单胺氧化酶抑制剂", "單胺氧化酶抑制劑"),
    "Serotonin antagonist and reuptake inhibitor": (
        "5-羟色胺拮抗与再摄取抑制剂",
        "血清素拮抗與回收抑制劑",
    ),
    "Noradrenergic and specific serotonergic antidepressant": (
        "去甲肾上腺素能与特异性5-羟色胺能抗抑郁药",
        "正腎上腺素能與特異性血清素能抗憂鬱藥",
    ),
    "Blocks the serotonin transporter and little else, which is why its effects and its side effects are both mostly serotonergic.": (
        "几乎只阻断5-羟色胺转运体，因此它的作用与副作用大多都是5-羟色胺性的。",
        "幾乎只阻斷血清素轉運體，因此它的作用與副作用大多都是血清素性的。",
    ),
    "Blocks serotonin and noradrenaline reuptake together. The noradrenaline share grows with dose, so a low dose can behave much like an SSRI.": (
        "同时阻断5-羟色胺和去甲肾上腺素的再摄取。去甲肾上腺素那一份随剂量增大，因此低剂量时表现可以很像SSRI。",
        "同時阻斷血清素和正腎上腺素的回收。正腎上腺素那一份隨劑量增大，因此低劑量時表現可以很像SSRI。",
    ),
    "Blocks the noradrenaline transporter and leaves the other two. In the prefrontal cortex that same transporter is what clears dopamine, so the effect there is not as purely noradrenergic as the name reads.": (
        "只阻断去甲肾上腺素转运体，另外两种不动。在前额叶皮层，清除多巴胺的正是同一个转运体，所以那里的作用并不像名字读起来那样纯粹是去甲肾上腺素性的。",
        "只阻斷正腎上腺素轉運體，另外兩種不動。在前額葉皮質，清除多巴胺的正是同一個轉運體，所以那裡的作用並不像名字讀起來那樣純粹是正腎上腺素性的。",
    ),
    "Blocks noradrenaline and dopamine reuptake, leaving serotonin alone — the activating end of the family.": (
        "阻断去甲肾上腺素和多巴胺的再摄取，不动5-羟色胺——这一类里偏兴奋的一端。",
        "阻斷正腎上腺素和多巴胺的回收，不動血清素——這一類裡偏興奮的一端。",
    ),
    "Blocks serotonin reuptake and acts on several serotonin receptors directly, agonist at some and antagonist at others. The receptor work is what separates it from an SSRI, not the transporter block they share.": (
        "既阻断5-羟色胺再摄取，又直接作用于多个5-羟色胺受体，对一些是激动，对另一些是拮抗。把它和SSRI区分开的是受体上的这部分作用，而不是两者共有的转运体阻断。",
        "既阻斷血清素回收，又直接作用於多個血清素受體，對一些是激動，對另一些是拮抗。把它和SSRI區分開的是受體上的這部分作用，而不是兩者共有的轉運體阻斷。",
    ),
    "Blocks serotonin and noradrenaline reuptake like an SNRI, and also histamine, muscarinic and α₁ receptors. That extra binding is the sedation, the dry mouth, and the narrow margin in overdose.": (
        "像SNRI一样阻断5-羟色胺和去甲肾上腺素的再摄取，同时还结合组胺、毒蕈碱和α₁受体。多出来的这部分结合，就是镇静、口干，以及过量时安全窗口狭窄的来源。",
        "像SNRI一樣阻斷血清素和正腎上腺素的回收，同時還結合組織胺、蕈毒鹼和α₁受體。多出來的這部分結合，就是鎮靜、口乾，以及過量時安全窗口狹窄的來源。",
    ),
    "Blocks the enzyme that breaks monoamines down, rather than the transporters that recycle them, so all three rise. The tyramine restriction and the long interaction list both follow from that.": (
        "阻断的是分解单胺的酶，而不是回收它们的转运体，所以三种单胺都会升高。酪胺饮食限制和那一长串相互作用，都由此而来。",
        "阻斷的是分解單胺的酶，而不是回收它們的轉運體，所以三種單胺都會升高。酪胺飲食限制和那一長串交互作用，都由此而來。",
    ),
    "Blocks 5-HT₂A while weakly inhibiting serotonin reuptake. The receptor block dominates at low doses, which is why trazodone reached far more people as a sleep drug than as an antidepressant.": (
        "阻断5-HT₂A，同时弱抑制5-羟色胺再摄取。低剂量时受体阻断占主导，这就是曲唑酮作为助眠药比作为抗抑郁药触及了多得多的人的原因。",
        "阻斷5-HT₂A，同時弱抑制血清素回收。低劑量時受體阻斷佔主導，這就是曲唑酮作為助眠藥比作為抗憂鬱藥觸及了多得多的人的原因。",
    ),
    "Raises noradrenaline and serotonin release by blocking the α₂ autoreceptors that normally brake it, instead of blocking reuptake. The H₁ block alongside it is the sedation and the appetite.": (
        "通过阻断本来起刹车作用的α₂自身受体来提高去甲肾上腺素和5-羟色胺的释放，而不是阻断再摄取。与之并行的H₁阻断，就是镇静和食欲的来源。",
        "透過阻斷本來起煞車作用的α₂自身受體來提高正腎上腺素和血清素的釋放，而不是阻斷回收。與之並行的H₁阻斷，就是鎮靜和食慾的來源。",
    ),
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
    "Bupropion": ("安非他酮", "安非他酮"),
    "Bupropion's reductive metabolites strongly inhibit CYP2D6, raising the levels of drugs cleared by it. For prodrugs activated by CYP2D6 (tramadol, codeine), it blocks the activation pathway instead.": (
        "安非他酮的还原代谢物强效抑制 CYP2D6，升高经该酶清除的药物浓度。对于由 CYP2D6 活化的前药（曲马多、可待因），其效果相反：活化通路被阻断。",
        "安非他酮的還原代謝物強效抑制 CYP2D6，升高經該酶清除的藥物濃度。對於由 CYP2D6 活化的前藥（曲馬多、可待因），其效果相反：活化通路被阻斷。",
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
    # Tolerance tool + explainer rewrite (Stage J, 2026-06-30). Friendly, second-person register
    # (a knowledgeable friend, not a textbook): 你, plain verbs, no academic 使/之/其, no cutesy particles.
    "Your brain adapts to what you keep giving it": (
        "你一直用，大脑就会去适应它",
        "你一直用，大腦就會去適應它",
    ),
    "Use a drug repeatedly and your brain learns to expect it, then pushes back to cancel the effect — so the same dose does less. That push-back is tolerance. Stop, and it relaxes back. It's not the drug “running out”; it's your system re-balancing around it.": (
        "一种药你反复用，大脑就学会了预判它，然后反过来抵消它的作用——所以同样的剂量效果就变小了。这种反向的推力就是耐受。你一停，它又会慢慢松回去。这不是药“用完了”，而是你的身体在围着它重新找平衡。",
        "一種藥你反覆用，大腦就學會了預判它，然後反過來抵消它的作用——所以同樣的劑量效果就變小了。這種反向的推力就是耐受。你一停，它又會慢慢鬆回去。這不是藥「用完了」，而是你的身體在圍著它重新找平衡。",
    ),
    "Why stopping can feel like the opposite": (
        "为什么一停反而像反过来了",
        "為什麼一停反而像反過來了",
    ),
    "When you stop, that push-back is briefly left unopposed — which is why withdrawal or a comedown often feels like the mirror of the drug's effects (a stimulant's flatness, an opioid's aches).": (
        "你一停，这股反向的推力会有一阵子没了对手——所以戒断或者落差感往往像药效的镜像（兴奋剂之后的提不起劲、阿片之后的浑身酸痛）。",
        "你一停，這股反向的推力會有一陣子沒了對手——所以戒斷或者落差感往往像藥效的鏡像（興奮劑之後的提不起勁、鴉片之後的渾身痠痛）。",
    ),
    "The idea": ("原理", "原理"),
    "Within a session": ("同一次使用之内", "同一次使用之內"),
    "A second dose soon after the first lands weaker — the fast-releasing pool runs thin (tachyphylaxis). It refills overnight, so it's separate from the slower tolerance below. Chasing it with more rarely works and stacks the risk.": (
        "第一次之后没多久再补一剂，效果会更弱——快速释放的那一部分被用得差不多了（快速耐受）。它过一夜就会补回来，所以和下面那种慢一点的耐受是两回事。靠多用来追效果很少奏效，反而把风险叠上去。",
        "第一次之後沒多久再補一劑，效果會更弱——快速釋放的那一部分被用得差不多了（快速耐受）。它過一夜就會補回來，所以和下面那種慢一點的耐受是兩回事。靠多用來追效果很少奏效，反而把風險疊上去。",
    ),
    "Over days to weeks": ("几天到几周之间", "幾天到幾週之間"),
    "Receptors and enzymes adjust, and your baseline shifts down — this is the tolerance most people mean, and what the bar on each card shows. It returns once you stop, at a pace set by the receptor.": (
        "受体和酶会做出调整，你的基线也往下移——大多数人说的耐受就是这种，每张卡片上那条进度条显示的也是它。你一停它就会回来，快慢由受体决定。",
        "受體和酶會做出調整，你的基線也往下移——大多數人說的耐受就是這種，每張卡片上那條進度條顯示的也是它。你一停它就會回來，快慢由受體決定。",
    ),
    "With heavy, prolonged use": ("长期大量使用之后", "長期大量使用之後"),
    "This can entrench a deeper change that takes months to relax. It shows up only well past everyday or therapeutic doses — steady use doesn't reach it.": (
        "这会留下一种更深的变化，要好几个月才松得下来。它只在远超日常或治疗剂量时才出现——正常用量碰不到它。",
        "這會留下一種更深的變化，要好幾個月才鬆得下來。它只在遠超日常或治療劑量時才出現——正常用量碰不到它。",
    ),
    "Three timescales": ("三种时间尺度", "三種時間尺度"),
    "Each card blends these into one reading: how much of your usual dose you'd feel now, and how long until it returns if you stop.": (
        "每张卡片把这几样合成一个结果：你现在还能感受到平时剂量的多少，以及停下来后要多久才能恢复。",
        "每張卡片把這幾樣合成一個結果：你現在還能感受到平時劑量的多少，以及停下來後要多久才能恢復。",
    ),
    "Two different drugs that hit the same receptor share tolerance. Recent LSD blunts a mushroom trip because both work at 5-HT2A; one benzodiazepine carries to another; one opioid to the next. That's why tolerance is tracked per receptor here, and why a “new” drug in the same family can still feel weak.": (
        "两种不同的药只要作用在同一个受体上，就会共享耐受。最近用过 LSD 会让蘑菇的体验变弱，因为两者都作用在 5-HT2A 上；一种苯二氮䓬会带到另一种；一种阿片会带到下一种。所以这里的耐受是按受体来算的，也是为什么同一类里一种“新”药用起来还是可能很弱。",
        "兩種不同的藥只要作用在同一個受體上，就會共享耐受。最近用過 LSD 會讓蘑菇的體驗變弱，因為兩者都作用在 5-HT2A 上；一種苯二氮平會帶到另一種；一種鴉片會帶到下一種。所以這裡的耐受是按受體來算的，也是為什麼同一類裡一種「新」藥用起來還是可能很弱。",
    ),
    "Your body learns when to brace": ("你的身体会学着做好准备", "你的身體會學著做好準備"),
    "When a drug is taken repeatedly in the same place, with the same ritual, the body learns to pre-compensate — it starts pushing back before the dose even arrives. That conditioned response is a real part of tolerance: you feel less, partly because your system saw the cues and braced for it.": (
        "在同一个地方、按同一套习惯反复用药，身体会学着提前代偿——还没等剂量生效就开始做出反向调整。这种条件反应确实是耐受的一部分：你感觉减弱了，有一部分原因正是你的系统看到了那些信号，提前做好了准备。",
        "在同一個地方、按同一套習慣反覆用藥，身體會學著提前代償——還沒等劑量生效就開始做出反向調整。這種條件反應確實是耐受的一部分：你感覺減弱了，有一部分原因正是你的系統看到了那些訊號，提前做好了準備。",
    ),
    "Change the setting, lose the bracing": ("换个地方，准备就不在了", "換個地方，準備就不在了"),
    "In a new place, the conditioned push-back doesn't fire, and the same dose hits as if tolerance were lower. Heroin-tolerant rats given a familiar dose in a novel environment died at markedly higher rates than ones dosed in their usual cage — the pharmacology was the same, the conditioning was not (Siegel et al., Science 1982).": (
        "换一个地方，那种条件性的反向调整就不会启动，同样的剂量会像耐受更低那样击中你。习惯了海洛因的大鼠在一个陌生环境下注射惯常剂量，死亡率明显高于在平时笼子里注射的——药理作用是一样的，条件反应不一样（Siegel 等，Science 1982）。",
        "換一個地方，那種條件性的反向調整就不會啟動，同樣的劑量會像耐受更低那樣擊中你。習慣了海洛因的大鼠在一個陌生環境下注射慣常劑量，死亡率明顯高於在平時籠子裡注射的——藥理作用是一樣的，條件反應不一樣（Siegel 等，Science 1982）。",
    ),
    "The cues alone can produce the opposite": (
        "光是信号就能引出反向效果",
        "光是訊號就能引出反向效果",
    ),
    "Once the compensatory response is conditioned, presenting the cues without the drug leaves the push-back running unopposed. The result feels like the drug's mirror: a stimulant's familiar setting without the stimulant can produce fatigue, an opioid's without the opioid can produce aches. This is one route into situational withdrawal.": (
        "一旦代偿反应被条件化了，只给信号不给药，反向调整就会在没有对手的情况下运行。感觉就像药效的反面：兴奋剂的熟悉环境里没有兴奋剂，可能会产生疲惫感；阿片的没有阿片，可能会出现疼痛。这是情境性戒断的一条路径。",
        "一旦代償反應被條件化了，只給訊號不給藥，反向調整就會在沒有對手的情況下運行。感覺就像藥效的反面：興奮劑的熟悉環境裡沒有興奮劑，可能會產生疲憊感；鴉片的沒有鴉片，可能會出現疼痛。這是情境性戒斷的一條路徑。",
    ),
    "Some tolerance only develops if you experience the effect": (
        "有些耐受只有在你体验到那种效果时才会形成",
        "有些耐受只有在你體驗到那種效果時才會形成",
    ),
    "Tolerance to amphetamine's appetite suppression does not build at all unless food is available while intoxicated — the tolerance is an instrumental response, not a receptor count (Carlton & Wolgin 1971). This means tolerance to one effect of a drug can exist while tolerance to another has never started.": (
        "安非他命对食欲的抑制，除非在药效期间有食物可吃，否则根本不会形成耐受——这种耐受是一种工具性反应，不是受体数量问题（Carlton & Wolgin 1971）。这意味着对一种药的某个效果可以有耐受，而对另一个效果的耐受可能从未开始。",
        "安非他命對食慾的抑制，除非在藥效期間有食物可吃，否則根本不會形成耐受——這種耐受是一種工具性反應，不是受體數量問題（Carlton & Wolgin 1971）。這意味著對一種藥的某個效果可以有耐受，而對另一個效果的耐受可能從未開始。",
    ),
    "The learned part of tolerance": ("耐受中学习来的部分", "耐受中學習來的部分"),
    "Siegel 1976; Siegel, Hinson, Krank & McCully 1982; Weise-Kelly & Siegel 2001; Carlton & Wolgin 1971.": (
        "Siegel 1976；Siegel、Hinson、Krank 和 McCully 1982；Weise-Kelly 和 Siegel 2001；Carlton 和 Wolgin 1971。",
        "Siegel 1976；Siegel、Hinson、Krank 和 McCully 1982；Weise-Kelly 和 Siegel 2001；Carlton 和 Wolgin 1971。",
    ),
    "Model boundary": ("模型边界", "模型邊界"),
    "What this number does not include": ("这个数字没有包含的部分", "這個數字沒有包含的部分"),
    "Every layer above is pharmacodynamic — it is computed from your dose log and the clock. A large part of real tolerance is associative and context-specific: it attaches to the setting, the ritual and the cues around a dose, which is why tolerance measured in a familiar context can be substantially higher than tolerance in an unfamiliar one, and why the same cues without the dose can produce the opposite of the drug's effect. Piru cannot see any of that, because it does not record where you were or what you were doing. Treat the shift as a pharmacological estimate, not a total.": (
        "上面所有层级都是药效动力学层面的——根据你的剂量记录和时间来计算。真实耐受中有很大一部分是联结性的、跟环境绑定的：它和用药时的地点、仪式、周围的线索绑在一起。这就是为什么在熟悉环境下测到的耐受可以远高于陌生环境，也是为什么同样的线索、没有药物时，身体可以产生药效的反面。Piru 看不到这些，因为它不记录你在哪里、在做什么。把这个数字当作药理学估计来看，不是总量。",
        "上面所有層級都是藥效動力學層面的——根據你的劑量記錄和時間來計算。真實耐受中有很大一部分是聯結性的、跟環境綁定的：它和用藥時的地點、儀式、周圍的線索綁在一起。這就是為什麼在熟悉環境下測到的耐受可以遠高於陌生環境，也是為什麼同樣的線索、沒有藥物時，身體可以產生藥效的反面。Piru 看不到這些，因為它不記錄你在哪裡、在做什麼。把這個數字當作藥理學估計來看，不是總量。",
    ),
    "Recovery timescales and behaviour are calibrated to the published literature for each receptor class. The note under each is the calibration basis; the badge is how well-established those kinetics are.": (
        "每一类受体的恢复时间和表现，都是照着已发表的文献校准的。每条下面的小字是校准依据；徽章表示这些动力学数据有多可靠。",
        "每一類受體的恢復時間和表現，都是照著已發表的文獻校準的。每條下面的小字是校準依據；徽章表示這些動力學數據有多可靠。",
    ),
    "Binding affinities come from the NIMH PDSP Kᵢ database and primary literature; the recovery kinetics are calibrated to published human studies. Every parameter is graded, and anything resting on a class default is flagged. The cards are predicted from your dose log and these curated values — estimates, not a measurement of you.": (
        "结合亲和力来自 NIMH PDSP Kᵢ 数据库和原始文献；恢复动力学则照着已发表的人体研究校准。每个参数都标了可信度，凡是用了类别默认值的都会标出来。卡片是根据你的剂量记录和这些经过整理的数值预测出来的——是估计，不是对你本人的实测。",
        "結合親和力來自 NIMH PDSP Kᵢ 資料庫和原始文獻；恢復動力學則照著已發表的人體研究校準。每個參數都標了可信度，凡是用了類別預設值的都會標出來。卡片是根據你的劑量記錄和這些經過整理的數值預測出來的——是估計，不是對你本人的實測。",
    ),
    "Real tolerance that drops after a break or a change of setting — which is exactly what makes returning to an old dose dangerous.": (
        "实打实的耐受，停一阵子或换了环境就会掉——这正是为什么回到以前的剂量会很危险。",
        "實打實的耐受，停一陣子或換了環境就會掉——這正是為什麼回到以前的劑量會很危險。",
    ),
    "Builds its own tolerance, and can also slow opioid tolerance when taken together.": (
        "自己会形成耐受，和阿片一起用时，还能减慢阿片耐受的形成。",
        "自己會形成耐受，和鴉片一起用時，還能減慢鴉片耐受的形成。",
    ),
    "Clean, predictable tolerance — the caffeine case.": (
        "干净、好预测的耐受——咖啡因就是这种。",
        "乾淨、好預測的耐受——咖啡因就是這種。",
    ),
    "A fast within-session fade, plus a modest, slower shift with heavy use. A bigger dose still works — but ramps the comedown and the risk, while the effect on your heart barely fades.": (
        "同一次使用内会很快减弱，大量使用时还会有一点更慢的变化。加大剂量仍然有用——但落差和风险都会跟着上去，而对心脏的负担几乎不会减弱。",
        "同一次使用內會很快減弱，大量使用時還會有一點更慢的變化。加大劑量仍然有用——但落差和風險都會跟著上去，而對心臟的負擔幾乎不會減弱。",
    ),
    "Runs down with use and returns over weeks. MDMA-type use is slower because it dents serotonin supply, not just the receptors.": (
        "用着用着会减弱，要好几周才回得来。MDMA 这类更慢，因为它伤的是血清素的供应，不只是受体。",
        "用著用著會減弱，要好幾週才回得來。MDMA 這類更慢，因為它傷的是血清素的供應，不只是受體。",
    ),
    "Mostly fast receptor desensitization that recovers between uses rather than a lasting change.": (
        "主要是受体的快速脱敏，在两次使用之间就会恢复，而不是一种持久的变化。",
        "主要是受體的快速去敏感化，在兩次使用之間就會恢復，而不是一種持久的變化。",
    ),
    "Barely builds tolerance — the real risk is stopping suddenly: blood pressure can rebound hard. Taper, don't quit cold.": (
        "几乎不会形成耐受——真正的风险是突然停用：血压可能猛烈反弹。要逐渐减量，别一下子停掉。",
        "幾乎不會形成耐受——真正的風險是突然停用：血壓可能猛烈反彈。要逐漸減量，別一下子停掉。",
    ),
    "Barely builds tolerance — the real risk is stopping suddenly: heart rate and blood pressure can rebound. Taper, don't quit cold.": (
        "几乎不会形成耐受——真正的风险是突然停用：心率和血压可能反弹。要逐渐减量，别一下子停掉。",
        "幾乎不會形成耐受——真正的風險是突然停用：心率和血壓可能反彈。要逐漸減量，別一下子停掉。",
    ),
    "Generic class-default kinetics at the lowest confidence.": (
        "采用通用的类别默认动力学，可信度最低。",
        "採用通用的類別預設動力學，可信度最低。",
    ),
    "View as": ("显示方式", "顯示方式"),
    "Model estimates from your dose log, assuming a %lld kg body weight — set yours in Settings.": (
        "模型根据你的剂量记录估算，假设体重为 %lld kg——在设置里填上你自己的。",
        "模型根據你的劑量記錄估算，假設體重為 %lld kg——在設定裡填上你自己的。",
    ),
    "Model estimates from your dose log and your body weight.": (
        "模型根据你的剂量记录和体重估算。",
        "模型根據你的劑量記錄和體重估算。",
    ),
    "Log a few doses and your predicted tolerance shows up here. Anything you haven't taken recently counts as no tolerance.": (
        "记几次剂量，你的预测耐受就会出现在这里。最近没用过的都算没耐受。",
        "記幾次劑量，你的預測耐受就會出現在這裡。最近沒用過的都算沒耐受。",
    ),
    "Can't predict yet": ("还无法预测", "還無法預測"),
    "Logged, but missing the pharmacokinetics the model needs — so it's blind here, which is not the same as no tolerance. %@.": (
        "已经记下了，但缺少模型需要的药代动力学数据——所以这里它看不清，这和没耐受不是一回事。%@。",
        "已經記下了，但缺少模型需要的藥代動力學數據——所以這裡它看不清，這和沒耐受不是一回事。%@。",
    ),
    "high tolerance": ("耐受高", "耐受高"),
    "no tolerance": ("没耐受", "沒耐受"),
    "Little tolerance builds — the thing to watch is stopping suddenly.": (
        "几乎不会形成耐受——要当心的是突然停用。",
        "幾乎不會形成耐受——要當心的是突然停用。",
    ),
    "Suppresses the enzyme that makes serotonin, so recovery takes weeks, not days.": (
        "它会抑制生成血清素的那种酶，所以恢复要几周，而不是几天。",
        "它會抑制生成血清素的那種酶，所以恢復要幾週，而不是幾天。",
    ),
    "No tolerance": ("没耐受", "沒耐受"),
    "Mild tolerance": ("轻微耐受", "輕微耐受"),
    "Moderate tolerance": ("中等耐受", "中等耐受"),
    "High tolerance": ("耐受较高", "耐受較高"),
    "Very high tolerance": ("耐受很高", "耐受很高"),
    "Recovers to about 90%% in %@ if you stop now, and fully over months.": (
        "如果现在停用，大约 %@ 内恢复到 90%% 左右，几个月内完全恢复。",
        "如果現在停用，大約 %@ 內恢復到 90%% 左右，幾個月內完全恢復。",
    ),
    "Recovers to about 90%% in %@ if you stop now.": (
        "如果现在停用，大约 %@ 内恢复到 90%% 左右。",
        "如果現在停用，大約 %@ 內恢復到 90%% 左右。",
    ),
    "Most of it fades in %@ if you stop now.": (
        "如果现在停用，大部分会在 %@ 内消退。",
        "如果現在停用，大部分會在 %@ 內消退。",
    ),
    "Most of it fades in %@ if you stop now — the deep part takes months.": (
        "如果现在停用，大部分会在 %@ 内消退——最深的那部分要几个月。",
        "如果現在停用，大部分會在 %@ 內消退——最深的那部分要幾個月。",
    ),
    "After a break or in a new setting, tolerance drops — a dose that felt fine before can stop your breathing. Restart low.": (
        "停一阵子或换了环境后耐受会掉——以前没事的剂量，这时可能让你停止呼吸。重新开始一定要减量。",
        "停一陣子或換了環境後耐受會掉——以前沒事的劑量，這時可能讓你停止呼吸。重新開始一定要減量。",
    ),
    "Heavy regular use builds dependence — stopping abruptly can be dangerous. Taper.": (
        "长期大量使用会形成依赖——突然停用可能很危险。要逐渐减量。",
        "長期大量使用會形成依賴——突然停用可能很危險。要逐漸減量。",
    ),
    "Regular use over weeks builds physical dependence — stopping abruptly can be dangerous even if you don't feel tolerant. Taper gradually.": (
        "连续数周的规律使用会形成身体依赖——即使你没有感觉到耐受，突然停用也可能很危险。要逐步减量。",
        "連續數週的規律使用會形成身體依賴——即使你沒有感覺到耐受，突然停用也可能很危險。要逐步減量。",
    ),
    "Don't stop α₂-agonists cold after regular use — blood pressure can rebound. Taper.": (
        "规律使用 α₂ 激动剂后别一下子停掉——血压可能反弹。要逐渐减量。",
        "規律使用 α₂ 激動劑後別一下子停掉——血壓可能反彈。要逐漸減量。",
    ),
    "Don't stop beta-blockers cold after regular use — heart rate and blood pressure can rebound. Taper.": (
        "规律使用 β 受体阻滞剂后别一下子停掉——心率和血压可能反弹。要逐渐减量。",
        "規律使用 β 受體阻滯劑後別一下子停掉——心率和血壓可能反彈。要逐漸減量。",
    ),
    "The high fades with tolerance, but the load on your heart and blood pressure doesn't.": (
        "兴奋感会随耐受减弱，但对心脏和血压的负担不会。",
        "興奮感會隨耐受減弱，但對心臟和血壓的負擔不會。",
    ),
    "Heavy chronic use has shifted your baseline; the deepest part recovers over months.": (
        "长期大量使用已经把你的基线压低了；最深的那部分要几个月才能恢复。",
        "長期大量使用已經把你的基線壓低了；最深的那部分要幾個月才能恢復。",
    ),
    "%@ · S ≈ %@×": ("%@ · S ≈ %@×", "%@ · S ≈ %@×"),
    "Engaged layers: %@": ("涉及的层：%@", "涉及的層：%@"),
    "acute": ("急性", "急性"),
    "adaptive": ("适应性", "適應性"),
    "deep": ("深层", "深層"),
    "synthesis": ("合成", "合成"),
    "Tachyphylaxis": ("快速耐受", "快速耐受"),
    "Deep": ("深层", "深層"),
    "none": ("无", "無"),
    "now": ("现在", "現在"),
    "high": ("高", "高"),
    "low": ("低", "低"),
    "%lldmo": ("%lld 个月", "%lld 個月"),
    "%lldwk": ("%lld 周", "%lld 週"),
    "%lldd": ("%lld 天", "%lld 天"),
    "Recovery if you stop now": ("现在停用的话，恢复情况", "現在停用的話，恢復情況"),
    "Everything's rested — nothing recovering right now.": (
        "一切都休息好了——现在没有在恢复的。",
        "一切都休息好了——現在沒有在恢復的。",
    ),
    "Each line is a mechanism recovering — a steeper climb means a faster reset. Showing the first 60 days.": (
        "每条线是一种机制在恢复——爬得越陡，重置得越快。这里只显示前 60 天。",
        "每條線是一種機制在恢復——爬得越陡，重置得越快。這裡只顯示前 60 天。",
    ),
    "Each line is a mechanism recovering — a steeper climb means a faster reset.": (
        "每条线是一种机制在恢复——爬得越陡，重置得越快。",
        "每條線是一種機制在恢復——爬得越陡，重置得越快。",
    ),
    "Each line is a mechanism's tolerance fading — a steeper drop means a faster reset. Showing the first 60 days.": (
        "每条线是一种机制的耐受在消退——掉得越陡，重置得越快。这里只显示前 60 天。",
        "每條線是一種機制的耐受在消退——掉得越陡，重置得越快。這裡只顯示前 60 天。",
    ),
    "Each line is a mechanism's tolerance fading — a steeper drop means a faster reset.": (
        "每条线是一种机制的耐受在消退——掉得越陡，重置得越快。",
        "每條線是一種機制的耐受在消退——掉得越陡，重置得越快。",
    ),
    "Cards": ("卡片", "卡片"),
    "Recovery chart": ("恢复图", "恢復圖"),
    "One card per mechanism": ("每种机制一张卡片", "每種機制一張卡片"),
    "All mechanisms, one axis": ("所有机制，同一坐标轴", "所有機制，同一座標軸"),
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
    "Expands the editor": ("展开编辑器", "展開編輯器"),
    "Log %@ %@ of %@": ("记录 %3$@ %1$@ %2$@", "記錄 %3$@ %1$@ %2$@"),
    "Log %@ of %@": ("记录 %2$@ %1$@", "記錄 %2$@ %1$@"),
    "Shared time": ("统一时间", "統一時間"),
    "Custom…": ("自定…", "自訂…"),
    "Discard staged doses?": ("舍弃待记录的剂量？", "捨棄待記錄的劑量？"),
    "Discard Doses": ("舍弃剂量", "捨棄劑量"),
    "Keep Logging": ("继续记录", "繼續記錄"),
    "Show %lld more doses": ("显示另外 %lld 个剂量", "顯示另外 %lld 個劑量"),
    "Custom dose": ("自定剂量", "自訂劑量"),
    "Active dose details": ("活性剂量详情", "活性劑量詳情"),
    # Journal state card (2026-07-22 plan/state/log restructure)
    "Active Now": ("当前活跃", "目前活躍"),
    # My Meds row split + Active Now → session (2026-07-22)
    "Opens this session.": ("打开本次记录。", "打開本次記錄。"),
    "Unlogs this dose": ("撤销此剂量记录", "撤銷此劑量記錄"),
    "Opens this med": ("打开此用药", "打開此用藥"),
    "%@ details": ("%@ 详情", "%@ 詳情"),
    # Quick-log VoiceOver audit fixes (2026-07-12)
    "Active dose": ("活性剂量", "活性劑量"),
    "Shows dosing advice": ("显示用药建议", "顯示用藥建議"),
    "about %@ %@ active, last dose %@ ago, %@ left": (
        "约 %@ %@ 仍在活性，上次用药于 %@ 前，剩余 %@",
        "約 %@ %@ 仍在活性，上次用藥於 %@ 前，剩餘 %@",
    ),
    "about %@ %@ active, last dose %@ ago": (
        "约 %@ %@ 仍在活性，上次用药于 %@ 前",
        "約 %@ %@ 仍在活性，上次用藥於 %@ 前",
    ),
    "Collapses the dosing advice": ("收起用药建议", "收起用藥建議"),
    "Custom dose of %@": ("自定 %@ 剂量", "自訂 %@ 劑量"),
    "Staged %@": ("已暂存 %@", "已暫存 %@"),
    "%lld staged": ("已暂存 %lld", "已暫存 %lld"),
    "Remove dose": ("移除剂量", "移除劑量"),
    "Decrease amount": ("减少剂量", "減少劑量"),
    "Increase amount": ("增加剂量", "增加劑量"),
    "Dose unit": ("剂量单位", "劑量單位"),
    "Adds a note to this dose": ("为此剂量添加备注", "為此劑量新增備註"),
    "Salt form": ("盐形式", "鹽形式"),
    "Isomer": ("异构体", "異構體"),
    "Stages this routine’s doses": ("暂存此日常的剂量", "暫存此日常的劑量"),
    "^[%lld item](inflect: true), all logged today": (
        "%lld 项，今天已全部记录",
        "%lld 項，今天已全部記錄",
    ),
    "^[%lld tag](inflect: true)": ("%lld 个标签", "%lld 個標籤"),
    "Reminder on": ("提醒已开启", "提醒已開啟"),
    # App-wide VoiceOver audit — Journal / Library / Tools / Insights / Settings (2026-07-12)
    "No active doses": ("无活性剂量", "無活性劑量"),
    "%@ in %@ at %lld percent": ("%@ 处于%@，%lld%%", "%@ 處於%@，%lld%%"),
    "%@ at %lld percent": ("%@ %lld%%", "%@ %lld%%"),
    "Dose level": ("剂量级别", "劑量級別"),
    "%@ range, %@": ("%@ 范围，%@", "%@ 範圍，%@"),
    "Session options": ("会话选项", "工作階段選項"),
    "Moving here will ask for a new time": (
        "移到此处将要求输入新时间",
        "移到此處將要求輸入新時間",
    ),
    "Edits the note": ("编辑备注", "編輯備註"),
    "Previous month": ("上个月", "上個月"),
    "Next month": ("下个月", "下個月"),
    "^[%lld dose](inflect: true)": ("%lld 个剂量", "%lld 個劑量"),
    "%@, Today": ("%@，今天", "%@，今天"),
    "Opens in Maps": ("在地图中打开", "在地圖中開啟"),
    "Used by %@": ("已用于 %@", "已用於 %@"),
    "Progress": ("进度", "進度"),
    "Step %lld of %lld": ("第 %lld 步，共 %lld 步", "第 %lld 步，共 %lld 步"),
    "Page %lld of %lld": ("第 %lld 页，共 %lld 页", "第 %lld 頁，共 %lld 頁"),
    "Priority %lld of %lld": ("优先级 %lld，共 %lld", "優先順序 %lld，共 %lld"),
    "Locating…": ("定位中…", "定位中…"),
    "Concentration over time": ("浓度随时间变化", "濃度隨時間變化"),
    "Combined depression over time": (
        "综合抑制随时间变化",
        "綜合抑制隨時間變化",
    ),
    "Tolerance recovery": ("耐受恢复", "耐受恢復"),
    "Recovery by mechanism": ("按机制的恢复", "按機制的恢復"),
    "Convert from": ("从", "從"),
    "Convert to": ("转换为", "轉換為"),
    "morning": ("上午", "上午"),
    "afternoon": ("下午", "下午"),
    "evening": ("傍晚", "傍晚"),
    "night": ("夜间", "夜間"),
    "%lld doses plotted; the largest reaches about %@× the total exposure of one reference dose.": (
        "已绘制 %lld 个剂量；最大者约达单次参考剂量总暴露量的 %@ 倍。",
        "已繪製 %lld 個劑量；最大者約達單次參考劑量總暴露量的 %@ 倍。",
    ),
    "%@ and %@ over time; both active from %@ to %@.": (
        "%@ 与 %@ 随时间变化；两者均在 %@ 至 %@ 期间具活性。",
        "%@ 與 %@ 隨時間變化；兩者均在 %@ 至 %@ 期間具活性。",
    ),
    "%@ and %@ over time; no overlapping active window.": (
        "%@ 与 %@ 随时间变化；无重叠的活性窗口。",
        "%@ 與 %@ 隨時間變化；無重疊的活性窗口。",
    ),
    "Peaks around %@; the dashed line marks the dangerous threshold.": (
        "约在 %@ 达到峰值；虚线标示危险阈值。",
        "約在 %@ 達到峰值；虛線標示危險閾值。",
    ),
    "Starts at %@, fading toward none.": (
        "从 %@ 开始，逐渐消退至无。",
        "從 %@ 開始，逐漸消退至無。",
    ),
    "%lld mechanisms plotted, each fading from its current tolerance toward none.": (
        "已绘制 %lld 种机制，各自从当前耐受逐渐消退至无。",
        "已繪製 %lld 種機制，各自從當前耐受逐漸消退至無。",
    ),
    "%lld entries across %lld days.": (
        "%lld 条记录，跨越 %lld 天。",
        "%lld 筆記錄，跨越 %lld 天。",
    ),
    "Most entries in the %@; %lld total.": (
        "多数记录在%@；共 %lld 条。",
        "多數記錄在%@；共 %lld 筆。",
    ),
    "%lld points, peak %@ %@.": ("%lld 个点，峰值 %@ %@。", "%lld 個點，峰值 %@ %@。"),
    "Now %@; peaked %@ about %@ after the first dose": (
        "当前 %@；在首次剂量后约 %@ 达到 %@ 峰值",
        "目前 %@；在首次劑量後約 %@ 達到 %@ 峰值",
    ),
    "Now %@; expected to peak %@ about %@ after the first dose": (
        "当前 %@；预计在首次剂量后约 %@ 达到 %@ 峰值",
        "目前 %@；預計在首次劑量後約 %@ 達到 %@ 峰值",
    ),
    "View citation": ("查看引用", "查看引用"),
    "Binding strength": ("结合强度", "結合強度"),
    "%lld of 3": ("%lld / 3", "%lld / 3"),
    "%lld nM": ("%lld nM", "%lld nM"),
    "Enantiomer potency": ("对映体效价", "對映體效價"),
    "Dopamine–serotonin lean": ("多巴胺–血清素倾向", "多巴胺–血清素傾向"),
    "About this section": ("关于此部分", "關於此部分"),
    "Shows the remaining doses": ("显示其余剂量", "顯示其餘劑量"),
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
    "Location access is off": ("定位权限已关闭", "定位權限已關閉"),
    "Turn on location access in Settings to use your current location.": (
        "请在设置中开启定位权限，以使用你的当前位置。",
        "請在設定中開啟定位權限，以使用你的目前位置。",
    ),
    "Location: %@": ("位置：%@", "位置：%@"),
    "Dose time: %@": ("剂量时间：%@", "劑量時間：%@"),
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
    "Pharmacological data is compiled from the sources above — community databases, FDA labeling, and peer-reviewed literature. Provided for reference and educational purposes only. Always consult a qualified healthcare professional before making decisions about substance use.": (
        "药理数据汇编自上述来源——社区数据库、FDA 药品标签以及同行评审文献。仅供参考与教育用途。在做出任何有关物质使用的决定前，请务必咨询合格的医疗专业人员。",
        "藥理資料彙編自上述來源——社群資料庫、FDA 藥品標籤以及同行評審文獻。僅供參考與教育用途。在做出任何有關物質使用的決定前，請務必諮詢合格的醫療專業人員。",
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
    "The file is missing a required field: %@.": (
        "文件缺少必需字段：%@。",
        "檔案缺少必要欄位：%@。",
    ),
    "The file has an empty value for a required field: %@.": (
        "文件的必需字段为空值：%@。",
        "檔案的必要欄位為空值：%@。",
    ),
    "The file isn't valid JSON.": ("文件不是有效的 JSON。", "檔案不是有效的 JSON。"),
    "The file has an unexpected value at: %@.": (
        "文件在此处包含意外的值：%@。",
        "檔案在此處包含非預期的值：%@。",
    ),
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
    "Delete Note": ("删除备注", "刪除備註"),
    "Merge with Previous": ("与上一段合并", "與上一段合併"),
    "Note": ("备注", "備註"),
    "Split Session Here": ("在此拆分记录", "在此拆分記錄"),
    "Split at Longest Break (%@)": ("在最长间隔处拆分（%@）", "在最長間隔處拆分（%@）"),
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
    "Expand Session Graph": ("展开记录图表", "展開記錄圖表"),
    "Always show the taller timeline graph when viewing a session. When off, the graph starts compact and you can expand it per session from the graph menu.": (
        "查看记录时始终显示更高的时间线图表。关闭后，图表以紧凑模式开始，你可以在每条记录中通过图表菜单单独展开。",
        "檢視記錄時始終顯示更高的時間軸圖表。關閉後，圖表以精簡模式開始，你可以在每條記錄中透過圖表選單單獨展開。",
    ),
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
    "Orexin Antagonist": ("食欲素拮抗剂", "食慾素拮抗劑"),
    # DORA (orexin antagonist) mechanism of action + interactions (2026-07-05).
    "Dual Orexin Receptor Antagonist (DORA)": (
        "双重食欲素受体拮抗剂（DORA）",
        "雙重食慾素受體拮抗劑（DORA）",
    ),
    'Competitively blocks the orexin (hypocretin) receptors OX1R and OX2R, the targets of the wake-promoting neuropeptides orexin-A and orexin-B released from the lateral hypothalamus. Rather than broadly sedating the brain like a GABAergic hypnotic, it withdraws a specific "stay awake" drive that stabilizes arousal — permitting the natural transition into sleep with largely preserved sleep architecture and arousability. Because it does not enhance GABA or depress brainstem respiratory centers, it lacks the respiratory-depression synergy and dependence liability characteristic of benzodiazepines, Z-drugs, and other GABAergic sedatives.': (
        "竞争性阻断食欲素（下丘脑分泌素）受体 OX1R 和 OX2R，这两种受体是外侧下丘脑释放的促醒神经肽食欲素-A 和食欲素-B 的作用靶点。它不像 GABA 能催眠药那样广泛抑制大脑，而是撤除一种维持觉醒的特定“保持清醒”驱动力——让人自然过渡到睡眠，同时基本保留睡眠结构和可唤醒性。由于它既不增强 GABA，也不抑制脑干呼吸中枢，因此没有苯二氮䓬类、Z 类药物及其他 GABA 能镇静剂所特有的呼吸抑制协同作用和依赖风险。",
        "競爭性阻斷食慾素（下視丘分泌素）受體 OX1R 和 OX2R，這兩種受體是外側下視丘釋放的促醒神經肽食慾素-A 和食慾素-B 的作用標的。它不像 GABA 能催眠藥那樣廣泛抑制大腦，而是撤除一種維持覺醒的特定「保持清醒」驅動力——讓人自然過渡到睡眠，同時基本保留睡眠結構和可喚醒性。由於它既不增強 GABA，也不抑制腦幹呼吸中樞，因此沒有苯二氮平類、Z 類藥物及其他 GABA 能鎮靜劑所特有的呼吸抑制協同作用和依賴風險。",
    ),
    "Added drowsiness and next-day grogginess, with more fall and coordination risk. Unlike a benzo, an orexin antagonist doesn't suppress breathing, so this isn't the deadly opioid+benzo combination — but still use less, and don't drive.": (
        "会增加困倦和次日昏沉，跌倒和协调障碍风险更高。与苯二氮䓬类不同，食欲素拮抗剂不会抑制呼吸，因此这不是致命的阿片+苯二氮䓬组合——但仍应减量，且不要开车。",
        "會增加睏倦和隔日昏沉，跌倒和協調障礙風險更高。與苯二氮平類不同，食慾素拮抗劑不會抑制呼吸，因此這不是致命的鴉片+苯二氮平組合——但仍應減量，且不要開車。",
    ),
    "Alcohol stacks psychomotor and memory impairment on top of the sleep med (and raises lemborexant's blood levels) — expect worse next-day grogginess and unsteadiness. The labels advise against drinking with these.": (
        "酒精会在这类安眠药之上叠加精神运动和记忆损害（并会升高莱博雷生的血药浓度）——次日昏沉和站立不稳会更明显。药品说明书建议服用期间不要饮酒。",
        "酒精會在這類安眠藥之上疊加精神運動和記憶損害（並會升高萊博雷生的血藥濃度）——隔日昏沉和站立不穩會更明顯。藥品仿單建議服用期間不要飲酒。",
    ),
    "Two sleep-promoting drugs stacked — additive next-day sedation and fall risk, and largely redundant. Not the respiratory danger of benzo+opioid, but heavier grogginess and impaired coordination.": (
        "两种促眠药叠加——次日镇静和跌倒风险相加，且大多重复。虽然不像苯二氮䓬+阿片那样有呼吸危险，但会带来更重的昏沉和协调障碍。",
        "兩種促眠藥疊加——隔日鎮靜和跌倒風險相加，且大多重複。雖然不像苯二氮平+鴉片那樣有呼吸危險，但會帶來更重的昏沉和協調障礙。",
    ),
    "Additive sedation and next-day grogginess — more drowsiness, dizziness, and fall risk. Use less and avoid driving.": (
        "镇静作用和次日昏沉相加——更明显的困倦、头晕和跌倒风险。请减量并避免开车。",
        "鎮靜作用和隔日昏沉相加——更明顯的睏倦、頭暈和跌倒風險。請減量並避免開車。",
    ),
    "Compounded sedation — stronger, deeper drowsiness. The orexin antagonist doesn't add respiratory depression itself, but GHB can, so keep doses low and don't combine when alone.": (
        "镇静作用叠加——困倦更强、更深。食欲素拮抗剂本身不会加重呼吸抑制，但 GHB 会，因此请保持低剂量，独处时不要合用。",
        "鎮靜作用疊加——睏倦更強、更深。食慾素拮抗劑本身不會加重呼吸抑制，但 GHB 會，因此請保持低劑量，獨處時不要合用。",
    ),
    "Both cause drowsiness — expect additive next-day sedation and grogginess. Use less and don't drive.": (
        "两者都会引起困倦——次日镇静和昏沉会相加。请减量，且不要开车。",
        "兩者都會引起睏倦——隔日鎮靜和昏沉會相加。請減量，且不要開車。",
    ),
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
    "Buccal": ("颊黏膜", "頰黏膜"),
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
    # Quick-log native dock sheet (2026-07-07)
    "Search to add a dose…": ("搜索以添加剂量…", "搜尋以新增劑量…"),
    "Cancel search": ("取消搜索", "取消搜尋"),
    "Start dictation": ("开始听写", "開始聽寫"),
    "Stop dictation": ("停止听写", "停止聽寫"),
    "Manage Routines": ("管理日常", "管理日常"),
    "Routines & Prescriptions": ("日常与处方", "日常與處方"),
    "Add & edit drink…": ("添加并编辑饮品…", "新增並編輯飲品…"),
    "Edit Drinks…": ("编辑饮品…", "編輯飲品…"),
    "Drinks": ("饮品", "飲品"),
    "New Drink": ("新增饮品", "新增飲品"),
    "Edit Drink": ("编辑饮品", "編輯飲品"),
    "A fixed serving fills strength and volume when selected — like a 330 mL can. Without one, only the strength is filled.": (
        "固定分量的饮品在选择时会同时填入浓度和容量（例如 330 mL 罐装）；没有固定分量时仅填入浓度。",
        "固定份量的飲品在選擇時會同時填入濃度和容量（例如 330 mL 罐裝）；沒有固定份量時僅填入濃度。",
    ),
    "Drag to reorder. Swipe left to remove.": (
        "拖动以重新排序。向左轻扫以移除。",
        "拖曳以重新排序。向左輕掃以移除。",
    ),
    "Lower amount": ("减少剂量", "減少劑量"),
    "Raise amount": ("增加剂量", "增加劑量"),
    "Edit routines and favorites": ("编辑日常与收藏", "編輯日常與收藏"),
    "Collapsed": ("已折叠", "已折疊"),
    "Expanded": ("已展开", "已展開"),
    "Expands a dose entry": ("展开剂量输入", "展開劑量輸入"),
    "Adds this dose": ("添加此剂量", "新增此劑量"),
    "Needs an amount": ("需要填写剂量", "需要填寫劑量"),
    "Collapses the dose entry": ("折叠剂量输入", "折疊劑量輸入"),
    "Search": ("搜索", "搜尋"),
    # Search redesign 2026-06 (landing + class grid + journal→library fallback)
    "Recently Searched": ("最近搜索", "最近搜尋"),
    "Browse by class": ("按类别浏览", "按類別瀏覽"),
    "Search Library instead": ("改为搜索物质库", "改為搜尋物質庫"),
    "Help & Safety": ("帮助与安全", "幫助與安全"),
    "Crisis resources, safety basics, and what's active right now.": (
        "危机求助资源、安全基础知识，以及当前活跃的物质。",
        "危機求助資源、安全基礎知識，以及目前活躍的物質。",
    ),
    "Class Not Found": ("未找到类别", "未找到類別"),
    "This class isn’t in the library anymore.": (
        "此类别已不在物质库中。",
        "此類別已不在物質庫中。",
    ),
    "Clear": ("清除", "清除"),
    # Common UI actions
    "Add": ("添加", "新增"),
    "Add Preset": ("添加预设", "新增預設"),
    "Quick Times": ("快捷时间", "快捷時間"),
    "Reset to Defaults": ("恢复默认", "恢復預設"),
    "That preset already exists.": ("该预设已存在。", "該預設已存在。"),
    "Choose at least one minute.": ("请至少选择一分钟。", "請至少選擇一分鐘。"),
    "Adds “%@”.": ("添加“%@”。", "新增「%@」。"),
    "These appear in the “When” menu when logging a dose, alongside Now and the full date picker. Swipe to remove, drag to reorder.": (
        "记录用药时，这些会显示在“时间”菜单中，与“现在”和完整日期选择器并列。左滑删除，拖动重新排序。",
        "記錄用藥時，這些會顯示在「時間」選單中，與「現在」和完整日期選擇器並列。左滑刪除，拖曳重新排序。",
    ),
    "%lld h": ("%lld 小时", "%lld 小時"),
    "Minutes": ("分钟", "分鐘"),
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
    "Removes this filter.": ("移除此筛选条件。", "移除此篩選條件。"),
    "Form": ("盐型", "鹽型"),
    "≈ %@ %@ elemental": ("≈ %@ %@ 元素含量", "≈ %@ %@ 元素含量"),
    "%lld%% elemental": ("%lld%% 元素含量", "%lld%% 元素含量"),
    "<1% elemental": ("<1% 元素含量", "<1% 元素含量"),
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
    "Slide to move, pinch to zoom": ("滑动移动，捏合缩放", "滑動移動，捏合縮放"),
    "Slide to move, pinch to zoom, hold to inspect": (
        "滑动移动，捏合缩放，长按查看",
        "滑動移動，捏合縮放，長按查看",
    ),
    # Mechanistic effect lenses + readouts (2026-07-08).
    "Feeling": ("感受", "感受"),
    "Energy": ("精力", "精力"),
    "Urge": ("渴求", "渴求"),
    "Euphoric": ("欣快", "欣快"),
    "Good": ("良好", "良好"),
    "Level": ("平稳", "平穩"),
    "Wired": ("亢奋", "亢奮"),
    "Driven": ("起劲", "起勁"),
    "Flat": ("平淡", "平淡"),
    "Sedated": ("镇静", "鎮靜"),
    "Craving": ("渴望", "渴望"),
    "Bliss": ("极乐", "極樂"),
    "Present": ("有感", "有感"),
    "Low": ("低", "低"),
    "Expand Graph": ("展开图表", "展開圖表"),
    "Shrink Graph": ("收起图表", "收起圖表"),
    "bpm": ("次/分", "次/分"),
    "mmHg": ("mmHg", "mmHg"),
    "Tags: %@": ("标签：%@", "標籤：%@"),
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
    "Computed from the molecular structure (PubChem, NPS-DataHub) rather than measured in a lab.": (
        "由分子结构计算得出（PubChem、NPS-DataHub），非实验室实测值。",
        "由分子結構計算得出（PubChem、NPS-DataHub），非實驗室實測值。",
    ),
    "Recreational doses — not a prescribed amount": (
        "娱乐用剂量——并非处方用量。",
        "娛樂用劑量——並非處方用量。",
    ),
    "LD50 is rodent toxicity (order of magnitude) — not a human safe dose.": (
        "LD50 为啮齿动物毒性（数量级参考），并非人体安全剂量。",
        "LD50 為齧齒動物毒性（數量級參考），並非人體安全劑量。",
    ),
    "IUPAC name": ("IUPAC 名称", "IUPAC 名稱"),
    "Molecular structure": ("分子结构", "分子結構"),
    "%lld atoms": ("%lld 个原子", "%lld 個原子"),
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
    # Substance detail — redesign (misconceptions + "for the curious" launcher)
    "Common misconceptions": ("常见误解", "常見誤解"),
    "Combinations": ("组合", "組合"),
    "Water & heat": ("水分与温度", "水分與溫度"),
    "Danger": ("危险", "危險"),
    "Guideline: %@": ("指南：%@", "指南：%@"),
    "For the curious": ("给好奇的你", "給好奇的你"),
    "Myth: %@": ("误解：%@", "誤解：%@"),
    "Retracted source: %@": ("已撤稿的来源：%@", "已撤稿的來源：%@"),
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
    "No effect timeline for this substance and route.": (
        "此物质和途径暂无效果时间轴。",
        "此物質和途徑暫無效果時間軸。",
    ),
    # "Also Active" — the metabolite surface.
    # "Also Active" — Xcode extracts these with NON-positional %@ keys, so the
    # positional %1$@ variants authored earlier went stale and their zh values
    # never reached a user. Keys must match what the extractor emits; the
    # translated VALUES still use %1$@/%2$@ to reorder, which is allowed.
    "%@ stays active in your body long after %@ itself is gone.": (
        "在 %2$@ 本身已排出后,%1$@ 仍在体内保持活性。",
        "在 %2$@ 本身已排出後,%1$@ 仍在體內保持活性。",
    ),
    "About %@× %@'s activity at the %@.": (
        "在%3$@上,活性约为 %2$@ 的 %1$@ 倍。",
        "在%3$@上,活性約為 %2$@ 的 %1$@ 倍。",
    ),
    "About %@× %@'s activity, by one measurement.": (
        "据一项测定,活性约为 %2$@ 的 %1$@ 倍。",
        "據一項測定,活性約為 %2$@ 的 %1$@ 倍。",
    ),
    "About %@× as strong as %@, dose for dose.": (
        "按相同剂量计,强度约为 %2$@ 的 %1$@ 倍。",
        "按相同劑量計,強度約為 %2$@ 的 %1$@ 倍。",
    ),
    "About as strong as %@ at the %@.": (
        "在%2$@上,强度与 %1$@ 相当。",
        "在%2$@上,強度與 %1$@ 相當。",
    ),
    "Also measured at %@× %@'s %@ at the %@ — a lab measurement, not clinical potency.": (
        "另在%4$@上测定值为 %2$@ %3$@的 %1$@ 倍——这是实验室测定值,并非临床效价。",
        "另在%4$@上測定值為 %2$@ %3$@的 %1$@ 倍——這是實驗室測定值,並非臨床效價。",
    ),
    "Also measured at %@× %@'s %@ — a lab measurement, not clinical potency.": (
        "另有测定值为 %2$@ %3$@的 %1$@ 倍——这是实验室测定值,并非临床效价。",
        "另有測定值為 %2$@ %3$@的 %1$@ 倍——這是實驗室測定值,並非臨床效價。",
    ),
    "Effects can outlast the duration above — %@ clears much more slowly than %@.": (
        "效果可能超出上方时长——%1$@ 的清除速度远慢于 %2$@。",
        "效果可能超出上方時長——%1$@ 的清除速度遠慢於 %2$@。",
    ),
    "Measured at %@× %@'s %@ at the %@ — a lab measurement, not clinical potency.": (
        "在%4$@上测定值为 %2$@ %3$@的 %1$@ 倍——这是实验室测定值,并非临床效价。",
        "在%4$@上測定值為 %2$@ %3$@的 %1$@ 倍——這是實驗室測定值,並非臨床效價。",
    ),
    "Measured at %@× %@'s %@ — a lab measurement, not clinical potency.": (
        "测定值为 %2$@ %3$@的 %1$@ 倍——这是实验室测定值,并非临床效价。",
        "測定值為 %2$@ %3$@的 %1$@ 倍——這是實驗室測定值,並非臨床效價。",
    ),
    "Molecule for molecule, %@ is about %@× as strong as %@ — but how much of a dose converts isn't recorded here.": (
        "按分子计,%1$@ 的强度约为 %3$@ 的 %2$@ 倍——但一次剂量中有多少会转化,此处尚无记录。",
        "按分子計,%1$@ 的強度約為 %3$@ 的 %2$@ 倍——但一次劑量中有多少會轉化,此處尚無記錄。",
    ),
    "Molecule for molecule, %@ is about %@× as strong as %@ — but only about %@%% of a dose becomes it.": (
        "按分子计,%1$@ 的强度约为 %3$@ 的 %2$@ 倍——但一次剂量中只有约 %4$@%% 会转化为它。",
        "按分子計,%1$@ 的強度約為 %3$@ 的 %2$@ 倍——但一次劑量中只有約 %4$@%% 會轉化為它。",
    ),
    "Molecule for molecule, %@ is about as strong as %@.": (
        "按分子计,%1$@ 的强度与 %2$@ 相当。",
        "按分子計,%1$@ 的強度與 %2$@ 相當。",
    ),
    "Molecule for molecule, about %@× as strong as %@.": (
        "按分子计,强度约为 %2$@ 的 %1$@ 倍。",
        "按分子計,強度約為 %2$@ 的 %1$@ 倍。",
    ),
    "What your body makes from this dose. Not a measured level.": (
        "身体从这次剂量中生成的物质。并非实测数值。",
        "身體從這次劑量中生成的物質。並非實測數值。",
    ),
    "Your body turns %@ into %@, which is active too.": (
        "身体会将 %1$@ 转化为 %2$@,后者同样具有活性。",
        "身體會將 %1$@ 轉化為 %2$@,後者同樣具有活性。",
    ),
    "Also Active": ("同时活跃", "同時活躍"),
    "Made by": ("生成酶", "生成酶"),
    "Share of dose": ("占剂量比例", "佔劑量比例"),
    "Effects can outlast the duration above — %1$@ clears much more slowly than %2$@.": (
        "效果可能超出上方时长——%1$@ 的清除速度远慢于 %2$@。",
        "效果可能超出上方時長——%1$@ 的清除速度遠慢於 %2$@。",
    ),
    "About as strong as %@, dose for dose.": (
        "按相同剂量计,强度与 %@ 相当。",
        "按相同劑量計,強度與 %@ 相當。",
    ),
    "About %1$@× as strong as %2$@, dose for dose.": (
        "按相同剂量计,强度约为 %2$@ 的 %1$@ 倍。",
        "按相同劑量計,強度約為 %2$@ 的 %1$@ 倍。",
    ),
    "%1$@ stays active in your body long after %2$@ itself is gone.": (
        "在 %2$@ 本身已排出后,%1$@ 仍在体内保持活性。",
        "在 %2$@ 本身已排出後,%1$@ 仍在體內保持活性。",
    ),
    "Molecule for molecule, %1$@ is about %2$@× as strong as %3$@ — but how much of a dose converts isn't recorded here.": (
        "按分子计,%1$@ 的强度约为 %3$@ 的 %2$@ 倍——但一次剂量中有多少会转化,此处尚无记录。",
        "按分子計,%1$@ 的強度約為 %3$@ 的 %2$@ 倍——但一次劑量中有多少會轉化,此處尚無記錄。",
    ),
    "Molecule for molecule, %1$@ is about %2$@× as strong as %3$@ — but only about %4$@% of a dose becomes it.": (
        "按分子计,%1$@ 的强度约为 %3$@ 的 %2$@ 倍——但一次剂量中只有约 %4$@% 会转化为它。",
        "按分子計,%1$@ 的強度約為 %3$@ 的 %2$@ 倍——但一次劑量中只有約 %4$@% 會轉化為它。",
    ),
    "Molecule for molecule, %1$@ is about as strong as %2$@.": (
        "按分子计,%1$@ 的强度与 %2$@ 相当。",
        "按分子計,%1$@ 的強度與 %2$@ 相當。",
    ),
    "Molecule for molecule, about %1$@× as strong as %2$@.": (
        "按分子计,强度约为 %2$@ 的 %1$@ 倍。",
        "按分子計,強度約為 %2$@ 的 %1$@ 倍。",
    ),
    "How much of this you make is partly genetic — the same dose produces noticeably more in some people than others.": (
        "生成量部分取决于基因——同样的剂量,有些人生成的明显更多。",
        "生成量部分取決於基因——同樣的劑量,有些人生成的明顯更多。",
    ),
    "About as strong as %1$@ at the %2$@.": (
        "在%2$@上,强度与 %1$@ 相当。",
        "在%2$@上,強度與 %1$@ 相當。",
    ),
    "About %1$@× %2$@'s activity at the %3$@.": (
        "在%3$@上,活性约为 %2$@ 的 %1$@ 倍。",
        "在%3$@上,活性約為 %2$@ 的 %1$@ 倍。",
    ),
    "About %1$@× %2$@'s activity, by one measurement.": (
        "据一项测定,活性约为 %2$@ 的 %1$@ 倍。",
        "據一項測定,活性約為 %2$@ 的 %1$@ 倍。",
    ),
    "Acts differently from %@ — not simply stronger or weaker.": (
        "作用方式与 %@ 不同——并非单纯更强或更弱。",
        "作用方式與 %@ 不同——並非單純更強或更弱。",
    ),
    # ---- Curated divergent-metabolite editorial notes (MetaboliteEditorial.swift) ----
    "Tramadol is itself a weak opioid that also raises serotonin and noradrenaline. Most of the opioid effect people feel comes from this metabolite — and how much you make of it depends on a CYP2D6 gene, so the same dose can be a real opioid for one person and almost none for another.": (
        "曲马多本身是一种弱阿片类药物,同时也会升高血清素和去甲肾上腺素。大多数人感受到的阿片效应来自这个代谢物——而生成量取决于 CYP2D6 基因,因此同样的剂量对一些人来说是真正的阿片效应,对另一些人则几乎没有。",
        "曲馬多本身是一種弱鴉片類藥物,同時也會升高血清素和去甲腎上腺素。大多數人感受到的鴉片效應來自這個代謝物——而生成量取決於 CYP2D6 基因,因此同樣的劑量對一些人來說是真正的鴉片效應,對另一些人則幾乎沒有。",
    ),
    "mCPP acts on serotonin in a different way than trazodone — it tends to feel activating or anxious rather than sedating, which is part of why trazodone's later hours can feel unlike its calm onset.": (
        "mCPP 以不同于曲唑酮的方式作用于血清素——它倾向于产生激活感或焦虑感,而非镇静,这是曲唑酮后半段感受可能与平静的起效阶段不同的部分原因。",
        "mCPP 以不同於曲唑酮的方式作用於血清素——它傾向於產生激活感或焦慮感,而非鎮靜,這是曲唑酮後半段感受可能與平靜的起效階段不同的部分原因。",
    ),
    "Noribogaine is long-lived and acts differently from ibogaine — it leans more on serotonin reuptake and κ-opioid signaling, and it is a large part of the extended after-effect rather than a continuation of the peak.": (
        "去甲伊博加因半衰期长,作用方式与伊博加因不同——更依赖血清素再摄取和 κ-阿片信号传导,构成延长后效应的重要部分,而非高峰期的延续。",
        "去甲伊博加因半衰期長,作用方式與伊博加因不同——更依賴血清素再攝取和 κ-鴉片訊號傳導,構成延長後效應的重要部分,而非高峰期的延續。",
    ),
    "Normeperidine isn't a painkiller — it's a stimulating metabolite that builds up with repeated or high doses and lowers the seizure threshold. It's why meperidine isn't used for long-term pain.": (
        "去甲哌替啶不是止痛药——它是一种兴奋性代谢物,在反复或大剂量使用时蓄积,降低癫痫发作阈值。这是哌替啶不用于长期镇痛的原因。",
        "去甲哌替啶不是止痛藥——它是一種興奮性代謝物,在反覆或大劑量使用時蓄積,降低癲癇發作閾值。這是哌替啶不用於長期鎮痛的原因。",
    ),
    "Dextrorphan blocks NMDA receptors more strongly than DXM itself does — it's the more dissociative species, and the main reason the character shifts at higher doses rather than simply lasting longer.": (
        "右啡烷对 NMDA 受体的阻断作用强于右美沙芬本身——它是更具解离性的活性种,也是高剂量时体验特征转变而非仅仅持续更久的主要原因。",
        "右啡烷對 NMDA 受體的阻斷作用強於右美沙芬本身——它是更具解離性的活性種,也是高劑量時體驗特徵轉變而非僅僅持續更久的主要原因。",
    ),
    "Meprobamate is a long-lived, barbiturate-like sedative in its own right — it acts more like a classic downer than carisoprodol, and much of the sedation and the dependence potential come from it rather than the parent.": (
        "美普罗巴酯本身就是一种长效的巴比妥类镇静剂——其作用更像经典的镇静药物,大部分镇静作用和依赖潜力来自于它而非母体药物。",
        "美普羅巴酯本身就是一種長效的巴比妥類鎮靜劑——其作用更像經典的鎮靜藥物,大部分鎮靜作用和依賴潛力來自於它而非母體藥物。",
    ),
    "Nortriptyline is a marketed antidepressant in its own right, and it leans more on noradrenaline than amitriptyline does — so the metabolite's character is more activating than the parent's.": (
        "去甲替林本身就是一种上市的抗抑郁药,比阿米替林更偏向去甲肾上腺素——因此代谢物的特征比母体药物更具激活性。",
        "去甲替林本身就是一種上市的抗憂鬱藥,比阿米替林更偏向去甲腎上腺素——因此代謝物的特徵比母體藥物更具激活性。",
    ),
    "Desipramine is a marketed antidepressant in its own right, and more noradrenergic than imipramine — so as it forms, the effect shifts toward the more activating end.": (
        "地昔帕明本身就是一种上市的抗抑郁药,比丙咪嗪更偏向去甲肾上腺素能——因此随着它的生成,效应向更具激活性的方向转移。",
        "地昔帕明本身就是一種上市的抗憂鬱藥,比丙咪嗪更偏向去甲腎上腺素能——因此隨著它的生成,效應向更具激活性的方向轉移。",
    ),
    "The desmethyl metabolite shifts clomipramine's strongly serotonergic action toward noradrenaline, so the two don't act quite alike — the balance moves as the metabolite accumulates.": (
        "去甲基代谢物将氯丙咪嗪强烈的血清素能作用向去甲肾上腺素方向转移,因此两者的作用并不完全相同——随着代谢物蓄积,平衡发生变化。",
        "去甲基代謝物將氯丙咪嗪強烈的血清素能作用向去甲腎上腺素方向轉移,因此兩者的作用並不完全相同——隨著代謝物蓄積,平衡發生變化。",
    ),
    "Norquetiapine adds effects quetiapine largely lacks — noradrenaline reuptake inhibition and antidepressant-like activity — so it contributes a different character than the parent's sedation.": (
        "去甲喹硫平增加了喹硫平基本不具备的作用——去甲肾上腺素再摄取抑制和抗抑郁样活性——因此它贡献的特征不同于母体药物的镇静作用。",
        "去甲喹硫平增加了喹硫平基本不具備的作用——去甲腎上腺素再攝取抑制和抗憂鬱樣活性——因此它貢獻的特徵不同於母體藥物的鎮靜作用。",
    ),
    "This metabolite (HNK) barely touches the NMDA receptor ketamine acts on — it's studied for a separate, non-dissociative antidepressant effect, so it isn't simply ketamine continuing.": (
        "这种代谢物(HNK)几乎不作用于氯胺酮所靶向的 NMDA 受体——它被研究的是一种独立的、非解离性的抗抑郁效应,因此并非氯胺酮效果的简单延续。",
        "這種代謝物(HNK)幾乎不作用於氯胺酮所靶向的 NMDA 受體——它被研究的是一種獨立的、非解離性的抗憂鬱效應,因此並非氯胺酮效果的簡單延續。",
    ),
    "Norbuprenorphine acts differently from buprenorphine — it behaves more like a full opioid agonist and contributes to respiratory effects, which buprenorphine's own ceiling doesn't fully predict.": (
        "去甲丁丙诺啡的作用方式不同于丁丙诺啡——它更像完全阿片激动剂,对呼吸抑制有贡献,而丁丙诺啡自身的天花板效应并不能完全预测这一点。",
        "去甲丁丙諾啡的作用方式不同於丁丙諾啡——它更像完全鴉片促效劑,對呼吸抑制有貢獻,而丁丙諾啡自身的天花板效應並不能完全預測這一點。",
    ),
    "Cetirizine — a common non-drowsy antihistamine — is hydroxyzine's main metabolite. It's far less sedating, so hydroxyzine's calming effect gives way to a plainer antihistamine as it converts.": (
        "西替利嗪——一种常见的非嗜睡抗组胺药——是羟嗪的主要代谢物。它的镇静作用弱得多,因此随着转化,羟嗪的镇静效果逐渐让位于单纯的抗组胺作用。",
        "西替利嗪——一種常見的非嗜睡抗組織胺藥——是羥嗪的主要代謝物。它的鎮靜作用弱得多,因此隨著轉化,羥嗪的鎮靜效果逐漸讓位於單純的抗組織胺作用。",
    ),
    "Norephedrine (phenylpropanolamine) is a peripheral sympathomimetic — it raises blood pressure and narrows blood vessels more than amphetamine's central action would predict. It adds cardiovascular load the parent's CNS profile doesn't warn about.": (
        "去甲麻黄碱(苯丙醇胺)是一种外周拟交感神经药——它升高血压和收缩血管的程度超过安非他明的中枢作用所能预测的。它增加了母体药物 CNS 特征所未提示的心血管负荷。",
        "去甲麻黃鹼(苯丙醇胺)是一種外周擬交感神經藥——它升高血壓和收縮血管的程度超過安非他命的中樞作用所能預測的。它增加了母體藥物 CNS 特徵所未提示的心血管負荷。",
    ),
    "7-aminoclonazepam has no meaningful activity at GABA-A — it's an inactive metabolite used as a urinary marker for clonazepam exposure, not a contributor to the drug's effect.": (
        "7-氨基氯硝西泮在 GABA-A 上无显著活性——它是一种无活性代谢物,用作氯硝西泮暴露的尿液标志物,不参与药物效应。",
        "7-胺基氯硝西泮在 GABA-A 上無顯著活性——它是一種無活性代謝物,用作氯硝西泮暴露的尿液標誌物,不參與藥物效應。",
    ),
    "Norfenfluramine is a more potent serotonin releaser than fenfluramine itself — it drives much of the pharmacological effect, including the 5-HT₂B agonism linked to cardiac valve damage in the 1990s weight-loss era.": (
        "去甲芬氟拉明是比芬氟拉明更强效的血清素释放剂——它驱动了大部分药理效应,包括与 1990 年代减肥时期心脏瓣膜损伤相关的 5-HT₂B 激动作用。",
        "去甲芬氟拉明是比芬氟拉明更強效的血清素釋放劑——它驅動了大部分藥理效應,包括與 1990 年代減肥時期心臟瓣膜損傷相關的 5-HT₂B 促效作用。",
    ),
    "This unusual Phase II conjugate retains the nor-mephedrone core — whether it has pharmacological activity is unknown, but its long plasma half-life means it lingers well past mephedrone's short duration.": (
        "这种不寻常的 II 相结合物保留了去甲甲卡西酮的核心结构——是否具有药理活性尚不明确,但其较长的血浆半衰期意味着它在甲卡西酮的短暂作用期过后仍会存留。",
        "這種不尋常的 II 相結合物保留了去甲甲卡西酮的核心結構——是否具有藥理活性尚不明確,但其較長的血漿半衰期意味著它在甲卡西酮的短暫作用期過後仍會存留。",
    ),
    "Cotinine has negligible nicotinic activity — it's the standard biomarker for tobacco exposure, not a continuation of nicotine's effect. Its long half-life (~16 hours) is why it's detectable in blood and urine days after the last cigarette.": (
        "可替宁的烟碱活性可忽略——它是烟草暴露的标准生物标志物,而非尼古丁效应的延续。其约 16 小时的长半衰期是最后一支烟后数天仍可在血液和尿液中检出的原因。",
        "可替寧的菸鹼活性可忽略——它是菸草暴露的標準生物標誌物,而非尼古丁效應的延續。其約 16 小時的長半衰期是最後一支菸後數天仍可在血液和尿液中檢出的原因。",
    ),
    "EDDP has no opioid activity — it's the primary urinary marker for methadone compliance monitoring, not a contributor to the drug's effect or duration.": (
        "EDDP 无阿片活性——它是美沙酮依从性监测的主要尿液标志物,不参与药物效应或持续时间。",
        "EDDP 無鴉片活性——它是美沙酮依從性監測的主要尿液標誌物,不參與藥物效應或持續時間。",
    ),
    "M3G is morphine's major metabolite (~60% of the dose) and has no analgesic activity — at high concentrations it's neuroexcitatory, contributing to myoclonus and paradoxical pain increase rather than pain relief. It accumulates in renal impairment, which is why morphine dosing needs adjustment when kidneys are compromised.": (
        "M3G 是吗啡的主要代谢物(约占剂量的 60%),无镇痛活性——高浓度时具有神经兴奋性,导致肌阵挛和矛盾性疼痛加重而非缓解。它在肾功能损害时蓄积,这是肾功能不全时需要调整吗啡剂量的原因。",
        "M3G 是嗎啡的主要代謝物(約佔劑量的 60%),無鎮痛活性——高濃度時具有神經興奮性,導致肌陣攣和矛盾性疼痛加重而非緩解。它在腎功能損害時蓄積,這是腎功能不全時需要調整嗎啡劑量的原因。",
    ),
    "Your body turns %1$@ into %2$@, which is active too.": (
        "身体会将 %1$@ 转化为 %2$@,后者同样具有活性。",
        "身體會將 %1$@ 轉化為 %2$@,後者同樣具有活性。",
    ),
    "A binding-affinity measurement, not clinical potency.": (
        "这是受体结合亲和力的测定值,并非临床效价。",
        "這是受體結合親和力的測定值,並非臨床效價。",
    ),
    "A lab measurement, not clinical potency.": (
        "这是实验室测定值,并非临床效价。",
        "這是實驗室測定值,並非臨床效價。",
    ),
    "How strong it is compared to %@ hasn't been established.": (
        "其相对于 %@ 的强度尚无定论。",
        "其相對於 %@ 的強度尚無定論。",
    ),
    "binding affinity": ("结合亲和力", "結合親和力"),
    "activity": ("活性", "活性"),
    "Measured at %1$@× %2$@'s %3$@ — a lab measurement, not clinical potency.": (
        "测定值为 %2$@ %3$@的 %1$@ 倍——这是实验室测定值,并非临床效价。",
        "測定值為 %2$@ %3$@的 %1$@ 倍——這是實驗室測定值,並非臨床效價。",
    ),
    "Also measured at %1$@× %2$@'s %3$@ — a lab measurement, not clinical potency.": (
        "另有测定值为 %2$@ %3$@的 %1$@ 倍——这是实验室测定值,并非临床效价。",
        "另有測定值為 %2$@ %3$@的 %1$@ 倍——這是實驗室測定值,並非臨床效價。",
    ),
    "Measured at %1$@× %2$@'s %3$@ at the %4$@ — a lab measurement, not clinical potency.": (
        "在%4$@上测定值为 %2$@ %3$@的 %1$@ 倍——这是实验室测定值,并非临床效价。",
        "在%4$@上測定值為 %2$@ %3$@的 %1$@ 倍——這是實驗室測定值,並非臨床效價。",
    ),
    "Also measured at %1$@× %2$@'s %3$@ at the %4$@ — a lab measurement, not clinical potency.": (
        "另在%4$@上测定值为 %2$@ %3$@的 %1$@ 倍——这是实验室测定值,并非临床效价。",
        "另在%4$@上測定值為 %2$@ %3$@的 %1$@ 倍——這是實驗室測定值,並非臨床效價。",
    ),
    "Opens this substance in the library.": ("在物质库中打开该物质。", "在物質庫中開啟該物質。"),
    "%@ days": ("%@ 天", "%@ 天"),
    "µ-opioid receptor": ("µ-阿片受体", "µ-鴉片受體"),
    "\u03ba-opioid receptor": ("\u03ba-阿片受体", "\u03ba-鴉片受體"),
    "\u03b4-opioid receptor": ("\u03b4-阿片受体", "\u03b4-鴉片受體"),
    "norepinephrine transporter": ("去甲肾上腺素转运体", "去甲腎上腺素轉運體"),
    "dopamine transporter": ("多巴胺转运体", "多巴胺轉運體"),
    "GABA-A receptor": ("GABA-A 受体", "GABA-A 受體"),
    "NMDA receptor": ("NMDA 受体", "NMDA 受體"),
    "nicotinic receptor": ("烟碱型受体", "菸鹼型受體"),
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
    "Recovery Tips": ("恢复提示", "恢復提示"),
    "Total in Your Body": ("体内总量", "體內總量"),
    # Dose detail redesign — session language (2026-07-12).
    "In Your Body": ("体内残留", "體內殘留"),
    "Part of Session": ("所属记录", "所屬記錄"),
    "About %@": ("关于%@", "關於%@"),
    "About %@ (%@)": ("关于%1$@（%2$@）", "關於%1$@（%2$@）"),
    "with %@": ("同服 %@", "同服 %@"),
    "+ %lld more": ("还有 %lld 条", "還有 %lld 條"),
    "Effects ended ~%@": ("效果已于 ~%@ 结束", "效果已於 ~%@ 結束"),
    "Effects ended ~%@ · cleared ~%@": (
        "效果已于 ~%1$@ 结束 · 约 %2$@ 清除",
        "效果已於 ~%1$@ 結束 · 約 %2$@ 清除",
    ),
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
    "Measured Interactions": (
        "实测相互作用",
        "實測交互作用",
    ),
    "Measured exposure": (
        "实测暴露量",
        "實測暴露量",
    ),
    "Kᵢ %@ µM": (
        "Kᵢ %@ µM",
        "Kᵢ %@ µM",
    ),
    "Additive CNS depression — increased sedation and impairment.": (
        "中枢抑制相加 — 镇静和损害加剧。",
        "中樞抑制相加 — 鎮靜和損害加劇。",
    ),
    "Combined respiratory depression with no ceiling — barbiturates deepen an opioid's suppression of breathing until it stops.": (
        "呼吸抑制相加且没有封顶——巴比妥类会不断加深阿片类对呼吸的抑制，直到呼吸停止。",
        "呼吸抑制相加且沒有封頂——巴比妥類會不斷加深鴉片類對呼吸的抑制，直到呼吸停止。",
    ),
    "Life-threatening respiratory depression. A barbiturate opens the GABA-A channel directly rather than modulating it, so this stacks past the point where benzodiazepines alone level off.": (
        "危及生命的呼吸抑制。巴比妥类直接打开 GABA-A 通道，而不只是调节它，因此这一组合会越过苯二氮䓬类单用时趋于平缓的那个点继续叠加。",
        "危及生命的呼吸抑制。巴比妥類直接打開 GABA-A 通道，而不只是調節它，因此這一組合會越過苯二氮平類單用時趨於平緩的那個點繼續疊加。",
    ),
    "Life-threatening respiratory depression and loss of consciousness — the classic fatal combination.": (
        "危及生命的呼吸抑制与意识丧失——典型的致命组合。",
        "危及生命的呼吸抑制與意識喪失——典型的致命組合。",
    ),
    "Severe respiratory depression — two direct-acting depressants with no shared ceiling.": (
        "严重呼吸抑制——两种直接作用的抑制剂，都没有封顶效应。",
        "嚴重呼吸抑制——兩種直接作用的抑制劑，都沒有封頂效應。",
    ),
    "Doses add with no plateau, and the gap between a sedating dose and a fatal one is narrow to begin with.": (
        "剂量相加且不会趋于平缓，而镇静剂量与致死剂量之间的差距本就很窄。",
        "劑量相加且不會趨於平緩，而鎮靜劑量與致死劑量之間的差距本就很窄。",
    ),
    "Additive sedation and respiratory depression.": (
        "镇静与呼吸抑制相加。",
        "鎮靜與呼吸抑制相加。",
    ),
    "Heavy additive sedation — profound drowsiness and impaired breathing.": (
        "镇静作用强烈相加——严重嗜睡与呼吸受损。",
        "鎮靜作用強烈相加——嚴重嗜睡與呼吸受損。",
    ),
    "Additive CNS and respiratory depression, with a raised risk of vomiting while unresponsive.": (
        "中枢与呼吸抑制相加，并且在失去反应时呕吐的风险升高。",
        "中樞與呼吸抑制相加，並且在失去反應時嘔吐的風險升高。",
    ),
    "Additive sedation, low blood pressure, and slow heart rate.": (
        "镇静、低血压与心率减慢相加。",
        "鎮靜、低血壓與心率減慢相加。",
    ),
    "Additive sedation and next-day impairment.": (
        "镇静相加，次日仍有功能损害。",
        "鎮靜相加，次日仍有功能損害。",
    ),
    "Additive sedation, dizziness, and slowed reaction time.": (
        "镇静、头晕与反应变慢相加。",
        "鎮靜、頭暈與反應變慢相加。",
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
    "All Substances": ("所有物质", "所有物質"),
    "Substances (%lld)": ("物质 (%lld)", "物質 (%lld)"),
    "Select All": ("全选", "全選"),
    "Deselect All": ("取消全选", "取消全選"),
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
    # 2026-08 — the deep-pharmacology sections (Genetics, Target Evidence,
    # concentration thresholds) and the drug-class write-ups moved to
    # Tools > Education.
    "^[%lld group](inflect: true)": ("%lld 个分类", "%lld 個分類"),
    "Genetics": ("基因", "基因"),
    "Target Evidence": ("靶点证据", "靶點證據"),
    "Pathway bias": ("通路偏向", "通路偏向"),
    "Receptor complex": ("受体复合物", "受體複合物"),
    "In vivo": ("体内", "體內"),
    "Drug Classes": ("药物类别", "藥物類別"),
    "What the members of a family share": ("同类药物的共同之处", "同類藥物的共同之處"),
    "No Classes": ("暂无类别", "暫無類別"),
    "Shared mechanism": ("共同机制", "共同機制"),
    "Shared kinetics": ("共同药代动力学", "共同藥物動力學"),
    "Shared safety profile": ("共同安全性特征", "共同安全性特徵"),
    "Structure and activity": ("构效关系", "構效關係"),
    "References": ("参考文献", "參考文獻"),
    "^[%lld other substance](inflect: true)": ("另有 %lld 种物质", "另有 %lld 種物質"),
    "^[%lld more combination](inflect: true)": ("另有 %lld 种组合", "另有 %lld 種組合"),
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
    "Select Month": ("选择月份", "選擇月份"),
    "Opens month picker": ("打开月份选择器", "開啟月份選擇器"),
    "Details & sources": ("详情与来源", "詳情與來源"),
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
    "Compare benzodiazepine doses against diazepam, or convert between two. Switching to a long-acting benzo before tapering is standard practice, though evidence for better outcomes is limited.": (
        "将苯二氮䓬的剂量与地西泮比较，或在两种之间换算。换用长效苯二氮䓬后再减量是常规做法，但改善结局的证据有限。",
        "將苯二氮䓬的劑量與地西泮比較，或在兩種之間換算。換用長效苯二氮䓬後再減量是常規做法，但改善結局的證據有限。",
    ),
    "If you have been drinking heavily and daily for weeks, stopping abruptly can be medically dangerous — seizures and delirium tremens peak 2–4 days after the last drink. Seek medical advice before going cold turkey.": (
        "如果你连续数周每天大量饮酒，突然戒断可能非常危险——癫痫发作和震颤性谵妄通常在最后一杯后 2–4 天达到高峰。戒酒前请先咨询医生。",
        "如果你連續數週每天大量飲酒，突然戒斷可能非常危險——癲癇發作和震顫性譫妄通常在最後一杯後 2–4 天達到高峰。戒酒前請先諮詢醫師。",
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
    # Session detail "In Your Body" section + row redesign (2026-07-09).
    "Estimates from population half-lives — individual clearance varies.": (
        "基于群体半衰期的估算——个体清除速率各异。",
        "基於群體半衰期的估算——個體清除速率各異。",
    ),
    "An estimate of how much of each substance is still in your body. This doesn't always correspond to how strong the effects feel, or to how long it stays detectable.": (
        "每种物质在你体内残留量的估算。这并不总是与效果的强弱，或可被检测到的时长直接相关。",
        "每種物質在你體內殘留量的估算。這並不總是與效果的強弱，或可被檢測到的時長直接相關。",
    ),
    "soon": ("很快", "很快"),
    "All recovery tips": ("全部恢复提示", "全部恢復提示"),
    "%@ total · %lld%% eliminated · clear ~%@": (
        "共 %1$@ · 已消除 %2$lld%% · 约 %3$@ 清除",
        "共 %1$@ · 已消除 %2$lld%% · 約 %3$@ 清除",
    ),
    "%lld%% eliminated · clear ~%@": (
        "已消除 %1$lld%% · 约 %2$@ 清除",
        "已消除 %1$lld%% · 約 %2$@ 清除",
    ),
    "Shows the elimination curve": ("显示消除曲线", "顯示消除曲線"),
    "Hydration, food, and rest for the comedown": (
        "补水、进食并休息以应对退效期。",
        "補水、進食並休息以應對退效期。",
    ),
    "Where the numbers come from": ("数字从何而来", "數字從何而來"),
    "Binding affinities come from the NIMH PDSP Kᵢ database and primary literature; the tolerance kinetics are calibrated to published human recovery studies. Every parameter is graded, and anything resting on a class default is flagged. Nothing here is measured from you — it's predicted from your dose log and these curated values.": (
        "结合亲和力来自 NIMH PDSP Kᵢ 数据库及原始文献；耐受动力学依据已发表的人体恢复研究校准。每个参数都经过分级，任何依赖类别默认值的内容都会被标注。这里没有任何数据是从你身上测得的——而是依据你的剂量记录和这些经过整理的数值预测得出。",
        "結合親和力來自 NIMH PDSP Kᵢ 資料庫及原始文獻；耐受動力學依據已發表的人體恢復研究校準。每個參數都經過分級，任何依賴類別預設值的內容都會被標註。這裡沒有任何數據是從你身上測得的——而是依據你的劑量記錄和這些經過整理的數值預測得出。",
    ),
    # Effect Estimates screen redesign — large title, one model card, taller graphs,
    # two bottom detail groups, and the "How this works" explainer (2026-07-10).
    "Effect Estimates": ("效应估算", "效應估算"),
    "Wanting": ("渴求", "渴求"),
    "Liking": ("愉悦", "愉悅"),
    "Compulsion": ("冲动", "衝動"),
    "Strain": ("负荷", "負荷"),
    "Experimental": ("实验性", "實驗性"),
    "How this session may feel over time": (
        "本次记录随时间可能的感受",
        "本次記錄隨時間可能的感受",
    ),
    "Fully eliminated": ("已完全消除", "已完全消除"),
    "Fully eliminated · active metabolite may persist": (
        "母体已完全消除 · 活性代谢物可能仍存在",
        "母體已完全消除 · 活性代謝物可能仍存在",
    ),
    # US-spelling renames of existing keys (2026-07-10); zh copied verbatim from the
    # British-spelled originals, which become stale orphans.
    "No half-life data — elimination not modeled": (
        "无半衰期数据 — 未建模消除",
        "無半衰期資料 — 未建模消除",
    ),
    "Recovery timescales and behavior are calibrated to the published literature for each receptor class. The note under each is the calibration basis; the badge is how well-established those kinetics are.": (
        "每一类受体的恢复时间和表现，都是照着已发表的文献校准的。每条下面的小字是校准依据；徽章表示这些动力学数据有多可靠。",
        "每一類受體的恢復時間和表現，都是照著已發表的文獻校準的。每條下面的小字是校準依據；徽章表示這些動力學數據有多可靠。",
    ),
    "A summary of how the drug affects the brain's three main signaling chemicals — serotonin, dopamine, and noradrenaline — and whether it releases them or blocks their reuptake. The slider shows which one it leans toward.": (
        "概述药物如何影响大脑三种主要的信号化学物质——5-羟色胺、多巴胺和去甲肾上腺素——以及它是促进释放还是阻断再摄取。滑块显示它更偏向哪一种。",
        "概述藥物如何影響大腦三種主要的訊號化學物質——5-羥色胺、多巴胺和去甲腎上腺素——以及它是促進釋放還是阻斷再攝取。滑桿顯示它更偏向哪一種。",
    ),
    "A busy session": ("复杂的记录", "複雜的記錄"),
    "The model is calibrated on a single substance taken once, in lab conditions. The interactions here stay mechanistic, but each extra dose and substance adds parameters and widens the margin of error.": (
        "该模型是在实验室条件下，基于单一物质单次摄入校准的。这里的相互作用仍是机制性的，但每增加一次用量或一种物质都会引入更多参数，扩大误差范围。",
        "此模型是在實驗室條件下，基於單一物質單次攝入校準的。這裡的交互作用仍是機制性的，但每增加一次用量或一種物質都會引入更多參數，擴大誤差範圍。",
    ),
    "Modeled from pharmacology": ("基于药理学建模", "基於藥理學建模"),
    "These curves estimate how this session may feel over time — how effects rise, peak, and fade, and how strong they get. Redoses and each substance's full duration are included, so a bigger dose lifts the curve higher.": (
        "这些曲线估算本次记录随时间可能的感受——效应如何上升、达到峰值、消退，以及强度如何。追加剂量和每种物质的完整作用时长都已纳入，因此剂量越大，曲线越高。",
        "這些曲線估算本次記錄隨時間可能的感受——效應如何上升、達到峰值、消退，以及強度如何。追加劑量和每種物質的完整作用時長都已納入，因此劑量越大，曲線越高。",
    ),
    "How this works": ("运作原理", "運作原理"),
    "Higher is better. Pleasure and warmth rise above the line; the comedown dips below.": (
        "越高越好。愉悦与暖意升至基线之上；退效期则跌至其下。",
        "越高越好。愉悅與暖意升至基線之上；退效期則跌至其下。",
    ),
    "Higher is livelier. Drive rises above the line, sedation sits below.": (
        "越高越有活力。驱动力升至基线之上，镇静则落于其下。",
        "越高越有活力。驅動力升至基線之上，鎮靜則落於其下。",
    ),
    "Higher is more pull. The rush and craving signal — can grow with repeated use even as the high fades.": (
        "越高渴求越强。冲动与渴望信号 — 即使快感减退，反复使用也可能使渴求增强。",
        "越高渴求越強。衝動與渴望信號 — 即使快感減退，反覆使用也可能使渴求增強。",
    ),
    "Higher is more pleasure. The opioid warmth signal — fades with tolerance.": (
        "越高愉悦越强。阿片温暖信号 — 随耐受而减弱。",
        "越高愉悅越強。阿片溫暖信號 — 隨耐受而減弱。",
    ),
    "Higher is more pull": ("越高渴求越强", "越高渴求越強"),
    "Higher is more pleasure": ("越高愉悦越强", "越高愉悅越強"),
    "Higher is more pull. The rush and craving signal.": (
        "越高渴求越强。冲动与渴望信号。",
        "越高渴求越強。衝動與渴望信號。",
    ),
    "Higher is more pleasure. The opioid warmth signal.": (
        "越高愉悦越强。阿片温暖信号。",
        "越高愉悅越強。阿片溫暖信號。",
    ),
    "Lower is better. The pull to take another dose.": (
        "越低越好。再服一剂的冲动。",
        "越低越好。再服一劑的衝動。",
    ),
    "Lower is better. Load on the body, shown with your heart rate when it's available.": (
        "越低越好。身体的负荷，在有数据时与你的心率一同显示。",
        "越低越好。身體的負荷，在有數據時與你的心率一同顯示。",
    ),
    "What these curves cover": ("这些曲线涵盖什么", "這些曲線涵蓋什麼"),
    "The model is calibrated on five stimulants: amphetamine, methylphenidate, mephedrone, 3-MMC, and 2-MMC. Other substances shape the curves through how they interact with these. Opioids are read through their dopamine activity, mostly to show those interactions.": (
        "该模型基于五种兴奋剂校准：安非他明、哌甲酯、4-甲基甲卡西酮、3-MMC 和 2-MMC。其他物质通过与它们的相互作用来影响曲线。阿片类物质则依据其多巴胺活性来解读，主要用于呈现这些相互作用。",
        "此模型基於五種興奮劑校準：安非他命、哌甲酯、4-甲基甲卡西酮、3-MMC 和 2-MMC。其他物質透過與它們的交互作用來影響曲線。鴉片類物質則依據其多巴胺活性來解讀，主要用於呈現這些交互作用。",
    ),
    "This session logs %@, which sit outside the model, so these curves stay empty.": (
        "本次记录包含 %@，它们不在模型范围内，因此这些曲线为空。",
        "本次記錄包含 %@，它們不在模型範圍內，因此這些曲線為空。",
    ),
    "These curves are built from %@. %@ sit outside the model.": (
        "这些曲线基于 %@ 构建。%@ 不在模型范围内。",
        "這些曲線基於 %@ 構建。%@ 不在模型範圍內。",
    ),
    "Reading the estimate": ("如何理解估算", "如何理解估算"),
    "This is a picture of typical pharmacology. Your own response shifts with tolerance, body chemistry, and the day.": (
        "这是典型药理反应的写照。你自身的反应会随耐受性、身体状况和当天状态而变化。",
        "這是典型藥理反應的寫照。你自身的反應會隨耐受性、身體狀況和當天狀態而變化。",
    ),
    "Confidence varies by substance. Well-studied ones like amphetamine and methylphenidate rest on firmer data than newer compounds.": (
        "可信度因物质而异。安非他明、哌甲酯等经过充分研究的物质，其数据基础比新型化合物更为扎实。",
        "可信度因物質而異。安非他命、哌甲酯等經過充分研究的物質，其數據基礎比新型化合物更為紮實。",
    ),
    "Compare the shape of a curve more than its exact height.": (
        "多比较曲线的形状，而非其确切高度。",
        "多比較曲線的形狀，而非其確切高度。",
    ),
    "A rough guide, not medical advice.": (
        "仅供粗略参考，并非医疗建议。",
        "僅供粗略參考，並非醫療建議。",
    ),
    "What you feel tracks a gap inside your dopamine system — the distance between the dopamine you have and the steady level your brain expects.": (
        "你的感受反映的是多巴胺系统内部的一段落差——现有多巴胺水平与大脑所预期的稳定水平之间的距离。",
        "你的感受反映的是多巴胺系統內部的一段落差——現有多巴胺水平與大腦所預期的穩定水平之間的距離。",
    ),
    "As a stimulant takes hold, dopamine climbs quickly. Your brain expects a steady baseline and adjusts toward the new level, but it catches up slowly. The gap between the two — dopamine now versus what your brain expects — is what reaches you.": (
        "当兴奋剂开始起效，多巴胺迅速攀升。大脑预期的是一个稳定的基线，会向新水平调整，但追赶得很慢。二者之间的落差——当前多巴胺与大脑所预期之间——正是你所感受到的。",
        "當興奮劑開始起效，多巴胺迅速攀升。大腦預期的是一個穩定的基線，會向新水平調整，但追趕得很慢。二者之間的落差——當前多巴胺與大腦所預期之間——正是你所感受到的。",
    ),
    "Rate over amount": ("速度胜过用量", "速度勝過用量"),
    "A fast route, like insufflation, outruns that adjustment and spikes. The same dose taken slowly lets the brain keep pace, so it barely registers as a rush.": (
        "鼻吸等快速给药方式会甩开这种调整，形成骤升。同样的剂量若缓慢摄入，大脑得以跟上节奏，便几乎感受不到冲劲。",
        "鼻吸等快速給藥方式會甩開這種調整，形成驟升。同樣的劑量若緩慢攝入，大腦得以跟上節奏，便幾乎感受不到衝勁。",
    ),
    "The comedown": ("退效期", "退效期"),
    "On the way down the expectation lags again. Dopamine returns to baseline while the expectation stays high, and that gap below the line is the comedown.": (
        "在下降过程中，预期再次滞后。多巴胺已回到基线，预期却仍居高不下，基线之下的这段落差便是退效期。",
        "在下降過程中，預期再次滯後。多巴胺已回到基線，預期卻仍居高不下，基線之下的這段落差便是退效期。",
    ),
    "Heavier doses": ("剂量越大", "劑量越大"),
    "A larger dose draws dopamine stores down harder: a bigger rise, and a deeper dip once it clears.": (
        "更大的剂量会更猛地消耗多巴胺储备：升得更高，代谢完后也跌得更深。",
        "更大的劑量會更猛地消耗多巴胺儲備：升得更高，代謝完後也跌得更深。",
    ),
    "Expected level": ("预期水平", "預期水平"),
    "The shaded gap is what you feel. As dopamine fades and the expectation lags above it, that gap turns into the comedown.": (
        "阴影区域即是你的感受。当多巴胺消退、预期滞留于其上时，这段落差便转为退效期。",
        "陰影區域即是你的感受。當多巴胺消退、預期滯留於其上時，這段落差便轉為退效期。",
    ),
    # Unmodeled release-form explainer on session detail — why a Concerta draws a
    # dot, not a curve (D.4.4, 2026-07-16). Named form reorders in zh, so the two
    # drop-ins are positional (%1$@ = product, %2$@ = base substance).
    "Piru doesn't model a timeline for the %@ form of %@. How long a form like this stays active isn't something Piru estimates, so the session shows when each dose was taken — not how long it lasts.": (
        "Piru 无法为 %2$@ 的 %1$@ 剂型绘制时间线。这类剂型的作用会持续多久并不在 Piru 的估算范围内，因此本次记录只显示每次用药的时间，而非其持续时长。",
        "Piru 無法為 %2$@ 的 %1$@ 劑型繪製時間線。這類劑型的作用會持續多久並不在 Piru 的估算範圍內，因此本次記錄只顯示每次用藥的時間，而非其持續時長。",
    ),
    "Piru doesn't model a timeline for some of these forms. How long they stay active isn't something Piru estimates, so the session shows when each dose was taken — not how long it lasts.": (
        "Piru 无法为其中部分剂型绘制时间线。它们的作用会持续多久并不在 Piru 的估算范围内，因此本次记录只显示每次用药的时间，而非其持续时长。",
        "Piru 無法為其中部分劑型繪製時間線。它們的作用會持續多久並不在 Piru 的估算範圍內，因此本次記錄只顯示每次用藥的時間，而非其持續時長。",
    ),
    # Meds & reminders redesign — hub, form, detail, card (2026-07-21).
    "My Meds": ("我的用药", "我的用藥"),
    "Set up your daily medications and supplements": (
        "设置您的每日用药和补充剂",
        "設定您的每日用藥和補充劑",
    ),
    "Med": ("用药", "用藥"),
    "Meds": ("用药", "用藥"),
    "%lld meds": ("%lld 项用药", "%lld 項用藥"),
    "1 med": ("1 项用药", "1 項用藥"),
    "No Meds Yet": ("尚无用药", "尚無用藥"),
    "Add a Med": ("添加用药", "新增用藥"),
    "Add Your Meds": ("添加你的用药", "新增你的用藥"),
    "Edit Med": ("编辑用药", "編輯用藥"),
    "Delete Med": ("删除用药", "刪除用藥"),
    "Delete this med?": ("删除这项用药？", "刪除這項用藥？"),
    "Manage Meds…": ("管理用药…", "管理用藥…"),
    "Log Meds": ("记录用药", "記錄用藥"),
    "Meds due": ("待服用药", "待服用藥"),
    "Med Reminders": ("用药提醒", "用藥提醒"),
    "Opens your meds": ("打开你的用药", "開啟你的用藥"),
    "Times": ("时间", "時間"),
    "Add a Time": ("添加时间", "新增時間"),
    "Add Another Time": ("再添加一个时间", "再新增一個時間"),
    "Anytime": ("随时", "隨時"),
    "anytime": ("随时", "隨時"),
    "Anytime — no set times": ("随时 — 未设定时间", "隨時 — 未設定時間"),
    "no set time": ("未设定时间", "未設定時間"),
    "As needed": ("按需", "按需"),
    "as needed": ("按需", "按需"),
    "no schedule": ("无计划", "無計劃"),
    "No daily limit": ("无每日上限", "無每日上限"),
    "up to %lld× daily": ("每日最多 %lld 次", "每日最多 %lld 次"),
    "Up to %lld× daily": ("每日最多 %lld 次", "每日最多 %lld 次"),
    "%lld× daily": ("每日 %lld 次", "每日 %lld 次"),
    "also %@": ("另有 %@", "另有 %@"),
    "before 12:00": ("12:00 之前", "12:00 之前"),
    "12:00 – 17:00": ("12:00 – 17:00", "12:00 – 17:00"),
    "17:00 – 21:00": ("17:00 – 21:00", "17:00 – 21:00"),
    "after 21:00": ("21:00 之后", "21:00 之後"),
    "Quiet": ("静默", "靜默"),
    "quiet": ("静默", "靜默"),
    "Quiet med": ("静默用药", "靜默用藥"),
    "Default": ("默认", "預設"),
    "10 min later": ("10 分钟后", "10 分鐘後"),
    "10 and 30 min later": ("10 分钟和 30 分钟后", "10 分鐘和 30 分鐘後"),
    "Reminders on": ("提醒已开启", "提醒已開啟"),
    "Reminders off": ("提醒已关闭", "提醒已關閉"),
    "Reminders, Ask Again, quiet hours, and everything else Piru sends.": (
        "提醒、再次询问、静默时段，以及 Piru 发送的其他一切。",
        "提醒、再次詢問、靜默時段，以及 Piru 傳送的其他一切。",
    ),
    "Keep track of what you take and when — one tap to set up gentle reminders. Prescriptions, supplements, vitamins: anything on a schedule.": (
        "记录你服用了什么、何时服用 — 轻点一下即可设置温和的提醒。处方药、补剂、维生素：任何按计划服用的东西。",
        "記錄你服用了什麼、何時服用 — 點一下即可設定溫和的提醒。處方藥、補劑、維生素：任何按計劃服用的東西。",
    ),
    "Quiet meds share one silent reminder per time of day — it never buzzes, it just waits in Notification Center. As-needed meds are never counted against you.": (
        "静默用药在每个时段共用一条无声提醒 — 它不会震动，只会在通知中心等待。按需用药永远不会被计为遗漏。",
        "靜默用藥在每個時段共用一條無聲提醒 — 它不會震動，只會在通知中心等待。按需用藥永遠不會被計為遺漏。",
    ),
    "Folds into the “Supplements” row and stays off the timeline graphs. Its reminders are silent — they wait in Notification Center instead of buzzing, and batch into iOS Scheduled Summary if you use it.": (
        "折叠进“补剂”一行，并且不出现在时间线图表中。它的提醒是无声的 — 只在通知中心等待而不会震动；如果你使用 iOS 的定时摘要，它们会汇总到那里。",
        "摺疊進「補劑」一行，並且不出現在時間線圖表中。它的提醒是無聲的 — 只在通知中心等待而不會震動；如果你使用 iOS 的定時摘要，它們會彙整到那裡。",
    ),
    "For supplements and other low-key meds: they fold into one “Supplements” row, share a single reminder per time of day, and stay off the timeline graphs. Adherence still counts them.": (
        "适用于补剂和其他低调用药：它们会折叠成一行“补剂”，在每个时段共用一条提醒，并且不出现在时间线图表中。依从性仍会统计它们。",
        "適用於補劑和其他低調用藥：它們會摺疊成一行「補劑」，在每個時段共用一條提醒，並且不出現在時間線圖表中。依從性仍會統計它們。",
    ),
    "Quiet meds' reminders arrive silently — no buzz, no lock-screen wake. If you use iOS Scheduled Summary, they batch there.": (
        "静默用药的提醒会无声送达 — 不震动，也不点亮锁定屏幕。如果你使用 iOS 的定时摘要，它们会汇总到那里。",
        "靜默用藥的提醒會無聲送達 — 不震動，也不亮起鎖定畫面。如果你使用 iOS 的定時摘要，它們會彙整到那裡。",
    ),
    "Ask Again re-asks if a dose isn't logged — “Default” follows the cadence in Notification Settings. Never a scold, just a nudge.": (
        "若某次用药未被记录，“再次询问”会再问一次 —“默认”遵循通知设置中的节奏。它从不是责备，只是轻轻提醒。",
        "若某次用藥未被記錄，「再次詢問」會再問一次 —「預設」遵循通知設定中的節奏。它從不是責備，只是輕輕提醒。",
    ),
    "A nudge at each med's set time so a dose never slips your mind. Tapping it opens Quick Log with that time's meds staged.": (
        "在每项用药的设定时间轻轻提醒，让你不会忘记服药。轻点即可打开快速记录，并预先放入该时段的用药。",
        "在每項用藥的設定時間輕輕提醒，讓你不會忘記服藥。點一下即可開啟快速記錄，並預先放入該時段的用藥。",
    ),
    "Asks again a little later if a med still isn't logged — like snooze for an alarm. Adjustable per med.": (
        "如果某项用药仍未被记录，稍后会再问一次 — 就像闹钟的稍后提醒。可为每项用药单独调整。",
        "如果某項用藥仍未被記錄，稍後會再問一次 — 就像鬧鐘的稍後提醒。可為每項用藥單獨調整。",
    ),
    "A reminder at each time. If you don't log it, Piru asks again %@ later — never a scold, just a nudge.": (
        "在每个时间提醒一次。如果你没有记录，Piru 会在 %@ 后再问一次 — 从不是责备，只是轻轻提醒。",
        "在每個時間提醒一次。如果你沒有記錄，Piru 會在 %@ 後再問一次 — 從不是責備，只是輕輕提醒。",
    ),
    "A logged dose checks this med off when the substance and route match — the same substance by another route stays a regular journal entry.": (
        "当物质和给药途径都匹配时，一次记录会将这项用药标记为已完成 — 同一物质若经其他途径使用，仍只是普通的日志记录。",
        "當物質和給藥途徑都匹配時，一次記錄會將這項用藥標記為已完成 — 同一物質若經其他途徑使用，仍只是普通的日誌記錄。",
    ),
    "No schedule and never marked missed — adherence doesn't count as-needed meds. A daily limit feeds the cumulative dose warnings.": (
        "没有计划，也永远不会被标记为遗漏 — 依从性不统计按需用药。设定每日上限可用于累积剂量警告。",
        "沒有計劃，也永遠不會被標記為遺漏 — 依從性不統計按需用藥。設定每日上限可用於累積劑量警告。",
    ),
    "No set time — this med still counts toward adherence once per due day.": (
        "未设定时间 — 这项用药在每个应服日仍计入一次依从性。",
        "未設定時間 — 這項用藥在每個應服日仍計入一次依從性。",
    ),
    "Reminders and adherence tracking stop. Doses you already logged stay in your journal.": (
        "提醒和依从性追踪将停止。你已经记录的剂量仍保留在日志中。",
        "提醒和依從性追蹤將停止。你已經記錄的劑量仍保留在日誌中。",
    ),
    "Time to log %@ — %@.": ("该记录 %@ 了 — %@。", "該記錄 %@ 了 — %@。"),
    "Still need to log %@?": ("还需要记录 %@ 吗？", "還需要記錄 %@ 嗎？"),
    "Still need your %@ supplements?": ("还需要服用 %@ 的补剂吗？", "還需要服用 %@ 的補劑嗎？"),
    "%@ supplements (%lld)": ("%@ 补剂（%lld）", "%@ 補劑（%lld）"),
    "Stages this group’s meds": ("将该组用药加入暂存", "將該組用藥加入暫存"),
    "Take All": ("全部服用", "全部服用"),
    "Not taken yet": ("尚未服用", "尚未服用"),
    "Collapses the list": ("折叠列表", "摺疊列表"),
    "Expands the list": ("展开列表", "展開列表"),
    # Quick Log: due-now strip, merged substances section (2026-07-21).
    "Due now": ("现在该服用", "現在該服用"),
    "Due": ("待服用", "待服用"),
    "due": ("待服用", "待服用"),
    "%lld due": ("%lld 项待服用", "%lld 項待服用"),
    "%lld meds due": ("%lld 项用药待服用", "%lld 項用藥待服用"),
    "Staged": ("已暂存", "已暫存"),
    "Stages this dose": ("将此剂量加入暂存", "將此劑量加入暫存"),
    "Your Substances": ("你的物质", "你的物質"),
    "Log a Dose": ("记录一次用药", "記錄一次用藥"),
    "Logs this dose": ("记录此剂量", "記錄此劑量"),
    # Adherence screen (2026-07-21).
    "Add your meds to see adherence": ("添加你的用药以查看依从性", "新增你的用藥以查看依從性"),
    "Adherence tracks how consistently you take your scheduled meds. Add one and this screen starts working.": (
        "依从性追踪你按计划服药的稳定程度。添加一项用药，这个页面就会开始工作。",
        "依從性追蹤你按計劃服藥的穩定程度。新增一項用藥，這個頁面就會開始運作。",
    ),
    "%lld of %lld taken": ("已服用 %lld / %lld", "已服用 %lld / %lld"),
    # Continuous timeline ribbon (2026-07-21).
    "Dose timeline": ("剂量时间线", "劑量時間線"),
    "Continuous dose timeline": ("连续剂量时间线", "連續劑量時間線"),
    # "Timeline" itself is already translated above (时间轴).
    "No Timeline Yet": ("尚无时间线", "尚無時間線"),
    "Opens the full timeline.": ("打开完整时间线。", "開啟完整時間線。"),
    "Explore the timeline": ("浏览时间线", "瀏覽時間線"),
    "Drag to explore doses": ("拖动以浏览各次用药", "拖動以瀏覽各次用藥"),
    "Log a dose and its effect curve will appear here.": (
        "记录一次用药，它的效果曲线就会出现在这里。",
        "記錄一次用藥，它的效果曲線就會出現在這裡。",
    ),
    "Scroll back through your history. Touch and hold to inspect a moment.": (
        "向后滚动浏览你的历史记录。触摸并按住可查看某一时刻。",
        "向後捲動瀏覽你的歷史記錄。觸摸並按住可查看某一時刻。",
    ),
    # Substance-detail redesign, feedback round 3 (2026-07-24).
    "Log Now": ("立即记录", "立即記錄"),
    "All phases": ("全部阶段", "全部階段"),
    # PK card: how many distinct studies stand behind one route (2026-07-25).
    "%lld studies": ("%lld 项研究", "%lld 項研究"),
    # Intervention ledger — GABA discontinuation evidence (§J, 2026-08-06).
    "Discontinuation evidence": ("停药证据", "停藥證據"),
    "Discontinuation Evidence": ("停药证据", "停藥證據"),
    "Clinical trial evidence for interventions during benzodiazepine discontinuation. Each row is what the study found — not a recommendation.": (
        "苯二氮卓类停药干预措施的临床试验证据。每行是研究发现——不是建议。",
        "苯二氮卓類停藥干預措施的臨床試驗證據。每行是研究發現——不是建議。",
    ),
    "Supported by evidence": ("有证据支持", "有證據支持"),
    "Not supported by evidence": ("无证据支持", "無證據支持"),
    "This half is the more useful half.": ("这一半更有用。", "這一半更有用。"),
    "Not medical advice. Benzodiazepine discontinuation can be medically dangerous — these are research findings, not a plan.": (
        "非医疗建议。苯二氮卓类停药可能有医疗风险——这些是研究发现，不是方案。",
        "非醫療建議。苯二氮卓類停藥可能有醫療風險——這些是研究發現，不是方案。",
    ),
    "CBT + gradual taper": ("认知行为疗法 + 逐步减量", "認知行為療法 + 逐步減量"),
    "The strongest result in the literature. Discontinuation significantly higher than taper alone at both 3 months and 6–12 months.": (
        "文献中最强的结果。停药率在3个月和6–12个月时均显著高于单纯减量。",
        "文獻中最強的結果。停藥率在3個月和6–12個月時均顯著高於單純減量。",
    ),
    "Meta-analysis": ("荟萃分析", "薈萃分析"),
    "Gradual taper": ("逐步减量", "逐步減量"),
    "About two-thirds discontinue short-term; roughly one-third sustain long-term. Consensus is to taper gradually over 4–6 weeks; there is no agreed rate — the trials here used 25% per week.": (
        "约三分之二短期成功停药；约三分之一长期维持。共识是在4–6周内逐步减量；减量速率没有公认标准——此处的试验采用每周减少25%。",
        "約三分之二短期成功停藥；約三分之一長期維持。共識是在4–6週內逐步減量；減量速率沒有公認標準——此處的試驗採用每週減少25%。",
    ),
    "Clinical consensus": ("临床共识", "臨床共識"),
    "Imipramine": ("丙米嗪", "丙米嗪"),
    "Taper success 82.6% vs 37.5% placebo.": (
        "减量成功率82.6% vs 安慰剂37.5%。",
        "減量成功率82.6% vs 安慰劑37.5%。",
    ),
    "RCT, n = 107": ("随机对照试验，n = 107", "隨機對照試驗，n = 107"),
    "%lld–%lld days": ("%lld–%lld 天", "%lld–%lld 天"),
    "%lld–%lld hours": ("%lld–%lld 小时", "%lld–%lld 小時"),
    "RCT, n = %lld": ("随机对照试验，n = %lld", "隨機對照試驗，n = %lld"),
    "n = %lld": ("n = %lld", "n = %lld"),
    "n = %lld, underpowered": ("n = %lld，统计效力不足", "n = %lld，統計效力不足"),
    "%lld RCTs": ("%lld项随机对照试验", "%lld項隨機對照試驗"),
    "%lld trials": ("%lld项试验", "%lld項試驗"),
    "1 RCT (n = %lld) + open study (n = 282)": (
        "1项随机对照试验 (n = %lld) + 开放研究 (n = 282)",
        "1項隨機對照試驗 (n = %lld) + 開放研究 (n = 282)",
    ),
    "More patients BZD-free at week 5; lower withdrawal incidence and anxiety in elderly.": (
        "第5周时更多患者已停用苯二氮卓；老年患者戒断发生率和焦虑均降低。",
        "第5週時更多患者已停用苯二氮卓；老年患者戒斷發生率和焦慮均降低。",
    ),
    "3 RCTs": ("3项随机对照试验", "3項隨機對照試驗"),
    "Pregabalin": ("普瑞巴林", "普瑞巴林"),
    "Safe and effective for tapering off long-term use; improved sleep.": (
        "对长期使用者减量安全有效；改善睡眠。",
        "對長期使用者減量安全有效；改善睡眠。",
    ),
    "1 RCT (n = 106) + open study (n = 282)": (
        "1项随机对照试验 (n = 106) + 开放研究 (n = 282)",
        "1項隨機對照試驗 (n = 106) + 開放研究 (n = 282)",
    ),
    "Valproate": ("丙戊酸盐", "丙戊酸鹽"),
    "79% abstinent at 5 weeks post-taper vs placebo. No effect at 12 weeks.": (
        "减量后第5周79%戒断 vs 安慰剂。第12周时无效果。",
        "減量後第5週79%戒斷 vs 安慰劑。第12週時無效果。",
    ),
    "RCT": ("随机对照试验", "隨機對照試驗"),
    "Flumazenil": ("氟马西尼", "氟馬西尼"),
    "Reversed withdrawal scores and craving vs oxazepam taper and placebo. Inpatient IV only — dangerous in chronic users (precipitated withdrawal).": (
        "逆转了戒断评分和渴求（对比奥沙西泮减量和安慰剂）。仅限住院静脉注射——对长期使用者危险（诱发戒断）。",
        "逆轉了戒斷評分和渴求（對比奧沙西泮減量和安慰劑）。僅限住院靜脈注射——對長期使用者危險（誘發戒斷）。",
    ),
    "2 trials": ("2项试验", "2項試驗"),
    "Melatonin": ("褪黑素", "褪黑素"),
    "One small positive trial (n = 34); two larger negative trials (n = 80, n = 38 at 1-year follow-up). Improved sleep quality without improving discontinuation.": (
        "一项小型阳性试验 (n = 34)；两项较大的阴性试验 (n = 80, n = 38，1年随访)。改善了睡眠质量但未改善停药率。",
        "一項小型陽性試驗 (n = 34)；兩項較大的陰性試驗 (n = 80, n = 38，1年隨訪)。改善了睡眠品質但未改善停藥率。",
    ),
    "Long-acting benzo switch": ("换用长效苯二氮卓", "換用長效苯二氮卓"),
    "Insufficient evidence to support the efficacy of this strategy — despite being the standard move and the core of the Ashton method.": (
        "证据不足以支持该策略的有效性——尽管它是标准操作且是Ashton方法的核心。",
        "證據不足以支持該策略的有效性——儘管它是標準操作且是Ashton方法的核心。",
    ),
    "Gabapentin": ("加巴喷丁", "加巴噴丁"),
    "No difference vs placebo.": ("与安慰剂无差异。", "與安慰劑無差異。"),
    "n = 19, underpowered": ("n = 19，统计效力不足", "n = 19，統計效力不足"),
    "Lithium": ("锂盐", "鋰鹽"),
    "More than 60% discontinuation in both arms; no difference.": (
        "两组停药率均超过60%；无差异。",
        "兩組停藥率均超過60%；無差異。",
    ),
    "n = 244": ("n = 244", "n = 244"),
    "Progesterone": ("黄体酮", "黃體酮"),
    "No difference on withdrawal severity, anxiety, or drug-free status.": (
        "戒断严重程度、焦虑或无药状态均无差异。",
        "戒斷嚴重程度、焦慮或無藥狀態均無差異。",
    ),
    "n = 40": ("n = 40", "n = 40"),
    "Magnesium aspartate": ("天冬氨酸镁", "天冬氨酸鎂"),
    "No difference on any endpoint.": ("所有终点均无差异。", "所有終點均無差異。"),
    "n = 144": ("n = 144", "n = 144"),
    "Ondansetron": ("昂丹司琼", "昂丹司瓊"),
    "No effect on taper rate, withdrawal severity, or anxiety.": (
        "对减量速率、戒断严重程度或焦虑无效。",
        "對減量速率、戒斷嚴重程度或焦慮無效。",
    ),
    "n = 108": ("n = 108", "n = 108"),
    "Buspirone": ("丁螺环酮", "丁螺環酮"),
    "Four small trials with contradictory results.": (
        "四项小型试验，结果相互矛盾。",
        "四項小型試驗，結果相互矛盾。",
    ),
    "Propranolol": ("普萘洛尔", "普萘洛爾"),
    "Reduced symptom severity in completers; no effect on dropout rate or incidence.": (
        "完成者的症状严重程度降低；对退出率或发生率无影响。",
        "完成者的症狀嚴重程度降低；對退出率或發生率無影響。",
    ),
    "Navarrete F, et al. Benzodiazepine Dependence: Clinical and Molecular Aspects, Preventive Strategies and Therapeutic Approaches. Int J Mol Sci. 2026;27(3):1430.": (
        "Navarrete F 等。苯二氮卓类依赖：临床和分子方面、预防策略和治疗方法。Int J Mol Sci. 2026;27(3):1430.",
        "Navarrete F 等。苯二氮卓類依賴：臨床和分子方面、預防策略和治療方法。Int J Mol Sci. 2026;27(3):1430.",
    ),
    "doi:10.3390/ijms27031430": ("doi:10.3390/ijms27031430", "doi:10.3390/ijms27031430"),
    "RCT, n = 78": ("随机对照试验，n = 78", "隨機對照試驗，n = 78"),
    # CYP2D6 metabolizer status (§F, 2026-08-06).
    "CYP2D6 status": ("CYP2D6状态", "CYP2D6狀態"),
    "Poor metabolizer": ("慢代谢者", "慢代謝者"),
    "Intermediate metabolizer": ("中间代谢者", "中間代謝者"),
    "Extensive metabolizer": ("快代谢者", "快代謝者"),
    "Ultra-rapid metabolizer": ("超快代谢者", "超快代謝者"),
    "CYP2D6 metabolizer status affects how your body handles codeine, tramadol, MDMA, and several other substances — set it if you know yours from a pharmacogenomics test. Unknown is treated as extensive (the most common).": (
        "CYP2D6代谢者状态影响你的身体处理可待因、曲马多、MDMA等多种物质的方式——如果你通过药物基因组学检测知道自己的类型，请在此设置。「未知」按照最常见的「快代谢者」处理。",
        "CYP2D6代謝者狀態影響你的身體處理可待因、曲馬多、MDMA等多種物質的方式——如果你通過藥物基因組學檢測知道自己的類型，請在此設置。「未知」按照最常見的「快代謝者」處理。",
    ),
    # Gabapentinoid α2δ class (§K.6, 2026-08-06).
    "Gabapentinoids (α2δ)": ("加巴喷丁类 (α2δ)", "加巴噴丁類 (α2δ)"),
    "Gabapentinoids": ("加巴喷丁类", "加巴噴丁類"),
    "α2δ subunit (VGCC)": ("α2δ亚基 (VGCC)", "α2δ亞基 (VGCC)"),
    "Sedative tolerance builds; dependence can develop within weeks of daily use. Phenibut withdrawal is among the most severe.": (
        "镇静耐受性会逐渐建立；每日使用数周即可产生依赖。苯乙胺丁酸的戒断反应属于最严重的类型之一。",
        "鎮靜耐受性會逐漸建立；每日使用數週即可產生依賴。苯乙胺丁酸的戒斷反應屬於最嚴重的類型之一。",
    ),
    # GABA cognitive impairment safety note (§B, 2026-08-06).
    "The dose that no longer makes you sleepy impairs your memory and coordination exactly as much as it did on day one.": (
        "不再让你困倦的剂量对你的记忆和协调能力的损害与第一天完全相同。",
        "不再讓你困倦的劑量對你的記憶和協調能力的損害與第一天完全相同。",
    ),
    # Phenibut protracted-withdrawal warning (§L.2, 2026-08-06).
    "If you are using phenibut or F-phenibut daily, dependence develops within weeks. Protracted withdrawal can last months — taper gradually with medical guidance.": (
        "如果你每天使用苯乙胺丁酸或氟苯乙胺丁酸，数周内就会产生依赖。迁延性戒断可持续数月——在医疗指导下逐步减量。",
        "如果你每天使用苯乙胺丁酸或氟苯乙胺丁酸，數週內就會產生依賴。遷延性戒斷可持續數月——在醫療指導下逐步減量。",
    ),
    # CYP2D6 pharmacogenomic notes (§F.2 wiring, 2026-08-06).
    "CYP2D6: %@": ("CYP2D6：%@", "CYP2D6：%@"),
    "Reduced conversion to active metabolite — you may get less effect from %@.": (
        "活性代谢物转化减少——%@ 的效果可能较弱。",
        "活性代謝物轉化減少——%@ 的效果可能較弱。",
    ),
    "Mildly reduced conversion to active metabolite — effect may be modestly lower.": (
        "活性代谢物转化略微减少——效果可能略低。",
        "活性代謝物轉化略微減少——效果可能略低。",
    ),
    "Faster conversion to active metabolite — higher active metabolite exposure. For codeine, this is an FDA contraindication due to the risk of respiratory depression.": (
        "活性代谢物转化加快——活性代谢物暴露量更高。对于可待因，因呼吸抑制风险，FDA 列为禁忌。",
        "活性代謝物轉化加快——活性代謝物暴露量更高。對於可待因，因呼吸抑制風險，FDA 列為禁忌。",
    ),
    "Slower CYP2D6 clearance — %@ may last longer and accumulate at repeated doses.": (
        "CYP2D6 清除较慢——%@ 的持续时间可能更长，多次给药时可能蓄积。",
        "CYP2D6 清除較慢——%@ 的持續時間可能更長，多次給藥時可能蓄積。",
    ),
    "Mildly slower CYP2D6 clearance — duration may be modestly longer.": (
        "CYP2D6 清除略慢——持续时间可能略长。",
        "CYP2D6 清除略慢——持續時間可能略長。",
    ),
    "Faster CYP2D6 clearance — shorter duration. Be aware of re-dose timing.": (
        "CYP2D6 清除加快——持续时间更短。注意补服时机。",
        "CYP2D6 清除加快——持續時間更短。注意補服時機。",
    ),
    "CYP2D6 is a major metabolic pathway for %@.": (
        "CYP2D6 是 %@ 的主要代谢途径。",
        "CYP2D6 是 %@ 的主要代謝途徑。",
    ),
    # b45 feedback — metabolizer variation chart (C1)
    "Fast metabolizer": ("快代谢型", "快代謝型"),
    "Slow metabolizer": ("慢代谢型", "慢代謝型"),
    "Genetic variation in %@ formation": (
        "%@ 生成的基因变异",
        "%@ 生成的基因變異",
    ),
    "Same dose, different conversion — the effect varies by genotype.": (
        "同样的剂量，不同的转化——效应因基因型而异。",
        "同樣的劑量，不同的轉化——效應因基因型而異。",
    ),
    # b45 feedback — insight group previews (D6)
    "substance modeled": ("种物质已建模", "種物質已建模"),
    "substances modeled": ("种物质已建模", "種物質已建模"),
    "Add regular meds to project steady state": (
        "添加常规用药以预测稳态",
        "新增常規用藥以預測穩態",
    ),
    "regular med": ("种常规药", "種常規藥"),
    "regular meds": ("种常规药", "種常規藥"),
    # b45 feedback — receptor load zoom (E2)
    "Wide": ("宽", "寬"),
    "Medium": ("中", "中"),
    "Close": ("近", "近"),
    "Zoom": ("缩放", "縮放"),
}

# Widget translations
WT = {
    # Today's Meds interactive widget (2026-07-21).
    "Today's Meds": ("今日用药", "今日用藥"),
    "No meds today": ("今日无用药", "今日無用藥"),
    "All taken": ("已全部服用", "已全部服用"),
    "That's everything today.": ("今天的都完成了。", "今天的都完成了。"),
    "Due · %@": ("待服用 · %@", "待服用 · %@"),
    "Take %@": ("服用 %@", "服用 %@"),
    "Take all supplements": ("服用全部补剂", "服用全部補劑"),
    "Take Med": ("服用用药", "服用用藥"),
    "Take Supplements": ("服用补剂", "服用補劑"),
    "Med identity": ("用药标识", "用藥識別"),
    "Logs one dose of a scheduled med.": ("记录一次计划内用药。", "記錄一次計劃內用藥。"),
    "Logs your remaining supplements for today.": (
        "记录你今天剩余的补剂。",
        "記錄你今天剩餘的補劑。",
    ),
    "See today's med schedule and take one right from the Home Screen.": (
        "查看今天的用药安排，并直接从主屏幕完成服用。",
        "查看今天的用藥安排，並直接從主畫面完成服用。",
    ),
    "Next Dose": ("下一剂", "下一劑"),
    "Countdown to your next scheduled med.": (
        "距离下一次计划用药的倒计时。",
        "距離下一次計畫用藥的倒計時。",
    ),
    "See how much you have left of what you track.": (
        "查看你追踪的物品还剩多少。",
        "查看你追蹤的物品還剩多少。",
    ),
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


sys.path.insert(0, str(Path(__file__).resolve().parent / "localization"))
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
    NEW_KEYS: set[str] = {
        # b46 feedback batches
        "Backups, export & import are under Tools › Data & Backup; preferences are under Settings.",
        "That's everything today — %lld days and counting",
        "That's everything today",
        "Scale by Dose Strength",
        "· %lld of %lld",
        "%lld of %lld logged today",
        "Dose Times",
        "Edit Dose Times…",
        "The quick offsets in the “Now” menu when logging a dose.",
        "Colors",
        "A color for every substance you log",
        "^[%lld substances](inflect: true) with a color",
        "Export, import, and encrypted backups",
        "Which source wins when they disagree, and opt-in updates to the bundled substance data.",
        "Tap a dot to name it",
        "Name on plot",
        "%@, this substance",
        "%@, measured in the same study",
        # Unified timeline
        "Compress empty time",
        "Effect curves",
        "How strongly effects are felt over time",
        "Body load (PK)",
        "How much is estimated to remain in your body",
        "Display Options",
        # Reports & Export hub
        "Reports",
        "Export sessions, generate clinical reports",
        "Latest",
        "By Date",
        "Select sessions",
        "Select Sessions",
        "Clinical Report",
        "Key findings, medication summary, dose trends — for your doctor",
        "Session Images",
        "Stitched Image",
        "All selected sessions in one tall image",
        "Plain-text session data — for notes, AI, or records",
        "No entries in this range",
        "· %lld entries",
        "%lld sessions as individual images",
        "Sessions in this range as individual images",
        "No sessions yet",
        # (previous keys below)
        "μ-Opioid Receptor Ligand",
        "Acts at μ-opioid receptors (MOR), G-protein coupled receptors distributed throughout the central and peripheral nervous system. MOR activation inhibits adenylyl cyclase, opens inwardly rectifying potassium channels, and closes voltage-gated calcium channels, reducing neuronal excitability and neurotransmitter release — producing analgesia, euphoria, respiratory depression, and slowed gastrointestinal transit. How far this particular compound activates the receptor, and whether it also engages κ or δ, is not characterized here; the receptor panel below carries whatever has been measured for it.",
        "Antipsychotic (Dopamine Receptor Antagonist)",
        "Blocks dopamine D2 receptors in the mesolimbic pathway, reducing positive psychotic symptoms. Whether this compound also carries the 5-HT2A antagonism that distinguishes the second-generation agents, and the histamine, muscarinic and adrenergic activity that drives sedation and orthostasis, varies across the class and is not characterized here.",
        "Histamine H1 Receptor Antagonist",
        "Blocks histamine H1 receptors, reducing the itching, flare, wheal and vasodilation of the histamine response. Whether this compound crosses into the central nervous system — the difference between a sedating first-generation antihistamine with a muscarinic load and a peripherally selective second-generation one — is not characterized here.",
        "Enters dopamine (DAT), norepinephrine (NET), and serotonin (SERT) nerve terminals and reverses their transporters, releasing all three monoamines. Also agonizes TAAR1 and acts at VMAT2 to redistribute vesicular monoamines into the cytosol.",
        "When it peaks",
        "Worst around %@",
        "%lld hours",
        "From a trial that stopped 57 people abruptly after a year or more of daily use and assessed them every day. Longer-acting drugs peak later because the drug is still leaving your system; active metabolites (diazepam, chlordiazepoxide, clonazepam) push it later still. When symptoms *start* is not shown because no source survives checking — the figures in circulation land at or after the measured peak, which cannot be right.",
        "Peak timing: Rickels K, et al. Long-term therapeutic use of benzodiazepines. I. Effects of abrupt discontinuation. Arch Gen Psychiatry. 1990;47(10):899-907.",
        "Symptom groups and drug classes: Navarrete F, et al. Benzodiazepine Dependence: Clinical and Molecular Aspects, Preventive Strategies and Therapeutic Approaches. Int J Mol Sci. 2026;27(3):1430.",
        "Both raise serotonin, so serotonin syndrome is possible — agitation, tremor, sweating, a racing heart — and most likely in the first weeks. This pairing is prescribed and monitored on purpose; SSRIs do not raise lithium levels.",
        "Both raise serotonin, so serotonin syndrome is possible — agitation, tremor, sweating, a racing heart — and most likely in the first weeks. This pairing is prescribed and monitored on purpose; SNRIs do not raise lithium levels.",
        "A large serotonin load on top of lithium's own. The lithium label names tramadol and fentanyl in this group; serotonin syndrome can start within hours.",
        "MAOIs block the enzyme that clears serotonin, so the load builds instead of levelling off. Serotonin syndrome is the risk; MAOIs do not raise lithium levels.",
        "Of 62 reports of this combination, 47% described a seizure and 39% involved medical attention — against none of 34 reports for lamotrigine. Self-reported, so the rate is not a measured one, but no other pairing shows a signal like it.",
        "MDMA releases serotonin in bulk and lithium adds to it, so serotonin syndrome is the main risk. Seizures are reported for lithium with classic psychedelics; MDMA has not been looked at the same way.",
        "Source: the Ashton Manual's equivalence table, which calls these doses approximate and notes that not every clinician agrees with them.",
        "Not in the Ashton Manual's equivalence table, and not sourced elsewhere — treat the number as a rough guide and dose by this drug's own threshold.",
        "One of these is from the Ashton Manual's equivalence table; the other is not in it and is not sourced elsewhere. Equivalences are approximate either way.",
        "Which class this belongs in is argued over — the label is the conventional one, not a settled one.",
        "Noradrenaline reuptake inhibitor",
        "Serotonin modulator and stimulator",
        "Blocks the noradrenaline transporter and leaves the other two. In the prefrontal cortex that same transporter is what clears dopamine, so the effect there is not as purely noradrenergic as the name reads.",
        "Blocks serotonin reuptake and acts on several serotonin receptors directly, agonist at some and antagonist at others. The receptor work is what separates it from an SSRI, not the transporter block they share.",
        "%lld–%lld days",
        "%lld–%lld hours",
        "RCT, n = %lld",
        "n = %lld",
        "n = %lld, underpowered",
        "%lld RCTs",
        "%lld trials",
        "1 RCT (n = %lld) + open study (n = 282)",
        "%@ (transdermal)",
        "Methadone's half-life is long and variable, and its peak effect on breathing arrives later and lasts longer than its peak pain relief — so a converted dose can look adequate while the risk is still building. CDC publishes a single factor for population-level accounting; Piru will not use it to convert a dose. This one belongs to a clinician.",
        "Transdermal fentanyl is dosed in micrograms per hour — a rate, not a mass, so it shares no unit space with the mg-based table (CDC gives 2.4 MME per mcg/hr). Absorption also changes with heat and other factors.",
        "Buprenorphine is a partial agonist with a ceiling on its effect on breathing, so risk doesn't scale the way a full agonist's does. CDC excludes it from MME entirely and says it should not be counted toward a daily total.",
        "<1% elemental",
        "Curated",
        "curated entry",
        "Crisis resources, safety basics, and what's active right now.",
        "Details & sources",
        "Select Month",
        "Opens month picker",
        "Set up your daily medications and supplements",
        "Pharmacological data is compiled from the sources above — community databases, FDA labeling, and peer-reviewed literature. Provided for reference and educational purposes only. Always consult a qualified healthcare professional before making decisions about substance use.",
        "Includes %lld min of workout — the dose rows leave it out",
        "Connect once to pull your body weight, heart rate, and blood pressure from Health — all read-only, on your device. Workouts come too, only so a run isn't read as a dose's effect.",
        "Heart rate %lld falling to %lld beats per minute",
        "Heart rate %lld beats per minute, no clear change",
        "overlaps %@",
        "Downstream",
        "No half-life data",
        "Known allergy to it",
        "With an MAOI, or within 14 days of one",
        "With other CNS depressants",
        "With a strong CYP3A4 inhibitor",
        "With a QT-prolonging drug",
        "With a live vaccine",
        "With a nitrate or a guanylate cyclase stimulator",
        "With alcohol",
        "With an anticoagulant",
        "Existing respiratory depression",
        "During an acute asthma attack",
        "Bowel obstruction",
        "Active bleeding",
        "Liver disease",
        "Kidney disease",
        "Anuria",
        "Recent heart attack or heart surgery",
        "Uncontrolled high blood pressure",
        "Heart rhythm disorder",
        "Heart failure",
        "Seizure disorder",
        "Narrow-angle glaucoma",
        "Urinary retention",
        "Adrenal insufficiency",
        "Systemic fungal infection",
        "Porphyria",
        "Pheochromocytoma",
        "Untreated thyroid disease",
        "Pregnancy",
        "Breastfeeding",
        "Children",
        "Eating disorder",
        "Myasthenia gravis",
        "Sleep apnea",
        "Smoking over the age of 35",
        "During low blood sugar",
        "Low potassium",
        "High potassium",
        "Personal or family history of thyroid cancer",
        "Marked anxiety or agitation",
        "Around surgery",
        "^[%lld group](inflect: true)",
        "Drug Classes",
        "What the members of a family share",
        "No Classes",
        "^[%lld other substance](inflect: true)",
        "^[%lld more combination](inflect: true)",
        "Patterns",
        "Log doses to see your patterns",
        "Days used, cumulative exposure, dose trend, and overlap — for you or your doctor",
        "Days used, exposure, dose trend, and overlap",
        "Log some doses to see your patterns.",
        "Nothing to Summarize",
        "Nothing logged in this range.",
        "A record and a model, not medical advice. Exposure uses clinical equivalents where they're established, and the substance's typical dose otherwise.",
        "Days used",
        "How often, across this range",
        "of %lld days",
        "of days",
        "longest break",
        "since last",
        "Cumulative exposure",
        "Total taken this range, in each substance's clinical or common-dose unit",
        "Benzodiazepines ≈ %@ mg diazepam-eq/day",
        "Opioids: peak day ≈ %@ MME",
        "below the CDC 50 MME/day reference",
        "at or above the CDC 50 MME/day reference",
        "at or above the CDC 90 MME/day reference",
        "Average %@ MME/day over the range",
        "%@: %@ %@ total",
        "Dose trend",
        "Whether your typical dose has moved over this range",
        "steady",
        "rising",
        "falling",
        "%@: dose %@, %@",
        "Active together",
        "Hours two substances were both in your body at once",
        "%@ and %@: %@ active together",
        "MME",
        "mg diazepam-eq",
        "common doses",
        "In your body over time",
        "Estimated amount still circulating, each line a share of its own peak",
        "How much of each substance has been circulating, day by day",
        "Log some doses to see what's been in your body over time.",
        "Nothing to Model",
        "None of your logged substances in this range have a modeled elimination curve.",
        "An estimate from a one-compartment model, not a measurement. How much is in your body doesn't always match how strong the effects feel, or how long a substance stays detectable.",
        "Nothing in your body at this time",
        "Tolerance & Receptors",
        "Your streak and this month's rate",
        "When and how much you log",
        "Predicted per-mechanism tolerance",
        "What's still active in your body right now",
        "How body-load has moved over time",
        "Receptor load over time",
        "Receptor Load",
        "How hard each mechanism has been driven, relative to your recent baseline",
        "How hard each mechanism has been driven over time",
        "Log some doses to see how your receptors have been driven.",
        "None of your logged substances in this range drive a modeled mechanism.",
        "A predicted relative load from your logged doses, not a measurement. It's a model of receptor drive, not of how you feel.",
        "Nothing driven at this time",
        "Toggles this mechanism's line",
        "Steady state",
        "Where a regular dose settles, from your own cadence",
        "No Steady Cadence Yet",
        "Steady state needs a regular schedule. Log a substance on a consistent cadence and its plateau appears here.",
        "A projection from your median dose and spacing, assuming you keep that cadence and linear kinetics. Body content in the dose's units, not a plasma level.",
        "Plateau",
        "Buildup",
        "Reaches",
        "Between doses",
        "about daily",
        "about every 2 days",
        "<1 day",
        "clears, no buildup",
        "every ~%lld h",
        "every ~%@ days",
        "Accumulation curve for %@",
        "Plateaus around %@, %@× one dose, reached in %@",
        "Clears between doses; each peaks around %@",
        "%@ now at %@ %@",
        "%@ now at %@",
        # Usage toolbar filter + substance sheet (CLI-added; not yet extracted).
        "All Substances",
        "Substances (%lld)",
        "Select All",
        "Deselect All",
        # Custom units (CLI-added; Xcode hasn't extracted them yet).
        "Custom Units",
        "No Custom Units",
        "Add Custom Unit",
        "Edit Custom Unit",
        "unit",
        "1 %@ =",
        "Unit label (e.g. capsule)",
        'This substance already has a "%@" unit.',
        "Logs in this unit convert to the mass automatically.",
        'Define a unit like "1 capsule = 30 mg" and it appears in the dose picker for that substance — log half a capsule, get 15 mg.',
        # Approximate-dose flag (CLI-added; Xcode hasn't extracted them yet).
        "Approximate amount",
        "Shows the dose with a ~; the estimate still drives the curves.",
        "approximately %@ %@",
        # Label scanner strings (CLI-added; Xcode hasn't extracted them yet).
        "Scan a label",
        "Close scanner",
        "Point at the medication name or its barcode",
        "Point at a barcode or label, then tap a highlighted area",
        "Resolving…",
        "Add to Log",
        "Scan Again",
        "No match",
        "Point the camera at the printed drug name.",
        "Camera Access Needed",
        "Scanning Unavailable",
        "Enable camera access in Settings to scan medication labels.",
        "Label scanning isn't available on this device.",
        # The 2026-08-04 sweep's two strings the extractor didn't pick up.
        "Estimates from primary literature.",
        "Suppresses the enzyme that makes serotonin, so recovery takes weeks.",
        "%@ acts through %@ — the pharmacology below is %@'s.",
        "Off-Target Effects",
        "Significant",
        "Limited",
        "Minor",
        "Clinically significant",
        "Real but bounded",
        "Not clinically dominant",
        "How Long It Stays",
        "Elimination half-life — not how long you feel it.",
        "Metabolite of the above",
        "Drug Class",
        "The rest of the family",
        "Selective serotonin reuptake inhibitor",
        "Serotonin–noradrenaline reuptake inhibitor",
        "Noradrenaline–dopamine reuptake inhibitor",
        "Tricyclic antidepressant",
        "Monoamine oxidase inhibitor",
        "Serotonin antagonist and reuptake inhibitor",
        "Noradrenergic and specific serotonergic antidepressant",
        "Blocks the serotonin transporter and little else, which is why its effects and its side effects are both mostly serotonergic.",
        "Blocks serotonin and noradrenaline reuptake together. The noradrenaline share grows with dose, so a low dose can behave much like an SSRI.",
        "Blocks noradrenaline and dopamine reuptake, leaving serotonin alone — the activating end of the family.",
        "Blocks serotonin and noradrenaline reuptake like an SNRI, and also histamine, muscarinic and α₁ receptors. That extra binding is the sedation, the dry mouth, and the narrow margin in overdose.",
        "Blocks the enzyme that breaks monoamines down, rather than the transporters that recycle them, so all three rise. The tyramine restriction and the long interaction list both follow from that.",
        "Blocks 5-HT₂A while weakly inhibiting serotonin reuptake. The receptor block dominates at low doses, which is why trazodone reached far more people as a sleep drug than as an antidepressant.",
        "Raises noradrenaline and serotonin release by blocking the α₂ autoreceptors that normally brake it, instead of blocking reuptake. The H₁ block alongside it is the sedation and the appetite.",
        "Log this",
        "Prescribing",
        "Approved uses",
        "Boxed warning",
        "Fewer",
        "Dose sources",
        "In use",
        "About metabolites",
        "Compare all %lld sources",
        "%@ · %lld sources",
        "Piru shows the source you rank highest — change that in Settings › Source Priority.",
        "Buccal",
        "More actions",
        "Computed from the molecular structure (PubChem, NPS-DataHub) rather than measured in a lab.",
        "Recreational doses — not a prescribed amount",
        "%lld studies",
        "No effect timeline for this substance and route.",
        "%@ stays active in your body long after %@ itself is gone.",
        "About %@× %@'s activity at the %@.",
        "About %@× %@'s activity, by one measurement.",
        "About %@× as strong as %@, dose for dose.",
        "About as strong as %@ at the %@.",
        "Also measured at %@× %@'s %@ at the %@ — a lab measurement, not clinical potency.",
        "Also measured at %@× %@'s %@ — a lab measurement, not clinical potency.",
        "Effects can outlast the duration above — %@ clears much more slowly than %@.",
        "Measured at %@× %@'s %@ at the %@ — a lab measurement, not clinical potency.",
        "Measured at %@× %@'s %@ — a lab measurement, not clinical potency.",
        "Molecule for molecule, %@ is about %@× as strong as %@ — but how much of a dose converts isn't recorded here.",
        "Molecule for molecule, %@ is about %@× as strong as %@ — but only about %@%% of a dose becomes it.",
        "Molecule for molecule, %@ is about as strong as %@.",
        "Molecule for molecule, about %@× as strong as %@.",
        "What your body makes from this dose. Not a measured level.",
        "Your body turns %@ into %@, which is active too.",
        "Also Active",
        "Made by",
        "Share of dose",
        "Effects can outlast the duration above — %1$@ clears much more slowly than %2$@.",
        "About as strong as %@, dose for dose.",
        "About %1$@× as strong as %2$@, dose for dose.",
        "%1$@ stays active in your body long after %2$@ itself is gone.",
        "Molecule for molecule, %1$@ is about %2$@× as strong as %3$@ — but how much of a dose converts isn't recorded here.",
        "Molecule for molecule, %1$@ is about %2$@× as strong as %3$@ — but only about %4$@% of a dose becomes it.",
        "Molecule for molecule, %1$@ is about as strong as %2$@.",
        "Molecule for molecule, about %1$@× as strong as %2$@.",
        "How much of this you make is partly genetic — the same dose produces noticeably more in some people than others.",
        "About as strong as %1$@ at the %2$@.",
        "About %1$@× %2$@'s activity at the %3$@.",
        "About %1$@× %2$@'s activity, by one measurement.",
        "Acts differently from %@ — not simply stronger or weaker.",
        "Your body turns %1$@ into %2$@, which is active too.",
        "A binding-affinity measurement, not clinical potency.",
        "A lab measurement, not clinical potency.",
        "How strong it is compared to %@ hasn't been established.",
        "binding affinity",
        "activity",
        "Measured at %1$@× %2$@'s %3$@ — a lab measurement, not clinical potency.",
        "Also measured at %1$@× %2$@'s %3$@ — a lab measurement, not clinical potency.",
        "Measured at %1$@× %2$@'s %3$@ at the %4$@ — a lab measurement, not clinical potency.",
        "Also measured at %1$@× %2$@'s %3$@ at the %4$@ — a lab measurement, not clinical potency.",
        "Opens this substance in the library.",
        "%@ days",
        "µ-opioid receptor",
        "\u03ba-opioid receptor",
        "\u03b4-opioid receptor",
        "serotonin transporter",
        "norepinephrine transporter",
        "dopamine transporter",
        "GABA-A receptor",
        "NMDA receptor",
        "nicotinic receptor",
        "The file is missing a required field: %@.",
        "The file has an empty value for a required field: %@.",
        "The file isn't valid JSON.",
        "The file has an unexpected value at: %@.",
        "Active Now",
        "Pick a substance and an amount to see how it may feel over time.",
        "Plan A",
        "Plan B",
        "Move to",
        "Compare with another plan",
        "Dose options",
        "Opens full size",
        "Calibrated",
        "Modeled alongside",
        "The model was calibrated on these. Each one can be modeled on its own.",
        "The engine can simulate these as part of a plan, but they need a calibrated substance in the same plan to anchor the curve.",
        "Add a Dose",
        "Clear All",
        "At start",
        "%lld min later",
        "%lld h later",
        "%lld h %lld m later",
        "All four lenses",
        "Choose a different substance",
        "A second plan is drawn as its own curve, so you can hold two ideas side by side — two meds, or a split dose against a single one.",
        "Nothing here can anchor a curve. Add a calibrated substance — amphetamine, methylphenidate, mephedrone, 3-MMC, or 2-MMC.",
        "How this is estimated",
        "Measured pharmacokinetics",
        "What the engine uses",
        "Binding used",
        "Weakest input",
        "Model anchor dose",
        "Elimination rate (ke)",
        "Absorption rate (ka)",
        "Transporter weights",
        "Releaser",
        "Half-life (t½)",
        "Time to peak (Tmax)",
        "Bioavailability (F)",
        "Distribution (Vd)",
        "Reference dose",
        "Species",
        "µ-opioid drive",
        "GABA-A drive",
        "No resolved pharmacology for this substance.",
        "What the simulation is actually computing, and why rate matters more than amount.",
        "Every curve starts as a number you typed and ends as a line on a chart. These are the steps in between.",
        "From dose to concentration",
        "Your dose is first expressed as a multiple of that substance's reference dose — the amount the model was tuned around. It then moves through a three-stage absorption chain into a central compartment that clears by first-order elimination, using an absorption rate (ka) and an elimination rate (ke) derived from the measured half-life and time to peak.",
        "Route changes how steeply the curve rises, and whether the drug redistributes into a peripheral compartment — not how high it peaks. An insufflated and an oral dose of the same size reach the same peak here. What differs is the slope, and the later stages are sensitive to slope.",
        "From concentration to target engagement",
        "Concentration becomes fractional occupancy of the dopamine, noradrenaline and serotonin transporters. The dopamine transporter gets a time-resolved binding equation — separate association and dissociation rates rather than instant equilibrium — so a drug that lets go slowly holds its occupancy plateau after concentration has begun to fall.",
        "The DAT:NET:SERT potency ratios are taken from one published assay, chosen by coverage and confidence, never mixed across labs. Only ratios measured in the same experiment are physically comparable.",
        "Everything present draws on one shared pool of free transporters, so a second substance finds fewer sites open. This is the point where combinations stop being additive.",
        "Releasers and reuptake blockers diverge",
        "A releaser's output is limited by the vesicular dopamine still in store, and is suppressed further if a reuptake blocker is also on board. A blocker is not store-limited — it raises dopamine by slowing clearance rather than by pushing transmitter out. The two are handled by different code paths, not by one shared knob.",
        "What you feel is a gap, not a level",
        "Two internal compensation signals chase the drug-driven dopamine elevation: a fast one that settles within minutes (autoreceptor feedback, transporter trafficking) and a slow one over hours (synthesis regulation). The felt effect is modeled as the distance between dopamine and those expectations — never the dopamine level itself.",
        "The fast gap is the rush. Because the fast signal catches up within minutes, that gap is effectively proportional to how quickly dopamine rose. The slow gap is the high while it stays positive; once the slow expectation overshoots the falling dopamine, the same term turns into part of the comedown.",
        "Reward is gated by rate",
        "Reward is multiplied by a gate that integrates how fast dopamine is rising. A substance can occupy the transporter fully and still register almost no reward if it arrived slowly — the same pharmacology reading as therapeutic or as euphoric depending on speed alone.",
        "Depletion, and where the comedown comes from",
        "Releasers spend vesicular stores in proportion to concentration, and dopamine elevation itself throttles resynthesis — so the debt deepens while the drug is still on board rather than being repaid in real time.",
        "Past a threshold that debt switches on a comedown term, which then recovers with accelerating synthesis over hours. Serotonin activity cushions it. That is why an amphetamine crash and a cathinone's calmer return separate so sharply in these curves.",
        "The comedown here is over-compensation plus a depletion debt — not dopamine falling below baseline.",
        "The four readouts",
        "Feeling sums reward, serotonin and opioid warmth, and liking, minus the comedown.",
        "Energy is a noradrenaline-led inverted U set against its own adaptation, minus sedative load. Past a point, more noradrenergic drive lowers functional energy instead of adding to it.",
        "Compulsion sums a slowly-decaying incentive envelope that charges from the rate of rise, and the gap between the rush you remember and the rush you are getting now.",
        "Strain sums a noradrenergic cardiovascular term drawing on a depletable vasoconstriction pool, plus an opioid respiratory term. It deliberately follows concentration rather than the felt gap, so it stays elevated after the effect itself has faded.",
        "How it is solved",
        "All of it is a set of coupled differential equations advanced by forward Euler in half-minute steps across twelve hours or more.",
        "Every substance shares one set of neural constants. Only the store-depletion susceptibility is fitted per substance, anchored to the observed contrast between an amphetamine crash and a crashless cathinone.",
        "Step by step",
        "No tolerance between sessions. Every simulation starts from a naive baseline; acclimation within the session is modeled, carry-over from yesterday is not.",
        "No body weight, bioavailability or volume of distribution. Concentration here is dimensionless and relative to a reference dose, not a measured blood level.",
        "No genetics, no metabolizer phenotype, and no drug–drug metabolic interaction. Interactions are pharmacodynamic only: shared transporters, shared stores, shared receptors.",
        "No individual variability. The same inputs always give the same curve, and no confidence band is drawn around it.",
        "Psychedelics, dissociatives and cannabinoids are out of scope — pharmacokinetics is not what drives their effects.",
        "What this does not model",
        "The idea first, then every stage from your dose to the line on the chart.",
        "The calculation, step by step",
        # CYP2D6 pharmacogenomic notes (§F.2, 2026-08-06).
        "CYP2D6: %@",
        "Reduced conversion to active metabolite — you may get less effect from %@.",
        "Mildly reduced conversion to active metabolite — effect may be modestly lower.",
        "Faster conversion to active metabolite — higher active metabolite exposure. For codeine, this is an FDA contraindication due to the risk of respiratory depression.",
        "Slower CYP2D6 clearance — %@ may last longer and accumulate at repeated doses.",
        "Mildly slower CYP2D6 clearance — duration may be modestly longer.",
        "Faster CYP2D6 clearance — shorter duration. Be aware of re-dose timing.",
        "CYP2D6 is a major metabolic pathway for %@.",
        # Isomer picker racemic-parent label (CLI-added).
        "Regular",
        "Racemic",
        # QuickLog "Form" pill accessibility label (CLI-added).
        "Formulation",
        # QuickLog brand picker (CLI-added).
        "Extended-release",
        "More…",
        # Usage insights: common-dose ranking + trends metric (CLI-added).
        "Ranked by how often, or by total common-dose units",
        "Common doses",
        "Entries/wk",
        "Common doses/wk",
        "No common dose defined for these substances",
        "No common dose defined",
        "Common-dose units count each dose as a multiple of its common dose. %lld of %lld substances have one.",
        "%@ common-dose units across %lld entries",
        "Common doses per week, 7-day rolling average",
        "Common doses per week, 4-week rolling average",
        "Entries/day",
        "Common doses/day",
        "Common doses per day",
        "Which weekdays you log on most",
        "Common-dose units by weekday",
        "Common-dose units by weekday, most on %@",
        "Which days and hours, by common-dose units",
        "%@ common-dose units",
        "%@ common-dose units, busiest around %@",
        "%@ rising to %@ per day",
        "%@ falling to %@ per day",
        "%@ steady at %@ per day",
        # Configurable dose-time presets (Settings › Journal › Quick Times).
        "Add Preset",
        "Quick Times",
        "Reset to Defaults",
        "That preset already exists.",
        "Choose at least one minute.",
        "Adds “%@”.",
        "These appear in the “When” menu when logging a dose, alongside Now and the full date picker. Swipe to remove, drag to reorder.",
        "%lld h",
        "Minutes",
        # Benzo effect ladder + occupancy / withdrawal (CLI-added; Xcode hasn't extracted them yet).
        "Faded",
        "Unchanged",
        "strong evidence",
        "moderate evidence",
        "low evidence",
        "not measured",
        "%lld%% left",
        "%lld percent left",
        "%lld days",
        "Muscle relaxation",
        "Coordination",
        "Fades near-completely in ~2 weeks",
        "The sleep effect tolerizes",
        "No decline detected",
        "Fades slowly and partially, over months",
        "Develops; rate not quantified",
        "No tolerance detected",
        "Receptor load",
        "About %lld%% of your recent peak GABA-A load right now, summed across everything active.",
        "Combined load across your active GABAergics, relative to your recent peak.",
        "Combined load across your active GABAergics, relative to your recent peak. Alcohol is included; it loads the receptor at a different site.",
        "GABA-A receptor load over time",
        "Combined load relative to your recent peak, currently about %lld percent, clearing over the following days.",
        'Three things people call "withdrawal" that behave differently, and roughly when each starts for drugs like the ones you\'ve logged.',
        "A model of your dose log, not medical advice. Stopping a benzodiazepine abruptly after regular use can cause seizures.",
        "Estimating how much is still in your system…",
        "Your modeled GABA-A load has essentially cleared — past the point where the drug itself is still leaving your system. The bands below say when symptoms tend to follow.",
        "under a day",
        "Your modeled GABA-A load is still about %lld%% of your recent peak — the drug is still clearing, so withdrawal hasn't started yet.",
        "Your modeled GABA-A load is still about %lld%% of your recent peak — the drug is still clearing, so withdrawal hasn't started. On your current clearance it drops into the onset range in about %@.",
        "Research findings, not medical advice. Benzodiazepine discontinuation can be medically dangerous.",
        "Effect-selective tolerance",
        "Some effects fade, others don't",
        "For most drugs every effect tolerizes together. Benzodiazepines are the exception: sedation fades almost completely in about two weeks, while the anxiety relief, memory impairment and loss of coordination barely change. That's why the benzodiazepine card shows an effect ladder instead of one bar.",
        "Why — the receptor comes in subtypes",
        "GABA-A is built from several α-subtypes that adapt at different rates. α1 carries sedation and desensitizes (it uncouples, then the receptors are pulled from the synapse); α5 is required for that sedative tolerance to develop at all; α2 and α3, which carry the anxiety relief, don't adapt. So the dose that no longer makes you sleepy impairs your memory and coordination exactly as much as it did on day one — which is how tolerance quietly drives the dose up.",
        "Benzodiazepine effect kinetics: Vinkers & Olivier 2012; Piot & Jovanovic 2026. These are directions from the literature, graded low — not fitted numbers.",
        "Why these effects differ",
        "Prediction",
        "Prediction from a model",
        # Steady State tool (CLI-added; Xcode hasn't extracted them yet).
        "On a fixed schedule, each dose lands on the tail of the last and the level climbs until intake and clearance balance — steady state.",
        "Values are body content in the dose's units, not a plasma concentration. Real accumulation varies with metabolism, dosing gaps, and metabolites.",
        "Uses the same one-compartment oral model, assuming a regular schedule and linear kinetics. Values are body content in the dose's units, not a plasma concentration. Real accumulation varies with metabolism, dosing gaps, and active metabolites.",
        "Steady State",
        "steady state",
        "Where a repeated dose settles, and when",
        "Where a med taken every day settles",
        "The Half-Life Calculator models one dose fading out. A dose repeated on a schedule instead lands on the tail of the last, and the level climbs until intake and clearance balance — steady state.",
        "Dose each time",
        "Taken every",
        "Every 4 hours",
        "Every 6 hours",
        "Every 8 hours",
        "Every 12 hours",
        "Once daily",
        "Twice daily",
        "Barely accumulates",
        "Accumulates modestly",
        "Accumulates substantially",
        "Each dose has mostly cleared before the next, so the level tracks a single dose.",
        "The level settles around %@ a single dose, reaching steady state in about %@.",
        "Doses stack faster than they clear — the level climbs to roughly %@ a single dose and takes about %@ to get there.",
        "Level over time — climbing to plateau",
        "Estimated amount in your body, in %@. The shaded band is the steady-state range once the level stops climbing; the dashed line is a single dose.",
        "At steady state",
        "Steady state by",
        "fully settled in %@",
        "Accumulation",
        "at the peak, vs. one dose",
        "Plateau range",
        "%@ · trough to peak",
        "Fluctuation",
        "smooth",
        "moderate swing",
        "spiky",
        "Time to steady state depends only on the half-life — not the dose or how often you take it. A bigger dose or shorter gap raises the plateau; it doesn't arrive sooner.",
        "This projects a perfectly regular schedule onto the same one-compartment oral model the Half-Life Calculator uses, assuming dose-proportional (linear) kinetics. Amounts are body content in the dose's units — not a plasma concentration, which would need an individual volume of distribution. Real accumulation varies with metabolism, missed or extra doses, active metabolites, and saturable elimination. A model of the pharmacology, not a dosing plan — it says what a level does, never what a dose should be. Not medical advice.",
        "%@ peak",
        "%@ trough",
        "days",
        "Climbs from one dose to a steady-state range of %@ to %@ %@, reached in about %lld days",
        "Taking this daily? See where the level settles",
        "Where a med taken on a schedule settles",
        "Half-life data not available for %@.",
        # Bupropion enzyme modulator (A1)
        "Bupropion",
        "Bupropion's reductive metabolites strongly inhibit CYP2D6, raising the levels of drugs cleared by it. For prodrugs activated by CYP2D6 (tramadol, codeine), it blocks the activation pathway instead.",
        # b45 feedback — metabolizer variation chart (C1)
        "Fast metabolizer",
        "Slow metabolizer",
        "Genetic variation in %@ formation",
        "Same dose, different conversion — the effect varies by genotype.",
        # b45 feedback — insight group previews (D6)
        "substance modeled",
        "substances modeled",
        "Add regular meds to project steady state",
        "regular med",
        "regular meds",
        # b45 feedback — receptor load zoom (E2)
        "Wide",
        "Medium",
        "Close",
        "Zoom",
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
    WIDGET_NEW_KEYS: set[str] = set()
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

    print()
    print("--- Live Activity catalog ---")
    # The Live Activity target has its own catalog and, like the widget, reuses
    # Shared strings. It went unhandled until 2026-08-03, when the heavy-tier
    # threshold band put target-specific strings there and they came back
    # untranslated: the export/import round-trip cross-fills from project-wide
    # translations, but only for keys Xcode already resolves elsewhere, so a
    # string that lives *only* in this catalog was never reached. Same empty
    # insert set as the widget — the keys are extracted by the build; this pass
    # only fills them.
    ACTIVITY_NEW_KEYS: set[str] = set()
    n, added, missing = apply_translations(
        project_root / "PiruLiveActivityExtension/Localizable.xcstrings",
        {**T, **WT},
        insert_keys=ACTIVITY_NEW_KEYS,
    )
    print(f"Translated: {n}  (inserted {len(added)} new key(s))")
    for a in added:
        print(f"  + {a!r}")
    print(f"Missing: {len(missing)}")
    for m in missing:
        print(f"  - {m!r}")

    # Hand all three catalogs back to Xcode so it re-collates every key into its
    # canonical order — this is what stops the IDE from churning the file on the
    # next build. Done last, after all translations are filled, so the export
    # captures the freshly-inserted keys. Skipped gracefully if xcodebuild is
    # unavailable (the Python serialization above is still valid, just unsorted).
    print()
    print("--- Canonicalizing key order via Xcode (export/import round-trip) ---")
    if canonicalize_catalogs(project_root / "Piru.xcodeproj"):
        print("Done — catalogs rewritten in Xcode's canonical order.")
