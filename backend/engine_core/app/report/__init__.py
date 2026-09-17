# -*- coding: utf-8 -*-
"""M3 报告层：三层 × 13 模块（算法册 V2.3 §6-§7）。

build(result, reg, ...) 是唯一入口，输出即 contracts/openapi.yaml 的 Report 形状
（camelCase，与契约字段一一对应；M4 API 层直接下发，不再做第二次映射）。

呈现铁律（算法册 §6）：
  - 可观测的事实给死数字（次数、毫秒）；推断值给档位不给点值；
  - 阈值永不出现（门槛数字只留 TopicModule.threshold 供内测对账）；
  - 证据不足的模块整体不出现（displayable=false / 字段缺省）；
  - 差距翻译成行为语言，禁止「只能做 X」断言。

商业化口径（2026-09-11 拍板）：报告全部免费，无订阅切分模块。
"""

from __future__ import annotations

from datetime import datetime, timezone

from ..core import constants as C
from ..engine import promotion as pr
from ..engine.state import GameState
from ..measure import bayes, investment, radar, topics

BANDS = ((2, "很低"), (4, "偏低"), (6, "中等"), (8, "偏高"), (11, "很高"))
CONSISTENCY_NOTE = "你的这一面是有条件的：有人看着和没人看着，表现不一样。"


def _band(v: float | None) -> str:
    """0-10 分 → 五档词。推断值只给档位不给点值（呈现铁律）。"""
    if v is None:
        return "无数据"
    for hi, name in BANDS:
        if v < hi:
            return name
    return "很高"


def _ref(d) -> dict:
    """DecisionRecord → EvidenceRef（契约 camelCase）。"""
    return {
        "seq": d.seq, "month": d.month, "restMonth": d.rest_month,
        "nodeId": d.node_id, "optionId": d.option_id,
        "hesitationMs": d.hesitation_ms, "switchCount": d.switch_count,
        "snippet": (d.option_text or d.node_id)[:60],
    }


def _refs(decisions, limit: int = 3) -> list[dict]:
    out = []
    for d in list(decisions)[:limit]:
        out.append(_ref(d))
    return out


# ---------------------------------------------------------------- 模块：精力管理
def _energy_ledger(state: GameState, reg) -> dict:
    """精力管理（H 轨迹）。铁律：不给 H 数值、不标危险线阈值，只用行为语言与证据编号。"""
    danger, pushed = [], []
    for d in state.decisions:
        before, after = d.snapshot_before, d.snapshot_after
        if not before or not after:
            continue
        if after.get("H", 99) <= C.H_DANGER:
            danger.append(d)
            if after.get("H", 0) < before.get("H", 0):
                pushed.append(d)
    # 恢复方式（算法册 §6 精力管理模块三类）：
    #   选择型休息 = 自由周末选了 solo 型独处活动（放弃社交/产出换独处）
    #   花精力主动休息 = 月度精力分配里花了休息点（放弃产出方向换恢复）
    #   被迫停下 = 倦怠事件 + 强制休息月（不是选择，是 measurement point）
    solo = 0
    for d in state.decisions:
        if d.source != "free_time":
            continue
        act = reg.activity(d.node_id) or {}
        if act.get("type") == "solo":
            solo += 1
    recovery = {
        "选择型休息": solo,
        "花精力主动休息": sum(1 for a in state.monthly_allocations if a.get("rest_applied")),
        "被迫停下": (sum(1 for i in state.incidents if i.get("kind") == "burnout")
                     + len(state.rest_months)),
    }
    line = ""
    if danger:
        line = (f"{len(state.decisions)} 个决策点里，你有 {len(danger)} 次把自己用到危险区，"
                f"其中 {len(pushed)} 次选了硬扛。")
    return {
        "dangerZoneCount": len(danger),
        "pushedThroughCount": len(pushed),
        "recoveryWays": recovery,
        "line": line,
        "evidence": _refs(pushed, limit=2),
    }


# ---------------------------------------------------------------- 模块：处境轨迹
def _situation_track(state: GameState, months_log: list[dict]) -> dict:
    """生存轨状态迁移史。只给事实与迁移原因，不给系统内部阈值。"""
    states = []
    for rec in months_log:
        tick = rec.get("survival") or {}
        if tick.get("changed"):
            states.append({"month": rec["month"], "state": tick.get("to"),
                           "reason": str(tick.get("reason", ""))[:60]})
    return {
        "states": states,
        "burnoutCount": sum(1 for i in state.incidents if i.get("kind") == "burnout"),
    }


# ---------------------------------------------------------------- 模块：晋升轨迹
def _promotion_track(state: GameState) -> dict:
    windows = [{"seq": i, "month": w["month"], "passed": w["promoted"],
                "levelAfter": w["level_after"]}
               for i, w in enumerate(state.promotion_windows, start=1)]
    grade = pr.final_grade(state)
    f = grade["frames"]
    line = (f"你在 {f['甩锅场合']} 次可以甩锅的场合守住了 {f['甩锅场合守住']} 次；"
            f"在 {f['无人监督场合']} 次没人监督的场合守住了 {f['无人监督场合守住']} 次。")
    return {
        "windows": windows,
        "finalGrade": {"grade": grade["grade"], "level": grade["level"],
                       "label": grade["label"], "line": line},
    }


# ---------------------------------------------------------------- 模块：冲刺与伪装
def _sprint_and_disguise(state: GameState, reg, tracking: list[dict]) -> dict:
    """冲刺检测 + 伪装指数（算法册 §7 特色分析 4/5）。

    冲刺：考核窗前两个月找某 NPC 的周末次数 vs 此前半年基线（explore_click 轨迹）。
    伪装：需要遮掩的选择（隐瞒类 flag）上犹豫显著低于个人中位数 → 只描述行为模式。
    措辞红线：不下「你是伪装者」结论。
    """
    explore = [t for t in tracking if t.get("tap") == "explore_click"]
    window_months = [t["month"] for t in tracking if t.get("tap") == "promotion_window"]

    def _npc_name(nid: str) -> str:
        return (reg.npcs().get(nid) or {}).get("name") or nid

    sprint = []
    for i, w in enumerate(window_months, start=1):
        targets = sorted({t for x in explore for t in x.get("targets", [])})
        for nid in targets:
            in_window = [x for x in explore
                         if nid in x.get("targets", []) and x["month"] in (w - 1, w)]
            baseline = [x for x in explore
                        if nid in x.get("targets", []) and w - 7 <= x["month"] <= w - 2]
            if len(in_window) >= 2 and not baseline:
                sprint.append({
                    "windowSeq": i,
                    "line": (f"此前半年没找过{_npc_name(nid)}，"
                             f"考核窗前两个月找了 {len(in_window)} 次。"),
                })

    hesses = sorted(d.hesitation_ms for d in state.decisions
                    if d.hesitation_ms is not None)
    median = hesses[len(hesses) // 2] if hesses else None
    conceal = [d for d in state.decisions
               if any(f in C.CONCEAL_FLAGS for f in d.flags_set)]
    fast = [d for d in conceal
            if median is not None and d.hesitation_ms is not None
            and d.hesitation_ms < median]
    if len(fast) >= 2:
        level, line = "high", "好几件需要遮掩的事，你都答得比平时快——快，本身就是信息。"
    elif len(fast) == 1:
        level, line = "medium", "有一件需要遮掩的事，你答得比平时快。"
    else:
        level, line = "low", "你的犹豫模式里没有刻意表演的痕迹。"

    return {"sprint": sprint, "disguise": {"level": level, "line": line}}


# ---------------------------------------------------------------- 模块：在场一幕回声
def _encounter_echoes(tracking: list[dict]) -> dict:
    """在场一幕回声（encounter_choice 聚合）。

    同一个活动、同一处境，不同的人应答不同——应答里带的性格标签（memory_tags）
    是报告能区分「主动招呼的人」和「想自己待着的人」的原料。
    红线：只报标签与次数描述，不报任何数值；一次都没上报过 → n=0、line 空串
    （与 psychDriveHighlights 同规则：无据不推断）。
    """
    rows = [t for t in tracking
            if t.get("tap") == "encounter_choice" and t.get("memoryTags")]
    if not rows:
        return {"n": 0, "tags": [], "line": ""}
    counts: dict[str, int] = {}
    for t in rows:
        for tag in t["memoryTags"]:
            tag = str(tag)
            if tag:
                counts[tag] = counts.get(tag, 0) + 1
    tags = [{"tag": k, "n": v}
            for k, v in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))]
    top = tags[0]["tag"]
    suffix = "的样子" if tags[0]["n"] >= 2 else "的样子（只记下过一次）"
    line = (f"{len(rows)} 次撞见人的时刻，"
            f"你最容易留下「{top}」{suffix}。" if counts else "")
    return {"n": len(rows), "tags": tags, "line": line}


# ---------------------------------------------------------------- 模块：证据回放
def _evidence_replay(state: GameState) -> list[dict]:
    """犹豫离群点 + 横跳离群点（算法册 §7 特色分析 1/2）：离群点 = 在意的事。"""
    hesses = sorted((d for d in state.decisions if d.hesitation_ms is not None),
                    key=lambda d: d.hesitation_ms)
    switches = sorted((d for d in state.decisions if d.switch_count is not None),
                      key=lambda d: d.switch_count)
    picks: list = []
    if len(hesses) >= 4:
        picks += [hesses[0], hesses[-1]]
    if len(switches) >= 4:
        picks.append(switches[-1])
    seen, out = set(), []
    for d in picks:
        if d.seq in seen:
            continue
        seen.add(d.seq)
        out.append(_ref(d))
    out.sort(key=lambda e: e["seq"])
    return out


# ---------------------------------------------------------------- 唯一入口
def build(result, reg, self_ratings: dict[str, float] | None = None,
          session_id: str = "sim") -> dict:
    """三层报告。result: simulation.RunResult；self_ratings: 建档自评（0-10，键为大五字母）。"""
    state: GameState = result.state
    months_log = result.log.months

    trait_rows = bayes.build_posteriors(state, reg.loading_base, self_ratings)
    topic_mods = [m for m in topics.build_topics(state) if m["displayable"]]

    by_key = {m["key"]: m for m in topic_mods}
    sketch = (by_key.get("regulatory_focus", {}).get("summary")
              or by_key.get("moral_foundation", {}).get("summary")
              or by_key.get("sdt", {}).get("summary") or "")

    # 自评 vs 行为显著矛盾点（呈现铁律：只给档位与行为语言，不给阈值）
    row_by_cn = {r["trait_cn"]: r for r in trait_rows}
    conflicts = []
    for r in trait_rows:
        if r["conflict_significant"]:
            conflicts.append({
                "traitCn": r["trait_cn"],
                "line": (f"你在{r['trait_cn']}上给自己打了「{_band(r['self'])}」，"
                         f"但 48 个月的行为落在「{_band(r['behavior'])}」。"),
                "evidence": _refs([d for d in state.decisions
                                   if any(f in C.CONCEAL_FLAGS for f in d.flags_set)], limit=2),
            })

    inv = investment.build_investment(state, reg)

    persona = {
        "personaSketch": sketch,
        "bigfive": [{
            "trait": r["trait"], "traitCn": r["trait_cn"],
            "self": r["self"], "behavior": r["behavior"], "behaviorStd": r["behavior_std"],
            "posterior": r["posterior"], "conflict": r["conflict"],
            "conflictSignificant": r["conflict_significant"],
            "evidenceCount": r["evidence_count"],
            "behaviorAvailable": r["behavior_available"],
            "consistency": r["consistency"],
            "note": (CONSISTENCY_NOTE if r["consistency"] == "situational"
                     else "" if r["behavior_available"]
                     else "行为证据不足，仅供参考"),
        } for r in trait_rows],
        "selfVsBehaviorConflicts": conflicts,
        "radar": radar.build_radar(state, reg),
        "topics": [{
            "key": m["key"], "title": m["title"], "displayable": m["displayable"],
            "n": m["n"], "threshold": m["threshold"], "summary": m["summary"],
            "bullets": m["bullets"], "evidence": m["evidence"],
        } for m in topic_mods],
        "investment": {
            "weekendCounts": inv["weekend_counts"],
            "innerMotivation": inv["inner_motivation"],
            "line": inv["line"],
            "evidence": _refs([d for d in state.decisions if d.source == "free_time"], limit=3),
        },
        "energyLedger": _energy_ledger(state, reg),
        "situationTrack": _situation_track(state, months_log),
        "promotionTrack": _promotion_track(state),
        "sprintAndDisguise": _sprint_and_disguise(state, reg, result.log.tracking),
        "encounterEchoes": _encounter_echoes(result.log.tracking),
        "psychDriveHighlights": [{"tag": p["tag"], "line": p["line"],
                                  "evidence": p["evidence"]}
                                 for p in topics.psych_drive(state)],
    }

    # ---- 三层 · 交叉提示：画像 vs 岗位要求。语料未接入 → 画像内提示 + 占位说明
    hints = []
    for c in conflicts:
        row = row_by_cn[c["traitCn"]]
        hints.append({
            "line": (f"职场里最看重的「{c['traitCn']}」，你的行为落在「{_band(row['behavior'])}」"
                     f"（你自己说的是「{_band(row['self'])}」）——差距不在能力，在具体那几次。"),
            "basis": c["evidence"],
        })
    hints.append({
        "line": ("岗位市场参考待接入真实 JD 语料后，按「画像 vs 岗位要求」生成精确差距提示。"
                 "本层是提示，不是结论。"),
        "basis": [],
    })

    return {
        "sessionId": session_id,
        "scoringVersion": str(reg.version.get("scoring_cards", "unknown")),
        "generatedAt": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "decisionCount": len(state.decisions),
        "layers": {
            "persona": persona,
            "market": {"dataSource": "stub", "corpusSize": 0, "jobs": []},
            "crossHints": {"hints": hints},
        },
        "evidenceReplay": _evidence_replay(state),
    }
