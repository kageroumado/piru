#!/usr/bin/env python3
"""Apply zh-Hans and zh-Hant translations to a Localizable.xcstrings catalog."""

import json
import sys
from pathlib import Path

# Translations: English -> (Simplified, Traditional)
T = {
    # Session model — Journal grouping, detail, overrides, widget
    "Yesterday": ("昨天", "昨天"),
    "Medications": ("用药", "用藥"),
    "Session": ("本次记录", "本次記錄"),
    "No active session": ("暂无进行中的记录", "暫無進行中的記錄"),
    "No Sessions": ("暂无记录", "暫無記錄"),
    "Move to Session…": ("移至其他记录…", "移至其他記錄…"),
    "Move %@": ("移动 %@", "移動 %@"),
    "New Session": ("新建记录", "新建記錄"),
    "Pull this dose into its own session.": ("将这一剂单独归入新记录。", "將這一劑單獨歸入新記錄。"),
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
    # Common UI actions
    "Add": ("添加", "新增"),
    "Cancel": ("取消", "取消"),
    "Save": ("保存", "儲存"),
    "Delete": ("删除", "刪除"),
    "Edit": ("编辑", "編輯"),
    "OK": ("好", "好"),
    "Done": ("完成", "完成"),
    "Skip": ("跳过", "跳過"),
    "Rename": ("重命名", "重新命名"),
    "Change": ("更改", "變更"),
    "Copy": ("复制", "複製"),
    "Copied": ("已复制", "已複製"),
    "Reset Filters": ("重置筛选", "重設篩選"),
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
    "Drag to pan, pinch to zoom, hold to inspect": ("拖动平移，捏合缩放，长按查看", "拖曳平移，捏合縮放，長按查看"),
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
    "This calculator uses a one-compartment oral pharmacokinetic model with absorption and elimination phases. Absorption rates are estimated from known duration profiles (onset + comeup timing) when available, or use a default 4× elimination rate ratio. Population-average elimination half-lives are sourced from FDA-approved prescribing information, published pharmacokinetic studies (PubMed), DrugBank, and established pharmacology references (Goodman & Gilman's, Stahl's Essential Psychopharmacology). Half-lives for some research chemicals and novel substances are estimated from structurally similar compounds and may be less reliable.\n\nReal pharmacokinetics vary significantly based on individual metabolism, genetics, liver and kidney function, body composition, age, drug interactions, tolerance, and route of administration. Multi-compartment distribution, protein binding, active metabolites, and enterohepatic recirculation are not accounted for. Polydrug use may alter elimination rates unpredictably.\n\nThese figures are approximate population averages — not a substitute for clinical monitoring or professional medical advice. Always consult a qualified healthcare professional.": (
        "此计算器使用一房室口服药代动力学模型,包含吸收和消除两个阶段。如有已知的持续时间数据(起效 + 上升期),则吸收速率会由此估算;否则使用默认的 4× 消除速率比。群体平均消除半衰期来源于 FDA 批准的处方信息、已发表的药代动力学研究(PubMed)、DrugBank 以及成熟的药理学参考资料(《古德曼&吉尔曼治疗学的药理学基础》、《Stahl 精神药理学精要》)。部分研究化学品和新型物质的半衰期是根据结构类似的化合物估算的,可能不够可靠。\n\n实际药代动力学因个人代谢、遗传、肝肾功能、体成分、年龄、药物相互作用、耐受性和给药途径而显著不同。多房室分布、蛋白结合、活性代谢物和肠肝循环未被纳入考虑。多药联用可能不可预测地改变消除速率。\n\n这些数字是群体的近似平均值 — 不能替代临床监测或专业医疗建议。请始终咨询合格的医疗专业人员。",
        "此計算器使用一房室口服藥動學模型,包含吸收和消除兩個階段。如有已知的持續時間資料(起效 + 上升期),則吸收速率會由此估算;否則使用預設的 4× 消除速率比。族群平均消除半衰期來源於 FDA 批准的處方資訊、已發表的藥動學研究(PubMed)、DrugBank 以及成熟的藥理學參考資料(《古德曼&吉爾曼治療學的藥理學基礎》、《Stahl 精神藥理學精要》)。部分研究化學品和新型物質的半衰期是根據結構類似的化合物估算的,可能不夠可靠。\n\n實際藥動學因個人代謝、遺傳、肝腎功能、體成分、年齡、藥物相互作用、耐受性和給藥途徑而顯著不同。多房室分布、蛋白質結合、活性代謝物和腸肝循環未被納入考慮。多藥聯用可能不可預測地改變消除速率。\n\n這些數字是族群的近似平均值 — 不能替代臨床監測或專業醫療建議。請始終諮詢合格的醫療專業人員。",
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


sys.path.insert(0, "/tmp")
try:
    from moa_translations import MOA_DESCRIPTIONS, MOA_SUMMARIES

    T.update(MOA_SUMMARIES)
    T.update(MOA_DESCRIPTIONS)
except ImportError:
    pass

if __name__ == "__main__":
    project_root = Path("/Users/kirie/Developer/piru")

    # Brand-new strings added from the CLI that Xcode hasn't extracted into the
    # catalog yet. List them here so they get inserted; clear once Xcode has
    # picked them up on a real build (after which they're update-only).
    NEW_KEYS = {
        "Move to Session…", "Move %@", "New Session",
        "Pull this dose into its own session.", "Move To",
        "Nowhere to Move", "This is the only session.",
        "Move", "Set Time", "New time on %@",
        "%@ is logged on a different day. Pick a time within this session's day so the session stays a single day.",
        "Location", "Current Location", "Results", "Add Location", "Change Location",
        "Remove location", "Search for a place or address",
        "Location access is off. Turn it on in Settings to use your current location.",
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
        "Session", "No active session", "Current Session",
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
