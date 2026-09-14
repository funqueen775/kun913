# -*- coding: utf-8 -*-
"""48 个月主循环：把时钟、调度、结算、晋升、生存轨、危机对话串成一条线。

顺序（每月）：
  月初清算 → 强制休息判定 →（主线/成就节点）→ 月度精力分配 → 自由周末（每 3 月）
  → 考核窗（每 6 月）→ 生存轨 tick → 危机对话（连续 2 窗未达标）→ 月末（生命归零触发下月强制休息）

时间口径（算法册 §6）：强制休息月不消耗剧情节点（主线顺延），但自由活动保留，
rest_month 标记进出统计；决策序号 seq 只对真实决策点自增。
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field

from ..core import constants as C
from ..core.loader import ConfigRegistry
from . import free_time as ft
from . import monthly as mo
from . import promotion as pr
from . import survival as sv
from . import timeline as tl
from .settlement import normalize_crisis, normalize_mainline, settle
from .state import GameState


# ------------------------------------------------------------------ 决策策略接口
class Policy:
    """决策策略。引擎与策略解耦——竞技/教学/自动跑批共用同一引擎。"""

    name = "base"

    def mainline(self, state: GameState, event, options: dict) -> str:
        return sorted(options)[0]

    def monthly(self, state: GameState, template_id: str, options: dict) -> str:
        return sorted(options)[0]

    def free_weekend(self, state: GameState, candidates: list, slot: int, month: int):
        act = candidates[0]
        npc = next(iter(sorted(state.npc_affinity))) if state.npc_affinity else "wang_ge"
        dec = act.get("decision", {}).get("options", [])
        return act["activity_id"], npc, (dec[0]["option_id"] if dec else None)

    def crisis(self, state: GameState, options: dict) -> str:
        return sorted(options)[0]

    def last_talk(self, state: GameState) -> str:
        return "C"


class IndexPolicy(Policy):
    """按选项编号顺序选（A→B→C）。可复现，用于回归测试。"""

    name = "index"


class RandomPolicy(Policy):
    name = "random"

    def __init__(self, seed: int = 0):
        self.rng = random.Random(seed)

    def mainline(self, state, event, options):
        return self.rng.choice(sorted(options))

    def monthly(self, state, template_id, options):
        return self.rng.choice(sorted(options))

    def crisis(self, state, options):
        return self.rng.choice(sorted(options))

    def free_weekend(self, state, candidates, slot, month):
        act = self.rng.choice(candidates)
        npcs = sorted(state.npc_affinity) or ["wang_ge", "xiao_lin", "xiao_zhao", "lao_zhou"]
        npc = self.rng.choice(npcs)
        dec = act.get("decision", {}).get("options", [])
        return act["activity_id"], npc, (self.rng.choice([o["option_id"] for o in dec]) if dec else None)


class UtilityPolicy(Policy):
    """功利策略：在六维上取「净收益最大、风险最小」。用于把引擎跑到上限做对账。

    注意：这是一个**明确的、可写进文档的策略**，不是「正确答案」——奖励不指向唯一最优解
    （防污染第 4 条），本策略只用于引擎压力测试。
    """

    name = "utility"
    WEIGHTS = {"S": 1.0, "O": 0.9, "N": 0.6, "D": 1.0, "H": 1.2, "risk": -1.5}

    def _score(self, opt: dict) -> float:
        s = 0.0
        for k, w in self.WEIGHTS.items():
            s += w * float(opt.get("state_delta", {}).get(k, 0))
        s += 0.3 * sum(opt.get("competency", {}).values())
        if opt.get("bonus_tier") == "excellent":
            s += 0.5
        s -= 2.0 * float(opt.get("life", 0) if opt.get("life", 0) < 0 else 0)
        return s

    def mainline(self, state, event, options):
        return max(sorted(options), key=lambda o: self._score(options[o]))

    def monthly(self, state, template_id, options):
        return max(sorted(options), key=lambda o: self._score(options[o]))

    def crisis(self, state, options):
        return "C"          # 内-行为归因（最健康）

    def free_weekend(self, state, candidates, slot, month):
        work = [a for a in candidates if a.get("type") == "work"]
        act = (work or candidates)[0]
        npcs = sorted(state.npc_affinity) or ["wang_ge"]
        dec = act.get("decision", {}).get("options", [])
        return act["activity_id"], npcs[0], (dec[0]["option_id"] if dec else None)


# ------------------------------------------------------------------ 主循环
@dataclass
class RunLog:
    months: list[dict] = field(default_factory=list)
    tracking: list[dict] = field(default_factory=list)


@dataclass
class RunResult:
    state: GameState
    log: RunLog

    def decisions_count(self) -> int:
        return len(self.state.decisions)


def run(reg: ConfigRegistry, policy: Policy | None = None, seed: int = 0,
        user_id: str = "sim", months: int = C.TOTAL_MONTHS,
        schedule: list[tuple[int, str]] | None = None) -> RunResult:
    policy = policy or IndexPolicy()
    rng = random.Random(seed)
    state = GameState(user_id=user_id, seed=seed)
    log = RunLog()

    queue = list(schedule or tl.build_schedule(reg))
    free_months = set(tl.free_time_months())
    slot = 0
    pending_rest = False
    crisis_done_for_streak = -1
    exited = False

    for m in range(1, months + 1):
        state.month = m
        state.in_rest_month = pending_rest
        pending_rest = False
        if state.in_rest_month:
            state.rest_months.append(m)
        mo.start_new_month(state)
        month_rec: dict = {"month": m, "rest_month": state.in_rest_month,
                           "events": [], "monthly": None, "free_weekend": None,
                           "promotion": None, "survival": None, "crisis": None}

        # ---- 主线 / 成就节点（强制休息月顺延，不消耗队列）
        if queue and queue[0][0] <= m and not state.in_rest_month and not exited:
            _, eid = queue.pop(0)
            ev = reg.events[eid]
            if ev.has_decision:
                opts = ev.options
                oid = policy.mainline(state, ev, opts)
                choice = normalize_mainline(reg, eid, oid)
                res = settle(state, choice, reg, hesitation_ms=rng.randint(3000, 25000),
                             switch_count=rng.randint(0, 4))
                month_rec["events"].append({"event_id": eid, "title": ev.title,
                                            "act": ev.act, "situation": ev.situation,
                                            "option_id": oid, "text": choice.option_text,
                                            "settle": res})
                log.tracking.append({"tap": "option_click", "month": m, "node_id": eid,
                                     "option_id": oid,
                                     "hesitation_ms": res and state.decisions[-1].hesitation_ms})
            else:
                month_rec["events"].append({"event_id": eid, "title": ev.title,
                                            "act": ev.act, "view": True})
                if eid in ("C1", "C2", "C3"):
                    log.tracking.append({"tap": "achievement_view", "month": m, "node_id": eid})

        # ---- 月度精力分配
        if not exited:
            tpl = mo.template_for_level(state.level)
            oid = policy.monthly(state, tpl, reg.monthly_templates[tpl]["options"])
            month_rec["monthly"] = mo.run_monthly_node(state, reg, oid)

        # ---- H 归零 → 倦怠事件（剧情册 §四：与「生命归零强制休息」是两件事，不取代不合并）
        #      倦怠不计生存轨失误（severity=0），它本身是测量点。
        #      一次倦怠期只记一次；H 回到 0 以上才算「恢复」，之后可再次触发。
        if state.H <= 0 and not state.burnout_active:
            state.burnout_active = True
            state.incidents.append({"month": m, "reason": "倦怠事件（H 归零）",
                                    "severity": 0, "kind": "burnout"})
            month_rec["burnout"] = True
        elif state.H > 0 and state.burnout_active:
            state.burnout_active = False
            month_rec["burnout_recovered"] = True

        # ---- 自由周末（每 3 个月，强制休息月保留）
        if m in free_months and not exited:
            slot += 1
            weather = ft.weather_for(reg, rng)
            cands = ft.available_activities(reg, state, m, weather)
            aid, npc, dec = policy.free_weekend(state, cands, slot, m)
            month_rec["free_weekend"] = ft.run_free_weekend(state, reg, rng, aid, slot, npc, dec)
            log.tracking.append({"tap": "explore_click", "month": m, "slot_index": slot,
                                 "activity_id": aid, "targets": [npc], "weather": weather})

        # ---- 考核窗（每 6 个月）
        if m in C.PROMOTION_MONTHS:
            sv.raise_flags(state, m)
            result = pr.settle_window(state, m)
            month_rec["promotion"] = result
            log.tracking.append({"tap": "promotion_window", "month": m,
                                 "promoted": result["promoted"], "level": state.level})

        # ---- 风险累积引爆事故（task_001_tech_stack.json 的 hooks.risk_threshold_event）
        if not exited:
            risk_th = (reg.template.get("hooks", {})
                       .get("risk_threshold_event", {})
                       .get("when", {}).get("risk_cumulative_gte", 5))
            if state.risk_cumulative >= risk_th:
                state.risk_cumulative -= risk_th
                sv.register_mistake(state, m, f"风险累积引爆事故（risk_cumulative>={risk_th}）", 1)
                month_rec["incident"] = True
                log.tracking.append({"tap": "incident", "month": m, "threshold": risk_th})

        # ---- 生存轨
        tick = sv.monthly_tick(state, m)
        month_rec["survival"] = tick
        if tick["changed"]:
            log.tracking.append({"tap": "survival_state_change", "month": m,
                                 "to": tick["to"]})

        # ---- 危机对话（连续 2 窗未达标；同一 streak 只触发一次）
        if (not exited and sv.should_trigger_crisis(state)
                and state.consecutive_promotion_failures != crisis_done_for_streak):
            crisis_done_for_streak = state.consecutive_promotion_failures
            opts = reg.crisis["options"]
            oid = policy.crisis(state, opts)
            choice = normalize_crisis(reg, oid)
            res = settle(state, choice, reg, hesitation_ms=rng.randint(4000, 30000))
            state.crisis_talks.append({"month": m, "option_id": oid,
                                       "attribution": choice.attribution,
                                       "consecutive": state.consecutive_promotion_failures})
            month_rec["crisis"] = {"option_id": oid, "text": choice.option_text,
                                   "attribution": choice.attribution, "settle": res}
            log.tracking.append({"tap": "crisis_talk_choice", "month": m, "option_id": oid})

        # ---- 最后谈话
        if state.survival_state == "last_talk" and not exited:
            exit_id = policy.last_talk(state)
            month_rec["last_talk"] = sv.trigger_last_talk(state, m, exit_id)
            if exit_id in ("A", "B"):
                exited = True

        # ---- 月末：生命归零 → 下月强制休息（顺手触发欠款）
        if state.life <= 0:
            pending_rest = True
            month_rec["forced_rest_next"] = True

        log.months.append(month_rec)

    return RunResult(state=state, log=log)


def summarize(reg: ConfigRegistry, result: RunResult) -> dict:
    """跑批摘要：给跑批脚本和／或报告层用的聚合视图。"""
    st = result.state
    bf = {t: [e["weighted"] for e in v] for t, v in st.bigfive_evidence.items()}
    by_source: dict[str, int] = {}
    for d in st.decisions:
        by_source[d.source] = by_source.get(d.source, 0) + 1
    # 算法册 §1 口径：39 主线 + 48 月度 + 16 自由周末 = 约 103 次选择
    core_choices = (by_source.get("mainline", 0) + by_source.get("monthly", 0)
                    + by_source.get("free_time", 0))
    return {
        "决策点数": len(st.decisions),
        "按来源": by_source,
        "核心选择数_算法册口径": core_choices,
        "月份": st.month,
        "强制休息月": st.rest_months,
        "六维": st.hidden_dims,
        "pending_dignity": st.pending_dignity,
        "职级": st.level,
        "考核窗": [(w["month"], w["promoted"], w["level_after"]) for w in st.promotion_windows],
        "连续未达标": st.consecutive_promotion_failures,
        "危机对话次数": len(st.crisis_talks),
        "生存轨": st.survival_state,
        "失误数_当前streak": st.survival_strikes,
        "失误数_累计": sum(1 for i in st.incidents if i.get("severity", 0) > 0),
        "事故清单": [f"M{i['month']}:{i['reason']}" for i in st.incidents if i.get("severity", 0) > 0],
        "倦怠事件次数": sum(1 for i in st.incidents if i.get("kind") == "burnout"),
        "危险区决策次数": len([d for d in st.decisions if d.snapshot_after.get("H", 99) <= C.H_DANGER]),
        "公开账本": {"生命": st.life, "专业能力": st.prof, "钱": st.money, "欠款": st.debt},
        "flags": st.flags,
        "大五证据条数": {k: len(v) for k, v in st.bigfive_evidence.items()},
        "大五加权和": {k: round(sum(v), 3) for k, v in bf.items()},
        "能力": st.competency,
        "SDT条数": len(st.sdt),
        "道德条数": len(st.moral_foundation),
        "调节焦点条数": len(st.regulatory_focus),
        "归因条数": len(st.attribution),
        "CFC/NFC条数": len(st.cognition),
        "psych_drive": [p["tag"] for p in st.psych_drive],
        "守界者计数器": {"甩锅场合": (st.counter_blame_scenes, st.counter_blame_held),
                         "无人监督场合": (st.counter_nosupervision, st.counter_nosupervision_held)},
        "好感度": st.npc_affinity,
        "记忆标签数": len(st.memory_tags),
        "终局": pr.final_grade(st),
    }
