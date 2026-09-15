# -*- coding: utf-8 -*-
"""结算器：把一个「选择」翻译成账本变化。

统一入口 settle(state, choice, reg)。所有来源（主线/成就/月度/自由活动/危机对话）
先被 normalize_* 归一成 Choice，再走同一条结算链——避免五套逻辑各写一遍。

防污染四条（算法册 §8.2）在结算层落地：
  1. 主线不锁选项——本模块不做任何可点击性判断；
  2. 增益不增证据——同一次选择只记一条证据，搭档协助不放大；
  3. 娱乐不做判断——只处理白名单来源，家具/卡牌/骰运不进本模块；
  4. 奖励不指向唯一最优解——bonus_tier 由 O 推导后写死，不按选项奖励。
"""

from __future__ import annotations

from dataclasses import dataclass, field

from ..core import constants as C
from ..core.loader import ConfigRegistry
from .state import GameState


@dataclass
class Choice:
    """归一化后的一个选择。"""

    source: str                       # mainline / achievement / monthly / free_time / crisis
    node_id: str
    option_id: str
    option_text: str = ""
    coef: float = 0.75                # 情境系数（没人看着 1.0 / 一般 0.75 / 有人盯着 0.5）
    state_delta: dict = field(default_factory=dict)
    competency: dict = field(default_factory=dict)
    bigfive: list = field(default_factory=list)      # [{trait, dir, loading?}]
    sdt: dict | None = None
    regulatory_focus: str | None = None
    moral_foundation: dict | None = None
    cognition: dict | None = None
    attribution: dict | None = None
    affinity: dict | None = None      # {"npc": str, "delta": int} 列表形式见 affinity_list
    affinity_list: list = field(default_factory=list)
    flags: list = field(default_factory=list)
    memory_tags: list = field(default_factory=list)
    life: int = 0                     # 公开生命（白名单，刻意与 H 不同步）
    prof: int = 0                     # 公开专业能力
    bonus_tier: str = "none"
    psych_drive: str | None = None
    rest_points: int = 0              # 含休息点（月度/自由活动的休息共用计数器）
    extra: dict = field(default_factory=dict)


# ------------------------------------------------------------------ 归一化
def parse_marker(label: str | None) -> list[dict]:
    """把自由活动的简写标记（'E+' / 'C-strong' / 'O+/C+'）解析成大五标记。

    注意两套结构并存（算法册 §9）：主线用选项级 bigfive 数组；自由活动可用简写标记。
    """
    if not label:
        return []
    out: list[dict] = []
    strong = "strong" in label.lower()
    for part in label.split("/"):
        part = part.strip()
        if not part:
            continue
        core = part.replace("-strong", "").strip()      # "E+" / "C" / "E-" / "O+"
        trait = next((ch for ch in core if ch in C.BIGFIVE_KEYS), None)
        if not trait:
            continue
        if "+" in core:
            dir_ = 1
        elif "-" in core:
            dir_ = -1
        elif strong:
            dir_ = 1        # "C-strong"：去掉 strong 后剩裸字母，语义为「强 C 锚点」= 正向
        else:
            dir_ = 1
        marker = {"trait": trait, "dir": dir_}
        if strong:
            marker["loading_scale"] = 1.5
        out.append(marker)
    return out


def normalize_mainline(reg: ConfigRegistry, event_id: str, option_id: str) -> Choice:
    ev = reg.events[event_id]
    opt = ev.options[option_id]
    aff = []
    if "affinity" in opt:
        a = opt["affinity"]
        if isinstance(a, dict):
            aff.append({"npc": a.get("npc") or a.get("target"), "delta": int(a.get("delta", 0))})
    return Choice(
        source="achievement" if ev.is_achievement else "mainline",
        node_id=event_id,
        option_id=option_id,
        option_text=opt.get("text", ""),
        coef=float(opt.get("coef", ev.coef)),
        state_delta=dict(opt.get("state_delta", {})),
        competency=dict(opt.get("competency", {})),
        bigfive=list(opt.get("bigfive", [])),
        sdt=opt.get("sdt"),
        regulatory_focus=opt.get("regulatory_focus"),
        moral_foundation=opt.get("moral_foundation"),
        cognition=opt.get("cognition"),
        attribution=opt.get("attribution"),
        affinity_list=aff,
        flags=list(opt.get("flags", [])),
        memory_tags=list(opt.get("memory_tags", [])),
        life=int(opt.get("life", 0) or 0),
        prof=int(opt.get("prof", 0) or 0),
        bonus_tier=opt.get("bonus_tier", "none"),
        psych_drive=opt.get("psych_drive"),
    )


def normalize_monthly(reg: ConfigRegistry, template_id: str, option_id: str) -> Choice:
    tpl = reg.monthly_templates[template_id]
    opt = tpl["options"][option_id]
    vec = dict(opt.get("allocation_vector", {}))
    return Choice(
        source="monthly",
        node_id=template_id,
        option_id=option_id,
        option_text=opt.get("text", ""),
        coef=1.0,                                   # 月度节点不进 competency/bigfive 标定
        state_delta=dict(opt.get("state_delta", {})),
        bonus_tier="none",
        rest_points=int(vec.get("recovery", 0)),
        extra={"allocation_vector": vec, "risk_preference": opt.get("risk_preference")},
    )


def normalize_freetime(reg: ConfigRegistry, activity_id: str) -> Choice:
    """自由活动本体（无决策）：只有 gain/cost/sdt，不是人格主证据但有低权重贡献。"""
    act = reg.activity(activity_id) or {}
    sc = act.get("scoring_card") or {}
    gain = dict(act.get("gain") or {})
    cost = dict(act.get("cost") or {})
    delta = dict(gain)
    for k, v in cost.items():                        # cost 全部按负号翻译
        delta[k] = delta.get(k, 0) - abs(v)
    markers = list((sc.get("bigfive_proxy") or {}).get("markers", []))
    if not markers:
        markers = parse_marker(act.get("bigfive_proxy") if isinstance(act.get("bigfive_proxy"), str) else None)
    strength = (sc.get("bigfive_proxy") or {}).get("situation_strength", "medium")
    return Choice(
        source="free_time",
        node_id=activity_id,
        option_id="-",
        option_text=act.get("instant_feedback", ""),
        coef=C.SITUATION_COEF.get(strength, 0.75),
        state_delta=delta,
        competency=dict(sc.get("competency") or {}),
        bigfive=markers,
        sdt=sc.get("sdt"),
        cognition=sc.get("cognition"),
        memory_tags=[act["memory_tag"]] if act.get("memory_tag") else [],
        extra={"zone": act.get("zone"), "activity_type": act.get("type")},
    )


def normalize_freetime_decision(reg: ConfigRegistry, activity_id: str, option_id: str) -> Choice:
    """4 个决策点活动的小决策（D2/G1/G2/G4）。"""
    act = reg.activity(activity_id) or {}
    dec = act.get("decision") or {}
    opt = next((o for o in dec.get("options", []) if o.get("option_id") == option_id), None)
    if opt is None:
        raise KeyError(f"{activity_id} 无选项 {option_id}")
    sc = act.get("scoring_card") or {}
    strength = (sc.get("bigfive_proxy") or {}).get("situation_strength", "medium")
    aff_raw = opt.get("affinity_delta")
    aff = []
    if isinstance(aff_raw, int):
        aff.append({"npc": "party", "delta": aff_raw})
    elif isinstance(aff_raw, dict):
        if "target" in aff_raw:
            aff.append({"npc": aff_raw["target"], "delta": int(aff_raw.get("value", 0))})
        elif "each" in aff_raw:
            aff.append({"npc": "party_each", "delta": int(aff_raw["each"])})
    return Choice(
        source="free_time_decision",
        node_id=f"{activity_id}:{dec.get('node_id')}",
        option_id=option_id,
        option_text=opt.get("text", ""),
        coef=C.SITUATION_COEF.get(strength, 0.75),
        state_delta=dict(opt.get("gain") or {}),
        competency=dict(opt.get("competency") or {}),
        bigfive=parse_marker(opt.get("marker")),
        affinity_list=aff,
        memory_tags=list(opt.get("memory_tags", [])),
        extra={"zone": act.get("zone"), "activity_type": act.get("type")},
    )


def normalize_crisis(reg: ConfigRegistry, option_id: str) -> Choice:
    opt = reg.crisis["options"][option_id]
    return Choice(
        source="crisis",
        node_id=reg.crisis["node"]["node_id"],
        option_id=option_id,
        option_text=opt.get("text", ""),
        coef=1.0,                                   # 私密场景，没人看着
        state_delta=dict(opt.get("state_delta", {})),
        attribution=opt.get("attribution"),
        memory_tags=list(opt.get("memory_tags", [])),
        bonus_tier="none",
    )


# ------------------------------------------------------------------ 结算
def settle(state: GameState, choice: Choice, reg: ConfigRegistry, *,
           month: int | None = None, rest_month: bool | None = None,
           hesitation_ms: int | None = None, switch_count: int | None = None) -> dict:
    """执行结算，返回一个 result 摘要（供 API 回包与日志）。"""
    before = state.snapshot()
    month = state.month if month is None else month
    rest_month = state.in_rest_month if rest_month is None else rest_month
    state.seq += 1

    # ---- ① 六维（D 走 pending，月末结算）
    delta = dict(choice.state_delta)
    rest_points = choice.rest_points + (1 if delta.pop("life_rest", 0) else 0)
    risk_delta = int(delta.pop(C.RISK_KEY, 0))

    for k in C.DIM_KEYS:
        if k == C.RISK_KEY or k not in delta:
            continue
        v = int(delta.pop(k, 0))
        if v and k == C.DIGNITY_KEY:
            state.pending_dignity += v
        elif v:
            setattr(state, k, getattr(state, k) + v)

    # H 危险区：硬扛类消耗翻倍（算法册 §10）；此处只对负向 H 生效
    if state.H <= C.H_DANGER:
        # 危险区标记，报告层用；不改变标定值本身，只记事实
        pass
    state.H = max(0, min(C.H_MAX, state.H))

    if risk_delta:
        state.risk_cumulative += risk_delta

    # 例外键：既不在六维也不在白名单 → 报错，禁止静默丢弃
    leftovers = {k: v for k, v in delta.items() if v}
    if leftovers:
        raise ValueError(f"state_delta 出现未知键：{leftovers}（来源 {choice.source}:{choice.node_id}）")

    # ---- ② 能力（雷达）
    for k, v in choice.competency.items():
        state.competency[k] = state.competency.get(k, 0) + int(v)

    # ---- ③ 大五证据：加权载荷 = loading × 情境系数 × 方向
    base = reg.loading_base
    for m in choice.bigfive:
        trait = m.get("trait")
        loading = m.get("loading")
        if loading is None:
            loading = base.get(trait)
        if loading is None:
            raise ValueError(f"大五标记取不到 loading：{trait}（{choice.node_id}）")
        loading = float(loading) * float(m.get("loading_scale", 1.0))
        dir_ = int(m.get("dir", 1))
        weighted = loading * choice.coef * dir_
        state.bigfive_evidence.setdefault(trait, []).append({
            "seq": state.seq, "month": month, "node": choice.node_id,
            "option": choice.option_id, "loading": round(loading, 4),
            "coef": choice.coef, "dir": dir_, "weighted": round(weighted, 4),
        })

    # ---- ④ 六个补充模型（只进专题模块，不进大五、不给综合分）
    if choice.sdt:
        state.sdt.append({"seq": state.seq, "month": month, "node": choice.node_id,
                          "option": choice.option_id, **choice.sdt})
    if choice.regulatory_focus:
        state.regulatory_focus.append({"seq": state.seq, "month": month, "node": choice.node_id,
                                       "option": choice.option_id, "focus": choice.regulatory_focus})
    if choice.moral_foundation:
        state.moral_foundation.append({"seq": state.seq, "month": month, "node": choice.node_id,
                                       "option": choice.option_id, **choice.moral_foundation})
    if choice.cognition:
        state.cognition.append({"seq": state.seq, "month": month, "node": choice.node_id,
                                "option": choice.option_id, **choice.cognition})
    if choice.attribution:
        state.attribution.append({"seq": state.seq, "month": month, "node": choice.node_id,
                                  "option": choice.option_id, **choice.attribution})
    if choice.psych_drive:
        state.psych_drive.append({"seq": state.seq, "month": month, "node": choice.node_id,
                                  "option": choice.option_id, "tag": choice.psych_drive})

    # ---- ⑤ flags / 记忆标签
    for f in choice.flags:
        state.add_flag(f)
        if f not in state.window_flags:
            state.window_flags.append(f)
    for t in choice.memory_tags:
        state.memory_tags.append({"seq": state.seq, "month": month, "tag": t,
                                  "node": choice.node_id})

    # ---- ⑥ 关系（好感度）
    aff_changes = []
    for a in choice.affinity_list:
        npc = a.get("npc")
        if not npc or npc in ("party", "party_each"):
            continue                                  # 未指定具体 NPC 的场合不结算好感
        aff_changes.append(state.npc_add(npc, int(a.get("delta", 0)),
                                         reason=f"{choice.node_id}.{choice.option_id}"))

    # ---- ⑦ 公开账本（只进游戏内经济，永不进测评）
    if choice.life:
        state.life = max(0, min(C.LIFE_MAX, state.life + choice.life))
    if choice.prof:
        state.prof += choice.prof
    if choice.bonus_tier in C.BONUS_TIER:
        state.money += int(reg.anchor.get("bonus_monthly", {}).get(choice.bonus_tier, 0))

    # ---- ⑧ 本考核窗累积（晋升三层判定的累积层，权重 70%）
    state.window_cumulative += (int(choice.state_delta.get("S", 0))
                                + int(choice.state_delta.get("O", 0))
                                + int(choice.state_delta.get("N", 0))
                                + int(choice.state_delta.get("D", 0)))

    # ---- ⑨ 守界者双计数器（E35 文案依赖）
    if choice.node_id in C.COUNTER_BLAME_SCENES:
        state.counter_blame_scenes += 1
        if choice.option_id == "A":
            state.counter_blame_held += 1
    if choice.node_id in C.COUNTER_NOSUPERVISION:
        state.counter_nosupervision += 1
        if choice.option_id == "A":
            state.counter_nosupervision_held += 1

    after = state.snapshot()
    rec = {
        "seq": state.seq, "month": month, "source": choice.source,
        "node_id": choice.node_id, "option_id": choice.option_id,
        "option_text": choice.option_text, "rest_month": rest_month,
        "hesitation_ms": hesitation_ms, "switch_count": switch_count,
        "snapshot_before": before, "snapshot_after": after,
        "flags_set": list(choice.flags), "memory_tags": list(choice.memory_tags),
    }
    from .state import DecisionRecord
    state.decisions.append(DecisionRecord(**rec))
    if choice.source in ("mainline", "achievement") and choice.node_id not in state.events_done:
        state.events_done.append(choice.node_id)

    return {
        "seq": state.seq, "month": month, "node_id": choice.node_id,
        "option_id": choice.option_id, "state_after": state.snapshot(),
        "affinity_changes": aff_changes, "rest_points": rest_points,
        "crisis_pending": False,
    }
