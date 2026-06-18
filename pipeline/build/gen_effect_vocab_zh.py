"""Generate / verify ``effect_vocab_zh.json`` — the curated zh label crosswalk.

Offline tool (NOT part of the build): holds the authoritative, hand-reviewed
zh-Hans label for every controlled-vocabulary effect, converts each to zh-Hant
with OpenCC, and emits the JSON the build reads. The build itself needs no
dependencies — it just reads the committed JSON.

Why hand-authored, not derived: the FreeODwiki ``药效`` corpus IS the same PW
taxonomy in Chinese, but extracting the en→zh mapping from co-occurrence is
unreliable — effects co-occur so densely that a rare effect's most-frequent
zh neighbour is just the globally-common term (``itchiness``→``镇静`` etc.). Only
*mutual-best-match* (each is the other's top partner) is trustworthy; that yields
~76 solid anchors. So ``ZH_HANS`` below is authored against PsychonautWiki's
Chinese SEI conventions, with those 76 native anchors used verbatim and as an
automated regression gate (``--verify`` flags any authored value that disagrees
with the native mutual-best alignment).

zh-Hant = OpenCC ``s2twp`` (Simplified → Traditional, Taiwan, phrase-aware) of the
zh-Hans label. Deterministic; flagged ``machine_translated=1`` in the build.

Usage:
  python3 pipeline/build/gen_effect_vocab_zh.py            # dry run + coverage
  python3 pipeline/build/gen_effect_vocab_zh.py --verify   # check vs native anchors
  python3 pipeline/build/gen_effect_vocab_zh.py --write     # write the JSON
"""

from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from effect_vocab import EFFECT_VOCAB, vocab_id_for  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
FREEOD = REPO / "data/sources/freeodwiki.json"
OUT = Path(__file__).resolve().parent / "effect_vocab_zh.json"

# Authoritative zh-Hans for every vocab_id. Authored against PsychonautWiki's
# Chinese SEI; the 76 native mutual-best anchors (see --verify) are used verbatim.
ZH_HANS: dict[str, str] = {
    # --- Physical ---
    "increased_heart_rate": "心率增快",
    "decreased_heart_rate": "心率减慢",
    "abnormal_heartbeat": "心律异常",
    "increased_blood_pressure": "血压升高",
    "decreased_blood_pressure": "血压降低",
    "blood_pressure_elevation": "血压上升",
    "vasoconstriction": "血管收缩",
    "vasodilation": "血管扩张",
    "cerebral_vasodilation": "脑血管扩张",
    "pupil_dilation": "瞳孔扩大",
    "pupil_constriction": "瞳孔缩小",
    "watery_eyes": "流泪",
    "photophobia": "畏光",
    "nausea": "恶心",
    "nausea_suppression": "恶心抑制",
    "vomiting": "呕吐",
    "constipation": "便秘",
    "diarrhea": "腹泻",
    "stomach_bloating": "腹胀",
    "stomach_cramps": "胃痉挛",
    "stomach_pain": "胃痛",
    "increased_salivation": "唾液分泌增多",
    "salivation": "流涎",
    "dry_mouth": "口干",
    "increased_appetite": "食欲增加",
    "appetite_enhancement": "食欲增强",
    "appetite_suppression": "食欲抑制",
    "decreased_appetite": "食欲减退",
    "dehydration": "脱水",
    "increased_thirst": "口渴增加",
    "respiratory_depression": "呼吸抑制",
    "bronchodilation": "支气管扩张",
    "bronchoconstriction": "支气管收缩",
    "cough_suppression": "咳嗽抑制",
    "runny_nose": "流鼻涕",
    "nasal_congestion": "鼻塞",
    "excessive_yawning": "过度打哈欠",
    "difficulty_breathing": "呼吸困难",
    "sedation": "镇静",
    "stimulation": "兴奋",
    "wakefulness": "清醒",
    "physical_fatigue": "躯体疲劳",
    "physical_euphoria": "躯体欣快感",
    "physical_dysphoria": "躯体不快",
    "stamina_enhancement": "耐力增强",
    "rejuvenation": "返老还童感",
    "restless_leg_syndrome": "不宁腿综合征",
    "muscle_relaxation": "肌肉松弛",
    "muscle_contractions": "肌肉收缩",
    "muscle_cramps": "肌肉痉挛",
    "muscle_spasms": "肌肉抽搐",
    "muscle_tension": "肌肉紧张",
    "muscle_twitching": "肌肉颤动",
    "motor_control_loss": "运动控制丧失",
    "difficulty_urinating": "排尿困难",
    "frequent_urination": "尿频",
    "increased_bodily_temperature": "体温升高",
    "decreased_bodily_temperature": "体温降低",
    "temperature_regulation_suppression": "体温调节抑制",
    "increased_perspiration": "出汗增加",
    "decreased_perspiration": "出汗减少",
    "skin_flushing": "皮肤潮红",
    "itchiness": "瘙痒",
    "skin_tingling": "皮肤刺痛感",
    "goosebumps": "起鸡皮疙瘩",
    "body_odor_alteration": "体味改变",
    "increased_libido": "性欲增强",
    "decreased_libido": "性欲减退",
    "temporary_erectile_dysfunction": "暂时性勃起功能障碍",
    "orgasm_enhancement": "性高潮增强",
    "orgasm_suppression": "性高潮抑制",
    "spontaneous_orgasm": "自发性高潮",
    "headaches": "头痛",
    "dizziness": "头晕",
    "seizure": "癫痫发作",
    "seizure_suppression": "癫痫抑制",
    "pain_relief": "镇痛",
    "analgesia": "痛觉缺失",
    "increased_pain_perception": "痛觉增强",
    "teeth_grinding": "磨牙",
    "mouth_numbing": "口腔麻木",
    "sublingual_numbing": "舌下麻木",
    "inner_ear_pressure": "内耳压迫感",
    "bodily_pressures": "躯体压迫感",
    "bodily_vibrations": "躯体振动感",
    "bodily_heaviness": "躯体沉重感",
    "bodily_lightness": "躯体轻盈感",
    "perception_of_decreased_weight": "体重减轻感",
    "perception_of_increased_weight": "体重增加感",
    "difficulty_swallowing": "吞咽困难",
    # --- Cognitive ---
    "anxiety": "焦虑",
    "anxiety_suppression": "焦虑抑制",
    "cognitive_euphoria": "认知欣快",
    "cognitive_dysphoria": "认知不快",
    "depression": "抑郁",
    "emotion_enhancement": "情感增强",
    "emotion_suppression": "情感抑制",
    "empathy_love_and_sociability_enhancement": "共情、爱与社交能力增强",
    "empathy_love_and_sociability_suppression": "共情、爱与社交能力抑制",
    "irritability": "易怒",
    "mania": "躁狂",
    "paranoia": "偏执",
    "panic_attacks": "惊恐发作",
    "simultaneous_emotions": "情绪并存",
    "laughter": "大笑",
    "existential_self_realization": "存在主义自我实现",
    "analysis_enhancement": "分析能力增强",
    "analysis_suppression": "分析能力抑制",
    "conceptual_thinking": "概念性思维",
    "thought_acceleration": "思维加速",
    "thought_deceleration": "思维减速",
    "thought_connectivity": "思维连通性",
    "thought_disorganization": "思维混乱",
    "thought_organization": "思维组织",
    "thought_loops": "思维循环",
    "thought_suppression": "思维抑制",
    "multiple_thought_streams": "多重思维流",
    "cognitive_fatigue": "认知疲劳",
    "information_processing_acceleration": "信息处理加速",
    "information_processing_suppression": "信息处理抑制",
    "language_suppression": "语言能力抑制",
    "memory_enhancement": "记忆增强",
    "memory_suppression": "记忆抑制",
    "amnesia": "失忆",
    "d_j_vu": "既视感",
    "jamais_vu": "未视感",
    "creativity_enhancement": "创造力增强",
    "creativity_suppression": "创造力抑制",
    "novelty_enhancement": "新奇感增强",
    "pattern_recognition_enhancement": "模式识别增强",
    "pattern_recognition_suppression": "模式识别抑制",
    "suggestibility_enhancement": "暗示性增强",
    "suggestibility_suppression": "暗示性抑制",
    "personal_bias_suppression": "个人偏见抑制",
    "personal_meaning_enhancement": "个人意义感增强",
    "subconscious_communication": "潜意识交流",
    "mindfulness": "正念",
    "focus_enhancement": "专注力增强",
    "focus_suppression": "专注力抑制",
    "motivation_enhancement": "动机增强",
    "motivation_suppression": "动机抑制",
    "immersion_enhancement": "沉浸感增强",
    "compulsive_redosing": "强迫性补量",
    "disinhibition": "去抑制",
    "increased_music_appreciation": "音乐欣赏能力增强",
    "increased_sense_of_humor": "幽默感增强",
    "ego_inflation": "自我膨胀",
    "ego_replacement": "自我替换",
    "personality_regression": "人格退行",
    "catharsis": "宣泄",
    "identity_alteration": "身份改变",
    "perception_of_self_design": "自我设计感知",
    "feelings_of_self_design": "自我设计感",
    "time_distortion": "时间扭曲",
    "dream_potentiation": "梦境强化",
    "dream_suppression": "梦境抑制",
    "sleep_paralysis": "睡眠瘫痪",
    "delusions": "妄想",
    "delusion": "妄想",
    "psychosis": "精神病发作",
    "confusion": "困惑",
    "perspective_alterations": "视角改变",
    "perspective_distortions": "视角扭曲",
    "memory_replays": "记忆回放",
    "spatial_disorientation": "空间定向障碍",
    # --- Visual ---
    "colour_enhancement": "颜色增强",
    "visual_acuity_enhancement": "视觉锐度增强",
    "acuity_enhancement": "锐度增强",
    "acuity_suppression": "锐度抑制",
    "magnification": "放大",
    "brightness_alteration": "亮度改变",
    "frame_rate_enhancement": "帧率增强",
    "frame_rate_suppression": "帧率抑制",
    "colour_shifting": "颜色偏移",
    "colour_replacement": "颜色替换",
    "colour_tinting": "颜色染色",
    "depth_perception_distortions": "深度感知扭曲",
    "diffraction": "衍射",
    "drifting": "漂移",
    "after_images": "残影",
    "tracers": "拖影",
    "visual_haze": "视觉迷雾",
    "visual_sliding": "视觉滑动",
    "vibrating_vision": "视物振动",
    "double_vision": "复视",
    "recursion": "递归",
    "scenery_slicing": "景物切片",
    "symmetrical_texture_repetition": "对称纹理重复",
    "environmental_cubism": "环境立体主义",
    "environmental_orbism": "环境球体化",
    "peripheral_information_misinterpretation": "周边信息误判",
    "visual_stretching": "视觉拉伸",
    "visual_flipping": "视觉翻转",
    "geometry": "几何",
    "internal_hallucinations": "内部幻觉",
    "external_hallucinations": "外部幻觉",
    "hallucinations": "幻觉",
    "transformations": "变形",
    "autonomous_entities": "自主实体",
    "settings_sceneries_and_landscapes": "场景、景物与风景",
    "scenarios_and_plots": "情景与剧情",
    "machinescapes": "机械景观",
    "shadow_people": "影子人",
    "unspeakable_horrors": "难以名状的恐怖",
    "object_alteration": "物体改变",
    "object_activation": "物体活化",
    "object_multiplication": "物体增殖",
    "texture_liquidation": "纹理液化",
    "texture_repetition": "纹理重复",
    "aura_vision": "光环视觉",
    "exposure_to_inner_mechanics_of_consciousness": "意识内在机制的显现",
    "exposure_to_semantic_concept_network": "语义概念网络的显现",
    # --- Auditory ---
    "auditory_enhancement": "听觉增强",
    "auditory_suppression": "听觉抑制",
    "auditory_distortion": "听觉扭曲",
    "auditory_hallucinations": "听觉幻觉",
    "auditory_misinterpretation": "听觉误判",
    # --- Tactile ---
    "tactile_enhancement": "触觉增强",
    "tactile_suppression": "触觉抑制",
    "tactile_hallucinations": "触觉幻觉",
    "spontaneous_tactile_sensations": "自发性触觉",
    "bodily_control_enhancement": "躯体控制增强",
    "physical_autonomy": "躯体自主性",
    "changes_in_felt_bodily_form": "躯体形态感知改变",
    "changes_in_gravity": "重力感改变",
    "gravity_perception_alteration": "重力感知改变",
    # --- Smell and taste ---
    "smell_enhancement": "嗅觉增强",
    "smell_suppression": "嗅觉抑制",
    "smell_hallucination": "嗅觉幻觉",
    "olfactory_hallucination": "嗅幻觉",
    "taste_enhancement": "味觉增强",
    "taste_suppression": "味觉抑制",
    "gustatory_hallucination": "味幻觉",
    "gustatory_enhancement": "味觉增强",
    "gustatory_suppression": "味觉抑制",
    # --- Multisensory ---
    "synaesthesia": "联觉",
    "synesthesia": "联觉",
    "multisensory_enhancement": "多感官增强",
    # --- Sensory ---
    "sensory_enhancement": "感官增强",
    "sensory_suppression": "感官抑制",
    "stimulation_suppression": "刺激抑制",
    "enhancement_and_suppression_cycles": "增强与抑制循环",
    # --- Transpersonal ---
    "spirituality_enhancement": "灵性增强",
    "unity_and_interconnectedness": "合一与互联感",
    "existential_realization": "存在主义领悟",
    "feelings_of_eternalism": "永恒主义感",
    "feelings_of_impending_doom": "末日临近感",
    "feelings_of_predeterminism": "宿命论感",
    "feelings_of_interdependent_opposites": "对立互依感",
    "perception_of_eternalism": "永恒主义感知",
    "perception_of_interdependent_opposites": "对立互依感知",
    "perception_of_predeterminism": "宿命论感知",
    # --- Disconnective ---
    "derealization": "现实感丧失",
    "depersonalization": "人格解体",
    "consciousness_disconnection": "意识断离",
    "ego_death": "自我死亡",
    "ego_dissolution": "自我消融",
    "visual_disconnection": "视觉断离",
    "auditory_disconnection": "听觉断离",
    "tactile_disconnection": "触觉断离",
    "cognitive_disconnection": "认知断离",
    "sensory_disconnection": "感官断离",
    "spatial_disconnection": "空间断离",
}


def native_anchors() -> dict[str, tuple[str, int, int]]:
    """vocab_id -> (zh, co_count, vid_count) via mutual-best-match (trustworthy)."""
    recs = json.loads(FREEOD.read_text(encoding="utf-8"))
    co: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    zco: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    vc: collections.Counter = collections.Counter()
    for r in recs:
        zh = {z.strip() for z in (r.get("subjective_effects") or []) if z.strip()}
        en = {e.strip() for e in (r.get("subjective_effects_en") or []) if e.strip()}
        if not (zh and en):
            continue
        vids = {vid for e in en if (vid := vocab_id_for(e))}
        for vid in vids:
            vc[vid] += 1
            for z in zh:
                co[vid][z] += 1
                zco[z][vid] += 1

    # Deterministic top pick: highest count, ties broken by label/id sort —
    # independent of PYTHONHASHSEED (set iteration order would otherwise flip
    # ties run-to-run and make the --verify gate non-reproducible).
    def best(cnt: collections.Counter) -> tuple[str, int]:
        key, c = max(cnt.items(), key=lambda kv: (kv[1], kv[0]))
        return key, c

    out: dict[str, tuple[str, int, int]] = {}
    for vid, cnt in co.items():
        z, c = best(cnt)
        if c < 2:
            continue
        if best(zco[z])[0] == vid and c / vc[vid] >= 0.5:
            out[vid] = (z, c, vc[vid])
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--verify", action="store_true")
    args = ap.parse_args()

    missing = [vid for vid in EFFECT_VOCAB if vid not in ZH_HANS]
    extra = [vid for vid in ZH_HANS if vid not in EFFECT_VOCAB]
    print(f"vocab entries: {len(EFFECT_VOCAB)}   zh-Hans authored: {len(ZH_HANS)}")
    if missing:
        print(f"MISSING zh-Hans ({len(missing)}):", missing)
    if extra:
        print(f"EXTRA (stale vocab_ids in ZH_HANS) ({len(extra)}):", extra)

    if args.verify:
        anchors = native_anchors()
        disagree = [
            (vid, ZH_HANS.get(vid), z, c, n)
            for vid, (z, c, n) in sorted(anchors.items())
            if ZH_HANS.get(vid) != z
        ]
        print(f"\nnative mutual-best anchors: {len(anchors)}")
        if disagree:
            print(f"DISAGREEMENTS vs authored ({len(disagree)}):")
            for vid, mine, z, c, n in disagree:
                print(f"  {vid}: authored={mine!r}  native={z!r}  ({c}/{n})")
        else:
            print("authored zh-Hans agrees with every native anchor ✓")

    if args.write:
        if missing:
            print("refusing to write: fill missing zh-Hans first", file=sys.stderr)
            return 1
        from opencc import OpenCC

        cc = OpenCC("s2twp")
        labels = {
            vid: {"zh-Hans": zh, "zh-Hant": cc.convert(zh)}
            for vid, zh in sorted(ZH_HANS.items())
            if vid in EFFECT_VOCAB
        }
        payload = {
            "_meta": {
                "source": "Hand-authored against PsychonautWiki zh SEI; 76 native "
                "FreeODwiki 药效 mutual-best anchors used verbatim. zh-Hant via OpenCC s2twp.",
                "machine_translated": {"zh-Hans": 0, "zh-Hant": 1},
            },
            "labels": labels,
        }
        OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"\nwrote {OUT}  ({len(labels)} vocab_ids)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
