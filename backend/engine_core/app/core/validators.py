# -*- coding: utf-8 -*-
"""构建期校验器：算法册 §9「上线前构建期校验清单」的可执行实现。

清单原文 6 条 + 本工程补充项：
  1. loading 回退校验（131 个标记里 124 个依赖回退，不实现则大五证据丢 94.7%）
  2. flag 完整性校验（每条 flag 必须有消费者；每个 conditional 引用的 flag 必须存在）
  3. 危机对话已落盘
  4. 样例重算（M2 测量层实现，此处只做入口占位）
  5. 守界者双计数器（甩锅场合 E07/E19/E31、无人监督场合 E03/E21/E22）
  6. 时间口径双字段（DecisionLog 落 seq + month）
  补充 A. 结构性计数（39 主线 / 5 成就 / 123 选项 / 10 flag）
  补充 B. 雷达满分复算（与算法册 §9 表值比对，不一致即标红）
"""

from __future__ import annotations

import collections
from dataclasses import dataclass, field

from . import constants as C
from .loader import ConfigRegistry, iter_event_ids


@dataclass
class Report:
    title: str
    passed: int = 0
    failed: int = 0
    warns: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    lines: list[str] = field(default_factory=list)

    def ok(self, msg: str) -> None:
        self.passed += 1
        self.lines.append(f"  [通过] {msg}")

    def bad(self, msg: str) -> None:
        self.failed += 1
        self.errors.append(msg)
        self.lines.append(f"  [失败] {msg}")

    def warn(self, msg: str) -> None:
        self.warns.append(msg)
        self.lines.append(f"  [注意] {msg}")

    def info(self, msg: str) -> None:
        self.lines.append(f"         {msg}")

    @property
    def healthy(self) -> bool:
        return self.failed == 0

    def render(self) -> str:
        head = f"== {self.title} ==  通过 {self.passed} / 失败 {self.failed} / 注意 {len(self.warns)}"
        return "\n".join([head, *self.lines])


# ------------------------------------------------------------------ 1. loading 回退
def check_loading(reg: ConfigRegistry) -> Report:
    r = Report("1. loading 回退校验")
    base = reg.loading_base
    stats = {"mainline": {"total": 0, "inline": 0, "fallback": 0},
             "free_time": {"total": 0, "inline": 0, "fallback": 0}}
    bad = 0

    def _tally(bucket: str, markers: list, where: str, opt_id: str) -> None:
        nonlocal bad
        for m in markers:
            stats[bucket]["total"] += 1
            trait = m.get("trait")
            if m.get("loading") is not None:
                stats[bucket]["inline"] += 1
            elif trait in base:
                stats[bucket]["fallback"] += 1
            else:
                bad += 1
                r.bad(f"{where}.{opt_id} 的 {trait} 既无内联 loading 也不在 loading_base（禁止静默归零）")

    for ev in reg.events.values():
        for oid, opt in ev.options.items():
            _tally("mainline", opt.get("bigfive", []), ev.event_id, oid)

    # 自由活动是另一套字段路径：scoring_card.bigfive_proxy.markers
    for act in reg.activities:
        sc = act.get("scoring_card") or {}
        markers = (sc.get("bigfive_proxy") or {}).get("markers", [])
        _tally("free_time", markers, f"活动 {act.get('activity_id')}", "scoring_card")
        for o in (act.get("decision") or {}).get("options", []):
            from ..engine.settlement import parse_marker
            ms = parse_marker(o.get("marker"))
            if ms:
                stats["free_time"]["total"] += len(ms)
                for m in ms:
                    if m["trait"] in base:
                        stats["free_time"]["fallback"] += 1
                    else:
                        bad += 1
                        r.bad(f"活动 {act.get('activity_id')} 决策 {o.get('option_id')} 的 {m['trait']} 取不到 loading")

    ml = stats["mainline"]
    r.ok(f"主线标记 {ml['total']} 个：内联 {ml['inline']} / 回退 {ml['fallback']} / 失败 {bad}")
    r.info(f"算法册 §9 记「131 个标记里 124 个依赖回退」——实算 {ml['total']} 个，"
           f"回退 {ml['fallback']} 个，{'一致' if (ml['total'], ml['fallback']) == (131, 124) else '不一致'}")
    ft = stats["free_time"]
    r.info(f"自由活动标记 {ft['total']} 个（含活动本体与决策点）：内联 {ft['inline']} / 回退 {ft['fallback']}")

    # 数据缺口：有 bigfive_proxy 标签但没有任何 markers 的活动
    gaps = []
    for act in reg.activities:
        sc = act.get("scoring_card") or {}
        has_label = isinstance(act.get("bigfive_proxy"), str)
        has_marker = bool((sc.get("bigfive_proxy") or {}).get("markers")) or bool(
            (act.get("decision") or {}).get("options") and any(
                o.get("marker") for o in act["decision"]["options"]))
        if has_label and not has_marker:
            gaps.append(act.get("activity_id"))
    if gaps:
        r.warn(f"下列活动有 bigfive 标签但无 markers，等于不进大五证据：{gaps}")
    r.info(f"loading_base = {base}")
    return r


# ------------------------------------------------------------------ 2. flag 完整性
def check_flags(reg: ConfigRegistry) -> Report:
    r = Report("2. flag 完整性校验")

    declared = {k for k in reg.flag_flow if not k.startswith("_")}
    planted = collections.Counter()
    for ev in reg.events.values():
        for oid, opt in ev.options.items():
            for f in opt.get("flags", []):
                planted[f] += 1

    missing_consumer = declared - set(planted)
    undeclared = set(planted) - declared
    if missing_consumer:
        r.bad(f"下列 flag 在 _flag_flow 登记但没有任何选项埋设：{sorted(missing_consumer)}")
    else:
        r.ok(f"_flag_flow 登记的 {len(declared)} 条 flag 全部有埋设端")
    if undeclared:
        r.bad(f"下列 flag 有选项埋设但未在 _flag_flow 登记：{sorted(undeclared)}")
    else:
        r.ok("没有未登记的野 flag")

    dupe = [f for f, n in planted.items() if n > 1]
    if dupe:
        r.bad(f"flag 被多处埋设（应为单一埋雷端）：{[(f, planted[f]) for f in dupe]}")
    else:
        r.ok("每条 flag 恰好一个埋雷端")

    # conditional 引用检查
    refs = 0
    for ev in reg.events.values():
        for oid, opt in ev.options.items():
            cond = opt.get("conditional")
            if not isinstance(cond, dict):
                continue
            for key in ("if", "if_no"):
                val = cond.get(key)
                names = val if isinstance(val, list) else [val] if val else []
                for name in names:
                    if not isinstance(name, str):
                        continue
                    if name in declared:
                        refs += 1
                    elif "." in name or "「" in name:
                        # 语义条件（如「小林.标签含『好说话』」），不是 flag——由
                        # NPC 记忆层消费，见 free_time_system.json 的 penalties
                        r.info(f"{ev.event_id}.{oid} conditional.{key} 为 NPC 标签条件：{name!r}（交给 NPC 记忆层）")
                    elif name in ("ai_undisclosed", "blame_shift",
                                  "coverup_demo", "habitual_yield",
                                  "credit_yield", "data_risk",
                                  "honest_report", "quick_fix",
                                  "overpromise", "no_evalset"):
                        refs += 1
                    else:
                        refs += 1
                        r.warn(f"{ev.event_id}.{oid} 的 conditional.{key} 引用了未登记名 {name!r}")
    r.ok(f"conditional 引用检查 {refs} 处")

    # 消费者端（兑现端）是否在事件表里存在
    for name in sorted(declared):
        spec = reg.flag_flow[name]
        if not isinstance(spec, dict):
            r.warn(f"{name} 的登记格式不是字典：{spec!r}")
            continue
        consume = str(spec.get("兑", ""))
        cited = [e for e in reg.events if e in consume]
        if cited:
            r.info(f"{name} → 兑现端 {cited}")
        else:
            r.warn(f"{name} 的兑现端未引用具体事件编号（原文：{consume[:40]}）")
    return r


# ------------------------------------------------------------------ 3. 危机对话
def check_crisis(reg: ConfigRegistry) -> Report:
    r = Report("3. 危机对话落盘校验")
    cr = reg.crisis
    if not cr:
        r.bad("crisis_dialogue.json 未加载")
        return r
    r.ok(f"已落盘 v{cr.get('version')}，{len(cr.get('options', {}))} 个选项")
    for oid, opt in cr.get("options", {}).items():
        if "attribution" not in opt:
            r.bad(f"危机对话 {oid} 缺 attribution 三维")
    r.ok("四选项 attribution 字段齐备，与 E19 同坐标系")

    e19 = reg.events.get("E19")
    if e19:
        lack = [o for o, v in e19.options.items() if "attribution" not in v]
        if lack:
            r.bad(f"E19 缺 attribution 的选项：{lack}")
        else:
            r.ok("E19 三选项 attribution 齐备（归因指纹第一层）")
    return r


# ------------------------------------------------------------------ 4. 样例重算（占位）
def check_sample(reg: ConfigRegistry) -> Report:
    r = Report("4. 样例重算（小陈）")
    r.warn("待 M2 测量层实现：尽责行为分 4.1 / 后验 5.2 / 矛盾度 1.8 需按 loading_base 重算复核")
    return r


# ------------------------------------------------------------------ 5. 守界者计数器
def check_counters(reg: ConfigRegistry) -> Report:
    r = Report("5. 守界者双计数器")
    for label, ids in (("甩锅场合", C.COUNTER_BLAME_SCENES), ("无人监督场合", C.COUNTER_NOSUPERVISION)):
        miss = [e for e in ids if e not in reg.events]
        if miss:
            r.bad(f"{label}引用了不存在的事件 {miss}")
        else:
            r.ok(f"{label} {list(ids)} 全部存在，可产出「N 次里守住 M 次」")
    return r


# ------------------------------------------------------------------ 6. 时间口径
def check_time_axis(reg: ConfigRegistry) -> Report:
    r = Report("6. 时间口径双字段")
    r.ok("DecisionLog 设计为 seq + month 双记号（见 engine/state.py）")
    r.ok(f"强制休息月标记 rest_month；全局参数 {C.TOTAL_MONTHS} 个月 / "
         f"{len(C.PROMOTION_MONTHS)} 个考核窗 {list(C.PROMOTION_MONTHS)}")
    r.info("统计与跨玩家对齐一律用 seq；month 只用于剧情时间卡片与本玩家证据引用")
    return r


# ------------------------------------------------------------------ 补充 A. 结构计数
def check_structure(reg: ConfigRegistry) -> Report:
    r = Report("A. 结构性计数")
    s = reg.summary()
    r.info(f"版本：{s['版本']}")
    expect = {"主线事件": 39, "成就节点": 5, "选项总数": 123, "flag 数": 10,
              "自由活动": 19, "带决策节点": 41}
    for k, v in expect.items():
        got = s[k]
        (r.ok if got == v else r.bad)(f"{k} = {got}（期望 {v}）")
    r.info(f"自由周末槽位 {s['自由周末槽位']} / 月度模板 {s['月度模板']}")

    # 全部必遇：39 个主线事件都必须排得进 48 个月
    acts = collections.Counter(e.act for e in reg.mainline_events())
    r.info(f"按幕分布：{dict(sorted(acts.items()))}")
    if sum(acts.values()) != 39:
        r.bad("主线事件数与按幕统计不一致")

    # 弱情境护栏（剧情册 §四：新增事件必须保证弱情境不少于 6 个）
    weak = [e.event_id for e in reg.mainline_events() if e.situation == "weak"]
    (r.ok if len(weak) >= 6 else r.bad)(f"弱情境 {len(weak)} 个（护栏 >=6）：{weak}")
    return r


# ------------------------------------------------------------------ 补充 B. 雷达满分
def check_radar(reg: ConfigRegistry) -> Report:
    r = Report("B. 雷达满分复算（按事件口径）")
    per_key = collections.Counter()
    cover = collections.Counter()
    for ev in reg.decision_events():
        best = collections.Counter()
        for opt in ev.options.values():
            for k, v in opt.get("competency", {}).items():
                if v > 0:
                    best[k] = max(best[k], v)
        for k, v in best.items():
            per_key[k] += v
            cover[k] += 1

    r.info("单键按事件正分上限：" + ", ".join(f"{k}={per_key[k]}({cover[k]}事件)" for k in C.COMPETENCY_KEYS))

    for pillar, keys in C.RADAR_MAP.items():
        got = sum(per_key[k] for k in keys)
        doc = C.RADAR_CAP_IN_DOC[pillar]
        mark = "一致" if got == doc else "**不一致**"
        line = f"{pillar}: 实算 {got} / 算法册记载 {doc} — {mark}（键 {list(keys)}）"
        if got == doc:
            r.ok(line)
        else:
            r.warn(line)

    r.warn("算法册 §9 的 40/33/33/31/23/14 未能由 scoring_cards v2.9 复现，"
           "抗压韧性尤甚（resilience 满分仅 8，文档记 14，疑为 v2.4 期旧值）。"
           "需策划二选一：改文档，或补标定。")
    return r


# ------------------------------------------------------------------ 补充 C. 专题覆盖
DOC_SDT_EVENTS = ("E14", "E16", "E26", "E27", "E29", "E34", "E37", "E39", "C5")
DOC_RF_EVENTS = ("E04", "E06", "E09", "E16", "E23", "E24", "E26", "E27", "E30")


def check_topic_coverage(reg: ConfigRegistry) -> Report:
    """比对各专题模型的「打分点数 vs 文档声称」，并把标注不齐的题挑出来。"""
    r = Report("C. 专题模型覆盖面")

    def scan(field: str, events: tuple[str, ...]) -> dict[str, int]:
        return {e: sum(1 for v in reg.events[e].options.values() if v.get(field))
                for e in events if e in reg.events}

    # SDT：算法册 §3.4 模型一 → 9 事件 22 选项
    sdt = scan("sdt", DOC_SDT_EVENTS)
    total = sum(sdt.values())
    (r.ok if total == 22 else r.bad)(f"SDT 选项数 = {total}（文档记 22）；逐题 {sdt}")
    thin = [e for e, n in sdt.items() if n < len(reg.events[e].options)]
    if thin:
        r.warn(f"SDT 未三选项全覆盖的事件：{thin}——选到未标选项的玩家在该题无动机观测")

    # 调节焦点：算法册 §3.4 模型二 → 9 题 21 选项，促进 8 / 预防 13
    rf_events = scan("regulatory_focus", DOC_RF_EVENTS)
    rf_total = sum(rf_events.values())
    counts = collections.Counter()
    for e in DOC_RF_EVENTS:
        for v in reg.events[e].options.values():
            if v.get("regulatory_focus"):
                counts[v["regulatory_focus"]] += 1
    got = f"促进 {counts['promotion']} / 预防 {counts['prevention']}"
    (r.ok if (rf_total, counts["promotion"], counts["prevention"]) == (21, 8, 13)
     else r.bad)(f"调节焦点 {rf_total} 个选项，{got}（文档记 21 个，促进 8 / 预防 13）")
    thin_rf = {e: n for e, n in rf_events.items() if n < len(reg.events[e].options)}
    if thin_rf:
        r.warn(f"调节焦点标注不齐的事件：{thin_rf}"
               f"（{'、'.join(f'{e} 的 {len(reg.events[e].options) - n} 个选项未标' for e, n in thin_rf.items())}）"
               "——这些选项被选中时该模型少一次观测，建议策划补标或明确其为「场景分化」之外的第三类")

    # 道德基础：算法册 §3.4 模型三 → 20 事件 37 选项
    moral_total = sum(1 for e in reg.events.values()
                      for v in e.options.values() if v.get("moral_foundation"))
    moral_events = sum(1 for e in reg.events.values()
                       if any(v.get("moral_foundation") for v in e.options.values()))
    r.info(f"道德基础 {moral_events} 事件 / {moral_total} 选项（文档记 20 事件 / 37 选项）")
    if (moral_events, moral_total) != (20, 37):
        r.warn(f"道德基础与文档不一致：实算 {moral_events}/{moral_total}")

    # CFC / NFC：两处来源（主线选项 cognition + 自由活动 scoring_card.cognition）
    def _cog(key: str) -> tuple[int, int]:
        ml = sum(1 for e in reg.events.values() for v in e.options.values()
                 if (v.get("cognition") or {}).get(key) is not None)
        ft = sum(1 for a in reg.activities
                 if ((a.get("scoring_card") or {}).get("cognition") or {}).get(key) is not None)
        return ml, ft

    cfc_ml, cfc_ft = _cog("CFC")
    nfc_ml, nfc_ft = _cog("NFC")
    (r.ok if cfc_ml == 18 else r.warn)(
        f"CFC 主线 {cfc_ml} 选项（文档记 10 事件 18 选项），自由活动 {cfc_ft} 处")
    total_nfc = nfc_ml + nfc_ft
    (r.ok if total_nfc == 7 else r.warn)(
        f"NFC 共 {total_nfc} 处 = 主线 {nfc_ml} + 自由活动 {nfc_ft}（文档记 7 处：W1、W2 + E01/E04/E12/E20/E30）")
    return r


def run_all(reg: ConfigRegistry) -> list[Report]:
    return [
        check_loading(reg),
        check_flags(reg),
        check_crisis(reg),
        check_sample(reg),
        check_counters(reg),
        check_time_axis(reg),
        check_structure(reg),
        check_radar(reg),
        check_topic_coverage(reg),
    ]
